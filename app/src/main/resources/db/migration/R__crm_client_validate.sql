-- Internal helper: client field rules shared by app.client_create and app.client_update.
-- Expects values already normalised (trimmed, empty -> NULL) by the caller.
CREATE OR ALTER PROCEDURE crm.client_validate
    @name   nvarchar(200),
    @nip    varchar(20),
    @email  varchar(254),
    @status varchar(10)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    IF @name IS NULL
        THROW 51010, N'Client name is required.', 1;
    IF @nip IS NOT NULL AND (LEN(@nip) <> 10 OR @nip LIKE '%[^0-9]%')
        THROW 51011, N'NIP must have exactly 10 digits.', 1;
    IF @email IS NOT NULL AND @email NOT LIKE '_%@_%._%'
        THROW 51012, N'E-mail address is not valid.', 1;
    IF @status IS NULL OR @status NOT IN ('LEAD', 'ACTIVE', 'INACTIVE')
        THROW 51013, N'Status must be LEAD, ACTIVE or INACTIVE.', 1;
END;
