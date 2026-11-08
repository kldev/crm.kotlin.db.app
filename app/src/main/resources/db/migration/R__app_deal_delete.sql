-- Delete a deal opened by mistake (ADR-0015); rowVersion required (51901).
CREATE OR ALTER PROCEDURE app.deal_delete
    @actor_id    int,
    @deal_id     bigint,
    @row_version binary(8)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.deal_require_visible @actor_id, @deal_id;
    DELETE crm.deals WHERE id = @deal_id AND row_version = @row_version;
    IF @@ROWCOUNT = 0
        THROW 51901, N'The record was changed by someone else. Reload it and try again.', 1;
END;
