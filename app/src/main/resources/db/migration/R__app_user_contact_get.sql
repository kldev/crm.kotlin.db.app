-- A user's contact for offers (ADR-0013): one's own, or anyone's for ADMIN and MANAGER.
CREATE OR ALTER PROCEDURE app.user_contact_get
    @actor_id int,
    @user_id  int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @role varchar(10);
    EXEC crm.actor_require @actor_id, @role OUTPUT;
    IF @user_id <> @actor_id AND @role NOT IN ('ADMIN', 'MANAGER')
        THROW 51301, N'You are not allowed to perform this operation.', 1;
    IF NOT EXISTS (SELECT 1 FROM crm.users WHERE id = @user_id)
        THROW 51402, N'User not found.', 1;
    SELECT id, display_name, job_title, phone, email FROM crm.users WHERE id = @user_id;
END;
