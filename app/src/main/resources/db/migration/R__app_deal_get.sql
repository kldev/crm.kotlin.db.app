-- One deal (ADR-0015); SALES only of their own clients (51407).
CREATE OR ALTER PROCEDURE app.deal_get
    @actor_id int,
    @deal_id  bigint
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.deal_require_visible @actor_id, @deal_id;
    EXEC crm.deal_select @deal_id;
END;
