-- One task (ADR-0014). Every user sees every task: the calendar is the team's shared plan.
CREATE OR ALTER PROCEDURE app.task_get
    @actor_id int,
    @task_id  bigint
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    IF NOT EXISTS (SELECT 1 FROM crm.tasks WHERE id = @task_id)
        THROW 51406, N'Task not found.', 1;
    EXEC crm.task_select @task_id;
END;
