/*
  Internal (ADR-0015): the fields of a deal. Title 1-200 (51190), value 0..10^12 with at most 2 decimals (51191),
  currency PLN / EUR / USD (51192), an expected close date (51193), an offer of the same client (51194).
*/
CREATE OR ALTER PROCEDURE crm.deal_check
    @title          nvarchar(4000) OUTPUT,
    @value          decimal(20, 4),
    @currency       char(3),
    @expected_close date,
    @client_id      bigint,
    @offer_id       bigint
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    SET @title = NULLIF(LTRIM(RTRIM(@title)), N'');
    IF @title IS NULL OR LEN(@title) > 200
        THROW 51190, N'The title is required (at most 200 characters).', 1;
    IF @value IS NULL OR @value < 0 OR @value > 1000000000000 OR @value <> ROUND(@value, 2)
        THROW 51191, N'The value is 0 or more, with at most 2 decimals.', 1;
    IF ISNULL(@currency, '') NOT IN ('PLN', 'EUR', 'USD')
        THROW 51192, N'The currency must be PLN, EUR or USD.', 1;
    IF @expected_close IS NULL
        THROW 51193, N'Enter the expected close date.', 1;
    IF @offer_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM crm.offers WHERE id = @offer_id AND client_id = @client_id)
        THROW 51194, N'The offer must be one of this client.', 1;
END;
