-- The car statuses in order (ADR-0018); needs_shop marks the repair-shop ones.
CREATE OR ALTER PROCEDURE app.car_status_list
    @actor_id int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    SELECT status, needs_shop, name_pl, name_en FROM crm.car_statuses ORDER BY sort_order;
END;
