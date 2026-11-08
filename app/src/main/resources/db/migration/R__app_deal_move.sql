/*
  Move a deal to another column of the board (ADR-0015). Any stage to any stage - a lost deal can come back - but LOST
  needs the reason (51197). Entering a closed stage stamps closed_at, leaving it clears it. rowVersion required (51901).
*/
CREATE OR ALTER PROCEDURE app.deal_move
    @actor_id    int,
    @deal_id     bigint,
    @stage       varchar(12),
    @lost_reason nvarchar(4000) = NULL,
    @row_version binary(8)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.deal_require_visible @actor_id, @deal_id;
    DECLARE @closed bit = (SELECT is_closed FROM crm.deal_stages WHERE stage = @stage);
    IF @closed IS NULL
        THROW 51196, N'Choose a stage of the pipeline.', 1;
    SET @lost_reason = NULLIF(LTRIM(RTRIM(@lost_reason)), N'');
    IF @stage = 'LOST' AND (@lost_reason IS NULL OR LEN(@lost_reason) > 400)
        THROW 51197, N'Say why the deal was lost (at most 400 characters).', 1;
    UPDATE crm.deals
    SET stage_changed_at = IIF(stage = @stage, stage_changed_at, SYSUTCDATETIME()),
        closed_at = IIF(@closed = 1, IIF(stage = @stage, closed_at, SYSUTCDATETIME()), NULL),
        stage = @stage, lost_reason = IIF(@stage = 'LOST', @lost_reason, NULL),
        updated_at = SYSUTCDATETIME(), updated_by = @actor_id
    WHERE id = @deal_id AND row_version = @row_version;
    IF @@ROWCOUNT = 0
        THROW 51901, N'The record was changed by someone else. Reload it and try again.', 1;
    EXEC crm.deal_select @deal_id;
END;
