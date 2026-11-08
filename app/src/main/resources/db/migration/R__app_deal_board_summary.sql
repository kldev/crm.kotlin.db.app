/*
  The board's totals (ADR-0015): per stage and currency the number of deals, their value and the value weighted by the
  stage's probability - over every deal the board's filters match, not only the cards shown. Same filters as
  app.deal_board.
*/
CREATE OR ALTER PROCEDURE app.deal_board_summary
    @actor_id      int,
    @scope         varchar(10)   = 'ALL',
    @owner_user_id int           = NULL,
    @search        nvarchar(100) = NULL,
    @closed_days   int           = 30
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @role varchar(10);
    EXEC crm.actor_require @actor_id, @role OUTPUT;
    IF ISNULL(@scope, '') NOT IN ('MINE', 'ALL')
        THROW 51195, N'Scope must be MINE or ALL.', 1;
    IF @closed_days IS NULL OR @closed_days NOT BETWEEN 0 AND 365
        THROW 51195, N'Closed deals are shown for 0 to 365 days.', 1;
    SET @search = NULLIF(LTRIM(RTRIM(@search)), N'');
    DECLARE @closed_since datetime2(3) = DATEADD(DAY, -@closed_days, SYSUTCDATETIME());

    SELECT d.stage, d.currency, COUNT(*) AS deals, SUM(d.value) AS value,
           CAST(SUM(d.value * s.probability / 100.0) AS decimal(18, 2)) AS weighted
    FROM crm.deals AS d
    JOIN crm.deal_stages AS s ON s.stage = d.stage
    JOIN crm.clients AS c ON c.id = d.client_id
    WHERE (s.is_closed = 0 OR d.closed_at >= @closed_since)
      AND (@role <> 'SALES' OR c.assigned_user_id = @actor_id)
      AND (@scope <> 'MINE' OR d.owner_user_id = @actor_id)
      AND (@owner_user_id IS NULL OR d.owner_user_id = @owner_user_id)
      AND (@search IS NULL OR d.title LIKE @search + N'%' OR c.name LIKE @search + N'%')
    GROUP BY d.stage, d.currency
    ORDER BY d.stage, d.currency
    OPTION (RECOMPILE);
END;
