/*
  Internal (ADR-0010): an account number as stored - upper case without spaces, a Polish 26-digit number gets "PL" -
  when its check digits are valid (ISO 13616, mod 97); NULL when it is not an IBAN.
*/
CREATE OR ALTER FUNCTION crm.desk_iban_normalize (@value nvarchar(200))
RETURNS varchar(34)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @iban varchar(200) = UPPER(REPLACE(REPLACE(REPLACE(@value, N' ', N''), NCHAR(160), N''), NCHAR(9), N''));
    IF LEN(@iban) = 26 AND @iban NOT LIKE '%[^0-9]%'
        SET @iban = 'PL' + @iban;
    IF LEN(@iban) NOT BETWEEN 15 AND 34 OR @iban NOT LIKE '[A-Z][A-Z]%' OR @iban LIKE '%[^A-Z0-9]%'
        RETURN NULL;
    DECLARE @rearranged varchar(200) = SUBSTRING(@iban, 5, 200) + LEFT(@iban, 4);
    DECLARE @remainder int = 0, @i int = 1, @c char(1), @digits int;
    WHILE @i <= LEN(@rearranged)
    BEGIN
        SET @c = SUBSTRING(@rearranged, @i, 1);
        SET @digits = IIF(@c LIKE '[0-9]', ASCII(@c) - 48, ASCII(@c) - 55);
        SET @remainder = IIF(@digits >= 10, (@remainder * 100 + @digits) % 97, (@remainder * 10 + @digits) % 97);
        SET @i += 1;
    END;
    RETURN IIF(@remainder = 1, @iban, NULL);
END;
