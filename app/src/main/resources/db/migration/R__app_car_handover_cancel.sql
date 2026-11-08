-- Cancel a handover entered by mistake (ADR-0018) - managers - with a reason (51234); not a returned one (51926). It stays in the history.
CREATE OR ALTER PROCEDURE app.car_handover_cancel
    @actor_id    int,
    @handover_id bigint,
    @reason      nvarchar(4000),
    @row_version binary(8)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.fleet_require_manager @actor_id;
    IF NOT EXISTS (SELECT 1 FROM crm.car_handovers WHERE id = @handover_id)
        THROW 51414, N'Handover not found.', 1;
    IF EXISTS (SELECT 1 FROM crm.car_handovers WHERE id = @handover_id AND (cancelled_at IS NOT NULL OR returned_on IS NOT NULL))
        THROW 51926, N'Only a live handover is cancelled.', 1;
    SET @reason = NULLIF(LTRIM(RTRIM(@reason)), N'');
    IF @reason IS NULL OR LEN(@reason) > 400
        THROW 51234, N'Say why the handover is cancelled (at most 400 characters).', 1;
    UPDATE crm.car_handovers SET cancelled_at = SYSUTCDATETIME(), cancel_reason = @reason
    WHERE id = @handover_id AND row_version = @row_version;
    IF @@ROWCOUNT = 0
        THROW 51901, N'The record was changed by someone else. Reload it and try again.', 1;
    EXEC crm.handover_select @handover_id = @handover_id;
END;
