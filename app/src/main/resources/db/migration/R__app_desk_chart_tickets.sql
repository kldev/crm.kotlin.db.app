/*
  The tickets behind the desk charts (ADR-0011): every ticket open at some moment of [@from, @to] (Warsaw days, both
  included) or reported in it, optionally of one category. The deadline state of open tickets is computed here, with
  the same clock and the same 60-minute rule as the lists; the Warsaw weekday (0 = Monday) and hour of the report feed
  the heatmap. `now_utc` is that clock, so the caller's "open now" agrees with the lists.
*/
CREATE OR ALTER PROCEDURE app.desk_chart_tickets
    @actor_id     int,
    @from         date,
    @to           date,
    @category_key varchar(40) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    IF @from IS NULL OR @to IS NULL OR @to < @from OR DATEDIFF(DAY, @from, @to) > 366
        THROW 51150, N'Choose a period of at most one year (from <= to).', 1;

    DECLARE @tz sysname = 'Central European Standard Time';
    DECLARE @now datetime2(3) = SYSUTCDATETIME();
    DECLARE @soon datetime2(3) = DATEADD(MINUTE, 60, @now);
    DECLARE @from_utc datetime2(3) =
        CAST((CAST(@from AS datetime2(3)) AT TIME ZONE @tz) AT TIME ZONE 'UTC' AS datetime2(3));
    DECLARE @until_utc datetime2(3) =
        CAST((CAST(DATEADD(DAY, 1, @to) AS datetime2(3)) AT TIME ZONE @tz) AT TIME ZONE 'UTC' AS datetime2(3));

    SELECT t.id, t.category_key, t.subcategory_key, t.priority, t.status, t.reported_at, t.deadline, t.resolved_at,
           t.resolved_late, t.assignee_user_id, t.assignee_name,
           CAST(IIF(t.status <> 'DONE' AND t.deadline <= @now, 1, 0) AS bit) AS is_overdue,
           CAST(IIF(t.status <> 'DONE' AND t.deadline > @now AND t.deadline < @soon, 1, 0) AS bit) AS is_due_soon,
           DATEDIFF(DAY, '19000101', CAST(local.at AS date)) % 7 AS report_weekday,
           DATEPART(HOUR, local.at) AS report_hour,
           @now AS now_utc
    FROM crm.tickets AS t
    CROSS APPLY (SELECT CAST((t.reported_at AT TIME ZONE 'UTC') AT TIME ZONE @tz AS datetime2(3)) AS at) AS local
    WHERE t.reported_at < @until_utc
      AND (t.resolved_at IS NULL OR t.resolved_at >= @from_utc)
      AND (@category_key IS NULL OR t.category_key = @category_key)
    OPTION (RECOMPILE);
END;
