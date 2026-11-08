-- Internal (ADR-0014): who may change a task - its author, its assignee, a manager or an administrator (51304).
CREATE OR ALTER PROCEDURE crm.task_require_editor
    @actor_id int,
    @task_id  bigint
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @role varchar(10);
    EXEC crm.actor_require @actor_id, @role OUTPUT;
    DECLARE @author int, @assignee int;
    SELECT @author = created_by, @assignee = assignee_user_id FROM crm.tasks WHERE id = @task_id;
    IF @author IS NULL
        THROW 51406, N'Task not found.', 1;
    IF @role = 'SALES' AND @actor_id NOT IN (@author, @assignee)
        THROW 51304, N'Only the author, the assignee or a manager can change this task.', 1;
END;
