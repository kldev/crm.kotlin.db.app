# 0014. Tasks on a calendar and a timeline, without statuses

Status: Accepted
Date: 2026-11-08

## Context

People plan work that lasts days: an audit, a campaign, a month-end close. They want to see who does what and when,
their own work and their department's. A kanban was considered and rejected by the team: the work has no workflow
worth columns, only "to do" and "done".

## Decision

- **A task** (`crm.tasks`) has a title, a description, one assignee, a first and a last day (`date`, both included,
  at most a year apart), an optional client or project, and `is_done` with `done_at`. **No statuses**: a task is open
  or done; "overdue" is an open task past its last day, computed, never stored.
- **Departments**: `crm.departments` is the list the desk uses (copied in V10); `crm.users.department` is set by an
  administrator (`app.user_set_department`, `PUT /api/users/{id}/department`). The "my department" view is the
  actor's department.
- **Reading by window**: `app.task_list` returns the tasks overlapping `from..to` (start <= to, end >= from; at most
  120 days, 2 000 rows) with a scope `MINE` / `DEPARTMENT` / `ALL`, a department and done / open. The window is the
  view - a month's whole weeks or the timeline's two weeks or month - so there is no paging.
- **Everybody sees all tasks** (planning is shared); **changing** follows `crm.task_require_editor`: MANAGER and
  ADMIN any task, SALES the ones they created or are assigned (51304). Updates and done carry the `rowversion`.
- **Two views of the same window** in `/tasks`: a month calendar (a bar across the days of a task, cut at week
  edges, overlapping bars in lanes, "+N" opens the week) and a timeline (a row per person grouped by department,
  weekends shaded, today a line). A click on a day or a person's empty day adds a task there. Filters, view and
  period are in the URL.
- **Seed**: `seed.tasks_run` (called by `seed.desk_run`) gives the ten desk agents departments and plans eight tasks
  each from three weeks back to five weeks ahead, the past mostly done.

## Consequences

Plus: one simple model that the calendar, the timeline and "mine / my department" all read the same way; the window
query is one index seek. Minus: no dependencies between tasks and no drag to move a bar (the drawer changes dates);
a long view (a quarter) needs a new, wider window.

## Alternatives considered

- **Kanban with statuses:** rejected - the work has no workflow, columns would be empty ceremony.
- **Departments as free text on users:** cheaper, but "my department" would split on typos.
