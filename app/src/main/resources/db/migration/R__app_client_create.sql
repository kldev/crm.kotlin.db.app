-- SALES creates clients for themselves (@assigned_user_id NULL = the actor); MANAGER/ADMIN assign to a SALES user
-- or leave the client unassigned. A duplicate NIP fails on ux_clients_nip (2601) and becomes 409 in the API.
CREATE OR ALTER PROCEDURE app.client_create
    @actor_id         int,
    @name             nvarchar(200),
    @nip              varchar(20)    = NULL,
    @email            varchar(254)   = NULL,
    @phone            varchar(30)    = NULL,
    @city             nvarchar(100)  = NULL,
    @status           varchar(10),
    @assigned_user_id int            = NULL,
    @note             nvarchar(2000) = NULL
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
    IF @actor_role = 'SALES' AND @assigned_user_id IS NULL
        SET @assigned_user_id = @actor_id;

    EXEC crm.client_validate @name, @nip, @email, @status;
    EXEC crm.client_check_assignee @actor_id, @actor_role, @assigned_user_id;

    DECLARE @id bigint;
    INSERT crm.clients (name, nip, email, phone, city, status, assigned_user_id, note, created_by, updated_by)
    VALUES (@name, @nip, @email, @phone, @city, @status, @assigned_user_id, @note, @actor_id, @actor_id);
    SET @id = SCOPE_IDENTITY();

    SELECT c.id, c.name, c.nip, c.email, c.phone, c.city, c.status, c.assigned_user_id,
           u.login AS assigned_user_login, c.note, c.created_at, c.created_by, c.updated_at, c.updated_by,
           c.row_version
    FROM crm.clients AS c
    LEFT JOIN crm.users AS u ON u.id = c.assigned_user_id
    WHERE c.id = @id;
END;
