-- ADMIN or the lead of the team adds an active user. Already a member = no change.
CREATE OR ALTER PROCEDURE app.team_member_add
    @actor_id int,
    @team_id  int,
    @user_id  int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE @actor_role varchar(10);
    EXEC crm.actor_require @actor_id, @actor_role OUTPUT;

    DECLARE @lead_user_id int = (SELECT lead_user_id FROM crm.teams WHERE id = @team_id);
    IF @lead_user_id IS NULL
        THROW 51404, N'Team not found.', 1;
    IF @actor_role <> 'ADMIN' AND @lead_user_id <> @actor_id
        THROW 51301, N'You are not allowed to perform this operation.', 1;
    IF NOT EXISTS (SELECT 1 FROM crm.users WHERE id = @user_id AND is_active = 1)
        THROW 51038, N'Only an active user can join a team.', 1;

    IF NOT EXISTS (SELECT 1 FROM crm.team_members WITH (UPDLOCK, HOLDLOCK) WHERE team_id = @team_id AND user_id = @user_id)
        INSERT crm.team_members (team_id, user_id) VALUES (@team_id, @user_id);
END;
