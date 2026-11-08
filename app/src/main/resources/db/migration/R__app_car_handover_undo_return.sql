-- Undo a return by mistake (ADR-0018) - managers - until the end of the day it was recorded for (51927).
CREATE OR ALTER PROCEDURE app.car_handover_undo_return
    @actor_id    int,
    @handover_id bigint,
    @row_version binary(8)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.fleet_require_manager @actor_id;
    DECLARE @car int, @holder int, @issue date, @planned date, @mileage int, @fuel int, @returned date;
    SELECT @car = car_id, @holder = holder_user_id, @issue = issue_date, @planned = planned_return, @mileage = issue_mileage,
           @fuel = issue_fuel, @returned = returned_on
    FROM crm.car_handovers WHERE id = @handover_id;
    IF @car IS NULL
        THROW 51414, N'Handover not found.', 1;
    IF @returned IS NULL OR @returned <> crm.fleet_today()
        THROW 51927, N'A return is undone only on its own day.', 1;
    BEGIN TRANSACTION;
    -- Running again, the handover must not collide with one made after the return.
    EXEC crm.handover_check @car, @holder, @issue, @planned, @mileage, @fuel, @handover_id;
    UPDATE crm.car_handovers SET returned_on = NULL, return_mileage = NULL, return_fuel = NULL, returned_by = NULL
    WHERE id = @handover_id AND row_version = @row_version;
    IF @@ROWCOUNT = 0
        THROW 51901, N'The record was changed by someone else. Reload it and try again.', 1;
    COMMIT;
    EXEC crm.handover_select @handover_id = @handover_id;
END;
