# 0016. The group's companies deliver projects and sign offers

Status: Accepted
Date: 2026-11-08

## Context

The business runs through several companies of one group: construction, IT and staffing each have their own company,
and the parent company signs the rest. A project is delivered, and an offer signed, by one of them; the offer PDF
must carry that company's name, address and tax id. Until now the company on the PDF was one set of settings
(ADR-0013). Ambit System solves the same with legal entities: the agency's own companies, distinct from its clients.

## Decision

- **`crm.legal_entities`** - the group's companies, not the clients: name, legal name, NIP (10 digits, check digit
  verified), EU VAT number, address, phone, e-mail, website, bank account, `active_from` and `active_to`. A company
  is closed by its last trading day and kept for history; it is never deleted. Four are seeded: Halycon Inc. (the
  company the settings used to name), Halycon Budownictwo, Halycon IT and Halycon Staff.
- **Projects**: `crm.projects.legal_entity_id` is required; the company must trade on the project's start date
  (51205) and changes only while the project is NEW (51908) - afterwards the delivering company is a fact. The
  projects before this decision belong to Halycon Inc. (filled by a default in the migration, then dropped); the seed
  spreads its projects over the four companies. The list filters by company (an index ending with the list's order).
- **Offers**: each template names its company (construction -> Budownictwo, IT -> IT, outsourcing -> Staff); a new
  offer takes it unless another trading company is chosen; a draft may change it. The PDF band, closing contact and
  footer are the signing company's - the `CRM_OFFER_COMPANY_*` settings are gone.
- **Who**: everybody reads the companies (pickers), ADMIN adds and changes them (51301). Users and clients do not
  belong to a company: anyone works for any of them, as in Ambit System.

## Consequences

Plus: one place for company data, the PDF follows the company that signs, reports can group by company. Minus: the
companies are data, so a new environment has to have them (the migration seeds four); nothing yet splits numbering
(offer numbers stay one sequence for the group).

## Alternatives considered

- **A company per user or per client:** simpler filters, but people and clients work across the group's companies.
- **Keep the company in settings:** one company only - exactly what the business outgrew.
