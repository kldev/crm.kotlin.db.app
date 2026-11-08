-- Internal (ADR-0018): ADMIN and MANAGER run the fleet; everybody else reads it (51301).
CREATE OR ALTER PROCEDURE crm.fleet_require_manager
    @actor_id int,
    @role     varchar(10) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id, @role OUTPUT;
    IF @role NOT IN ('ADMIN', 'MANAGER')
        THROW 51301, N'Only a manager or an administrator runs the fleet.', 1;
END;
