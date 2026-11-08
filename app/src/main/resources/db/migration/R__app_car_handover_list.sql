-- A car's handovers, newest first (ADR-0018).
CREATE OR ALTER PROCEDURE app.car_handover_list
    @actor_id int,
    @car_id   int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    EXEC crm.handover_select @car_id = @car_id;
END;
