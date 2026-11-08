CREATE OR ALTER PROCEDURE app.client_get
    @actor_id int,
    @id       bigint
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE @actor_role varchar(10);
    EXEC crm.actor_require @actor_id, @actor_role OUTPUT;

    DECLARE @owner_id int = IIF(@actor_role = 'SALES', @actor_id, NULL);

    -- A client of another sales user is "not found", not "forbidden": its existence is not revealed.
    IF NOT EXISTS (SELECT 1 FROM crm.clients
                   WHERE id = @id AND (@owner_id IS NULL OR assigned_user_id = @owner_id))
        THROW 51401, N'Client not found.', 1;

    SELECT c.id, c.name, c.nip, c.email, c.phone, c.city, c.status, c.assigned_user_id,
           u.login AS assigned_user_login, c.note, c.created_at, c.created_by, c.updated_at, c.updated_by,
           c.row_version
    FROM crm.clients AS c
    LEFT JOIN crm.users AS u ON u.id = c.assigned_user_id
    WHERE c.id = @id;
END;
