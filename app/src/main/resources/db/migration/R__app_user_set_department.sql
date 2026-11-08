-- An administrator sets a user's department (ADR-0014); NULL takes it off. 51183 for a name off the list.
CREATE OR ALTER PROCEDURE app.user_set_department
    @actor_id   int,
    @user_id    int,
    @department nvarchar(50) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @role varchar(10);
    EXEC crm.actor_require @actor_id, @role OUTPUT;
    IF @role <> 'ADMIN'
        THROW 51301, N'You are not allowed to perform this operation.', 1;
    SET @department = NULLIF(LTRIM(RTRIM(@department)), N'');
    IF @department IS NOT NULL AND NOT EXISTS (SELECT 1 FROM crm.departments WHERE name = @department)
        THROW 51183, N'Choose a department from the list.', 1;
    UPDATE crm.users SET department = @department, updated_at = SYSUTCDATETIME(), updated_by = @actor_id WHERE id = @user_id;
    IF @@ROWCOUNT = 0
        THROW 51402, N'User not found.', 1;
    SELECT id, display_name, department FROM crm.users WHERE id = @user_id;
END;
