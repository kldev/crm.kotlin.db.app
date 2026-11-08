-- "My car" (ADR-0018): my live handovers and the ones returned in the last 30 days, newest first.
CREATE OR ALTER PROCEDURE app.car_my
    @actor_id int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    EXEC crm.handover_select @holder_user_id = @actor_id;
END;
