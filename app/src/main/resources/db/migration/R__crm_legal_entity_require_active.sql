-- Internal (ADR-0016): the company exists (51408) and trades on @on (51205) - a project's start, an offer's day.
CREATE OR ALTER PROCEDURE crm.legal_entity_require_active
    @legal_entity_id int,
    @on              date
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @from date, @to date;
    SELECT @from = active_from, @to = active_to FROM crm.legal_entities WHERE id = @legal_entity_id;
    IF @from IS NULL
        THROW 51408, N'Company not found.', 1;
    IF @on < @from OR @on > @to
        THROW 51205, N'The company does not trade on that day.', 1;
END;
