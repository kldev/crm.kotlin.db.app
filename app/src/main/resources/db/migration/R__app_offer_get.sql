-- One offer with its client, author and totals (ADR-0013).
CREATE OR ALTER PROCEDURE app.offer_get
    @actor_id int,
    @offer_id bigint
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.offer_require_visible @actor_id, @offer_id;
    EXEC crm.offer_select @offer_id;
END;
