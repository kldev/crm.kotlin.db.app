-- Internal (ADR-0012): the system pages are for administrators (51301 otherwise).
CREATE OR ALTER PROCEDURE crm.monitoring_require_admin
    @actor_id int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @role varchar(10);
    EXEC crm.actor_require @actor_id, @role OUTPUT;
    IF @role <> 'ADMIN'
        THROW 51301, N'You are not allowed to perform this operation.', 1;
END;
