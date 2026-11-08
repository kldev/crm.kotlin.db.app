-- Users page (keyset by id). ADMIN and MANAGER (who assigns clients to SALES users).
CREATE OR ALTER PROCEDURE app.user_list
    @actor_id  int,
    @role      varchar(10) = NULL,
    @after_id  int         = NULL,
    @page_size int         = 50
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE @actor_role varchar(10);
    EXEC crm.actor_require @actor_id, @actor_role OUTPUT;

    IF @actor_role NOT IN ('ADMIN', 'MANAGER')
        THROW 51301, N'You are not allowed to perform this operation.', 1;
    IF @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 200
        THROW 51014, N'Page size must be between 1 and 200.', 1;
    IF @role IS NOT NULL AND @role NOT IN ('ADMIN', 'MANAGER', 'SALES')
        THROW 51016, N'Role must be ADMIN, MANAGER or SALES.', 1;

    -- page_size + 1 rows: the caller knows whether there is a next page.
    SELECT TOP (@page_size + 1)
           id, login, display_name, role, is_active, locked_until, last_login_at, created_at, updated_at, row_version
    FROM crm.users
    WHERE (@role IS NULL OR role = @role)
      AND (@after_id IS NULL OR id > @after_id)
    ORDER BY id
    OPTION (RECOMPILE);
END;
