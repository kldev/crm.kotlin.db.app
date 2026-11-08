# crm.kotlin.db.app

A small CRM: users, clients, teams and the projects that teams deliver for clients, with stages and comments - and a
**service desk** (ported from Halcyon): requests to the company's teams, one event stream per ticket (ADR-0007).
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
- Service desk: the pool, my tickets and all tickets (filters in the URL, open by deadline then resolved, total on
  request), counters of overdue / due soon / pool / mine in the top bar, a new ticket registered by an agent (dated
  back up to 30 days), the ticket page (take, resolve, hand over, return, priority with the new deadline, the person
  doing the work, comments, attachments with image thumbnails, the timeline from the event stream), agents and people. The public form
  <http://127.0.0.1:8088/report> needs no sign-in, takes files with the report and gives the requester the ticket
  number. Attachments live in RustFS (S3, console <http://127.0.0.1:19001>), ADR-0009.
- Report data per topic (PESEL, IBAN, amounts, dates, choices; ADR-0010) on the forms and the ticket page, five
  category reports and the agents' work with XLSX, PDF and CSV exports, campaigns linked to recruitment tickets.
- Charts (ADR-0011): flow in and out, backlog, deadlines kept, SLA use per priority, by category, the queue now,
  agents and a weekday x hour heatmap, each with a table view; reports and charts use the whole screen width.
- System pages for administrators (ADR-0012): status with HTTP answers per hour or day, codes and failures, the log,
  the database (sessions with blocking, tables, the event store) and the monitoring queues with "run now".
- Offers (ADR-0013): for a client from three templates (Sales Budownictwo, Sales IT, Sales Outsourcing), edited as a
  draft with lines and VAT, sent, accepted or rejected, printed as a Halycon Inc. PDF in the Obsidian look that closes
  with the salesperson's phone and e-mail ("My contact" in the account menu).
- Tasks (ADR-0014): who does what from which day to which day, on a month calendar or a timeline by person and
  department, with "only mine" / "my department" / all, open or done - no statuses, no kanban; administrators set
  users' departments.
- Sales pipeline (ADR-0015): a kanban board of deals - Kontakt, Potrzeba potwierdzona, Oferta, Negocjacje, Wygrana,
  Przegrana - with drag and drop, column sums, the weighted forecast, won deals and the win rate.
- Multi-company (ADR-0016): the group's own companies (Halycon Inc., Budownictwo, IT, Staff) deliver projects and
  sign offers - a company per project (changed only while NEW) and per offer (its template's by default), filters on
  both lists, the offer PDF under the signing company's name; administrators keep the companies on "Companies".
- My day for salespeople (ADR-0017): follow-ups due (overdue first), started tasks and deals with no next step on one
  screen; a deal page with the next step and the activity log (calls, e-mails, meetings...); tasks of a deal log on
  it when done.
- Fleet (ADR-0018): the companies' cars with status by hand and its history, financing (bought / leasing), inspection
  and insurance deadlines, repair shops and leasing companies, and handovers to people without overlaps; "my car" on
  My day.
- Business trips (ADR-0019): client visits, trade fairs, project sites; the settlement under the Polish rules (per
  diems by length less meals, lump sums, mileage, expenses, advance) and its way - submitted, approved or returned,
  paid.
- Reports keep their first column in place while scrolling sideways; ticket reports have a row menu that opens the
  ticket. Dates are picked in the app's own date picker (typed or from a calendar), not the browser's.
- Polish and English with a PL / EN switch (ADR-0008); Polish is the default.
- The Docker image builds the app in a Node stage; for work on the front end see
  [Local development](#local-development).

## How it works

| Layer | What it does |
|---|---|
| Spring Security | login (JSON), session cookie, CSRF cookie, coarse role rules |
| Controllers (`app/src/main/kotlin/crm/*/…Controller.kt`) | request validation, paging cursors, one repository call |
| Repositories (`…Repository.kt`) | one method = one `EXEC app.<procedure>` through `JdbcClient` |
| `app` schema (`app/src/main/resources/db/migration/R__app_*.sql`) | every rule: validation, visibility, state changes, concurrency |
| `crm` schema (`V0001__…`, `V0003__…`, `V0005__…`) | tables, the view `crm.v_projects`, the indexed view `crm.v_team_project_stats`, the desk's event stream `crm.ticket_events` and its read model `crm.tickets` |

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
./start.sh            # mssql -> db-init -> migrate (Flyway) -> app; rustfs -> rustfs-init (bucket) -> app
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
It also seeds the service desk (`seed.desk_run`: ten agents such as `anna.nowak`, 40 people and Halcyon's 238 ticket
histories replayed at their moments in the past, `CRM_SEED_DESK_STORIES`). The same step seeds the newer modules at a smaller scale - about 10 000 records each: tasks, deals with ~25 000
activities and their next steps, offers with their lines, a fleet of 2 000 cars with ~10 000 handovers, and ~10 000 business trips - each
only into an empty table.
That part is idempotent; for a database seeded before the desk existed run only it:
`CRM_SEED_DESK_ONLY=true docker compose --profile seed run --rm seed`.

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
| `GET /api/desk/catalog` | `desk_catalog_list`, `desk_priority_list` | all |
| `GET /api/desk/tickets`, `/count`, `/counters` | `desk_ticket_search`, `desk_ticket_count`, `desk_ticket_counters` | all |
| `POST /api/desk/tickets`, `GET /api/desk/tickets/{id}`, `/by-number/{number}`, `/{id}/events` | `desk_ticket_report`, `desk_ticket_get`, `desk_ticket_find`, `desk_ticket_event_list` | all |
| `POST /api/desk/tickets/{id}/take`, `/hand-over`, `/return`, `/priority`, `/resolve`, `/comments`, `/handler` | `desk_ticket_take`, `_hand_over`, `_return`, `_change_priority`, `_resolve`, `_comment`, `_assign_handler` | all (the rules of the assignee in the procedures) |
| `GET/POST /api/desk/tickets/{id}/attachments`, `GET …/attachments/{attachmentId}` | `desk_attachment_list`, `desk_attachment_check` + `desk_ticket_attach`, `desk_attachment_get` | all |
| `GET/PUT /api/desk/tickets/{id}/fields`, `GET …/linked` | `desk_ticket_field_list`, `desk_ticket_update_fields`, `desk_ticket_linked_list` | all |
| `GET /api/desk/reports/categories/{slug}[/export.{csv,xlsx,pdf}]`, `GET /api/desk/reports/agents[/export.…]` | `desk_report_category`, `desk_report_agents`, `desk_report_period_list` | all |
| `GET /api/desk/charts?range=DAYS_7\|DAYS_30\|WEEKS_12&categoryKey=` | `desk_chart_tickets` | all |
| `GET /api/system/status`, `/requests`, `/logs`, `/database`, `/queues`, `POST /api/system/jobs/{name}/run` | `monitoring_http_*`, `monitoring_request_list`, `monitoring_log_list`, `monitoring_db_*` (signed) | ADMIN |
| `GET/POST /api/offers`, `/count`, `/templates`, `GET/PUT/DELETE /api/offers/{id}`, `/items`, `POST …/status`, `GET …/pdf` | `offer_search`, `offer_count`, `offer_template_list`, `offer_get`, `offer_create`, `offer_update`, `offer_delete`, `offer_item_list`, `offer_change_status` | all (SALES: offers of own clients) |
| `GET/PUT /api/auth/me/contact`, `/api/users/{id}/contact` | `user_contact_get`, `user_contact_update` | own; others: ADMIN (read: MANAGER too) |
| `GET /api/tasks?from&to&scope=MINE\|DEPARTMENT\|ALL&department&done`, `GET/POST/PUT/DELETE /api/tasks/{id}`, `POST …/done` | `task_list`, `task_get`, `task_create`, `task_update`, `task_delete`, `task_set_done` | all (change: author or assignee for SALES) |
| `GET/POST /api/deals?scope=MINE\|ALL&ownerUserId&search&closedDays&perStage`, `/stages`, `/summary`, `GET/PUT/DELETE /api/deals/{id}`, `POST …/move` | `deal_board`, `deal_board_summary`, `deal_stage_list`, `deal_get`, `deal_create`, `deal_update`, `deal_delete`, `deal_move` | all (SALES: deals of own clients) |
| `GET/POST /api/legal-entities`, `GET/PUT /api/legal-entities/{id}` | `legal_entity_list`, `legal_entity_get`, `legal_entity_save` | read: all; write: ADMIN |
| `GET /api/deals/activity-types`, `GET/POST /api/deals/{id}/activities`, `PUT /api/deals/{id}/next-step`, `GET /api/sales/follow-ups?until&scope`, `/without-next-step`, `GET /api/tasks/agenda?until&doneSince` | `deal_activity_type_list`, `deal_activity_list`, `deal_activity_add`, `deal_set_next_step`, `sales_follow_ups`, `sales_without_next_step`, `task_agenda` | all (SALES: deals of own clients) |
| `GET/POST /api/fleet/cars`, `/count`, `GET/PUT/DELETE /api/fleet/cars/{id}`, `PUT …/financing`, `POST …/status`, `GET …/status-history`, `GET/POST …/handovers`, `POST /api/fleet/handovers/{id}/return`, `/undo-return`, `/cancel`, `PUT /api/fleet/handovers/{id}`, `GET /api/fleet/my`, `/statuses`, `/makes`, `GET/POST/PUT /api/fleet/partners` | `car_list`, `car_count`, `car_get`, `car_save`, `car_delete`, `car_set_financing`, `car_change_status`, `car_status_history`, `car_handover_*`, `car_my`, `car_status_list`, `car_make_list`, `fleet_partner_list`, `fleet_partner_save` | read: all; write: ADMIN, MANAGER |
| `GET/POST /api/trips?scope=MINE\|TO_APPROVE\|ALL&status&purpose&from&to`, `/count`, `/rates`, `GET/PUT /api/trips/{id}`, `GET/PUT …/expenses`, `POST …/status` | `trip_list`, `trip_count`, `trip_rate_list`, `trip_get`, `trip_create`, `trip_update`, `trip_expense_list`, `trip_expenses_save`, `trip_change_status` | own trips; all and approvals: ADMIN, MANAGER |
| `GET /api/departments`, `PUT /api/users/{id}/department` | `department_list`, `user_set_department` | all / ADMIN |
| `GET /api/desk/agents`, `/people` | `desk_agent_list`, `desk_person_list` | all |
| `GET /api/public/desk/catalog`, `/people`, `POST /api/public/desk/tickets` | `desk_catalog_list`, `desk_public_person_list`, `desk_ticket_report_public` | anyone (public form, 30 tickets/min) |

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
| 51100-51110 | desk ticket: title, description, category, subcategory (retired), priority, report date (future, > 30 days back), requester | 400 |
| 51111-51116 | desk: reason, comment, hand over to yourself, handler outside the department, list filter | 400 |
| 51120-51124 | attachment: no name, type not allowed, empty, over 20 MB, more than 10 per ticket | 400 |
| 51130-51146 | report data: field of another subcategory, required, length, date, e-mail, amount, IBAN, count, multi-choice, choice, ticket number, identity document and PESEL rules, no report data | 400 |
| 51150 | report period: from <= to, at most a year | 400 |
| 51160 | monitoring cleanup: cutoff and batch size | 400 |
| 51170-51178 | offer: title, template, validity, lines, currency, texts, no lines to send, contact, status filter | 400 |
| 51180-51184 | task: title, dates (end before start, over a year, window over 120 days), scope, department, description | 400 |
| 51190-51197 | deal: title, value, currency, expected close, offer of another client, board filter, stage, lost reason | 400 |
| 51200-51205 | company: name, legal name and address, NIP check digit, trading dates, contact, not trading on the day | 400 |
| 51210-51214 | activity type, note, moment (last 90 days, not future); next step both or neither; a task of a deal is for its client | 400 |
| 51220-51236 | car: name, year, plate, VIN, notes, VIN correction reason, financing, status day, repair shop; handover: dates, mileage and fuel, return day and mileage, cancel reason; filters; partner | 400 |
| 51237-51248 | trip: client, event, project, destination and country, dates, transport, meals and nights, advance, description, expenses, return note, scope | 400 |
| 51304 | sales user changes only tasks they created or are assigned | 403 |
| 51310-51313 | only the agent working on the ticket can hand it over, return it, resolve it, name its handler | 403 |
| 51410-51413 | ticket, person, agent, attachment not found | 404 |
| 51405 | offer not found (or not visible) | 404 |
| 51406 | task not found | 404 |
| 51407 | deal not found (or not visible) | 404 |
| 51408 | company not found | 404 |
| 51409, 51414 | car, handover not found | 404 |
| 51415 | business trip not found (or not yours) | 404 |
| 51910 | ticket already in progress with another agent (someone was faster) | 409 |
| 51911, 51912 | ticket already resolved / still in the pool (take it first) | 409 |
| 51913 | the ticket's stream changed meanwhile | 409 |
| 51908 | the delivering company changes only while the project is NEW | 409 |
| 51909 | a closed deal has no next step | 409 |
| 51928-51931 | trip: not editable now, settled after the return, not your own approval, step not allowed | 409 |
| 51920-51927 | fleet: not for sale / archived while handed over, archive only by an administrator, delete only if never handed over, car taken, person has a car, car for sale cannot go, handover not live, undo only on the day | 409 |
| 51906, 51907 | offer: only a draft is edited or deleted / status move not allowed | 409 |
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

`./gradlew build` runs the tests on a real SQL Server 2025 Express (Testcontainers, the same image as compose):
architecture rules (no SQL text in Kotlin, only `EXEC app.*`, no ORM imports), database permissions (the app login
gets error 229 on tables and on `seed`), login and lockout, clients, projects, stages, comments and the indexed view
over HTTP, the service desk (rules of every action, three agents taking one ticket at once, deadlines, lists in two
phases, the public form, attachments on a real RustFS: refused types, the limit of 10, refused uploads deleted from
the bucket, download headers), report data (every kind and the PESEL / IBAN rules, changes listed in the event),
the reports and their CSV / XLSX / PDF exports, the charts' numbers agreeing with each other and the lists, the
monitoring (answers and log recorded, admin only, the signed procedures seeing the server while the app login does
not), and the seed.

## Configuration

All settings are environment variables (see `infrastructure/.env-sample` and `app/src/main/resources/application.yml`):
database URL and logins (`CRM_DB_*`), pool size (`CRM_DB_POOL_SIZE`), session timeout (`CRM_SESSION_TIMEOUT`),
lockout (`CRM_LOGIN_MAX_FAILED`, `CRM_LOGIN_LOCK_MINUTES`), first admin (`CRM_ADMIN_*`), seed (`CRM_SEED_*`;
`CRM_SEED_DESK_STORIES`, and `CRM_SEED_DESK_ONLY=true` to add the desk to an already seeded database), dev login
(`CRM_DEV_LOGIN`), public desk form limit (`CRM_DESK_PUBLIC_REPORTS_PER_MINUTE`), attachments bucket (`CRM_S3_ENDPOINT`,
`CRM_S3_ACCESS_KEY`, `CRM_S3_SECRET_KEY`, `CRM_S3_BUCKET`, `CRM_S3_REGION`), monitoring (`CRM_MONITORING_ENABLED`,
`_QUEUE_CAPACITY`, `_FLUSH_INTERVAL`, `_WRITE_BATCH_SIZE`, `_RETENTION`, `_CLEANUP_INTERVAL`, `_CLEANUP_BATCH_SIZE`,
`_LOG_LEVEL`). The companies on offer PDFs are data, not settings: the "Companies" page (ADR-0016).

## Build

```bash
./gradlew build            # compile, tests, verifyNoOrm
docker build -t crm-app .  # the image used by compose
```

## License

[MIT](LICENSE)
