CREATE OR ALTER PROCEDURE app.team_member_list
    @actor_id int,
    @team_id  int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE @actor_role varchar(10);
    EXEC crm.actor_require @actor_id, @actor_role OUTPUT;

    IF NOT EXISTS (SELECT 1 FROM crm.teams WHERE id = @team_id)
        THROW 51404, N'Team not found.', 1;

    SELECT tm.user_id, u.login, u.display_name, u.role, u.is_active, tm.joined_at
    FROM crm.team_members AS tm
    JOIN crm.users AS u ON u.id = tm.user_id
    WHERE tm.team_id = @team_id
    ORDER BY u.login;
END;
