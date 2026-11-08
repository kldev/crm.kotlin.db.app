# crm.kotlin.db.app

A small CRM: users, clients, teams and the projects that teams deliver for clients, with stages and comments.
**Kotlin + Spring Boot 4** for the HTTP API and identity, **all data logic in plain T-SQL procedures** on
**SQL Server 2025 Express**. No ORM, no generated endpoints: every endpoint is written by hand and calls exactly
one procedure with `EXEC app.<procedure>`.

- Diagrams: [docs/diagrams.md](docs/diagrams.md)
- Decisions: [docs/adr/](docs/adr/README.md)
- Performance: [perf/README.md](perf/README.md)

## Web app

A React app (Vite, HeroUI v3, TanStack Router/Query/Form) in `frontend/`, styled with the Ambit Obsidian theme,
served by the same Spring Boot application: open <http://127.0.0.1:8088/> after `./start.sh`.

- Overview (overdue and due-soon projects, latest clients), clients with prefix search and filters in the URL,
  client details with its projects, projects with stage, team and overdue filters, project details with the stage
  path, stage changes with a comment, comments and stage history, teams with delivery statistics from the indexed
  view and membership, users (ADMIN/MANAGER).
- The Docker image builds the app in a Node stage; for work on the front end see
  [Local development](#local-development).

## How it works

| Layer | What it does |
|---|---|
| Spring Security | login (JSON), session cookie, CSRF cookie, coarse role rules |
| Controllers (`app/src/main/kotlin/crm/*/…Controller.kt`) | request validation, paging cursors, one repository call |
| Repositories (`…Repository.kt`) | one method = one `EXEC app.<procedure>` through `JdbcClient` |
| `app` schema (`app/src/main/resources/db/migration/R__app_*.sql`) | every rule: validation, visibility, state changes, concurrency |
| `crm` schema (`V1__…`, `V3__…`) | tables, the view `crm.v_projects`, the indexed view `crm.v_team_project_stats` |

The application's database login has **only** `EXECUTE` on schema `app` (ADR-0002). `./gradlew check` fails if an
ORM or query mapper reaches the classpath.

## Local development

### Requirements

| Tool | Needed for |
|---|---|
| Docker with compose v2 | the whole stack (SQL Server, migrations, app) - enough to just run the app |
| JDK 25 | `./gradlew build` / tests (Testcontainers, so Docker must be running) and running the API from the IDE |
| Node 22 + corepack (Yarn 4.18 from `packageManager`) | front-end development (`frontend/`) |

The SQL Server image is `linux/amd64`; on Apple Silicon enable Rosetta emulation in Docker Desktop.

### 1. First start (everything in Docker)

```bash
cd infrastructure
cp .env-sample .env   # fill in every empty password (strong: 8+ chars, upper/lower case, digit, symbol; no ')
./start.sh            # mssql -> db-init (database, logins) -> migrate (Flyway) -> app
```

Then open:

- web app: <http://127.0.0.1:8088/> (port `CRM_HTTP_PORT`)
- API docs: <http://127.0.0.1:8088/swagger-ui.html>, OpenAPI: `/v3/api-docs`
- SQL Server: `127.0.0.1,14333` (`CRM_DB_HOST_PORT`), login `sa` / `MSSQL_SA_PASSWORD` (e.g. Azure Data Studio,
  DataGrip, `sqlcmd`)

Log in as `CRM_ADMIN_LOGIN` / `CRM_ADMIN_PASSWORD` (created on the first start). The database starts empty.

### 2. Test data (optional)

```bash
CRM_SEED_CLIENTS=10000 CRM_SEED_PROJECTS=10000 CRM_SEED_COMMENTS=5000 ./start.sh --seed   # small, seconds
./start.sh --seed                                                                         # full set, ~13 min
```

After the seed log in as `perf.sales.0001`, `perf.manager.0001` or `perf.admin.0001` with `CRM_SEED_PASSWORD`.
The seed runs only on an empty database (error 51060 otherwise); start over with `./start.sh --clean --seed`.

### 3. Day to day

| Task | Command |
|---|---|
| rebuild and restart after a Kotlin or SQL change (migrations run again) | `infrastructure/start.sh` |
| stop everything (data stays in the `mssql-data` volume) | `infrastructure/start.sh --down` |
| drop the database and start from zero | `infrastructure/start.sh --clean` |
| build, tests, ORM guard | `./gradlew build` |
| front-end lint and format | `cd frontend && yarn check` / `yarn format` |

### Front end with hot reload

Keep the stack running (`./start.sh`), then:

```bash
cd frontend
corepack enable
yarn install
yarn dev              # http://127.0.0.1:5173, /api and /v3 proxied to http://127.0.0.1:8088
```

The proxy keeps one origin, so the session and `XSRF-TOKEN` cookies work as in production. A different API
address: `CRM_API_URL=http://127.0.0.1:8080 yarn dev`. After changing an endpoint, regenerate the client with the
new API running: `yarn api:gen` (orval from `/v3/api-docs`, files in `src/api/`).

### API from the IDE (debugging Kotlin)

Run the database and migrations in Docker, the API from IntelliJ or Gradle:

```bash
cd infrastructure && ./start.sh && docker compose --env-file .env stop app && cd ..
set -a; . infrastructure/.env; set +a
export CRM_DB_URL="jdbc:sqlserver://127.0.0.1:${CRM_DB_HOST_PORT};databaseName=${CRM_DB_NAME};encrypt=true;trustServerCertificate=true"
PORT=8088 ./gradlew :app:bootRun
```

In IntelliJ set the same variables in the Spring Boot run configuration of the application (`CRM_DB_URL`, `CRM_DB_APP_USER`,
`CRM_DB_APP_PASSWORD`, `CRM_ADMIN_LOGIN`, `CRM_ADMIN_PASSWORD`, `PORT=8088`). With `PORT=8088` `yarn dev` works
without changes. Migrations (`R__app_*.sql`, `V*__*.sql`) are applied by the `migrate` container, so after a SQL
change run `infrastructure/start.sh` again. To serve the built web app from `bootRun`, run
`frontend/build-to-resources.sh` first (copies `dist/` to `app/src/main/resources/static`, git-ignored).

### Calling the API with curl

```bash
B=http://127.0.0.1:8088
curl -s -c j -b j -o /dev/null $B/api/auth/csrf
X=$(awk '$6=="XSRF-TOKEN"{print $7}' j)
curl -s -c j -b j -H "X-XSRF-TOKEN: $X" -H 'Content-Type: application/json' \
     -d '{"login":"perf.sales.0001","password":"<CRM_SEED_PASSWORD>"}' $B/api/auth/login
curl -s -b j "$B/api/clients?namePrefix=Zielony&size=5"
curl -s -b j "$B/api/projects?overdue=true&size=5"
```

## Endpoints

| Method and path | Procedure | Who |
|---|---|---|
| `GET /api/auth/csrf` | - | anyone |
| `POST /api/auth/login` | `user_get_for_login`, `user_login_succeeded` / `user_login_failed` | anyone |
| `POST /api/auth/logout`, `GET /api/auth/me` | - | logged in |
| `POST /api/auth/password` | `user_get_for_login`, `user_set_password` | logged in |
| `GET /api/users` | `user_list` | ADMIN, MANAGER |
| `POST /api/users`, `PUT /api/users/{id}/role`, `/active`, `/password` | `user_create`, `user_change_role`, `user_set_active`, `user_set_password` | ADMIN |
| `GET /api/clients` | `client_search` | all (SALES: own clients) |
| `GET/POST/PUT/DELETE /api/clients[/{id}]` | `client_get`, `client_create`, `client_update`, `client_delete` | all; delete: MANAGER, ADMIN |
| `GET /api/projects` | `project_search` (filters: stage, team, client, owner, overdue, due range) | all (SALES: own / team / client projects) |
| `GET/POST/PUT /api/projects[/{id}]` | `project_get`, `project_create`, `project_update` | all visible |
| `POST /api/projects/{id}/stage` | `project_change_stage` | all visible |
| `GET /api/projects/{id}/stages` | `project_stage_history_list` | all visible |
| `GET/POST /api/projects/{id}/comments` | `project_comment_list`, `project_comment_add` | all visible |
| `GET/POST /api/teams`, `GET /api/teams/{id}/members`, `GET /api/teams/{id}/stats` | `team_list`, `team_create`, `team_member_list`, `team_project_stats` | all; create: ADMIN |
| `POST/DELETE /api/teams/{id}/members[/{userId}]` | `team_member_add`, `team_member_remove` | ADMIN, team lead |

Lists are keyset-paged: pass `nextCursor` from a page as `cursor` for the next one. Updates need the
`rowVersion` from the last read (409 when someone changed the row in the meantime).

## Error catalogue

Procedures `THROW` these numbers; the API returns them as RFC 9457 ProblemDetail with `errorNumber`.

| Number | Meaning | HTTP |
|---|---|---|
| 50001 | actor not passed (bug) | 500 |
| 51010-51013 | client: name, NIP (10 digits), e-mail, status | 400 |
| 51014 | page size outside 1-200 | 400 |
| 51015, 51016, 51019, 51020 | user: login, role, display name, password | 400 |
| 51017 | client can be assigned only to an active sales user | 400 |
| 51018 | cannot change own role or deactivate yourself | 400 |
| 51030-51034 | project: name, stage, dates, budget, comment text | 400 |
| 51035-51038 | team: lead must be an active manager, name, owner must be a team member, member must be active | 400 |
| 51050, 51060 | seed: invalid parameter, database already seeded | 400 |
| 51301 | role not allowed | 403 |
| 51302 | own account not active | 403 |
| 51303 | sales user works only on own clients | 403 |
| 51401-51404 | client, user, project, team not found (or not visible) | 404 |
| 51901 | `rowVersion` changed by someone else | 409 |
| 51902 | stage change not allowed / closed project | 409 |
| 51904 | client has projects, cannot be deleted | 409 |
| 51905 | member still owns open projects of the team | 409 |
| 2601, 2627 | duplicate (login, NIP, team name) | 409 |

## SQL Server 2025 Express

Express is used on purpose (`MSSQL_PID=Express` in `infrastructure/docker-compose.yml`). Its limits shape the
results:

| Limit | Value |
|---|---|
| Database size | 50 GB per database |
| Buffer pool | about 1.4 GB |
| Compute | the lesser of 1 socket or 4 cores |
| Indexed views | not matched automatically; queries use `WITH (NOEXPAND)` |

## Seed

One seed, default values below, each configurable in `infrastructure/.env` (`CRM_SEED_*`). Deterministic for the
same values and `CRM_SEED_RANDOM_SEED`.

| Data | Default |
|---|---|
| Users | 5 000: 10 ADMIN, 490 MANAGER, 4 500 SALES |
| Teams | 900 (5 SALES each, led by managers) |
| Clients | 5 000 000 |
| Projects | 5 000 000 (+ 5 000 000 stage history rows) |
| Comments | 2 000 000 |

Measured with the defaults (2026-11-08, laptop: 16 cores, 30 GB RAM, Docker; SQL Server 2025 Express RTM-CU10):

| Measure | Value |
|---|---|
| Seed time | 798 s (about 13 min) |
| Database files after the seed | 7.6 GB (data 2.4 GB, indexes 3.5 GB) - about 15% of the 50 GB Express limit |
| Largest tables | projects 2.5 GB, clients 2.4 GB, stage history 0.5 GB, comments 0.4 GB |

## Performance

200 virtual users of mixed traffic for 13 minutes on the full data set, SQL Server Express on a laptop:

| Run | p95 | p99 | Errors | Requests/s |
|---|---:|---:|---:|---:|
| baseline | 56.1 ms | 81.2 ms | 0.00% | 334 |
| after read indexes (V4) | **8.5 ms** | **10.4 ms** | 0.00% | 338 |

Details, per-endpoint latencies and logical reads per procedure: [perf/README.md](perf/README.md).

## Tests

`./gradlew build` runs 41 tests on a real SQL Server 2025 Express (Testcontainers, the same image as compose):
architecture rules (no SQL text in Kotlin, only `EXEC app.*`, no ORM imports), database permissions (the app login
gets error 229 on tables and on `seed`), login and lockout, clients, projects, stages, comments and the indexed view
over HTTP, and the seed.

## Configuration

All settings are environment variables (see `infrastructure/.env-sample` and `app/src/main/resources/application.yml`):
database URL and logins (`CRM_DB_*`), pool size (`CRM_DB_POOL_SIZE`), session timeout (`CRM_SESSION_TIMEOUT`),
lockout (`CRM_LOGIN_MAX_FAILED`, `CRM_LOGIN_LOCK_MINUTES`), first admin (`CRM_ADMIN_*`), seed (`CRM_SEED_*`).

## Build

```bash
./gradlew build            # compile, tests, verifyNoOrm
docker build -t crm-app .  # the image used by compose
```

## License

[MIT](LICENSE)
