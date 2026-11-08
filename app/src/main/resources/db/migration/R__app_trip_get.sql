-- One business trip (ADR-0019): own trips for everybody, every trip for ADMIN and MANAGER (51415).
CREATE OR ALTER PROCEDURE app.trip_get
    @actor_id int,
    @trip_id  bigint
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.trip_require @actor_id, @trip_id;
    EXEC crm.trip_select @trip_id = @trip_id;
END;
