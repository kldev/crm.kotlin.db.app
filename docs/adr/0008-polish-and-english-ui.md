# 0008. Polish and English in the web app

Status: Accepted
Date: 2026-11-08

## Context

The service desk (ADR-0007) comes from Halcyon, a Polish tool with an English switch; its catalog, people and refusals
are Polish. The CRM pages were English only. The whole app gets one switch.

## Decision

- Two languages, Polish by default. The user's choice is kept in this browser (`localStorage`), never taken from
  Accept-Language: the team works in Polish whatever their browsers say. The PL / EN switch is in the top bar, on the
  sign-in page and on the public form; switching re-renders, no reload.
- Texts are written in both languages where they are used: `t("Pula", "Pool")` (`frontend/src/i18n`). No keys and no
  resource files - a page reads with its English next to the Polish.
- Stored data never changes. Catalog names are Polish in the database (their identity); `n(name)` shows the English
  name from `catalogEn.ts`, copied from Halcyon. What people typed is shown as it is.
- Procedures throw English messages with a number; `problemText` maps the number to the Polish (or English) text, and
  takes a name or a department out of the message with a pattern. An unknown number shows the server's message.
- Dates and times are formatted with Intl in `pl-PL` / `en-GB`, desk times in Europe/Warsaw.

## Consequences

Plus: no translation machinery, every text is reviewable in place. Minus: a text in only one language is a bug that only
review catches; the CRM pages are being translated step by step.

## Alternatives considered

- **i18next with keys:** the standard, but several hundred keys for a two-language internal tool.
- **A server-side culture cookie (as in Halcyon):** needed for Blazor's server rendering, not for a single-page app.
