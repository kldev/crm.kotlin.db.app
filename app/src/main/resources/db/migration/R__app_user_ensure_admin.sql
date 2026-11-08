-- Bootstrap of the first administrator at application start (CRM_ADMIN_LOGIN / CRM_ADMIN_PASSWORD).
-- Creates the account only when there is no ADMIN at all; otherwise does nothing. Returns created = 1/0.
CREATE OR ALTER PROCEDURE app.user_ensure_admin
    @login         varchar(64),
    @display_name  nvarchar(200),
    @password_hash varchar(100)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE @created bit = 0;
    SET @login = LOWER(LTRIM(RTRIM(@login)));

    IF @login IS NULL OR LEN(@login) < 3 OR @login LIKE '%[^a-z0-9._-]%'
        THROW 51015, N'Login must have 3-64 characters: letters, digits, dot, underscore or hyphen.', 1;
    IF @password_hash IS NULL OR LEN(@password_hash) = 0
        THROW 51020, N'Password is required.', 1;

    BEGIN TRANSACTION;

    IF NOT EXISTS (SELECT 1 FROM crm.users WITH (UPDLOCK, HOLDLOCK) WHERE role = 'ADMIN')
    BEGIN
        INSERT crm.users (login, display_name, role, password_hash)
        VALUES (@login, COALESCE(NULLIF(LTRIM(RTRIM(@display_name)), N''), @login), 'ADMIN', @password_hash);
        SET @created = 1;
    END;

    COMMIT TRANSACTION;

    SELECT @created AS created;
END;
