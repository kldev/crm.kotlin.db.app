-- New password hash (computed by the application). Own password (the application has verified the current one)
-- or any user's password when the actor is ADMIN. Clears a lockout.
CREATE OR ALTER PROCEDURE app.user_set_password
    @actor_id      int,
    @id            int,
    @password_hash varchar(100)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE @actor_role varchar(10);
    EXEC crm.actor_require @actor_id, @actor_role OUTPUT;

    IF @id <> @actor_id AND @actor_role <> 'ADMIN'
        THROW 51301, N'You are not allowed to perform this operation.', 1;
    IF @password_hash IS NULL OR LEN(@password_hash) = 0
        THROW 51020, N'Password is required.', 1;
    IF NOT EXISTS (SELECT 1 FROM crm.users WHERE id = @id)
        THROW 51402, N'User not found.', 1;

    UPDATE crm.users
    SET password_hash      = @password_hash,
        failed_login_count = 0,
        locked_until       = NULL,
        updated_at         = SYSUTCDATETIME(),
        updated_by         = @actor_id
    WHERE id = @id;
END;
