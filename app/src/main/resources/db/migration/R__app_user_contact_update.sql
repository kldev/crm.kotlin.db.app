/*
  Set a user's contact for offers (ADR-0013): one's own, or anyone's for ADMIN. Job title up to 100 characters, a phone
  of digits, spaces, + ( ) - (6-30), an e-mail address; an empty value clears it (51177).
*/
CREATE OR ALTER PROCEDURE app.user_contact_update
    @actor_id  int,
    @user_id   int,
    @job_title nvarchar(400) = NULL,
    @phone     varchar(100)  = NULL,
    @email     varchar(400)  = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @role varchar(10);
    EXEC crm.actor_require @actor_id, @role OUTPUT;
    IF @user_id <> @actor_id AND @role <> 'ADMIN'
        THROW 51301, N'You are not allowed to perform this operation.', 1;
    IF NOT EXISTS (SELECT 1 FROM crm.users WHERE id = @user_id)
        THROW 51402, N'User not found.', 1;
    SET @job_title = NULLIF(LTRIM(RTRIM(@job_title)), N'');
    SET @phone = NULLIF(LTRIM(RTRIM(@phone)), '');
    SET @email = NULLIF(LOWER(LTRIM(RTRIM(@email))), '');
    IF LEN(@job_title) > 100
        THROW 51177, N'The job title can have at most 100 characters.', 1;
    IF @phone IS NOT NULL AND (LEN(@phone) NOT BETWEEN 6 AND 30 OR @phone LIKE '%[^0-9 +()-]%')
        THROW 51177, N'The phone number can have 6-30 digits, spaces and + ( ) -.', 1;
    IF @email IS NOT NULL AND (LEN(@email) > 254 OR @email LIKE '% %' OR @email NOT LIKE '_%@_%._%'
                               OR LEN(@email) - LEN(REPLACE(@email, '@', '')) <> 1)
        THROW 51177, N'Not a valid e-mail address.', 1;
    UPDATE crm.users SET job_title = @job_title, phone = @phone, email = @email, updated_at = SYSUTCDATETIME(),
                         updated_by = @actor_id
    WHERE id = @user_id;
    SELECT id, display_name, job_title, phone, email FROM crm.users WHERE id = @user_id;
END;
