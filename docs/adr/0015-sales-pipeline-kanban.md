# 0015. The sales pipeline as a kanban board

Status: Accepted
Date: 2026-11-08

## Context

Salespeople follow their chances to sell from the first contact to the signature, and managers want to know what is
in the pipeline and what it is likely to bring. Unlike tasks (ADR-0014), a deal does go through stages, so here a
kanban board is the natural view.

## Decision

- **A deal** (`crm.deals`) belongs to a client: what is sold, the value with currency (PLN / EUR / USD), the expected
  close date, an optional offer of the same client (ADR-0013). Its **owner** is the client's salesperson when the
  deal is opened (or the author if the client has none), so "mine" on the board means the deals I own.
- **Stages as data** (`crm.deal_stages`): Kontakt 10 %, Potrzeba potwierdzona 25 %, Oferta 50 %, Negocjacje 75 %,
  Wygrana 100 %, Przegrana 0 %. The probability weights the forecast; Won and Lost are closed. `app.deal_move` moves
  between any two stages (a lost deal can come back); Lost needs a reason (51197); entering a closed stage stamps
  `closed_at`, leaving it clears it. Every change carries the `rowversion`.
- **Visibility**: SALES see and change the deals of their own clients (51407 / 51401), MANAGER and ADMIN all - the
  client's rule.
- **The board** (`app.deal_board`, `/pipeline`) reads the open deals and those closed in the last 30 days - the first
  100 cards of each column by close date, so a long column never pushes the others off - with scope MINE / ALL and a
  name prefix. The column heads and four tiles (the pipeline, the weighted forecast, won in 30 days, the win rate) come
  from `app.deal_board_summary` over every matching deal. Amounts in different currencies are never added together.
- **Moving a card** is native HTML drag and drop with an optimistic update (the card jumps at once, a refused move puts
  it back); the drawer has the same stages as buttons for the keyboard. Dropping on Lost asks for the reason.
- **Seed**: `seed.deals_run` (called by `seed.desk_run`) gives the first twelve salespeople ten deals each across the
  stages.

## Consequences

Plus: the forecast comes from data the team already keeps; stages and probabilities change with a migration, not a
release. Minus: no order of cards inside a column (they sort by the close date); no history of moves beyond
`stage_changed_at`; currencies are not converted.

## Alternatives considered

- **Statuses on offers instead of deals:** an offer is one document; a deal lives before the first offer and across
  several of them.
- **A drag and drop library:** nicer keyboard dragging, but native events and the drawer cover the board without a
  dependency.
