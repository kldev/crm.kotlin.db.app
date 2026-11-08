/*
  Moves a project to another stage. Allowed moves are rows of crm.project_stage_transitions (otherwise 51902).
  Writes the history row and, when given, a comment - in one transaction with the stage change.
  Same stage = no change: no history row, no comment, same row_version.
*/
CREATE OR ALTER PROCEDURE app.project_change_stage
    @actor_id    int,
    @id          bigint,
    @to_stage    varchar(12),
    @comment     nvarchar(4000) = NULL,
    @row_version binary(8)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE @actor_role varchar(10);
    EXEC crm.actor_require @actor_id, @actor_role OUTPUT;

    IF @to_stage IS NULL OR @to_stage NOT IN ('NEW', 'ACCEPTED', 'ACTIVE', 'ON_HOLD', 'CLOSED', 'DECLINED')
        THROW 51031, N'Stage must be NEW, ACCEPTED, ACTIVE, ON_HOLD, CLOSED or DECLINED.', 1;

    EXEC crm.project_require_visible @actor_id, @actor_role, @id;
    SET @comment = NULLIF(LTRIM(RTRIM(@comment)), N'');

    DECLARE @current binary(8), @from_stage varchar(12);

    BEGIN TRANSACTION;

    SELECT @current = row_version, @from_stage = stage FROM crm.projects WITH (UPDLOCK) WHERE id = @id;

    IF @current <> @row_version
        THROW 51901, N'The project was changed by someone else. Reload it and try again.', 1;

    IF @from_stage <> @to_stage
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM crm.project_stage_transitions
                       WHERE from_stage = @from_stage AND to_stage = @to_stage)
            THROW 51902, N'This stage change is not allowed.', 1;

        UPDATE crm.projects
        SET stage            = @to_stage,
            stage_changed_at = SYSUTCDATETIME(),
            updated_at       = SYSUTCDATETIME(),
            updated_by       = @actor_id
        WHERE id = @id;

        INSERT crm.project_stage_history (project_id, from_stage, to_stage, changed_by)
        VALUES (@id, @from_stage, @to_stage, @actor_id);

        IF @comment IS NOT NULL
            INSERT crm.project_comments (project_id, author_id, body)
            VALUES (@id, @actor_id, @comment);
    END;

    COMMIT TRANSACTION;

    SELECT v.id, v.name, v.stage, v.start_date, v.due_date, v.budget, v.is_overdue, v.stage_changed_at,
           v.client_id, v.client_name, v.client_city, v.team_id, v.team_name, v.owner_user_id, v.owner_login,
           v.owner_display_name, v.legal_entity_id, v.legal_entity_name, v.updated_at, v.row_version
    FROM crm.v_projects AS v
    WHERE v.id = @id;
END;
