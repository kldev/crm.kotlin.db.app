# 0013. Offers from templates, printed in the Obsidian look

Status: Accepted
Date: 2026-11-08

## Context

Sales prepares priced offers for CRM clients in three lines of business - construction, IT and staff outsourcing -
and sends them as a PDF under the company's name, Halycon Inc. When a salesperson writes the offer, the client should
see whom to call.

## Decision

- **An offer belongs to a client** (`crm.offers`, lines in `crm.offer_items`), numbered `OF/<year>/<nnnn>` per year in
  Warsaw time (`crm.offer_numbers`, the year's row locked while a number is taken). SALES works only on offers of
  their own clients (51405 / 51401), MANAGER and ADMIN on all - the client's visibility rule.
- **Three templates as data** (`crm.offer_templates`, `crm.offer_template_items`): Sales Budownictwo, Sales IT,
  Sales Outsourcing - name, document title, introduction and terms in Polish and English, a default validity and
  default lines. A new offer copies them in the user's language; from then on the offer owns its texts and lines, so a
  later change of a template never rewrites a sent offer.
- **Rules in the procedures:** a draft is edited as a whole (texts, currency PLN / EUR / USD, validity from today up to
  a year, at most 100 lines with a description, unit, quantity > 0, price with 2 decimals, VAT 0 / 5 / 8 / 23 %) with
  its `rowversion`; DRAFT -> SENT (with at least one line) -> ACCEPTED | REJECTED, SENT -> DRAFT for corrections;
  only a draft is deleted. Amounts are rounded per line, totals are sums of the rounded lines.
- **Contacts:** users get a job title, phone and e-mail (`app.user_contact_*`): one's own for everybody, anyone's for
  ADMIN. The PDF closes with the author's contact when the author is SALES, otherwise with the company's.
- **The PDF** (`OfferPdf`, OpenPDF): A4, an obsidian band with the company in Cormorant Garamond and a champagne rule,
  the client and details, the introduction, the lines with a linen head, the contact next to the totals (one block,
  never split), the terms, a footer with "page x of y" - in Polish or English (`lang`). Cormorant Garamond SemiBold is a
  static instance of the OFL variable font; the text is Lato (ADR-0010). The company's name, address, tax id, phone,
  e-mail and website are settings (`CRM_OFFER_COMPANY_*`, default "Halycon Inc.").

## Consequences

Plus: one place for the rules, a PDF that looks like the application, texts that never change under a sent offer.
Minus: a template's texts exist in two languages and are kept by hand; the PDF layout is code.

## Alternatives considered

- **HTML to PDF in a headless browser:** the same CSS as the app, but a browser inside the image.
- **Templates in code:** fewer tables, but every text change would be a release of the application, not a migration.
