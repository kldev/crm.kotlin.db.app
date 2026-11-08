/*
  Internal (ADR-0016): the fields of a company. Name 1-100 (51200), legal name and address required (51201), NIP of 10
  digits with a valid check digit (51202), trading dates (51203), contact: phone 6-30 of digits and + ( ) -, e-mail,
  IBAN-like bank account of 15-34 letters and digits (51204).
*/
CREATE OR ALTER PROCEDURE crm.legal_entity_check
    @name         nvarchar(4000) OUTPUT,
    @legal_name   nvarchar(4000) OUTPUT,
    @tax_id       varchar(100)   OUTPUT,
    @address      nvarchar(4000) OUTPUT,
    @phone        varchar(100)   OUTPUT,
    @email        nvarchar(4000) OUTPUT,
    @bank_account varchar(100)   OUTPUT,
    @active_from  date,
    @active_to    date
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    SELECT @name = NULLIF(LTRIM(RTRIM(@name)), N''), @legal_name = NULLIF(LTRIM(RTRIM(@legal_name)), N''),
           @tax_id = REPLACE(REPLACE(LTRIM(RTRIM(@tax_id)), '-', ''), ' ', ''), @address = NULLIF(LTRIM(RTRIM(@address)), N''),
           @phone = NULLIF(LTRIM(RTRIM(@phone)), ''), @email = LOWER(NULLIF(LTRIM(RTRIM(@email)), N'')),
           @bank_account = NULLIF(REPLACE(UPPER(LTRIM(RTRIM(@bank_account))), ' ', ''), '');
    IF @name IS NULL OR LEN(@name) > 100
        THROW 51200, N'The name is required (at most 100 characters).', 1;
    IF @legal_name IS NULL OR LEN(@legal_name) > 200 OR @address IS NULL OR LEN(@address) > 300
        THROW 51201, N'The legal name (at most 200 characters) and the address (at most 300) are required.', 1;
    IF @tax_id IS NULL OR @tax_id LIKE '%[^0-9]%' OR LEN(@tax_id) <> 10
       OR (6 * CAST(SUBSTRING(@tax_id, 1, 1) AS int) + 5 * CAST(SUBSTRING(@tax_id, 2, 1) AS int)
           + 7 * CAST(SUBSTRING(@tax_id, 3, 1) AS int) + 2 * CAST(SUBSTRING(@tax_id, 4, 1) AS int)
           + 3 * CAST(SUBSTRING(@tax_id, 5, 1) AS int) + 4 * CAST(SUBSTRING(@tax_id, 6, 1) AS int)
           + 5 * CAST(SUBSTRING(@tax_id, 7, 1) AS int) + 6 * CAST(SUBSTRING(@tax_id, 8, 1) AS int)
           + 7 * CAST(SUBSTRING(@tax_id, 9, 1) AS int)) % 11 <> CAST(SUBSTRING(@tax_id, 10, 1) AS int)
        THROW 51202, N'The NIP must be 10 digits with a valid check digit.', 1;
    IF @active_from IS NULL OR @active_to < @active_from
        THROW 51203, N'The company trades from a date, and stops no earlier than it started.', 1;
    IF (@phone IS NOT NULL AND (LEN(@phone) NOT BETWEEN 6 AND 30 OR @phone LIKE '%[^0-9 +()-]%'))
       OR (@email IS NOT NULL AND (LEN(@email) > 254 OR @email NOT LIKE '_%@_%._%' OR @email LIKE '% %'))
       OR (@bank_account IS NOT NULL AND (LEN(@bank_account) NOT BETWEEN 15 AND 34 OR @bank_account LIKE '%[^A-Z0-9]%'))
        THROW 51204, N'Check the phone, e-mail and bank account.', 1;
END;
