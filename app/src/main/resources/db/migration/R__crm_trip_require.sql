/*
  Internal (ADR-0019): the trip exists and the actor may see it (51415) - their own trips for everybody, every trip for
  ADMIN and MANAGER. @edit = 1 also requires a state the traveller may still change - planned or returned (51928).
*/
CREATE OR ALTER PROCEDURE crm.trip_require
    @actor_id int,
    @trip_id  bigint,
    @edit     bit         = 0,
    @role     varchar(10) = NULL OUTPUT,
    @status   varchar(10) = NULL OUTPUT,
    @mine     bit         = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id, @role OUTPUT;
    DECLARE @traveller int;
    SELECT @traveller = traveller_user_id, @status = status FROM crm.trips WHERE id = @trip_id;
    SET @mine = IIF(@traveller = @actor_id, 1, 0);
    IF @traveller IS NULL OR (@mine = 0 AND @role NOT IN ('ADMIN', 'MANAGER'))
        THROW 51415, N'Business trip not found.', 1;
    IF @edit = 1 AND @status NOT IN ('PLANNED', 'RETURNED')
        THROW 51928, N'Only a planned trip or one returned for corrections is changed.', 1;
END;
