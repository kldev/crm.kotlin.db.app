# 0009. Desk attachments in S3, recorded as events

Status: Accepted
Date: 2026-11-08

## Context

Requesters and agents attach screenshots, contracts, invoices and campaign material to tickets (as in Halcyon's
ADR-0008). The rules must stay in the procedures (ADR-0002); the bytes do not belong in SQL Server Express (its size
limit per database and its small buffer pool, and every backup would carry them).

## Decision

- The bytes go to a private S3 bucket (`CRM_S3_*`; RustFS `rustfs/rustfs:1.0.0` in compose, created by the one-shot
  `rustfs-init`), key `attachments/<uuid>`. The app streams files to signed-in agents; nothing is served by S3.
- The record is the event `TicketAttachmentAdded` in the ticket's stream; `crm.ticket_attachments` is its read model.
- The rules are data and procedures: `crm.desk_attachment_types` (extension -> type, inline or not; SVG and HTML are
  missing on purpose), `crm.desk_attachment_normalize` (no folders or control characters in the name, at most 200
  characters, type by extension - never the browser's claim, not empty, at most 20 MB), at most 10 per ticket, any state.
- Order of writing: `app.desk_attachment_check` per file (spares an upload that would be refused), the bytes to S3,
  then one transaction that checks everything again under the ticket's lock and appends the events. A refusal deletes
  the stored objects again; a crash between the two steps leaves an orphan object, never an event pointing at nothing.
- The public form sends the ticket and its files in one multipart request; the report and its attachments are one
  transaction (`app.desk_ticket_report_public @attachments`). An agent's new ticket uploads its files right after the
  report (the ticket exists, so a refused file is reported and nothing is lost).
- Download only for signed-in agents (`GET /api/desk/tickets/{id}/attachments/{attachmentId}`): images and PDF inline
  (or `download=true`), the rest as a file; always `X-Content-Type-Options: nosniff`, `Content-Security-Policy: sandbox`
  and `Cache-Control: private, max-age=3600`.
- The S3 client (AWS SDK for Java 2, JDK HTTP client) uses path-style URLs and checksums only when required
  (`WHEN_REQUIRED`): the SDK's default CRC32 trailers are not understood by every S3-compatible server.
- Readiness (`/actuator/health/readiness`) includes the bucket. A storage failure is 503 for the request.

## Consequences

Plus: the database stays small, the history shows every file, a script in a file cannot run in the app's origin.
Minus: one more service to run and back up; orphan objects after a crash need a cleanup job (not written: rare, and
harmless).

## Alternatives considered

- **Bytes in SQL Server (`varbinary(max)` / FILESTREAM):** one backup, but Express's 10 GB limit and the buffer pool.
- **Presigned upload straight from the browser:** no bytes through the app, but CORS on the bucket, and the procedure
  would see a file only after it is stored.
