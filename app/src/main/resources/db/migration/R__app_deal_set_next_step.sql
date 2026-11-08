/*
  The follow-up of a deal (ADR-0017): what to do next and when (UTC), both or neither - empty clears it. 1-400
  characters (51213); only an open deal has a next step (51909). rowVersion required (51901).
*/
CREATE OR ALTER PROCEDURE app.deal_set_next_step
    @actor_id     int,
    @deal_id      bigint,
    @next_step    nvarchar(4000) = NULL,
    @next_step_at datetime2(3)   = NULL,
    @row_version  binary(8)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.deal_require_visible @actor_id, @deal_id;
    SET @next_step = NULLIF(LTRIM(RTRIM(@next_step)), N'');
    IF (@next_step IS NULL AND @next_step_at IS NOT NULL) OR (@next_step IS NOT NULL AND @next_step_at IS NULL)
       OR LEN(@next_step) > 400
        THROW 51213, N'The next step needs both what (at most 400 characters) and when.', 1;
    IF @next_step IS NOT NULL AND EXISTS (SELECT 1 FROM crm.deals AS d JOIN crm.deal_stages AS s ON s.stage = d.stage
                                          WHERE d.id = @deal_id AND s.is_closed = 1)
        THROW 51909, N'A closed deal has no next step.', 1;
    UPDATE crm.deals
    SET next_step = @next_step, next_step_at = @next_step_at, updated_at = SYSUTCDATETIME(), updated_by = @actor_id
    WHERE id = @deal_id AND row_version = @row_version;
    IF @@ROWCOUNT = 0
        THROW 51901, N'The record was changed by someone else. Reload it and try again.', 1;
    EXEC crm.deal_select @deal_id;
END;
