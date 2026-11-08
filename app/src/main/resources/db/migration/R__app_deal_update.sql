-- Change a deal's title, value, currency, expected close and offer (ADR-0015); the stage moves with deal_move. 51901.
CREATE OR ALTER PROCEDURE app.deal_update
    @actor_id       int,
    @deal_id        bigint,
    @title          nvarchar(4000),
    @value          decimal(20, 4),
    @currency       char(3),
    @expected_close date,
    @offer_id       bigint = NULL,
    @row_version    binary(8)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.deal_require_visible @actor_id, @deal_id;
    DECLARE @client_id bigint = (SELECT client_id FROM crm.deals WHERE id = @deal_id);
    EXEC crm.deal_check @title OUTPUT, @value, @currency, @expected_close, @client_id, @offer_id;
    UPDATE crm.deals
    SET title = @title, value = @value, currency = @currency, expected_close = @expected_close, offer_id = @offer_id,
        updated_at = SYSUTCDATETIME(), updated_by = @actor_id
    WHERE id = @deal_id AND row_version = @row_version;
    IF @@ROWCOUNT = 0
        THROW 51901, N'The record was changed by someone else. Reload it and try again.', 1;
    EXEC crm.deal_select @deal_id;
END;
