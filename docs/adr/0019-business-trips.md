# 0019. Business trips and their settlement

Status: Accepted
Date: 2026-11-08

## Context

Salespeople visit clients and go to trade fairs, marketing goes to fairs and events, the operational people travel to
the sites where projects are delivered. Every trip is settled afterwards under the Polish rules for business travel
(the regulation of the Minister of Family and Social Policy of 2022 and its annex for trips abroad; mileage by the
Minister of Infrastructure's regulation of 2023). Ambit System has no such module; the rules come from the law.

## Decision

- **A trip** (`crm.trips`, numbered `DEL/<year>/<nnnn>`) has a traveller, the paying company (ADR-0016), a purpose -
  a client visit (a client), a trade fair (the event's name), a project site (a project), other - a destination and a
  country, the departure and return (instants, at most 60 days), the transport (a fleet car of ADR-0018, a private car
  with the vehicle and km - domestic only -, train, plane, bus), the meals provided, nights without an invoice, the
  local-transport lump sum, an advance, and expense lines with documents (hotel lines count their nights).
- **Rates as data** (`crm.trip_diet_rates`, `crm.trip_mileage_rates`) with the day they apply from: Poland 45 zł,
  hotel limit 900 zł; Germany 49 EUR / 170, France and Belgium 55 / 200, Czechia 41 / 120, the United Kingdom 45 GBP /
  220; mileage 1.15 zł/km (car over 900 cc), 0.89 (up to 900 cc), 0.69 (motorcycle), 0.42 (moped). The draft raising
  the domestic diet to 60 zł is not law yet (November 2026); when it is, it is one row.
- **The settlement** (`crm.trip_compute`, stored on the trip at every change), at the rate of the first day:
  per diems by length - domestic: under 8 h none, 8-12 h half, over 12 h one; longer trips one per full day and the
  rest up to 8 h half, over 8 h one; abroad one per full day and the rest up to 8 h a third, 8-12 h half, over 12 h one -
  less the meals provided (domestic 25 / 50 / 25 %, abroad 15 / 30 / 30 % for breakfast / lunch / dinner), never below
  zero; lump sums for nights without an invoice (150 % of the diet, abroad 25 % of the hotel limit) and local transport
  (20 % of the diet per started day, abroad 10 %); mileage; expenses. To pay = total - advance; negative means the
  traveller gives money back. A hotel night above the limit is flagged, not refused (the employer may agree to it).
  One trip, one country and one currency - no conversion.
- **The way**: PLANNED -> (after the return) SUBMITTED -> APPROVED -> PAID, or SUBMITTED -> RETURNED with a note ->
  SUBMITTED; a planned trip can be cancelled. The traveller (or a manager) plans, corrects and submits; ADMIN and
  MANAGER approve, return and pay - never their own trip. Everybody sees their own trips, managers all of them, with
  "to approve" as a list of its own.
- **Seed**: 20 125 trips over seven months (at most fifty a person) - client visits, fairs (some abroad),
  project sites, other - with expenses, in every state.

## Consequences

Plus: the settlement is computed by one procedure the tests pin down, the rates change without a release. Minus:
trips through several countries, currency conversion at the NBP rate, the travel order PDF and accounting exports are
left for later.

## Alternatives considered

- **Computing in the browser:** quick to show, but two places for the rules; the browser shows what the database says.
- **Rates in settings:** a change of the regulation would need a deployment and lose the history of old trips.
