-- Move the planned return of a live handover or change its notes (ADR-0018) - managers; the overlap rules hold (51923/51924).
CREATE OR ALTER PROCEDURE app.car_handover_change
    @actor_id       int,
    @handover_id    bigint,
    @planned_return date           = NULL,
    @notes          nvarchar(4000) = NULL,
    @row_version    binary(8)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.fleet_require_manager @actor_id;
    DECLARE @car int, @holder int, @issue date, @mileage int, @fuel int, @live bit;
    SELECT @car = car_id, @holder = holder_user_id, @issue = issue_date, @mileage = issue_mileage, @fuel = issue_fuel,
           @live = IIF(cancelled_at IS NULL AND returned_on IS NULL, 1, 0)
    FROM crm.car_handovers WHERE id = @handover_id;
    IF @car IS NULL
        THROW 51414, N'Handover not found.', 1;
    IF @live = 0
        THROW 51926, N'Only a live handover is changed.', 1;
    SET @notes = NULLIF(LTRIM(RTRIM(@notes)), N'');
    IF LEN(@notes) > 1000
        THROW 51224, N'The notes have at most 1000 characters.', 1;
    BEGIN TRANSACTION;
    EXEC crm.handover_check @car, @holder, @issue, @planned_return, @mileage, @fuel, @handover_id;
    UPDATE crm.car_handovers SET planned_return = @planned_return, notes = @notes
    WHERE id = @handover_id AND row_version = @row_version;
    IF @@ROWCOUNT = 0
        THROW 51901, N'The record was changed by someone else. Reload it and try again.', 1;
    COMMIT;
    EXEC crm.handover_select @handover_id = @handover_id;
END;
