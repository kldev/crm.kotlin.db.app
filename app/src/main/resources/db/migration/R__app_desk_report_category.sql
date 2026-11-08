/*
  A category report (ADR-0010): the tickets of one category reported between @from and @to - whole calendar days in
  Warsaw time, both ends included - with their report data as a JSON object; filters: market, subcategory, open /
  resolved. Ordered by the report date. The caller pivots the fields into columns (only those with a value).
*/
CREATE OR ALTER PROCEDURE app.desk_report_category
    @actor_id        int,
    @category_key    varchar(40),
    @from            date,
    @to              date,
    @market          nvarchar(50) = NULL,
    @subcategory_key varchar(60)  = NULL,
    @completion      varchar(4)   = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    IF NOT EXISTS (SELECT 1 FROM crm.desk_categories WHERE category_key = @category_key)
        THROW 51104, N'Choose a category from the list.', 1;
    IF @from IS NULL OR @to IS NULL OR @to < @from OR DATEDIFF(DAY, @from, @to) > 366
        THROW 51150, N'Choose a period of at most one year (from <= to).', 1;
    IF @completion IS NOT NULL AND @completion NOT IN ('OPEN', 'DONE')
        THROW 51116, N'Completion filter must be OPEN or DONE.', 1;

    -- Warsaw midnights as UTC instants: a DST change moves them, the days stay whole.
    DECLARE @from_utc datetime2(3) =
        CAST((CAST(@from AS datetime2(3)) AT TIME ZONE 'Central European Standard Time') AT TIME ZONE 'UTC' AS datetime2(3));
    DECLARE @until_utc datetime2(3) =
        CAST((CAST(DATEADD(DAY, 1, @to) AS datetime2(3)) AT TIME ZONE 'Central European Standard Time') AT TIME ZONE 'UTC' AS datetime2(3));

    SELECT t.id, t.number, t.reported_at, s.market, t.subcategory_key, t.title, t.requester_incognito, t.requester_name,
           t.status, t.priority, t.assignee_name, t.handler_name, t.deadline, t.resolved_at, t.resolved_late,
           (SELECT tf.field_key AS k, tf.value AS v FROM crm.ticket_fields AS tf WHERE tf.ticket_id = t.id
            FOR JSON PATH) AS fields
    FROM crm.tickets AS t
    JOIN crm.desk_subcategories AS s ON s.subcategory_key = t.subcategory_key
    WHERE t.category_key = @category_key
      AND t.reported_at >= @from_utc AND t.reported_at < @until_utc
      AND (@market IS NULL OR s.market = @market)
      AND (@subcategory_key IS NULL OR t.subcategory_key = @subcategory_key)
      AND (@completion IS NULL OR (@completion = 'DONE' AND t.status = 'DONE')
           OR (@completion = 'OPEN' AND t.status <> 'DONE'))
    ORDER BY t.reported_at, t.id
    OPTION (RECOMPILE);
END;
