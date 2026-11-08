CREATE OR ALTER PROCEDURE app.user_change_role
    @actor_id int,
    @id       int,
    @role     varchar(10)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE @actor_role varchar(10);
    EXEC crm.actor_require @actor_id, @actor_role OUTPUT;

    IF @actor_role <> 'ADMIN'
        THROW 51301, N'You are not allowed to perform this operation.', 1;
    IF @role IS NULL OR @role NOT IN ('ADMIN', 'MANAGER', 'SALES')
        THROW 51016, N'Role must be ADMIN, MANAGER or SALES.', 1;
    IF @id = @actor_id
        THROW 51018, N'You cannot change your own role or deactivate yourself.', 1;
    IF NOT EXISTS (SELECT 1 FROM crm.users WHERE id = @id)
        THROW 51402, N'User not found.', 1;

    -- Same role = no change, no write, same row_version.
    UPDATE crm.users
    SET role       = @role,
        updated_at = SYSUTCDATETIME(),
        updated_by = @actor_id
    WHERE id = @id
      AND role <> @role;

    SELECT id, login, display_name, role, is_active, locked_until, last_login_at, created_at, updated_at, row_version
    FROM crm.users
    WHERE id = @id;
END;
