# 0018. The fleet: cars, statuses, financing and handovers

Status: Accepted
Date: 2026-11-08

## Context

The group's companies (ADR-0016) own cars that people use for work. The office needs to know which car is where -
in use, at a repair shop, for sale - who has it until when, how it is financed and when the technical inspection and
the insurance run out. Ambit System has a fleet module with a deliberately narrow scope; we take its rules.

## Decision

- **Cars** (`crm.cars`): name, make (suggested from a list and from the fleet), production year (1900 to next year),
  registration number (letters, digits, spaces, hyphens; unique among cars in use compared without spaces and hyphens,
  "WA 12345" = "wa-12345"; archiving frees it), VIN (17 characters without I/O/Q, unique for good, given once - an
  administrator corrects it with a reason), notes, the owning company, inspection and insurance deadlines (our
  addition: a list filter and amber within 30 days, red when past).
- **Status by hand** (`crm.car_statuses`): new, operational, to / in / ready at a repair shop (these name a shop of the
  list, frozen in the history), for sale, archived - each change from a day not in the future and not before the
  current status, with a note, into `crm.car_status_history`. For sale and archived only without a current or planned
  handover; out of the archive only an administrator, only to operational. A car never handed over can be deleted,
  any other is archived.
- **Financing**: unknown, bought (purchase date) or leasing (company of the list, monthly instalment, currency, start,
  1-120 months, contract number); the lease ends at start + months - 1 day. Instalment and contract only for ADMIN
  and MANAGER.
- **Handovers** (`crm.car_handovers`): a car to one person from a day, until a planned return or open-ended, with the
  mileage and fuel. One handover per car and one car per person at a time; days are inclusive ("until the 12th" then
  "from the 13th" is fine). The checks lock the rows they read, so two requests cannot slip past each other - the race
  Ambit System documents. Return (day between issue and today, mileage not below the issue), undo the return on its own
  day, move the planned return, cancel with a reason (kept in the history). The handover state and the car's
  availability (free, handed over, overdue) are computed for today in Warsaw, never stored; a planned handover leaves
  the car free today. A car at a repair shop can be handed over, with a warning.
- **Partners** (`crm.fleet_partners`): repair shops and leasing companies, unique per kind ignoring case and Polish
  letters; hidden, never deleted, once used.
- **Who**: ADMIN and MANAGER run the fleet (51301 otherwise); everybody reads it; "my car" shows on My day.
- **Screens**: `/fleet` (filters: text, status, availability, company, repair shop, deadlines within 30 days, archive;
  total on request) and `/fleet/{id}` (data, handovers, status history; the actions as dialogs).
- **Seed**: 2 000 cars, nine partners and about 10 000 handovers in two-month rounds, each round giving every car a
  different person.

## Consequences

Plus: the rules live in the procedures and the overlap check is safe under concurrency. Minus: no costs, fuel logs,
damages, documents or reminders by e-mail yet - the deadlines are a filter and a colour.

## Alternatives considered

- **Handovers as tasks (ADR-0014):** a task has no mileage and no exclusivity; overlapping cars would go unnoticed.
- **Status derived from handovers:** a car at a repair shop can still be lent; the two are independent, as in Ambit
  System.
