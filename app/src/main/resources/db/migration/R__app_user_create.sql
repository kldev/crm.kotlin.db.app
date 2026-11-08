CREATE OR ALTER PROCEDURE app.user_create
    @actor_id      int,
    @login         varchar(64),
    @display_name  nvarchar(200),
    @role          varchar(10),
    @password_hash varchar(100)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE @actor_role varchar(10);
    EXEC crm.actor_require @actor_id, @actor_role OUTPUT;

    IF @actor_role <> 'ADMIN'
        THROW 51301, N'You are not allowed to perform this operation.', 1;

    SET @login = LOWER(LTRIM(RTRIM(@login)));
    SET @display_name = NULLIF(LTRIM(RTRIM(@display_name)), N'');

    IF @login IS NULL OR LEN(@login) < 3 OR @login LIKE '%[^a-z0-9._-]%'
        THROW 51015, N'Login must have 3-64 characters: letters, digits, dot, underscore or hyphen.', 1;
    IF @display_name IS NULL
        THROW 51019, N'Display name is required.', 1;
    IF @role IS NULL OR @role NOT IN ('ADMIN', 'MANAGER', 'SALES')
        THROW 51016, N'Role must be ADMIN, MANAGER or SALES.', 1;
    IF @password_hash IS NULL OR LEN(@password_hash) = 0
        THROW 51020, N'Password is required.', 1;

    -- A duplicate login fails on uq_users_login (2627) and becomes 409 in the API.
    DECLARE @id int;
    INSERT crm.users (login, display_name, role, password_hash, created_by, updated_by)
    VALUES (@login, @display_name, @role, @password_hash, @actor_id, @actor_id);
    SET @id = SCOPE_IDENTITY();

    SELECT id, login, display_name, role, is_active, locked_until, last_login_at, created_at, updated_at, row_version
    FROM crm.users
    WHERE id = @id;
END;
