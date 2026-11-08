/*
  Number of projects matching the filters of app.project_search, with the same visibility (SALES: own projects,
  projects of own teams, projects of own clients, each counted once). Not part of the list: a count reads every
  matching row, so the list stays keyset-only and the UI calls this only when the user asks for the total.
*/
CREATE OR ALTER PROCEDURE app.project_count
    @actor_id      int,
    @stage         varchar(12) = NULL,
    @team_id       int         = NULL,
    @client_id     bigint      = NULL,
    @owner_user_id int         = NULL,
    @overdue_only  bit         = 0,
    @due_from      date        = NULL,
    @due_to        date        = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE @actor_role varchar(10);
    EXEC crm.actor_require @actor_id, @actor_role OUTPUT;

    IF @stage IS NOT NULL AND @stage NOT IN ('NEW', 'ACCEPTED', 'ACTIVE', 'ON_HOLD', 'CLOSED', 'DECLINED')
        THROW 51031, N'Stage must be NEW, ACCEPTED, ACTIVE, ON_HOLD, CLOSED or DECLINED.', 1;

    DECLARE @today date = CAST(SYSUTCDATETIME() AS date);
    SET @overdue_only = ISNULL(@overdue_only, 0);
    IF @overdue_only = 1 AND (@due_to IS NULL OR @due_to >= @today)
        SET @due_to = DATEADD(DAY, -1, @today);

    IF @actor_role = 'SALES'
    BEGIN
        -- UNION (not UNION ALL): a project visible through two sources is counted once.
        SELECT COUNT_BIG(*) AS total
        FROM (
            SELECT p.id
            FROM crm.projects AS p
            WHERE p.owner_user_id = @actor_id
            UNION
            SELECT p.id
            FROM crm.team_members AS tm
            JOIN crm.projects AS p ON p.team_id = tm.team_id
            WHERE tm.user_id = @actor_id
            UNION
            SELECT p.id
            FROM crm.clients AS c
            JOIN crm.projects AS p ON p.client_id = c.id
            WHERE c.assigned_user_id = @actor_id
        ) AS visible
        JOIN crm.projects AS p ON p.id = visible.id
        WHERE (@stage IS NULL OR p.stage = @stage)
          AND (@team_id IS NULL OR p.team_id = @team_id)
          AND (@client_id IS NULL OR p.client_id = @client_id)
          AND (@owner_user_id IS NULL OR p.owner_user_id = @owner_user_id)
          AND (@overdue_only = 0 OR p.stage IN ('NEW', 'ACCEPTED', 'ACTIVE', 'ON_HOLD'))
          AND (@due_from IS NULL OR p.due_date >= @due_from)
          AND (@due_to IS NULL OR p.due_date <= @due_to)
        OPTION (RECOMPILE);
        RETURN;
    END;

    SELECT COUNT_BIG(*) AS total
    FROM crm.projects AS p
    WHERE (@stage IS NULL OR p.stage = @stage)
      AND (@team_id IS NULL OR p.team_id = @team_id)
      AND (@client_id IS NULL OR p.client_id = @client_id)
      AND (@owner_user_id IS NULL OR p.owner_user_id = @owner_user_id)
      AND (@overdue_only = 0 OR p.stage IN ('NEW', 'ACCEPTED', 'ACTIVE', 'ON_HOLD'))
      AND (@due_from IS NULL OR p.due_date >= @due_from)
      AND (@due_to IS NULL OR p.due_date <= @due_to)
    OPTION (RECOMPILE);
END;
