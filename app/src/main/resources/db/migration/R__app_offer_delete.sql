-- Delete a draft offer with its lines (ADR-0013). A sent offer stays: it is a record of what the client got (51906).
CREATE OR ALTER PROCEDURE app.offer_delete
    @actor_id    int,
    @offer_id    bigint,
    @row_version binary(8)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.offer_require_visible @actor_id, @offer_id;
    BEGIN TRANSACTION;
    DECLARE @status varchar(10), @current binary(8);
    SELECT @status = status, @current = row_version FROM crm.offers WITH (UPDLOCK, HOLDLOCK) WHERE id = @offer_id;
    IF @current <> @row_version
        THROW 51901, N'The record was changed by someone else. Reload it and try again.', 1;
    IF @status <> 'DRAFT'
        THROW 51906, N'Only a draft offer can be deleted.', 1;
    DELETE crm.offers WHERE id = @offer_id;
    COMMIT;
END;
