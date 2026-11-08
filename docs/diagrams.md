# Diagrams

## Architecture

The application never touches a table. Every call is `EXEC app.<procedure>` over JDBC with a login that has
only `EXECUTE` on schema `app`.

```mermaid
flowchart LR
    client["Browser: React + HeroUI<br/>(static files from the same app)<br/>or curl, Swagger UI, k6"]
    subgraph app["Spring Boot 4 (Kotlin)"]
        security["Spring Security<br/>session cookie + CSRF"]
        controllers["Controllers<br/>(hand-written endpoints)"]
        repos["Repositories<br/>JdbcClient: EXEC app.*"]
        errors["ApiExceptionHandler<br/>THROW number -> ProblemDetail"]
    end
    subgraph db["SQL Server 2025 Express"]
        appschema["schema app<br/>procedures (API of the database)"]
        crmschema["schema crm<br/>tables, views, helpers"]
        seedschema["schema seed<br/>seed.run"]
    end
    client -->|HTTPS JSON| security --> controllers --> repos
    repos -->|"EXEC app.* (login crm_app)"| appschema
    appschema -->|ownership chaining| crmschema
    repos -. SQL error .-> errors
    seedschema --> crmschema
```

## Containers (docker compose)

```mermaid
flowchart TB
    mssql[("mssql<br/>SQL Server 2025 Express")]
    init["db-init (one-shot)<br/>sqlcmd init.sql: database, logins"]
    migrate["migrate (one-shot)<br/>CRM_MODE=migrate: Flyway, login crm_migrator"]
    app["app<br/>CRM_MODE=app, login crm_app"]
    seed["seed (profile seed, one-shot)<br/>CRM_MODE=seed: EXEC seed.run"]
    k6["k6 (profile perf)<br/>results -> perf/results/"]
    mssql -->|healthy| init -->|completed| migrate -->|completed| app
    migrate -->|completed| seed
    app -->|healthy| k6
```

## Data model

```mermaid
erDiagram
    USERS ||--o{ CLIENTS : "is assigned"
    USERS ||--o{ TEAMS : "leads"
    TEAMS ||--o{ TEAM_MEMBERS : has
    USERS ||--o{ TEAM_MEMBERS : "is member"
    CLIENTS ||--o{ PROJECTS : "orders"
    TEAMS ||--o{ PROJECTS : delivers
    USERS ||--o{ PROJECTS : owns
    PROJECTS ||--o{ PROJECT_STAGE_HISTORY : "moves through"
    PROJECTS ||--o{ PROJECT_COMMENTS : has
    USERS ||--o{ PROJECT_COMMENTS : writes
    PROJECT_STAGE_TRANSITIONS }o--o{ PROJECTS : "allows stage changes of"

    USERS {
        int id PK
        varchar login UK
        nvarchar display_name
        varchar role "ADMIN | MANAGER | SALES"
        varchar password_hash
        bit is_active
        int failed_login_count
        datetime2 locked_until
        rowversion row_version
    }
    CLIENTS {
        bigint id PK
        nvarchar name
        char nip UK "10 digits"
        varchar email
        nvarchar city
        varchar status "LEAD | ACTIVE | INACTIVE"
        int assigned_user_id FK
        rowversion row_version
    }
    TEAMS {
        int id PK
        nvarchar name UK
        int lead_user_id FK "MANAGER"
    }
    TEAM_MEMBERS {
        int team_id PK, FK
        int user_id PK, FK
    }
    PROJECTS {
        bigint id PK
        bigint client_id FK
        int team_id FK
        int owner_user_id FK "member of the team"
        nvarchar name
        varchar stage
        date start_date
        date due_date
        decimal budget
        rowversion row_version
    }
    PROJECT_STAGE_TRANSITIONS {
        varchar from_stage PK
        varchar to_stage PK
    }
    PROJECT_STAGE_HISTORY {
        bigint id PK
        bigint project_id FK
        varchar from_stage
        varchar to_stage
        int changed_by
    }
    PROJECT_COMMENTS {
        bigint id PK
        bigint project_id FK
        int author_id FK
        nvarchar body
    }
```

Read models: `crm.v_projects` (project + client + team + owner, expanded into each query) and the indexed view
`crm.v_team_project_stats` (count and budget per team and stage, read with `WITH (NOEXPAND)`).

## Project stages

The allowed moves are rows of `crm.project_stage_transitions`; `app.project_change_stage` refuses anything else
with error 51902 (HTTP 409).

```mermaid
stateDiagram-v2
    [*] --> NEW
    NEW --> ACCEPTED
    NEW --> DECLINED
    ACCEPTED --> ACTIVE
    ACCEPTED --> DECLINED
    ACTIVE --> ON_HOLD
    ON_HOLD --> ACTIVE
    ACTIVE --> CLOSED
    ON_HOLD --> CLOSED
    CLOSED --> [*]
    DECLINED --> [*]
```

## Login

```mermaid
sequenceDiagram
    autonumber
    participant C as Client
    participant S as Spring Security
    participant A as AuthController
    participant D as SQL Server
    C->>S: GET /api/auth/csrf
    S-->>C: 204 + cookie XSRF-TOKEN
    C->>A: POST /api/auth/login {login, password} + header X-XSRF-TOKEN
    A->>D: EXEC app.user_get_for_login @login
    D-->>A: id, role, password_hash, is_active, locked_until
    A->>A: PasswordEncoder.matches (bcrypt), locked / disabled checks
    alt wrong password
        A->>D: EXEC app.user_login_failed (locks after N failures)
        A-->>C: 401 "Invalid login or password." (same for every failure)
    else success
        A->>D: EXEC app.user_login_succeeded
        A->>A: new session id, SecurityContext in HttpSession
        A-->>C: 200 {id, login, role} + cookie JSESSIONID
    end
```

## A write with a business error

```mermaid
sequenceDiagram
    autonumber
    participant C as Client
    participant P as ProjectController
    participant R as ProjectRepository
    participant D as app.project_change_stage
    participant H as ApiExceptionHandler
    C->>P: POST /api/projects/42/stage {stage: CLOSED, rowVersion}
    P->>R: changeStage(actor.id, 42, body)
    R->>D: EXEC app.project_change_stage @actor_id, @id, @to_stage, @comment, @row_version
    D->>D: actor active? project visible? row_version current? transition allowed?
    alt rule broken
        D-->>R: THROW 51902 'This stage change is not allowed.'
        R-->>H: DataAccessException (SQL error 51902)
        H-->>C: 409 ProblemDetail {detail, errorNumber: 51902}
    else ok
        D->>D: UPDATE projects, INSERT stage history (+ comment), one transaction
        D-->>R: row of crm.v_projects
        R-->>C: 200 ProjectResponse (new rowVersion)
    end
```

## Performance test

```mermaid
flowchart LR
    seed["./start.sh --seed<br/>EXEC seed.run<br/>5M clients, 5M projects,<br/>2M comments, 5000 users"]
    k6["./start.sh --k6<br/>200 VUs: login, search,<br/>details, writes"]
    reads["perf/sql: logical reads<br/>of each procedure"]
    results["perf/results/&lt;date&gt;-&lt;scenario&gt;/<br/>summary.json, summary.txt, REPORT.md"]
    seed --> k6 --> results
    seed --> reads --> results
```
