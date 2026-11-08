# 0012. The application reports on itself: HTTP answers, log, database, queues

Status: Accepted
Date: 2026-11-08

## Context

Administrators should see how the application answers, what it logs, how the database is doing and whether its
background work keeps up - without a separate log stack (Halcyon's ADR-0011, spec 010). The database login of the
application may only execute procedures (ADR-0002), yet server state lives in DMVs that need VIEW SERVER STATE.

## Decision

- **Recorded, never written from the request.** A servlet filter first in the chain records every answer (method,
  path without the query string, status as the client got it, time, user, a trace id also put into the log MDC); a
  Logback appender takes the log from `CRM_MONITORING_LOG_LEVEL` (INFO) up, except the monitoring's own entries. Both
  only add to a bounded in-memory queue (`CRM_MONITORING_QUEUE_CAPACITY`, 10 000); a full queue drops and counts.
  Probes and static files are skipped.
- **Written in batches.** `MonitoringWriter` drains the queues every `CRM_MONITORING_FLUSH_INTERVAL` (2 s) and at
  shutdown, `CRM_MONITORING_WRITE_BATCH_SIZE` (500) entries per `EXEC app.monitoring_*_write` (a JSON array, one
  INSERT). A refused batch is dropped and counted, never retried, so a database outage cannot grow memory.
- **Retention:** `MonitoringCleanup` runs after the start and every `CRM_MONITORING_CLEANUP_INTERVAL` (1 h), deleting
  rows older than `CRM_MONITORING_RETENTION` (14 days) in batches of `CRM_MONITORING_CLEANUP_BATCH_SIZE`. Idempotent:
  replicas need no lock.
- **Tables** `crm.http_requests` and `crm.app_logs` with indexes on time and on (status | level, time).
- **System pages for ADMIN only** (CRM has roles, Halcyon had none): status (health of the database and the bucket,
  answers by outcome per hour or day, average and p95, codes, the most frequent failures, the list of answers, the
  effective settings with their variable names - never a secret), the log, the database (server, size, sessions with
  blocking marked, tables, the event store) and the queues with their jobs and "run now". Spring Security and every
  procedure check the role.
- **Module signing for the DMVs.** `infrastructure/sql/init.sql` (as sa) creates the certificate `crm_monitoring` in
  master with a login holding VIEW SERVER STATE, and a copy in the database whose private key is protected by the
  database master key. Flyway's `afterMigrate` callback signs `app.monitoring_db_overview`, `_sessions` and `_tables`
  after every migration (CREATE OR ALTER drops a signature). The permission exists only while those procedures run;
  the application login itself still sees only its own session (tested).

## Consequences

Plus: one place to look, the same database, no extra service; answers and logs never wait for an INSERT.
Minus: entries in a queue are lost on a crash (up to 2 s); a deployment without `init.sql` must create the certificate
itself, otherwise the database page shows only what the application login may see.

## Alternatives considered

- **A log stack (Loki, Seq) or OpenTelemetry to a collector:** the better answer once the platform has one; the console
  log stays, so adding it later changes nothing here.
- **GRANT VIEW SERVER STATE to the application login, or TRUSTWORTHY ON:** simpler, but gives the application far more
  than three procedures need.
- **Writing from the request:** every page would wait for an INSERT, and a slow database would slow every page.
