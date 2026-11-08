-- Internal helper: project field rules and the owner/team rule, shared by create and update.
CREATE OR ALTER PROCEDURE crm.project_validate
    @name          nvarchar(200),
    @team_id       int,
    @owner_user_id int,
    @start_date    date,
    @due_date      date,
    @budget        decimal(19, 2)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    IF @name IS NULL
        THROW 51030, N'Project name is required.', 1;
    IF @start_date IS NULL OR @due_date IS NULL OR @due_date < @start_date
        THROW 51032, N'Start and due dates are required and the due date cannot be before the start date.', 1;
    IF @budget IS NULL OR @budget < 0
        THROW 51033, N'Budget must be 0 or more.', 1;
    IF NOT EXISTS (SELECT 1 FROM crm.teams WHERE id = @team_id)
        THROW 51404, N'Team not found.', 1;
    IF NOT EXISTS (SELECT 1
                   FROM crm.team_members AS tm
                   JOIN crm.users AS u ON u.id = tm.user_id
                   WHERE tm.team_id = @team_id AND tm.user_id = @owner_user_id AND u.is_active = 1)
        THROW 51037, N'The project owner must be an active member of the project team.', 1;
END;
