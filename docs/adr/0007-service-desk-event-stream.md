# 0007. Service desk: a ticket is an event stream, decided by procedures

Status: Accepted
Date: 2026-11-08

## Context

The service desk of the Halcyon project (Marten event store on PostgreSQL, Blazor) is ported to this stack: requests to
the company's teams (IT, legal, marketing, HR in Poland and abroad, recruitment, finance, legalisation) go into one pool;
an agent takes one, works it, hands it over or gives it back, and resolves it, against a deadline set by its priority.
Halcyon kept the rules in a C# aggregate (decide, then fold) and the history in Marten's streams. Here every rule lives
in T-SQL procedures (ADR-0002), and there is no event store library.

## Decision

- **The stream is a table.** `crm.ticket_events (ticket_id, version, event_type, at, actor, data)`: append-only facts,
  `data` is the event as JSON (`ISJSON` check), the actor's name is a snapshot. `(ticket_id, version)` is the primary
  key, so two writers can never store the same version (`crm.desk_ticket_append` turns a duplicate into 51913,
  "someone was faster").
- **The read model is written with the event.** `crm.tickets` is the inline projection: every
  `app.desk_ticket_*` procedure appends the event and updates the row in one transaction, so a list is consistent right
  after the click. The timeline of a ticket is its stream (`app.desk_ticket_event_list`); the UI renders each event type.
- **Decide on the state under a lock.** A procedure reads the ticket row `WITH (UPDLOCK, HOLDLOCK)`
  (`crm.desk_ticket_lock`), checks the rules and appends. Two agents taking one ticket queue up: the second decides on the
  state the first left and is told who was faster (51910) - the same message Halcyon gave from its concurrency
  exception. A no-op (the same priority, the same handler) stores nothing.
- **Events:** TicketReported, TicketTaken, TicketHandedOver, TicketReturnedToPool, TicketPriorityChanged, TicketResolved
  (with `late`), TicketCommented, TicketHandlerAssigned; attachments and report fields follow in later steps.
- **Rules** (as in Halcyon): title 1-200, description 1-4000, comment 1-2000, reason up to 500; an active subcategory of
  the chosen category; the requester is a person XOR incognito; an agent may date a report back up to 30 days, never
  more than 5 minutes ahead; the public form reports now. Only the agent working on a ticket hands it over, returns it,
  resolves it or names its handler (from the category's department); anybody may change the priority of an open ticket
  and comment on any ticket.
- **Deadlines** (Halcyon ADR-0004): deadline = report date + SLA of the current priority (`crm.desk_priorities`:
  3 h, 8 h, 3 days, 7 days, calendar time 24/7). A priority change recomputes it from the report date; handover and
  return never move it. Overdue / due soon (< 60 min) are computed when read - the lists and counters use the database
  clock, the UI re-renders every 30 s - so no background job can be late. Resolved at or after the deadline is late
  for good. Times are stored in UTC and shown in Europe/Warsaw.
- **Agents are CRM users.** Any active user works tickets with their own login; there are no desk roles. Requesters
  and handlers are `crm.people`, who never sign in.
- **The public form** (`/report`, `/api/public/desk/**`, no sign-in) reads the catalog and names (no contacts) and
  creates tickets - nothing else. Picking a name is not authentication, accepted for an internal tool. CSRF applies;
  `CRM_DESK_PUBLIC_REPORTS_PER_MINUTE` (30) caps it per application instance (429).
- **The catalog is data from a migration** (8 categories, 63 subcategories, Polish names, stable keys copied from
  Halcyon): a key is never renamed or reused, a subcategory is retired with `is_active = 0`.
- **Lists** are keyset-paged in two phases: open tickets by `(deadline, id)`, then resolved ones by
  `(resolved_at DESC, id DESC)`; filtered indexes per list. The total is a separate count on request.
- The number given to the requester is `HAL-` and 8 random hex digits (unique index).
- **One clock for writes, `crm.desk_now()`:** the database clock - except for a `db_owner` (the seed, run with the
  migrator login), which may set `SESSION_CONTEXT 'desk.now'`. The seed replays Halcyon's 238 ticket histories
  (`desk/seed-tickets.json`, dumped from its seed data) step by step at their moments in the past through the very
  procedures the application calls (`seed.desk_replay`), so every rule holds and the charts and reports have a real
  history. The application login is never `db_owner` and cannot move the clock (tested).

## Consequences

Plus: one place for the rules (the procedures), the history is complete and immutable, the read model never lags, the
concurrency rule is visible in a dozen lines of T-SQL and covered by a test with three simultaneous agents.
Minus: decisions read the state from the projection, not by folding the stream, so the projection must stay correct -
it is only written by the same procedures that append the events. Rebuilding it from the stream would need a script.

## Alternatives considered

- **A Kotlin aggregate folding the stream (as in Halcyon), procedures only appending:** testable without a database,
  but breaks ADR-0002 (rules in two languages) and needs an expected-version round trip on every action.
- **CRUD tickets with a history table:** simpler, but the history becomes a second, optional write.
