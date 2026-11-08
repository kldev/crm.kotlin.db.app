/*
  Tasks overlapping [@from, @to] (calendar days, both included) for the calendar and the timeline (ADR-0014).
  @scope: MINE (assigned to me), DEPARTMENT (assigned to people of @department, or of my department), ALL.
  @done: NULL all, 0 open, 1 done. At most 2000 rows, by start date.
*/
CREATE OR ALTER PROCEDURE app.task_list
    @actor_id   int,
    @from       date,
    @to         date,
    @scope      varchar(10)  = 'ALL',
    @department nvarchar(50) = NULL,
    @done       bit          = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    IF @from IS NULL OR @to IS NULL OR @to < @from OR DATEDIFF(DAY, @from, @to) > 120
        THROW 51181, N'Choose a window of at most 120 days (from <= to).', 1;
    IF ISNULL(@scope, '') NOT IN ('MINE', 'DEPARTMENT', 'ALL')
        THROW 51182, N'Scope must be MINE, DEPARTMENT or ALL.', 1;
    SET @department = NULLIF(LTRIM(RTRIM(@department)), N'');
    IF @scope = 'DEPARTMENT' AND @department IS NULL
        SET @department = (SELECT department FROM crm.users WHERE id = @actor_id);
    IF @department IS NOT NULL AND NOT EXISTS (SELECT 1 FROM crm.departments WHERE name = @department)
        THROW 51183, N'Choose a department from the list.', 1;

    SELECT TOP (2000)
           t.id, t.title, t.description, t.assignee_user_id, a.display_name AS assignee_name,
           a.department AS assignee_department, t.start_date, t.end_date, t.is_done, t.done_at, t.client_id,
           c.name AS client_name, t.project_id, p.name AS project_name, t.created_by, cb.display_name AS created_by_name,
           t.created_at, t.updated_at, t.row_version, t.deal_id, dl.title AS deal_title
    FROM crm.tasks AS t
    JOIN crm.users AS a ON a.id = t.assignee_user_id
    JOIN crm.users AS cb ON cb.id = t.created_by
    LEFT JOIN crm.clients AS c ON c.id = t.client_id
    LEFT JOIN crm.projects AS p ON p.id = t.project_id
    LEFT JOIN crm.deals AS dl ON dl.id = t.deal_id
    WHERE t.start_date <= @to AND t.end_date >= @from
      AND (@scope <> 'MINE' OR t.assignee_user_id = @actor_id)
      -- A department chosen in the filter narrows any scope; DEPARTMENT without one uses mine.
      AND (@department IS NULL OR a.department = @department)
      AND (@scope <> 'DEPARTMENT' OR @department IS NOT NULL)
      AND (@done IS NULL OR t.is_done = @done)
    ORDER BY t.start_date, t.end_date, t.id
    OPTION (RECOMPILE);
END;
