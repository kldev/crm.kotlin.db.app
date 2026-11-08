-- Counts a failed login. After @max_failed failures in a row the account is locked for @lock_minutes.
-- Unknown login: nothing happens (and the caller answers exactly like for a wrong password).
CREATE OR ALTER PROCEDURE app.user_login_failed
    @login        varchar(64),
    @max_failed   int,
    @lock_minutes int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    UPDATE crm.users
    SET failed_login_count = IIF(failed_login_count + 1 >= @max_failed, 0, failed_login_count + 1),
        locked_until       = IIF(failed_login_count + 1 >= @max_failed,
                                 DATEADD(MINUTE, @lock_minutes, SYSUTCDATETIME()),
                                 locked_until)
    WHERE login = LOWER(LTRIM(RTRIM(@login)));
END;
