-- Number of tickets matching the filters of app.desk_ticket_search. Called only when the user asks for the total.
CREATE OR ALTER PROCEDURE app.desk_ticket_count
    @actor_id        int,
    @scope           varchar(4)    = 'ALL',
    @category_key    varchar(40)   = NULL,
    @subcategory_key varchar(60)   = NULL,
    @priority        varchar(8)    = NULL,
    @deadline        varchar(8)    = NULL,
    @completion      varchar(4)    = NULL,
    @search          nvarchar(200) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;

    IF ISNULL(@scope, '') NOT IN ('POOL', 'MINE', 'ALL')
        THROW 51116, N'Scope must be POOL, MINE or ALL.', 1;
    IF @deadline IS NOT NULL AND @deadline NOT IN ('OVERDUE', 'DUE_SOON')
        THROW 51116, N'Deadline filter must be OVERDUE or DUE_SOON.', 1;
    IF @completion IS NOT NULL AND @completion NOT IN ('OPEN', 'DONE')
        THROW 51116, N'Completion filter must be OPEN or DONE.', 1;

    DECLARE @now datetime2(3) = SYSUTCDATETIME();
    DECLARE @soon datetime2(3) = DATEADD(MINUTE, 60, @now);
    SET @search = NULLIF(LTRIM(RTRIM(@search)), N'');
    DECLARE @number char(12) = IIF(UPPER(@search) LIKE 'HAL-[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]',
                                   UPPER(@search), NULL);
    DECLARE @pattern nvarchar(410) =
        N'%' + REPLACE(REPLACE(REPLACE(@search, N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%';
    DECLARE @with_open bit = IIF(@completion = 'DONE' AND @scope = 'ALL', 0, 1);
    DECLARE @with_done bit = IIF(@scope = 'ALL' AND ISNULL(@completion, 'DONE') = 'DONE' AND @deadline IS NULL, 1, 0);

    SELECT COUNT_BIG(*) AS total
    FROM crm.tickets AS t
    WHERE ((@with_open = 1 AND t.status <> 'DONE') OR (@with_done = 1 AND t.status = 'DONE'))
      AND (@scope <> 'POOL' OR t.status = 'IN_POOL')
      AND (@scope <> 'MINE' OR (t.status = 'IN_PROGRESS' AND t.assignee_user_id = @actor_id))
      AND (@category_key IS NULL OR t.category_key = @category_key)
      AND (@subcategory_key IS NULL OR t.subcategory_key = @subcategory_key)
      AND (@priority IS NULL OR t.priority = @priority)
      AND (@deadline IS NULL OR (@deadline = 'OVERDUE' AND t.deadline <= @now)
           OR (@deadline = 'DUE_SOON' AND t.deadline > @now AND t.deadline < @soon))
      AND (@search IS NULL OR t.title LIKE @pattern OR t.number = @number)
    OPTION (RECOMPILE);
END;
