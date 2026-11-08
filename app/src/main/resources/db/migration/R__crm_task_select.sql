-- Internal (ADR-0014): the task row every task read and write returns, with the assignee, links and creator.
CREATE OR ALTER PROCEDURE crm.task_select
    @task_id bigint
AS
BEGIN
    SET NOCOUNT ON;
    SELECT t.id, t.title, t.description, t.assignee_user_id, a.display_name AS assignee_name,
           a.department AS assignee_department, t.start_date, t.end_date, t.is_done, t.done_at, t.client_id,
           c.name AS client_name, t.project_id, p.name AS project_name, t.created_by, cb.display_name AS created_by_name,
           t.created_at, t.updated_at, t.row_version, t.deal_id, dl.title AS deal_title
    FROM crm.tasks AS t
    JOIN crm.users AS a ON a.id = t.assignee_user_id
    JOIN crm.users AS cb ON cb.id = t.created_by
    LEFT JOIN crm.clients AS c ON c.id = t.client_id
    LEFT JOIN crm.projects AS p ON p.id = t.project_id
    LEFT JOIN crm.deals AS dl ON dl.id = t.deal_id
    WHERE t.id = @task_id;
END;
