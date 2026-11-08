/*
  How the agents work (ADR-0010): per agent and period (crm.desk_report_periods), the tickets they took from the pool,
  resolved, and resolved after the deadline - counted from the events, so a ticket handed over counts for whoever
  really took or resolved it - and what each one has in progress now. Agents without any of it are left out.
*/
CREATE OR ALTER PROCEDURE app.desk_report_agents
    @actor_id int,
    @previous bit = 0
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    DECLARE @wf date, @wt date, @mf date, @mt date, @tf date, @tt date;
    EXEC crm.desk_report_periods @previous, @wf OUTPUT, @wt OUTPUT, @mf OUTPUT, @mt OUTPUT, @tf OUTPUT, @tt OUTPUT;

    DECLARE @tz sysname = 'Central European Standard Time';
    DECLARE @w0 datetime2(3) = CAST((CAST(@wf AS datetime2(3)) AT TIME ZONE @tz) AT TIME ZONE 'UTC' AS datetime2(3)),
            @w1 datetime2(3) = CAST((CAST(@wt AS datetime2(3)) AT TIME ZONE @tz) AT TIME ZONE 'UTC' AS datetime2(3)),
            @m0 datetime2(3) = CAST((CAST(@mf AS datetime2(3)) AT TIME ZONE @tz) AT TIME ZONE 'UTC' AS datetime2(3)),
            @m1 datetime2(3) = CAST((CAST(@mt AS datetime2(3)) AT TIME ZONE @tz) AT TIME ZONE 'UTC' AS datetime2(3)),
            @t0 datetime2(3) = CAST((CAST(@tf AS datetime2(3)) AT TIME ZONE @tz) AT TIME ZONE 'UTC' AS datetime2(3)),
            @t1 datetime2(3) = CAST((CAST(@tt AS datetime2(3)) AT TIME ZONE @tz) AT TIME ZONE 'UTC' AS datetime2(3));
    DECLARE @from datetime2(3) = (SELECT MIN(v) FROM (VALUES (@w0), (@m0), (@t0)) AS x (v));
    DECLARE @until datetime2(3) = (SELECT MAX(v) FROM (VALUES (@w1), (@m1), (@t1)) AS x (v));

    WITH work AS (
        SELECT e.actor_user_id AS user_id, e.at,
               IIF(e.event_type = 'TicketTaken', 1, 0) AS taken,
               IIF(e.event_type = 'TicketResolved', 1, 0) AS resolved,
               IIF(e.event_type = 'TicketResolved' AND JSON_VALUE(e.data, '$.late') = 'true', 1, 0) AS late
        FROM crm.ticket_events AS e
        WHERE e.event_type IN ('TicketTaken', 'TicketResolved') AND e.at >= @from AND e.at < @until
          AND e.actor_user_id IS NOT NULL
    ),
    per_agent AS (
        SELECT user_id,
               SUM(IIF(at >= @w0 AND at < @w1, taken, 0)) AS taken_week,
               SUM(IIF(at >= @w0 AND at < @w1, resolved, 0)) AS resolved_week,
               SUM(IIF(at >= @w0 AND at < @w1, late, 0)) AS late_week,
               SUM(IIF(at >= @m0 AND at < @m1, taken, 0)) AS taken_month,
               SUM(IIF(at >= @m0 AND at < @m1, resolved, 0)) AS resolved_month,
               SUM(IIF(at >= @m0 AND at < @m1, late, 0)) AS late_month,
               SUM(IIF(at >= @t0 AND at < @t1, taken, 0)) AS taken_three,
               SUM(IIF(at >= @t0 AND at < @t1, resolved, 0)) AS resolved_three,
               SUM(IIF(at >= @t0 AND at < @t1, late, 0)) AS late_three
        FROM work
        GROUP BY user_id
    ),
    now_open AS (
        SELECT assignee_user_id AS user_id, COUNT(*) AS in_progress
        FROM crm.tickets WHERE status = 'IN_PROGRESS' GROUP BY assignee_user_id
    )
    SELECT u.id AS user_id, u.display_name,
           ISNULL(a.taken_week, 0) AS taken_week, ISNULL(a.resolved_week, 0) AS resolved_week,
           ISNULL(a.late_week, 0) AS late_week,
           ISNULL(a.taken_month, 0) AS taken_month, ISNULL(a.resolved_month, 0) AS resolved_month,
           ISNULL(a.late_month, 0) AS late_month,
           ISNULL(a.taken_three, 0) AS taken_three, ISNULL(a.resolved_three, 0) AS resolved_three,
           ISNULL(a.late_three, 0) AS late_three,
           ISNULL(o.in_progress, 0) AS in_progress,
           @wf AS week_from, @wt AS week_to, @mf AS month_from, @mt AS month_to, @tf AS three_from, @tt AS three_to
    FROM crm.users AS u
    LEFT JOIN per_agent AS a ON a.user_id = u.id
    LEFT JOIN now_open AS o ON o.user_id = u.id
    WHERE a.user_id IS NOT NULL OR o.user_id IS NOT NULL
    ORDER BY u.display_name, u.id;
END;
