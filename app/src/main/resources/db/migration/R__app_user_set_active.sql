CREATE OR ALTER PROCEDURE app.user_set_active
    @actor_id  int,
    @id        int,
    @is_active bit
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE @actor_role varchar(10);
    EXEC crm.actor_require @actor_id, @actor_role OUTPUT;

    IF @actor_role <> 'ADMIN'
        THROW 51301, N'You are not allowed to perform this operation.', 1;
    IF @id = @actor_id
        THROW 51018, N'You cannot change your own role or deactivate yourself.', 1;
    IF NOT EXISTS (SELECT 1 FROM crm.users WHERE id = @id)
        THROW 51402, N'User not found.', 1;

    UPDATE crm.users
    SET is_active  = @is_active,
        updated_at = SYSUTCDATETIME(),
        updated_by = @actor_id
    WHERE id = @id
      AND is_active <> @is_active;

    SELECT id, login, display_name, role, is_active, locked_until, last_login_at, created_at, updated_at, row_version, department
    FROM crm.users
    WHERE id = @id;
END;
