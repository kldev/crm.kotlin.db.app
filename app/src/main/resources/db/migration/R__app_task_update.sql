-- Change a task (ADR-0014): every field, also the dates when it is moved on the calendar. rowVersion required (51901).
CREATE OR ALTER PROCEDURE app.task_update
    @actor_id         int,
    @task_id          bigint,
    @title            nvarchar(4000),
    @description      nvarchar(max) = NULL,
    @assignee_user_id int,
    @start_date       date,
    @end_date         date,
    @client_id        bigint = NULL,
    @project_id       bigint = NULL,
    @row_version      binary(8)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.task_require_editor @actor_id, @task_id;
    EXEC crm.task_check @title OUTPUT, @description OUTPUT, @assignee_user_id, @start_date, @end_date, @client_id, @project_id;
    UPDATE crm.tasks
    SET title = @title, description = @description, assignee_user_id = @assignee_user_id, start_date = @start_date,
        end_date = @end_date, client_id = @client_id, project_id = @project_id, updated_at = SYSUTCDATETIME(),
        updated_by = @actor_id
    WHERE id = @task_id AND row_version = @row_version;
    IF @@ROWCOUNT = 0
        THROW 51901, N'The record was changed by someone else. Reload it and try again.', 1;
    EXEC crm.task_select @task_id;
END;
