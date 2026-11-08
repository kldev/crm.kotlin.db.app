/*
  "My day" (ADR-0017): my open tasks that have started by @until - the overdue ones too, by their last day - and the
  ones I finished since @done_since (UTC), newest first. At most 200 of each.
*/
CREATE OR ALTER PROCEDURE app.task_agenda
    @actor_id   int,
    @until      date,
    @done_since datetime2(3) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    IF @until IS NULL
        THROW 51181, N'Choose the last day of the agenda.', 1;
    WITH agenda AS (
        SELECT o.id, 0 AS part
        FROM (SELECT TOP (200) t.id FROM crm.tasks AS t
              WHERE t.assignee_user_id = @actor_id AND t.is_done = 0 AND t.start_date <= @until
              ORDER BY t.end_date, t.start_date, t.id) AS o
        UNION ALL
        SELECT d.id, 1
        FROM (SELECT TOP (200) t.id FROM crm.tasks AS t
              WHERE t.assignee_user_id = @actor_id AND t.is_done = 1 AND @done_since IS NOT NULL AND t.done_at >= @done_since
              ORDER BY t.done_at DESC) AS d
    )
    SELECT t.id, t.title, t.description, t.assignee_user_id, a.display_name AS assignee_name,
           a.department AS assignee_department, t.start_date, t.end_date, t.is_done, t.done_at, t.client_id,
           c.name AS client_name, t.project_id, p.name AS project_name, t.created_by, cb.display_name AS created_by_name,
           t.created_at, t.updated_at, t.row_version, t.deal_id, dl.title AS deal_title
    FROM agenda AS g
    JOIN crm.tasks AS t ON t.id = g.id
    JOIN crm.users AS a ON a.id = t.assignee_user_id
    JOIN crm.users AS cb ON cb.id = t.created_by
    LEFT JOIN crm.clients AS c ON c.id = t.client_id
    LEFT JOIN crm.projects AS p ON p.id = t.project_id
    LEFT JOIN crm.deals AS dl ON dl.id = t.deal_id
    ORDER BY g.part, IIF(g.part = 0, t.end_date, NULL), t.done_at DESC, t.id;
END;
