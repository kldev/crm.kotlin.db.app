/*
  Tickets list (ADR-0007). @scope: POOL (in the pool), MINE (in progress with me), ALL.
  Order: open tickets by deadline (the most urgent first), then resolved ones, newest first. Keyset pagination in
  two phases: (@after_phase 0, @after_time = deadline, @after_id) inside the open part, (1, resolved_at, id) inside
  the resolved part. Returns @page_size + 1 rows so the caller knows if there is a next page.
  Filters: category, subcategory, priority, @deadline (OVERDUE: deadline passed; DUE_SOON: under 60 minutes left -
  both only for open tickets), @completion (OPEN / DONE, ALL scope only), @search (title contains, or the exact
  number). Time-based states use the database clock, the same clock that stores the times.
*/
CREATE OR ALTER PROCEDURE app.desk_ticket_search
    @actor_id        int,
    @scope           varchar(4)    = 'ALL',
    @category_key    varchar(40)   = NULL,
    @subcategory_key varchar(60)   = NULL,
    @priority        varchar(8)    = NULL,
    @deadline        varchar(8)    = NULL,
    @completion      varchar(4)    = NULL,
    @search          nvarchar(200) = NULL,
    @after_phase     tinyint       = NULL,
    @after_time      datetime2(3)  = NULL,
    @after_id        bigint        = NULL,
    @page_size       int           = 25
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;

    IF @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 200
        THROW 51014, N'Page size must be between 1 and 200.', 1;
    IF ISNULL(@scope, '') NOT IN ('POOL', 'MINE', 'ALL')
        THROW 51116, N'Scope must be POOL, MINE or ALL.', 1;
    IF @deadline IS NOT NULL AND @deadline NOT IN ('OVERDUE', 'DUE_SOON')
        THROW 51116, N'Deadline filter must be OVERDUE or DUE_SOON.', 1;
    IF @completion IS NOT NULL AND @completion NOT IN ('OPEN', 'DONE')
        THROW 51116, N'Completion filter must be OPEN or DONE.', 1;

    DECLARE @now datetime2(3) = SYSUTCDATETIME();
    DECLARE @soon datetime2(3) = DATEADD(MINUTE, 60, @now);
    DECLARE @n int = @page_size + 1;
    SET @search = NULLIF(LTRIM(RTRIM(@search)), N'');
    DECLARE @number char(12) = IIF(UPPER(@search) LIKE 'HAL-[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]',
                                   UPPER(@search), NULL);
    DECLARE @pattern nvarchar(410) =
        N'%' + REPLACE(REPLACE(REPLACE(@search, N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%';

    -- The pool and my tickets are open by definition; a deadline filter only makes sense for open tickets.
    DECLARE @with_open bit = IIF(@completion = 'DONE' AND @scope = 'ALL', 0, 1);
    DECLARE @with_done bit = IIF(@scope = 'ALL' AND ISNULL(@completion, 'DONE') = 'DONE' AND @deadline IS NULL, 1, 0);

    DECLARE @page TABLE (ord int IDENTITY (1, 1) PRIMARY KEY, id bigint NOT NULL);

    IF @with_open = 1 AND ISNULL(@after_phase, 0) = 0
        INSERT @page (id)
        SELECT TOP (@n) t.id
        FROM crm.tickets AS t
        WHERE t.status <> 'DONE'
          AND (@scope <> 'POOL' OR t.status = 'IN_POOL')
          AND (@scope <> 'MINE' OR (t.status = 'IN_PROGRESS' AND t.assignee_user_id = @actor_id))
          AND (@category_key IS NULL OR t.category_key = @category_key)
          AND (@subcategory_key IS NULL OR t.subcategory_key = @subcategory_key)
          AND (@priority IS NULL OR t.priority = @priority)
          AND (@deadline IS NULL OR (@deadline = 'OVERDUE' AND t.deadline <= @now)
               OR (@deadline = 'DUE_SOON' AND t.deadline > @now AND t.deadline < @soon))
          AND (@search IS NULL OR t.title LIKE @pattern OR t.number = @number)
          AND (@after_phase IS NULL OR t.deadline > @after_time OR (t.deadline = @after_time AND t.id > @after_id))
        ORDER BY t.deadline, t.id
        OPTION (RECOMPILE);

    DECLARE @have int = (SELECT COUNT(*) FROM @page);
    IF @with_done = 1 AND @have < @n
        INSERT @page (id)
        SELECT TOP (@n - @have) t.id
        FROM crm.tickets AS t
        WHERE t.status = 'DONE'
          AND (@category_key IS NULL OR t.category_key = @category_key)
          AND (@subcategory_key IS NULL OR t.subcategory_key = @subcategory_key)
          AND (@priority IS NULL OR t.priority = @priority)
          AND (@search IS NULL OR t.title LIKE @pattern OR t.number = @number)
          AND (ISNULL(@after_phase, 0) = 0 OR t.resolved_at < @after_time
               OR (t.resolved_at = @after_time AND t.id < @after_id))
        ORDER BY t.resolved_at DESC, t.id DESC
        OPTION (RECOMPILE);

    SELECT t.id, t.number, t.title, t.description, t.category_key, t.subcategory_key, t.priority, t.original_priority,
           t.reported_at, t.deadline, t.status, t.assignee_user_id, t.assignee_name, t.handler_person_id,
           t.handler_name, t.requester_incognito, t.requester_person_id, t.requester_name, t.channel,
           t.registered_by_name, t.recorded_at, t.resolved_at, t.resolved_late, t.comment_count, t.attachment_count,
           t.version, t.last_change_at
    FROM @page AS p
    JOIN crm.tickets AS t ON t.id = p.id
    ORDER BY p.ord;
END;
