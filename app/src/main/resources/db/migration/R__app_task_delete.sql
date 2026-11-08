-- Delete a task (ADR-0014): its author, its assignee, a manager or an administrator. rowVersion required.
CREATE OR ALTER PROCEDURE app.task_delete
    @actor_id    int,
    @task_id     bigint,
    @row_version binary(8)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.task_require_editor @actor_id, @task_id;
    DELETE crm.tasks WHERE id = @task_id AND row_version = @row_version;
    IF @@ROWCOUNT = 0
        THROW 51901, N'The record was changed by someone else. Reload it and try again.', 1;
END;
