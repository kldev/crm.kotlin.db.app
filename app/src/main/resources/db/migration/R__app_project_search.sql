/*
  Projects page from crm.v_projects, ordered by (due_date, id), keyset pagination: next page after
  (@after_due_date, @after_id). Returns @page_size + 1 rows so the caller knows if there is a next page.

  Filters: stage, team, client, owner, due date range, overdue only. Each filter has an index that starts with it
  and ends with (due_date, id), so a page is a range seek plus TOP, whatever the size of crm.projects.

  SALES: visible projects are a union of three small, indexed sets (own projects, projects of own teams, projects
  of own clients). Building that set first is cheaper than testing visibility row by row while scanning
  millions of projects in due-date order.
*/
CREATE OR ALTER PROCEDURE app.project_search
    @actor_id       int,
    @stage          varchar(12) = NULL,
    @team_id        int         = NULL,
    @client_id      bigint      = NULL,
    @owner_user_id  int         = NULL,
    @overdue_only   bit         = 0,
    @due_from       date        = NULL,
    @due_to         date        = NULL,
    @after_due_date date        = NULL,
    @after_id       bigint      = NULL,
    @page_size      int         = 50
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE @actor_role varchar(10);
    EXEC crm.actor_require @actor_id, @actor_role OUTPUT;

    IF @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 200
        THROW 51014, N'Page size must be between 1 and 200.', 1;
    IF @stage IS NOT NULL AND @stage NOT IN ('NEW', 'ACCEPTED', 'ACTIVE', 'ON_HOLD', 'CLOSED', 'DECLINED')
        THROW 51031, N'Stage must be NEW, ACCEPTED, ACTIVE, ON_HOLD, CLOSED or DECLINED.', 1;

    DECLARE @today date = CAST(SYSUTCDATETIME() AS date);
    SET @overdue_only = ISNULL(@overdue_only, 0);
    -- Overdue projects: due before today. Keyset continues after (@after_due_date, @after_id).
    IF @overdue_only = 1 AND (@due_to IS NULL OR @due_to >= @today)
        SET @due_to = DATEADD(DAY, -1, @today);
    -- Lower bound for the keyset: lets every branch seek straight to the next page.
    IF @after_due_date IS NOT NULL AND (@due_from IS NULL OR @due_from < @after_due_date)
        SET @due_from = @after_due_date;

    IF @actor_role = 'SALES'
    BEGIN
        DECLARE @visible TABLE (id bigint PRIMARY KEY);

        INSERT @visible (id)
        SELECT p.id
        FROM crm.projects AS p
        WHERE p.owner_user_id = @actor_id
          AND (@due_from IS NULL OR p.due_date >= @due_from)
        UNION
        SELECT p.id
        FROM crm.team_members AS tm
        JOIN crm.projects AS p ON p.team_id = tm.team_id
        WHERE tm.user_id = @actor_id
          AND (@due_from IS NULL OR p.due_date >= @due_from)
        UNION
        SELECT p.id
        FROM crm.clients AS c
        JOIN crm.projects AS p ON p.client_id = c.id
        WHERE c.assigned_user_id = @actor_id
          AND (@due_from IS NULL OR p.due_date >= @due_from)
        OPTION (RECOMPILE);

        SELECT TOP (@page_size + 1)
               v.id, v.name, v.stage, v.start_date, v.due_date, v.budget, v.is_overdue, v.stage_changed_at,
               v.client_id, v.client_name, v.client_city, v.team_id, v.team_name, v.owner_user_id, v.owner_login,
               v.owner_display_name, v.updated_at, v.row_version
        FROM @visible AS vis
        JOIN crm.v_projects AS v ON v.id = vis.id
        WHERE (@stage IS NULL OR v.stage = @stage)
          AND (@team_id IS NULL OR v.team_id = @team_id)
          AND (@client_id IS NULL OR v.client_id = @client_id)
          AND (@owner_user_id IS NULL OR v.owner_user_id = @owner_user_id)
          AND (@overdue_only = 0 OR v.stage IN ('NEW', 'ACCEPTED', 'ACTIVE', 'ON_HOLD'))
          AND (@due_from IS NULL OR v.due_date >= @due_from)
          AND (@due_to IS NULL OR v.due_date <= @due_to)
          AND (@after_due_date IS NULL OR v.due_date > @after_due_date
               OR (v.due_date = @after_due_date AND v.id > @after_id))
        ORDER BY v.due_date, v.id
        OPTION (RECOMPILE);
        RETURN;
    END;

    IF @overdue_only = 1
    BEGIN
        -- Literal stage list = the predicate of the filtered index ix_projects_open_due.
        SELECT TOP (@page_size + 1)
               v.id, v.name, v.stage, v.start_date, v.due_date, v.budget, v.is_overdue, v.stage_changed_at,
               v.client_id, v.client_name, v.client_city, v.team_id, v.team_name, v.owner_user_id, v.owner_login,
               v.owner_display_name, v.updated_at, v.row_version
        FROM crm.v_projects AS v
        WHERE v.stage IN ('NEW', 'ACCEPTED', 'ACTIVE', 'ON_HOLD')
          AND (@stage IS NULL OR v.stage = @stage)
          AND (@team_id IS NULL OR v.team_id = @team_id)
          AND (@client_id IS NULL OR v.client_id = @client_id)
          AND (@owner_user_id IS NULL OR v.owner_user_id = @owner_user_id)
          AND (@due_from IS NULL OR v.due_date >= @due_from)
          AND v.due_date <= @due_to
          AND (@after_due_date IS NULL OR v.due_date > @after_due_date
               OR (v.due_date = @after_due_date AND v.id > @after_id))
        ORDER BY v.due_date, v.id
        OPTION (RECOMPILE);
        RETURN;
    END;

    SELECT TOP (@page_size + 1)
           v.id, v.name, v.stage, v.start_date, v.due_date, v.budget, v.is_overdue, v.stage_changed_at,
           v.client_id, v.client_name, v.client_city, v.team_id, v.team_name, v.owner_user_id, v.owner_login,
           v.owner_display_name, v.updated_at, v.row_version
    FROM crm.v_projects AS v
    WHERE (@stage IS NULL OR v.stage = @stage)
      AND (@team_id IS NULL OR v.team_id = @team_id)
      AND (@client_id IS NULL OR v.client_id = @client_id)
      AND (@owner_user_id IS NULL OR v.owner_user_id = @owner_user_id)
      AND (@due_from IS NULL OR v.due_date >= @due_from)
      AND (@due_to IS NULL OR v.due_date <= @due_to)
      AND (@after_due_date IS NULL OR v.due_date > @after_due_date
           OR (v.due_date = @after_due_date AND v.id > @after_id))
    ORDER BY v.due_date, v.id
    OPTION (RECOMPILE);
END;
