# crm.kotlin.db.app

A small CRM: users, clients, teams and the projects that teams deliver for clients, with stages and comments.
**Kotlin + Spring Boot 4** for the HTTP API and identity, **all data logic in plain T-SQL procedures** on
**SQL Server 2025 Express**. No ORM, no generated endpoints: every endpoint is written by hand and calls exactly
one procedure with `EXEC app.<procedure>`.

- Diagrams: [docs/diagrams.md](docs/diagrams.md)
- Decisions: [docs/adr/](docs/adr/README.md)
- Performance: [perf/README.md](perf/README.md)

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

## Run locally

Requirements: Docker with compose. JDK 25 only to build outside Docker.

```bash
cd infrastructure
cp .env-sample .env        # set the passwords (SQL Server needs strong ones; no single quote)
./start.sh                 # mssql -> db-init -> migrate (Flyway) -> app
./start.sh --seed          # the performance data set (several minutes, see below)
./start.sh --clean --seed  # from an empty database
./start.sh --down
```

API: <http://127.0.0.1:8088/swagger-ui.html> (port `CRM_HTTP_PORT`). Log in as `CRM_ADMIN_LOGIN` /
`CRM_ADMIN_PASSWORD`, or after the seed as `perf.sales.0001` (or `perf.manager.0001`, `perf.admin.0001`) with
`CRM_SEED_PASSWORD`.

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
