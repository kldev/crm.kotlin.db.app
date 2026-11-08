/*
  A new deal for a client (ADR-0015), in the first stage unless @stage names another open one. The owner is the
  client's salesperson, or the author when the client has none; SALES only for their own clients (51401).
*/
CREATE OR ALTER PROCEDURE app.deal_create
    @actor_id       int,
    @client_id      bigint,
    @title          nvarchar(4000),
    @value          decimal(20, 4),
    @currency       char(3)     = 'PLN',
    @expected_close date,
    @offer_id       bigint      = NULL,
    @stage          varchar(12) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @role varchar(10), @owner int;
    EXEC crm.actor_require @actor_id, @role OUTPUT;
    SELECT @owner = ISNULL(assigned_user_id, @actor_id)
    FROM crm.clients WHERE id = @client_id AND (@role <> 'SALES' OR assigned_user_id = @actor_id);
    IF @owner IS NULL
        THROW 51401, N'Client not found.', 1;
    SET @stage = ISNULL(@stage, 'LEAD');
    IF NOT EXISTS (SELECT 1 FROM crm.deal_stages WHERE stage = @stage AND is_closed = 0)
        THROW 51196, N'A new deal starts in an open stage.', 1;
    EXEC crm.deal_check @title OUTPUT, @value, @currency, @expected_close, @client_id, @offer_id;

    INSERT crm.deals (title, client_id, owner_user_id, stage, value, currency, expected_close, offer_id, created_by, updated_by)
    VALUES (@title, @client_id, @owner, @stage, @value, @currency, @expected_close, @offer_id, @actor_id, @actor_id);
    DECLARE @deal_id bigint = SCOPE_IDENTITY();
    EXEC crm.deal_select @deal_id;
END;
