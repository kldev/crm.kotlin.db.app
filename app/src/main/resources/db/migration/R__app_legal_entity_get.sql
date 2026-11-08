-- One company (ADR-0016); 51408 when there is none.
CREATE OR ALTER PROCEDURE app.legal_entity_get
    @actor_id        int,
    @legal_entity_id int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    IF NOT EXISTS (SELECT 1 FROM crm.legal_entities WHERE id = @legal_entity_id)
        THROW 51408, N'Company not found.', 1;
    EXEC crm.legal_entity_select @legal_entity_id;
END;
