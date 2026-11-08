/*
  The expenses of a trip as a whole list (ADR-0019) - JSON [{category, description, spentOn, document, amount,
  nights}], at most 50: a category of the list, a description 1-200, a day within the trip (one day of slack), an amount
  > 0 with 2 decimals, a document up to 60, nights 1-60 on a hotel line (51246 with the line number). Recomputed;
  rowVersion (51901).
*/
CREATE OR ALTER PROCEDURE app.trip_expenses_save
    @actor_id    int,
    @trip_id     bigint,
    @items       nvarchar(max),
    @row_version binary(8)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.trip_require @actor_id, @trip_id, 1;
    DECLARE @from date, @to date;
    SELECT @from = DATEADD(DAY, -1, CAST(starts_at AS date)), @to = DATEADD(DAY, 1, CAST(ends_at AS date)) FROM crm.trips WHERE id = @trip_id;
    DECLARE @lines TABLE (line_no int, category varchar(20), description nvarchar(400), spent_on date, document nvarchar(100),
                          amount decimal(20, 4), nights int);
    INSERT @lines
    SELECT CAST(j.[key] AS int) + 1, x.category, NULLIF(LTRIM(RTRIM(x.description)), N''), TRY_CAST(x.spentOn AS date),
           NULLIF(LTRIM(RTRIM(x.document)), N''), TRY_CAST(x.amount AS decimal(20, 4)), x.nights
    FROM OPENJSON(ISNULL(@items, N'[]')) AS j
    CROSS APPLY OPENJSON(j.value) WITH (category varchar(20), description nvarchar(400), spentOn varchar(30),
                                        document nvarchar(100), amount nvarchar(40), nights int) AS x;
    IF (SELECT COUNT(*) FROM @lines) > 50
        THROW 51246, N'At most 50 expenses.', 1;
    DECLARE @bad int = (SELECT MIN(line_no) FROM @lines
        WHERE ISNULL(category, '') NOT IN ('HOTEL', 'TICKET', 'FUEL', 'PARKING', 'TOLL', 'TAXI', 'OTHER')
           OR description IS NULL OR LEN(description) > 200 OR spent_on IS NULL OR spent_on NOT BETWEEN @from AND @to
           OR amount IS NULL OR amount <= 0 OR amount <> ROUND(amount, 2) OR amount > 1000000 OR LEN(document) > 60
           OR (category = 'HOTEL' AND ISNULL(nights, 0) NOT BETWEEN 1 AND 60));
    IF @bad IS NOT NULL
    BEGIN
        DECLARE @message nvarchar(400) = FORMATMESSAGE(N'Line %d: a category, a description, a day of the trip, an amount over 0 (hotel: nights).', @bad);
        THROW 51246, @message, 1;
    END;
    BEGIN TRANSACTION;
    UPDATE crm.trips SET updated_at = SYSUTCDATETIME(), updated_by = @actor_id WHERE id = @trip_id AND row_version = @row_version;
    IF @@ROWCOUNT = 0
        THROW 51901, N'The record was changed by someone else. Reload it and try again.', 1;
    DELETE crm.trip_expenses WHERE trip_id = @trip_id;
    INSERT crm.trip_expenses (trip_id, line_no, category, description, spent_on, document, amount, nights)
    SELECT @trip_id, line_no, category, description, spent_on, document, amount, IIF(category = 'HOTEL', nights, NULL) FROM @lines;
    EXEC crm.trip_compute @trip_id;
    COMMIT;
    EXEC crm.trip_select @trip_id = @trip_id;
END;
