# 0005. Teams, projects, stages and comments; read views

Status: Accepted
Date: 2026-11-08

## Decision

- A team (led by a MANAGER, members are users) delivers projects for a client; one team member owns each project.
- Stages: NEW, ACCEPTED, ACTIVE, ON_HOLD, CLOSED, DECLINED. Allowed moves are rows of
  `crm.project_stage_transitions`; every move writes `crm.project_stage_history` and may add a comment, in one
  transaction. CLOSED and DECLINED are final; their details cannot be edited.
- `crm.v_projects` is the read model of a project (joins client, team, owner). It is a plain view, expanded into
  each query, so filters reach the indexes of `crm.projects`.
- Indexes for project lists all end in `(due_date, id)`, the sort and keyset key: by client, team, owner, stage,
  plus a filtered index of open projects for "overdue".
- SALES visibility in `app.project_search`: the union of three small indexed sets (own projects, projects of own
  teams, projects of own clients) is built first, then filtered and paged.
- Team statistics come from the indexed view `crm.v_team_project_stats` (count and budget per team and stage),
  read with `WITH (NOEXPAND)` because Express never matches indexed views on its own.

## Consequences

Plus: lists stay a range seek plus TOP regardless of the table size; statistics read at most six rows.
Minus: every project write also updates the indexed view row of its team and stage.
