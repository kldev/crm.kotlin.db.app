# 0011. Desk charts drawn without a chart library

Status: Accepted
Date: 2026-11-08

## Context

Agents and team leads want to see how tickets flow and whether deadlines are kept (Halcyon's spec 009 / ADR-0010):
flow in and out, the backlog, deadlines kept, SLA use per priority, by category, the queue now, agents and when
tickets arrive.

## Decision

- **One query, counted in Kotlin.** `app.desk_chart_tickets` returns every ticket open at some moment of the range or
  reported in it (optionally of one category), with the deadline state of open tickets computed in the database - the
  same clock and the same 60-minute rule as the lists and counters - and the Warsaw weekday and hour of the report.
  `DeskCharts` buckets and aggregates: the last 7 or 30 Warsaw days by day, or 12 weeks Monday to Sunday; medians and
  the nearest-rank p90 (from 5 tickets) of time to resolve as a share of the SLA; top 8 agents and "others". Fine for a
  team desk (thousands of tickets); a bigger desk would aggregate in the procedure.
- **Drawn as SVG and HTML in React** (`features/desk/charts/ChartKit.tsx`), to the dataviz rules: one axis per chart,
  thin bars with a rounded data end and a 2px gap between stacked segments, 2px lines, a crosshair tooltip on lines
  and a per-segment tooltip on bars, a legend on every chart with two or more series, a table view of the same numbers
  under every chart.
- **Colour by job**, as tokens in `global.css` (`--viz-*`): two categorical slots for reported / resolved (validated:
  CVD separation 24.7, normal vision 33.6, contrast >= 3:1 on the white surface), the fixed status set for on time /
  due soon / late or overdue - always with an icon and a label - a neutral for "open", one blue sequential ramp for the
  weekday x hour heatmap. The SLA chart caps at 300% so one very late priority does not flatten the others.
- **One row of filters** (range, category) above everything it scopes; while new numbers load, the old ones stay
  dimmed - no skeleton flash. The charts and the reports use the whole screen width (`staticData.wide`).

## Consequences

Plus: no chart dependency; the numbers agree with each other and with the lists (tested: heatmap and category totals
equal "reported", the last backlog point equals "open now", the queue equals the top-bar counters).
Minus: more drawing code to own than a library call.

## Alternatives considered

- **A chart library (Recharts, ECharts):** less code, but its defaults fight the mark specs and it is a large bundle
  for eight charts.
- **SQL aggregation per chart:** less data over the wire, but eight procedures for one page; worth it only at a scale
  this desk does not have.
