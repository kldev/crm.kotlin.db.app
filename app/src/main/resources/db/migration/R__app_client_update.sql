/*
  Full update of a client with optimistic concurrency: @row_version must be the value the caller read
  (51901 when someone else changed the client in the meantime). Identical values = no write, same row_version.
*/
CREATE OR ALTER PROCEDURE app.client_update
    @actor_id         int,
    @id               bigint,
    @name             nvarchar(200),
    @nip              varchar(20)    = NULL,
    @email            varchar(254)   = NULL,
    @phone            varchar(30)    = NULL,
    @city             nvarchar(100)  = NULL,
    @status           varchar(10),
    @assigned_user_id int            = NULL,
    @note             nvarchar(2000) = NULL,
    @row_version      binary(8)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE @actor_role varchar(10);
    EXEC crm.actor_require @actor_id, @actor_role OUTPUT;

    SET @name = NULLIF(LTRIM(RTRIM(@name)), N'');
    SET @nip = NULLIF(REPLACE(REPLACE(LTRIM(RTRIM(@nip)), '-', ''), ' ', ''), '');
    SET @email = NULLIF(LOWER(LTRIM(RTRIM(@email))), '');
    SET @phone = NULLIF(LTRIM(RTRIM(@phone)), '');
    SET @city = NULLIF(LTRIM(RTRIM(@city)), N'');
    SET @note = NULLIF(LTRIM(RTRIM(@note)), N'');

    EXEC crm.client_validate @name, @nip, @email, @status;

    DECLARE @owner_id int = IIF(@actor_role = 'SALES', @actor_id, NULL);
    DECLARE @current binary(8);

    BEGIN TRANSACTION;

    SELECT @current = row_version
    FROM crm.clients WITH (UPDLOCK)
    WHERE id = @id
      AND (@owner_id IS NULL OR assigned_user_id = @owner_id);

    IF @current IS NULL
        THROW 51401, N'Client not found.', 1;
    IF @current <> @row_version
        THROW 51901, N'The client was changed by someone else. Reload it and try again.', 1;

    EXEC crm.client_check_assignee @actor_id, @actor_role, @assigned_user_id;

    UPDATE crm.clients
    SET name             = @name,
        nip              = @nip,
        email            = @email,
        phone            = @phone,
        city             = @city,
        status           = @status,
        assigned_user_id = @assigned_user_id,
        note             = @note,
        updated_at       = SYSUTCDATETIME(),
        updated_by       = @actor_id
    WHERE id = @id
      AND EXISTS (SELECT @name, @nip, @email, @phone, @city, @status, @assigned_user_id, @note
                  EXCEPT
                  SELECT name, nip, email, phone, city, status, assigned_user_id, note);

    COMMIT TRANSACTION;

    SELECT c.id, c.name, c.nip, c.email, c.phone, c.city, c.status, c.assigned_user_id,
           u.login AS assigned_user_login, c.note, c.created_at, c.created_by, c.updated_at, c.updated_by,
           c.row_version
    FROM crm.clients AS c
    LEFT JOIN crm.users AS u ON u.id = c.assigned_user_id
    WHERE c.id = @id;
END;
