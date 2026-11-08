# 0010. Report data of desk tickets, reports and exports

Status: Accepted
Date: 2026-11-08

## Context

Teams need numbers from their tickets: HR abroad a Limosa number and the dates of a posting, HR a new employee's PESEL,
finance an invoice amount and account, marketing a campaign budget (Halcyon's spec 008 / ADR-0009). The reports and
their XLSX / PDF / CSV exports are how those numbers leave the desk.

## Decision

- **Fields are catalog data** (`V7`): `crm.desk_fields` (key, Polish label, kind), `crm.desk_field_options` (choices,
  favourites first), `crm.desk_subcategory_fields` (which fields a subcategory collects, in order, and which are
  required). A key is stored on tickets: never renamed or reused, one meaning in every subcategory - only "required"
  differs. 44 fields copied from Halcyon.
- **Kinds and rules live in `crm.desk_fields_check`** (ADR-0002): text, date (`yyyy-mm-dd`), e-mail, choice,
  multi-choice (stored `A, B` in list order), amount (spaces and a decimal comma accepted, stored `1234.56`, at most
  2 decimals, under 10^12), IBAN (mod 97, a 26-digit Polish number gets `PL`), count (1-10000), ticket number
  (`HAL-` + 8 hex). At most 200 characters. The identity document and its number go together: a PESEL needs a valid
  check digit (1-3-7-9), an ID card number is stored without spaces in capitals, "no documents" has no number.
- **Stored in the stream:** the values given at the report travel in `TicketReported.fields`; later changes are
  `TicketFieldsUpdated` with only the changed fields and the label at that moment (any agent, any state, like a
  comment). `crm.ticket_fields` is the read model. The update takes the whole set; an empty value clears a field,
  a required one cannot be cleared; nothing changed stores nothing.
- **Reports** read the read model and the events: five category reports (slugs as in Halcyon: kadry-polska,
  kadry-zagranica, finanse, rekrutacja, marketing) for whole Warsaw days, with market / subcategory / open-resolved
  filters - fixed columns and then one column per report field that has a value in at least one row; the agents'
  report counts `TicketTaken` / `TicketResolved` (late from the event) per agent in this week, month and 3 months
  (or the periods before), plus what is in progress now.
- **One table, three formats.** `DeskReports` builds a typed `ReportTable` (text, date, instant, number, amount) that
  the page shows and every export writes: XLSX with Apache POI (real dates and numbers, frozen header, autofilter),
  PDF with OpenPDF (A4 landscape, A3 over 13 columns, header on every page, Lato embedded for Polish letters), CSV for
  a Polish Excel (`;`, UTF-8 BOM, CRLF, decimal comma, `'` before a value starting with = + - @). `lang=pl|en` names
  the headers and translates catalog values (`desk/catalog-en.json`, generated from the same data as the web app's
  `catalogEn.ts`); what people typed is never translated.
- **Linked campaigns:** a recruitment ticket lists marketing tickets whose `related-ticket` is its number, and "order a
  campaign" opens the new-ticket form filled in from the link.

## Consequences

Plus: one rule set for the form, the public page and the update; the timeline says what changed; the exports equal the
page. Minus: the validation is long T-SQL (IBAN and PESEL included), and the English catalog exists twice (web app and
server resources), both generated from one source.

## Alternatives considered

- **Fields as a JSON document on the ticket:** simpler to store, but the category reports and the linked campaigns
  would scan JSON instead of seeking `(field_key, value)`.
- **Exports in the browser:** no libraries on the server, but PDF and real XLSX types in JavaScript, and the same
  table built twice.
