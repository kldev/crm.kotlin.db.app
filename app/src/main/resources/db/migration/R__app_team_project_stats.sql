-- Projects and budget of a team per stage, from the indexed view: at most 6 rows read, however many projects.
-- WITH (NOEXPAND) is required: SQL Server Express never uses an indexed view on its own.
CREATE OR ALTER PROCEDURE app.team_project_stats
    @actor_id int,
    @team_id  int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE @actor_role varchar(10);
    EXEC crm.actor_require @actor_id, @actor_role OUTPUT;

    IF NOT EXISTS (SELECT 1 FROM crm.teams WHERE id = @team_id)
        THROW 51404, N'Team not found.', 1;

    SELECT s.stage, s.project_count, s.budget_total
    FROM crm.v_team_project_stats AS s WITH (NOEXPAND)
    WHERE s.team_id = @team_id
    ORDER BY s.stage;
END;
