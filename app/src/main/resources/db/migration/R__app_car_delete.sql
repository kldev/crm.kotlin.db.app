-- Delete a car added by mistake (ADR-0018) - managers - only if it was never handed over (51922); otherwise archive it.
CREATE OR ALTER PROCEDURE app.car_delete
    @actor_id    int,
    @car_id      int,
    @row_version binary(8)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.fleet_require_manager @actor_id;
    IF NOT EXISTS (SELECT 1 FROM crm.cars WHERE id = @car_id)
        THROW 51409, N'Car not found.', 1;
    IF EXISTS (SELECT 1 FROM crm.car_handovers WHERE car_id = @car_id AND cancelled_at IS NULL)
        THROW 51922, N'A car that was handed over is archived, not deleted.', 1;
    DELETE crm.cars WHERE id = @car_id AND row_version = @row_version;
    IF @@ROWCOUNT = 0
        THROW 51901, N'The record was changed by someone else. Reload it and try again.', 1;
END;
