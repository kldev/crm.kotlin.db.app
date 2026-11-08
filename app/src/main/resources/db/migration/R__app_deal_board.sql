/*
  The kanban board (ADR-0015): open deals and the ones closed in the last @closed_days days, by stage and expected close
  date - at most @per_stage cards per column (100 by default), so a column of thousands never pushes the others off
  the board; the totals come from app.deal_board_summary. @scope MINE (I own them) or ALL - for SALES "all" is still
  only deals of their own clients. @owner_user_id narrows to one salesperson, @search to a title or client name prefix.
*/
CREATE OR ALTER PROCEDURE app.deal_board
    @actor_id      int,
    @scope         varchar(10)   = 'ALL',
    @owner_user_id int           = NULL,
    @search        nvarchar(100) = NULL,
    @closed_days   int           = 30,
    @per_stage     int           = 100
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @role varchar(10);
    EXEC crm.actor_require @actor_id, @role OUTPUT;
    IF ISNULL(@scope, '') NOT IN ('MINE', 'ALL')
        THROW 51195, N'Scope must be MINE or ALL.', 1;
    IF @closed_days IS NULL OR @closed_days NOT BETWEEN 0 AND 365 OR @per_stage IS NULL OR @per_stage NOT BETWEEN 1 AND 500
        THROW 51195, N'Closed deals are shown for 0 to 365 days, 1 to 500 cards per column.', 1;
    SET @search = NULLIF(LTRIM(RTRIM(@search)), N'');
    DECLARE @closed_since datetime2(3) = DATEADD(DAY, -@closed_days, SYSUTCDATETIME());

    WITH board AS (
        SELECT d.id, ROW_NUMBER() OVER (PARTITION BY d.stage ORDER BY d.expected_close, d.id) AS rn
        FROM crm.deals AS d
        JOIN crm.deal_stages AS s ON s.stage = d.stage
        JOIN crm.clients AS c ON c.id = d.client_id
        WHERE (s.is_closed = 0 OR d.closed_at >= @closed_since)
          AND (@role <> 'SALES' OR c.assigned_user_id = @actor_id)
          AND (@scope <> 'MINE' OR d.owner_user_id = @actor_id)
          AND (@owner_user_id IS NULL OR d.owner_user_id = @owner_user_id)
          AND (@search IS NULL OR d.title LIKE @search + N'%' OR c.name LIKE @search + N'%')
    )
    SELECT d.id, d.title, d.client_id, c.name AS client_name, d.owner_user_id, o.display_name AS owner_name, d.stage,
           s.probability, s.is_closed, d.value, d.currency, d.expected_close, d.offer_id, f.number AS offer_number,
           d.lost_reason, d.stage_changed_at, d.closed_at, d.created_at, d.updated_at, d.row_version,
           d.next_step, d.next_step_at, d.last_activity_at, d.last_activity_type
    FROM board AS b
    JOIN crm.deals AS d ON d.id = b.id
    JOIN crm.deal_stages AS s ON s.stage = d.stage
    JOIN crm.clients AS c ON c.id = d.client_id
    JOIN crm.users AS o ON o.id = d.owner_user_id
    LEFT JOIN crm.offers AS f ON f.id = d.offer_id
    WHERE b.rn <= @per_stage
    ORDER BY s.sort_order, d.expected_close, d.id
    OPTION (RECOMPILE);
END;
