-- The group's companies (ADR-0016), for everybody: the pickers and the companies page.
CREATE OR ALTER PROCEDURE app.legal_entity_list
    @actor_id int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    EXEC crm.legal_entity_select;
END;
