-- Internal (ADR-0010): a PESEL is 11 digits, the last one the check digit of weights 1-3-7-9.
CREATE OR ALTER FUNCTION crm.desk_pesel_valid (@value nvarchar(200))
RETURNS bit
WITH SCHEMABINDING
AS
BEGIN
    IF @value IS NULL OR LEN(@value) <> 11 OR @value LIKE N'%[^0-9]%'
        RETURN 0;
    DECLARE @sum int = 0, @i int = 1;
    WHILE @i <= 10
    BEGIN
        SET @sum += CAST(SUBSTRING(@value, @i, 1) AS int) * CHOOSE((@i - 1) % 4 + 1, 1, 3, 7, 9);
        SET @i += 1;
    END;
    RETURN IIF((10 - @sum % 10) % 10 = CAST(SUBSTRING(@value, 11, 1) AS int), 1, 0);
END;
