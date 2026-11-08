CREATE OR ALTER PROCEDURE app.user_login_succeeded
    @user_id int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    UPDATE crm.users
    SET failed_login_count = 0,
        locked_until       = NULL,
        last_login_at      = SYSUTCDATETIME()
    WHERE id = @user_id;
END;
