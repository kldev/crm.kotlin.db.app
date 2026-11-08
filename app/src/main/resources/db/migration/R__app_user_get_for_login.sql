-- Data for Spring Security: the hash is verified in the application (PasswordEncoder), never in SQL.
CREATE OR ALTER PROCEDURE app.user_get_for_login
    @login varchar(64)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    SELECT id, login, display_name, role, password_hash, is_active, locked_until
    FROM crm.users
    WHERE login = LOWER(LTRIM(RTRIM(@login)));
END;
