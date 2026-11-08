-- Mark a task done or open again (ADR-0014). rowVersion required (51901). Finishing a task of a deal logs it on the
-- deal (ADR-0017), once per finishing.
CREATE OR ALTER PROCEDURE app.task_set_done
    @actor_id    int,
    @task_id     bigint,
    @done        bit,
    @row_version binary(8)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.task_require_editor @actor_id, @task_id;
    DECLARE @was_done bit, @deal_id bigint, @title nvarchar(200);
    SELECT @was_done = is_done, @deal_id = deal_id, @title = title FROM crm.tasks WHERE id = @task_id;
    BEGIN TRANSACTION;
    UPDATE crm.tasks
    SET is_done = ISNULL(@done, 0), done_at = IIF(@done = 1, SYSUTCDATETIME(), NULL), updated_at = SYSUTCDATETIME(),
        updated_by = @actor_id
    WHERE id = @task_id AND row_version = @row_version;
    IF @@ROWCOUNT = 0
        THROW 51901, N'The record was changed by someone else. Reload it and try again.', 1;
    IF @done = 1 AND @was_done = 0 AND @deal_id IS NOT NULL
    BEGIN
        DECLARE @note nvarchar(1000) = CONCAT(N'Zadanie wykonane: ', @title), @now datetime2(3) = SYSUTCDATETIME();
        EXEC crm.deal_activity_log @deal_id, 'TASK', @note, @now, @actor_id;
    END;
    COMMIT;
    EXEC crm.task_select @task_id;
END;
