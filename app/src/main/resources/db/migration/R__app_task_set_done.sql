-- Mark a task done or open again (ADR-0014). rowVersion required (51901).
CREATE OR ALTER PROCEDURE app.task_set_done
    @actor_id    int,
    @task_id     bigint,
    @done        bit,
    @row_version binary(8)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.task_require_editor @actor_id, @task_id;
    UPDATE crm.tasks
    SET is_done = ISNULL(@done, 0), done_at = IIF(@done = 1, SYSUTCDATETIME(), NULL), updated_at = SYSUTCDATETIME(),
        updated_by = @actor_id
    WHERE id = @task_id AND row_version = @row_version;
    IF @@ROWCOUNT = 0
        THROW 51901, N'The record was changed by someone else. Reload it and try again.', 1;
    EXEC crm.task_select @task_id;
END;
