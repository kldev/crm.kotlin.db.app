/*
  Internal (ADR-0010): the report data of a subcategory. @values is a JSON object {field_key: value}, the whole set:
  a missing or empty value means "not given". Returns the values as stored (@normalized, a JSON object of the given
  ones only) or refuses:
    51130 a field of another subcategory      51131 a required field is empty     51132 over 200 characters
    51133 not a date (yyyy-mm-dd)             51134 not an e-mail                 51135 not an amount (2 decimals)
    51136 not an IBAN                         51137 not a count 1-10000          51138 a multi-choice value off the list
    51139 a choice off the list               51140 not a ticket number          51141-51145 identity document rules
  Stored forms: dates yyyy-mm-dd, amounts 1234.56, IBAN upper case without spaces, counts without separators,
  multi-choice "A, B" in the list's order, choices and ticket numbers as the list / upper case has them.
*/
CREATE OR ALTER PROCEDURE crm.desk_fields_check
    @subcategory_key varchar(60),
    @values          nvarchar(max),
    @normalized      nvarchar(max) OUTPUT
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    SET @values = ISNULL(NULLIF(LTRIM(RTRIM(@values)), N''), N'{}');
    IF ISJSON(@values) = 0 OR LEFT(@values, 1) <> N'{'
        THROW 50004, N'Report fields must be a JSON object.', 1;

    DECLARE @in TABLE (field_key nvarchar(400) NOT NULL PRIMARY KEY, value nvarchar(max) NULL);
    INSERT @in (field_key, value) SELECT [key], [value] FROM OPENJSON(@values);

    DECLARE @message nvarchar(2000), @bad nvarchar(400);
    SELECT TOP (1) @bad = i.field_key
    FROM @in AS i
    WHERE NOT EXISTS (SELECT 1 FROM crm.desk_subcategory_fields AS sf
                      WHERE sf.subcategory_key = @subcategory_key AND sf.field_key = i.field_key);
    IF @bad IS NOT NULL
    BEGIN
        SET @message = FORMATMESSAGE(N'The field "%s" does not belong to this subcategory.', @bad);
        THROW 51130, @message, 1;
    END;

    DECLARE @out TABLE (field_key varchar(40) NOT NULL PRIMARY KEY, value nvarchar(200) NOT NULL);
    DECLARE @defs TABLE (n int IDENTITY (1, 1) PRIMARY KEY, field_key varchar(40), label nvarchar(200),
                         kind varchar(14), is_required bit);
    INSERT @defs (field_key, label, kind, is_required)
    SELECT f.field_key, f.label, f.kind, sf.is_required
    FROM crm.desk_subcategory_fields AS sf
    JOIN crm.desk_fields AS f ON f.field_key = sf.field_key
    WHERE sf.subcategory_key = @subcategory_key
    ORDER BY sf.sort_order;

    DECLARE @i int = 1, @last int = (SELECT COUNT(*) FROM @defs);
    WHILE @i <= @last
    BEGIN
        DECLARE @key varchar(40), @label nvarchar(200), @kind varchar(14), @required bit, @v nvarchar(max),
                @result nvarchar(200) = NULL;
        SELECT @key = field_key, @label = label, @kind = kind, @required = is_required FROM @defs WHERE n = @i;
        SET @v = NULLIF(LTRIM(RTRIM((SELECT value FROM @in WHERE field_key = @key))), N'');
        SET @i += 1;

        IF @v IS NULL
        BEGIN
            IF @required = 1
            BEGIN
                SET @message = FORMATMESSAGE(N'Fill in the field "%s".', @label);
                THROW 51131, @message, 1;
            END;
            CONTINUE;
        END;
        IF LEN(@v) > 200
        BEGIN
            SET @message = FORMATMESSAGE(N'The field "%s" can have at most 200 characters.', @label);
            THROW 51132, @message, 1;
        END;

        IF @kind = 'DATE'
        BEGIN
            DECLARE @date date = IIF(@v LIKE N'[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]', TRY_CONVERT(date, @v, 23), NULL);
            IF @date IS NULL
            BEGIN
                SET @message = FORMATMESSAGE(N'The field "%s" must be a date (yyyy-mm-dd).', @label);
                THROW 51133, @message, 1;
            END;
            SET @result = CONVERT(char(10), @date, 23);
        END
        ELSE IF @kind = 'EMAIL'
        BEGIN
            IF @v LIKE N'% %' OR @v NOT LIKE N'_%@_%._%' OR LEN(@v) - LEN(REPLACE(@v, N'@', N'')) <> 1
               OR @v LIKE N'%..%' OR @v LIKE N'%.' OR @v LIKE N'.%' OR @v LIKE N'%@.%'
            BEGIN
                SET @message = FORMATMESSAGE(N'The field "%s" must be an e-mail address.', @label);
                THROW 51134, @message, 1;
            END;
            SET @result = @v;
        END
        ELSE IF @kind = 'AMOUNT'
        BEGIN
            -- Spaces (also non-breaking) as thousands separators, a comma or a dot as the decimal point.
            DECLARE @compact nvarchar(200) = REPLACE(REPLACE(REPLACE(@v, N' ', N''), NCHAR(160), N''), N',', N'.');
            DECLARE @amount decimal(20, 4) =
                IIF(@compact LIKE N'%[^0-9.+-]%', NULL, TRY_CONVERT(decimal(20, 4), @compact));
            IF @amount IS NULL OR ROUND(@amount, 2) <> @amount OR ABS(@amount) >= 1000000000000
            BEGIN
                SET @message = FORMATMESSAGE(N'The field "%s" must be an amount, e.g. 1 234.56 (at most 2 decimals).', @label);
                THROW 51135, @message, 1;
            END;
            SET @result = CONVERT(nvarchar(30), CAST(@amount AS decimal(15, 2)));
        END
        ELSE IF @kind = 'IBAN'
        BEGIN
            SET @result = crm.desk_iban_normalize(@v);
            IF @result IS NULL
            BEGIN
                SET @message = FORMATMESSAGE(N'The field "%s" is not a valid account number (IBAN).', @label);
                THROW 51136, @message, 1;
            END;
        END
        ELSE IF @kind = 'COUNT'
        BEGIN
            DECLARE @digits nvarchar(200) = REPLACE(@v, N' ', N'');
            DECLARE @count int = IIF(@digits LIKE N'%[^0-9]%' OR LEN(@digits) > 6, NULL, TRY_CONVERT(int, @digits));
            IF @count IS NULL OR @count NOT BETWEEN 1 AND 10000
            BEGIN
                SET @message = FORMATMESSAGE(N'The field "%s" must be a number from 1 to 10000.', @label);
                THROW 51137, @message, 1;
            END;
            SET @result = CAST(@count AS nvarchar(10));
        END
        ELSE IF @kind = 'MULTI_CHOICE'
        BEGIN
            DECLARE @picked TABLE (value nvarchar(200));
            DELETE @picked;
            INSERT @picked (value)
            SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@v, N',') WHERE LTRIM(RTRIM(value)) <> N'';
            SELECT TOP (1) @bad = p.value FROM @picked AS p
            WHERE NOT EXISTS (SELECT 1 FROM crm.desk_field_options AS o WHERE o.field_key = @key AND o.option_value = p.value);
            IF @@ROWCOUNT > 0
            BEGIN
                SET @message = FORMATMESSAGE(N'"%s" is not on the list of the field "%s".', @bad, @label);
                THROW 51138, @message, 1;
            END;
            SELECT @result = STRING_AGG(o.option_value, N', ') WITHIN GROUP (ORDER BY o.sort_order)
            FROM crm.desk_field_options AS o
            WHERE o.field_key = @key AND EXISTS (SELECT 1 FROM @picked AS p WHERE p.value = o.option_value);
        END
        ELSE IF @kind = 'CHOICE'
        BEGIN
            SET @result = (SELECT option_value FROM crm.desk_field_options WHERE field_key = @key AND option_value = @v);
            IF @result IS NULL
            BEGIN
                SET @message = FORMATMESSAGE(N'Choose the value of the field "%s" from the list.', @label);
                THROW 51139, @message, 1;
            END;
        END
        ELSE IF @kind = 'TICKET_NUMBER'
        BEGIN
            SET @result = UPPER(@v);
            IF LEN(@result) <> 12 OR @result NOT LIKE N'HAL-[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]'
            BEGIN
                SET @message = FORMATMESSAGE(N'The field "%s" must be a ticket number, e.g. HAL-1A2B3C4D.', @label);
                THROW 51140, @message, 1;
            END;
        END
        ELSE
            SET @result = @v;

        INSERT @out (field_key, value) VALUES (@key, @result);
    END;

    -- The identity document and its number go together: a PESEL must be valid, "no documents" has no number.
    DECLARE @document nvarchar(200) = (SELECT value FROM @out WHERE field_key = 'identity-document');
    DECLARE @number nvarchar(200) = (SELECT value FROM @out WHERE field_key = 'identity-number');
    IF @document IS NULL AND @number IS NOT NULL
        THROW 51141, N'Choose the type of document the number belongs to.', 1;
    IF @document = N'Brak dokumentów' AND @number IS NOT NULL
        THROW 51142, N'With "no documents" no document number is given.', 1;
    IF @document = N'PESEL' AND @number IS NULL
        THROW 51143, N'Enter the PESEL number.', 1;
    IF @document = N'PESEL' AND crm.desk_pesel_valid(@number) = 0
        THROW 51144, N'The PESEL number is not valid (11 digits with a correct check digit).', 1;
    IF @document = N'Dowód osobisty' AND @number IS NULL
        THROW 51145, N'Enter the ID card number.', 1;
    IF @document = N'Dowód osobisty'
        UPDATE @out SET value = UPPER(REPLACE(value, N' ', N'')) WHERE field_key = 'identity-number';

    SET @normalized = ISNULL(
        (SELECT N'{' + STRING_AGG(N'"' + STRING_ESCAPE(field_key, 'json') + N'":"' + STRING_ESCAPE(value, 'json') + N'"', N',')
                + N'}' FROM @out),
        N'{}');
END;
