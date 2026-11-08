/*
  Internal (ADR-0013): replaces the lines of an offer with @items, a JSON array of {description, unit, quantity,
  unitPrice, vatRate}, inside the caller's transaction. At most 100 lines; a description (1-400) and a unit (1-20), a
  quantity above 0, a price of 0 or more with at most 2 decimals, VAT 0, 5, 8 or 23 percent (51173).
*/
CREATE OR ALTER PROCEDURE crm.offer_items_save
    @offer_id bigint,
    @items    nvarchar(max)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    IF @items IS NULL OR ISJSON(@items) = 0 OR LEFT(LTRIM(@items), 1) <> N'['
        THROW 51173, N'Offer lines must be a list.', 1;

    DECLARE @lines TABLE (line_no int NOT NULL PRIMARY KEY, description nvarchar(4000), unit nvarchar(400),
                          quantity decimal(20, 6), unit_price decimal(20, 6), vat_rate int);
    INSERT @lines (line_no, description, unit, quantity, unit_price, vat_rate)
    SELECT CAST(item.[key] AS int) + 1, LTRIM(RTRIM(x.description)), LTRIM(RTRIM(x.unit)),
           TRY_CAST(x.quantity AS decimal(20, 6)), TRY_CAST(x.unit_price AS decimal(20, 6)), TRY_CAST(x.vat_rate AS int)
    FROM OPENJSON(@items) AS item
    CROSS APPLY OPENJSON(item.value)
         WITH (description nvarchar(4000) '$.description', unit nvarchar(400) '$.unit',
               quantity nvarchar(50) '$.quantity', unit_price nvarchar(50) '$.unitPrice',
               vat_rate nvarchar(10) '$.vatRate') AS x;

    IF (SELECT COUNT(*) FROM @lines) > 100
        THROW 51173, N'An offer can have at most 100 lines.', 1;
    DECLARE @bad int = (SELECT MIN(line_no) FROM @lines
                        WHERE description IS NULL OR description = N'' OR LEN(description) > 400
                           OR unit IS NULL OR unit = N'' OR LEN(unit) > 20
                           OR quantity IS NULL OR quantity <= 0 OR quantity >= 1000000000 OR ROUND(quantity, 3) <> quantity
                           OR unit_price IS NULL OR unit_price < 0 OR unit_price >= 1000000000000 OR ROUND(unit_price, 2) <> unit_price
                           OR vat_rate IS NULL OR vat_rate NOT IN (0, 5, 8, 23));
    IF @bad IS NOT NULL
    BEGIN
        DECLARE @message nvarchar(400) = FORMATMESSAGE(
            N'Line %d: a description (up to 400 characters), a unit, a quantity above 0, a price with at most 2 decimals and VAT 0, 5, 8 or 23%%.',
            @bad);
        THROW 51173, @message, 1;
    END;

    DELETE crm.offer_items WHERE offer_id = @offer_id;
    INSERT crm.offer_items (offer_id, line_no, description, unit, quantity, unit_price, vat_rate)
    SELECT @offer_id, line_no, description, unit, quantity, unit_price, vat_rate FROM @lines;
END;
