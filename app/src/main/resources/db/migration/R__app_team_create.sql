CREATE OR ALTER PROCEDURE app.team_create
    @actor_id     int,
    @name         nvarchar(200),
    @lead_user_id int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE @actor_role varchar(10);
    EXEC crm.actor_require @actor_id, @actor_role OUTPUT;

    IF @actor_role <> 'ADMIN'
        THROW 51301, N'You are not allowed to perform this operation.', 1;

    SET @name = NULLIF(LTRIM(RTRIM(@name)), N'');
    IF @name IS NULL
        THROW 51036, N'Team name is required.', 1;
    IF NOT EXISTS (SELECT 1 FROM crm.users WHERE id = @lead_user_id AND role = 'MANAGER' AND is_active = 1)
        THROW 51035, N'A team lead must be an active manager.', 1;

    -- A duplicate name fails on uq_teams_name (2627) and becomes 409 in the API.
    DECLARE @id int;
    INSERT crm.teams (name, lead_user_id, created_by) VALUES (@name, @lead_user_id, @actor_id);
    SET @id = SCOPE_IDENTITY();

    SELECT t.id, t.name, t.lead_user_id, u.login AS lead_login, 0 AS member_count, t.created_at
    FROM crm.teams AS t
    JOIN crm.users AS u ON u.id = t.lead_user_id
    WHERE t.id = @id;
END;
