-- ADMIN or the team lead removes a member. A member who still owns open projects of the team stays (51905).
CREATE OR ALTER PROCEDURE app.team_member_remove
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
    IF EXISTS (SELECT 1 FROM crm.projects
               WHERE owner_user_id = @user_id AND team_id = @team_id
                 AND stage IN ('NEW', 'ACCEPTED', 'ACTIVE', 'ON_HOLD'))
        THROW 51905, N'The user still owns open projects of this team. Reassign them first.', 1;

    DELETE crm.team_members WHERE team_id = @team_id AND user_id = @user_id;
END;
