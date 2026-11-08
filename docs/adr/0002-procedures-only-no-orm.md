# 0002. Data access only through T-SQL procedures, no ORM

Status: Accepted
Date: 2026-11-08

## Context

The data rules (validation, visibility, state changes, concurrency) should live in one place and be easy to read.
No generic machinery: no endpoints generated from the database catalogue, no dispatcher "procedure name from URL".

## Decision

1. Every database call from the application is `EXEC app.<procedure> @param = :param, ...` through Spring's
   `JdbcClient`. Each procedure has one hand-written repository method; each endpoint has one hand-written
   controller method. No JPA/Hibernate, Spring Data, jOOQ, Exposed, MyBatis or other mapper.
2. Schemas: `crm` (tables, views, internal helper procedures), `app` (procedures for the application),
   `seed` (data seed). The application login has **only** `GRANT EXECUTE ON SCHEMA::app`; procedures reach the
   tables through ownership chaining. The migrator login (db_owner) is used by Flyway and the seed only.
3. Procedures start with `SET NOCOUNT, XACT_ABORT ON`, validate before writing and report broken rules with
   `THROW` numbers from one catalogue (README, `ProcedureErrors.kt`): 51000-51299 -> 400, 513xx -> 403,
   514xx -> 404, 519xx -> 409, 2601/2627 -> 409.
4. The actor is the `@actor_id` parameter, filled by the server from the authenticated session, never from the
   request body. Procedures re-read the actor's role and active flag on every call.
5. Writes return the changed row as a result set (not `OUTPUT` parameters): one calling style (`query`) for all
   procedures, which `JdbcClient` supports directly.
6. Optimistic concurrency with `rowversion`: updates take `@row_version`, a mismatch is 51901 (409); identical
   values do not write and keep the same `row_version`.
7. Lists use keyset pagination (`TOP (@page_size + 1)` after the last key) with an index ending in the sort key,
   never `OFFSET`. Optional filters use `OPTION (RECOMPILE)` so the plan fits the filters actually passed.
8. `./gradlew check` fails when an ORM or query mapper appears on the classpath (`verifyNoOrm`).

## Consequences

Plus: a rule change is a migration, the API code is mostly parameter lists; permissions are enforced by the
database even for a bug in the API.
Minus: more SQL to write by hand; `OPTION (RECOMPILE)` costs a compilation per search call (measured in the
performance report).

## Alternatives considered

- Views and table-valued functions read directly by the application: would need `SELECT` permission; rejected to
  keep a single access path.
- `OUTPUT` parameters with `SimpleJdbcCall`: a second calling style for no gain.
