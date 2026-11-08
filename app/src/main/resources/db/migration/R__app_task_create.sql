-- A new task (ADR-0014). Anyone may plan a task for anyone; the author is the actor.
CREATE OR ALTER PROCEDURE app.task_create
    @actor_id         int,
    @title            nvarchar(4000),
    @description      nvarchar(max) = NULL,
    @assignee_user_id int,
    @start_date       date,
    @end_date         date,
    @client_id        bigint = NULL,
    @project_id       bigint = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    EXEC crm.task_check @title OUTPUT, @description OUTPUT, @assignee_user_id, @start_date, @end_date, @client_id, @project_id;
    INSERT crm.tasks (title, description, assignee_user_id, start_date, end_date, client_id, project_id, created_by, updated_by)
    VALUES (@title, @description, @assignee_user_id, @start_date, @end_date, @client_id, @project_id, @actor_id, @actor_id);
    DECLARE @id bigint = SCOPE_IDENTITY();
    EXEC crm.task_select @id;
END;
