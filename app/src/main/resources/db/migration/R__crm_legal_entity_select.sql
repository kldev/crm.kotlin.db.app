-- Internal (ADR-0016): the company row every read and write returns; trading = active today in Warsaw.
CREATE OR ALTER PROCEDURE crm.legal_entity_select
    @legal_entity_id int = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @today date = CAST((SYSUTCDATETIME() AT TIME ZONE 'UTC') AT TIME ZONE 'Central European Standard Time' AS date);
    SELECT e.id, e.name, e.legal_name, e.tax_id, e.vat_number, e.address, e.phone, e.email, e.website, e.bank_account,
           e.active_from, e.active_to,
           CAST(IIF(e.active_from <= @today AND (e.active_to IS NULL OR e.active_to >= @today), 1, 0) AS bit) AS is_trading,
           (SELECT COUNT_BIG(*) FROM crm.offers AS o WHERE o.legal_entity_id = e.id) AS offers,
           e.updated_at, e.row_version
    FROM crm.legal_entities AS e
    WHERE @legal_entity_id IS NULL OR e.id = @legal_entity_id
    ORDER BY e.id;
END;
