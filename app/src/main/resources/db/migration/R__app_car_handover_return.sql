/*
  Take a car back (ADR-0018) - managers: the return day not before the issue and not in the future (51232), the mileage
  not below the issue mileage, fuel 0-100 % (51233). Only a live handover that has started (51926). rowVersion required.
*/
CREATE OR ALTER PROCEDURE app.car_handover_return
    @actor_id       int,
    @handover_id    bigint,
    @returned_on    date,
    @return_mileage int,
    @return_fuel    int,
    @row_version    binary(8)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.fleet_require_manager @actor_id;
    DECLARE @issue date, @mileage int, @live bit, @today date = crm.fleet_today();
    SELECT @issue = issue_date, @mileage = issue_mileage, @live = IIF(cancelled_at IS NULL AND returned_on IS NULL, 1, 0)
    FROM crm.car_handovers WHERE id = @handover_id;
    IF @issue IS NULL
        THROW 51414, N'Handover not found.', 1;
    IF @live = 0 OR @issue > @today
        THROW 51926, N'Only a running handover is returned.', 1;
    IF @returned_on IS NULL OR @returned_on < @issue OR @returned_on > @today
        THROW 51232, N'The return day is between the issue day and today.', 1;
    IF @return_mileage IS NULL OR @return_mileage < @mileage OR @return_mileage > 5000000 OR @return_fuel IS NULL OR @return_fuel NOT BETWEEN 0 AND 100
        THROW 51233, N'The return mileage is not below the issue mileage; fuel is 0 to 100 %.', 1;
    UPDATE crm.car_handovers
    SET returned_on = @returned_on, return_mileage = @return_mileage, return_fuel = @return_fuel, returned_by = @actor_id
    WHERE id = @handover_id AND row_version = @row_version;
    IF @@ROWCOUNT = 0
        THROW 51901, N'The record was changed by someone else. Reload it and try again.', 1;
    EXEC crm.handover_select @handover_id = @handover_id;
END;
