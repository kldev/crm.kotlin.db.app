/*
  Edit a draft offer (ADR-0013): title, introduction, terms, currency, validity and the whole list of lines. Only a
  draft (51906); `@row_version` from the last read (51901 when someone changed it meanwhile). The signing company
  (ADR-0016) may change too while it trades (51205); NULL keeps it.
*/
CREATE OR ALTER PROCEDURE app.offer_update
    @actor_id    int,
    @offer_id    bigint,
    @title       nvarchar(400),
    @intro       nvarchar(max),
    @terms       nvarchar(max),
    @currency    char(3),
    @valid_until date,
    @items       nvarchar(max),
    @row_version binary(8),
    @legal_entity_id int = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.offer_require_visible @actor_id, @offer_id;

    SET @title = LTRIM(RTRIM(@title));
    SET @intro = LTRIM(RTRIM(ISNULL(@intro, N'')));
    SET @terms = LTRIM(RTRIM(ISNULL(@terms, N'')));
    IF @title IS NULL OR @title = N'' OR LEN(@title) > 200
        THROW 51170, N'The title is required and can have at most 200 characters.', 1;
    IF LEN(@intro) > 2000 OR LEN(@terms) > 4000
        THROW 51175, N'The introduction can have at most 2000 characters and the terms 4000.', 1;
    IF @currency IS NULL OR @currency NOT IN ('PLN', 'EUR', 'USD')
        THROW 51174, N'Currency must be PLN, EUR or USD.', 1;
    DECLARE @today date = CAST((SYSUTCDATETIME() AT TIME ZONE 'UTC') AT TIME ZONE 'Central European Standard Time' AS date);
    IF @valid_until IS NULL OR @valid_until < @today OR @valid_until > DATEADD(YEAR, 1, @today)
        THROW 51172, N'The offer must be valid from today up to a year.', 1;
    IF @legal_entity_id IS NOT NULL
        EXEC crm.legal_entity_require_active @legal_entity_id, @today;

    BEGIN TRANSACTION;
    DECLARE @status varchar(10), @current binary(8);
    SELECT @status = status, @current = row_version FROM crm.offers WITH (UPDLOCK, HOLDLOCK) WHERE id = @offer_id;
    IF @current <> @row_version
        THROW 51901, N'The record was changed by someone else. Reload it and try again.', 1;
    IF @status <> 'DRAFT'
        THROW 51906, N'Only a draft offer can be edited.', 1;

    EXEC crm.offer_items_save @offer_id, @items;
    UPDATE crm.offers
    SET title = @title, intro = @intro, terms = @terms, currency = @currency, valid_until = @valid_until,
        legal_entity_id = ISNULL(@legal_entity_id, legal_entity_id),
        updated_at = SYSUTCDATETIME(), updated_by = @actor_id
    WHERE id = @offer_id;
    COMMIT;

    EXEC crm.offer_select @offer_id;
END;
