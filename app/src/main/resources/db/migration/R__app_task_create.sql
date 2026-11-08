-- A new task (ADR-0014). Anyone may plan a task for anyone; the author is the actor.
CREATE OR ALTER PROCEDURE app.task_create
    @actor_id         int,
    @title            nvarchar(4000),
    @description      nvarchar(max) = NULL,
    @assignee_user_id int,
    @start_date       date,
    @end_date         date,
    @client_id        bigint = NULL,
    @project_id       bigint = NULL,
    @deal_id          bigint = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    -- A task of a deal only for a deal the author sees (ADR-0017).
    IF @deal_id IS NOT NULL
        EXEC crm.deal_require_visible @actor_id, @deal_id;
    EXEC crm.task_check @title OUTPUT, @description OUTPUT, @assignee_user_id, @start_date, @end_date, @client_id, @project_id,
         @deal_id, @client_id OUTPUT;
    INSERT crm.tasks (title, description, assignee_user_id, start_date, end_date, client_id, project_id, deal_id, created_by, updated_by)
    VALUES (@title, @description, @assignee_user_id, @start_date, @end_date, @client_id, @project_id, @deal_id, @actor_id, @actor_id);
    DECLARE @id bigint = SCOPE_IDENTITY();
    EXEC crm.task_select @id;
END;
