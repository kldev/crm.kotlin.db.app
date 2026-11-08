# 0017. A salesperson's day: activities, the next step, tasks of a deal

Status: Accepted
Date: 2026-11-08

## Context

The pipeline (ADR-0015) says where each deal stands, but not what a salesperson has to do today, nor what has
happened on a deal so far. Ambit System's sales workspace answers both with three ideas: an activity log on the
opportunity, one "next action" (follow-up) per opportunity, and tasks linked to it - shown together as the
salesperson's day. We take the ideas, not the code.

## Decision

- **Activities** (`crm.deal_activities`): what happened on a deal - call, e-mail, meeting, presentation, note, task,
  other (`crm.deal_activity_types`, data) - with a note and the moment it happened (now, or up to 90 days back, never
  in the future: 51210-51212). Append-only: nobody edits history. The deal keeps its newest activity
  (`last_activity_at/_type`); a backdated entry does not move it back.
- **The next step** (follow-up) is one pair on the deal - `next_step` and `next_step_at` (UTC), both or neither
  (51213). Only an open deal has one (51909); winning or losing clears it. It is not a task: it is the deal's "what
  now", replaced when done. Logging a contact and planning the next step are one dialog.
- **Tasks of a deal**: `crm.tasks.deal_id` (ADR-0014 tasks) - the deal's client becomes the task's (51214), the author
  must see the deal. Finishing such a task logs a `TASK` activity on the deal ("Zadanie wykonane: …") in the same
  transaction.
- **"My day"** (`/my-day`): the follow-ups due by the end of today or this week (overdue always included, oldest
  first, `app.sales_follow_ups`), my started tasks (overdue first, `app.task_agenda`) with those done today, and open
  deals with no next step (`app.sales_without_next_step`) - the ones about to go cold. Tiles count overdue,
  due, open tasks and deals without a step. Managers can switch to the team's view; SALES see their own clients'
  deals only, as everywhere.
- **The deal page** (`/pipeline/{id}`): the next step on top (overdue in red), the activity log, the facts; a kanban
  card opens it.
- **Dates and times** are picked in the app's own pickers (HeroUI DatePicker with a time field), shown in Warsaw
  time, sent as UTC instants.

## Consequences

Plus: one screen tells a salesperson what to do and nothing slips (overdue items never leave the list); the log
gives managers the history without asking. Minus: one next step per deal (no queue of planned steps); no reminders
by e-mail yet - the list is the reminder.

## Alternatives considered

- **Follow-ups as tasks:** one list, but a task has days and an assignee while a follow-up is a moment on a deal;
  mixing them makes both worse (Ambit System keeps them apart for the same reason).
- **Editable activities:** convenient, but the log is evidence of what was agreed; a correction is a new note.
