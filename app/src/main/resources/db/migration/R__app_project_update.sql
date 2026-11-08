-- Project details (not the stage: see app.project_change_stage). Optimistic concurrency with @row_version;
-- identical values = no write, same row_version. Closed and declined projects are read-only (51902).
CREATE OR ALTER PROCEDURE app.project_update
    @actor_id      int,
    @id            bigint,
    @team_id       int,
    @owner_user_id int,
    @name          nvarchar(200),
    @start_date    date,
    @due_date      date,
    @budget        decimal(19, 2),
    @row_version   binary(8)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE @actor_role varchar(10);
    EXEC crm.actor_require @actor_id, @actor_role OUTPUT;
    EXEC crm.project_require_visible @actor_id, @actor_role, @id;

    SET @name = NULLIF(LTRIM(RTRIM(@name)), N'');
    EXEC crm.project_validate @name, @team_id, @owner_user_id, @start_date, @due_date, @budget;

    DECLARE @current binary(8), @stage varchar(12);

    BEGIN TRANSACTION;

    SELECT @current = row_version, @stage = stage FROM crm.projects WITH (UPDLOCK) WHERE id = @id;

    IF @current <> @row_version
        THROW 51901, N'The project was changed by someone else. Reload it and try again.', 1;
    IF @stage IN ('CLOSED', 'DECLINED')
        THROW 51902, N'A closed or declined project cannot be changed.', 1;

    UPDATE crm.projects
    SET team_id       = @team_id,
        owner_user_id = @owner_user_id,
        name          = @name,
        start_date    = @start_date,
        due_date      = @due_date,
        budget        = @budget,
        updated_at    = SYSUTCDATETIME(),
        updated_by    = @actor_id
    WHERE id = @id
      AND EXISTS (SELECT @team_id, @owner_user_id, @name, @start_date, @due_date, @budget
                  EXCEPT
                  SELECT team_id, owner_user_id, name, start_date, due_date, budget);

    COMMIT TRANSACTION;

    SELECT v.id, v.name, v.stage, v.start_date, v.due_date, v.budget, v.is_overdue, v.stage_changed_at,
           v.client_id, v.client_name, v.client_city, v.team_id, v.team_name, v.owner_user_id, v.owner_login,
           v.owner_display_name, v.updated_at, v.row_version
    FROM crm.v_projects AS v
    WHERE v.id = @id;
END;
