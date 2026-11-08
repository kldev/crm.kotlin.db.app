-- The kinds of activity logged on a deal (ADR-0017), in order.
CREATE OR ALTER PROCEDURE app.deal_activity_type_list
    @actor_id int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    SELECT activity_type, name_pl, name_en FROM crm.deal_activity_types ORDER BY sort_order;
END;
