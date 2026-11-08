/*
  The fleet list (ADR-0018), by name, keyset-paged after (@after_name, @after_id), @page_size + 1 rows. Filters: a text
  (name, plate however spaced, make), status, availability today, owning company, repair shop, archived ones too, and
  "due soon" - inspection or insurance within 30 days. Everybody reads; money only for ADMIN and MANAGER.
*/
CREATE OR ALTER PROCEDURE app.car_list
    @actor_id        int,
    @search          nvarchar(100) = NULL,
    @status          varchar(20)   = NULL,
    @availability    varchar(12)   = NULL,
    @legal_entity_id int           = NULL,
    @repair_shop_id  int           = NULL,
    @archived        bit           = 0,
    @due_soon        bit           = 0,
    @after_name      nvarchar(100) = NULL,
    @after_id        int           = NULL,
    @page_size       int           = 50
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @role varchar(10);
    EXEC crm.actor_require @actor_id, @role OUTPUT;
    IF @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 200
        THROW 51014, N'Page size must be between 1 and 200.', 1;
    SET @search = NULLIF(LTRIM(RTRIM(@search)), N'');
    SELECT @archived = ISNULL(@archived, 0), @due_soon = ISNULL(@due_soon, 0);
    IF @availability IS NOT NULL AND @availability NOT IN ('FREE', 'HANDED_OVER', 'OVERDUE')
        THROW 51235, N'Availability must be FREE, HANDED_OVER or OVERDUE.', 1;
    DECLARE @today date = crm.fleet_today();
    DECLARE @ids nvarchar(max) = (
        SELECT STRING_AGG(CAST(p.id AS nvarchar(max)), ',')
        FROM (SELECT TOP (@page_size + 1) c.id
              FROM crm.cars AS c
    OUTER APPLY (SELECT TOP (1) x.planned_return FROM crm.car_handovers AS x
                 WHERE x.car_id = c.id AND x.cancelled_at IS NULL AND x.returned_on IS NULL AND x.issue_date <= @today
                 ORDER BY x.issue_date DESC) AS cur
    WHERE (@archived = 1 OR c.status <> 'ARCHIVED')
      AND (@status IS NULL OR c.status = @status)
      AND (@legal_entity_id IS NULL OR c.legal_entity_id = @legal_entity_id)
      AND (@repair_shop_id IS NULL OR c.repair_shop_id = @repair_shop_id)
      AND (@search IS NULL OR c.name LIKE N'%' + @search + N'%' OR c.plate_key LIKE REPLACE(REPLACE(UPPER(@search), ' ', ''), '-', '') + '%'
           OR c.make LIKE @search + N'%')
      AND (@availability IS NULL
           OR (@availability = 'FREE' AND cur.planned_return IS NULL AND NOT EXISTS (SELECT 1 FROM crm.car_handovers AS y
                   WHERE y.car_id = c.id AND y.cancelled_at IS NULL AND y.returned_on IS NULL AND y.issue_date <= @today))
           OR (@availability = 'HANDED_OVER' AND EXISTS (SELECT 1 FROM crm.car_handovers AS y
                   WHERE y.car_id = c.id AND y.cancelled_at IS NULL AND y.returned_on IS NULL AND y.issue_date <= @today)
               AND (cur.planned_return IS NULL OR cur.planned_return >= @today))
           OR (@availability = 'OVERDUE' AND cur.planned_return < @today))
      AND (@due_soon = 0 OR c.inspection_due <= DATEADD(DAY, 30, @today) OR c.insurance_due <= DATEADD(DAY, 30, @today))
                AND (@after_id IS NULL OR c.name > @after_name OR (c.name = @after_name AND c.id > @after_id))
              ORDER BY c.name, c.id) AS p);
    DECLARE @money bit = IIF(@role IN ('ADMIN', 'MANAGER'), 1, 0);
    IF @ids IS NULL
        EXEC crm.car_select @car_id = -1;
    ELSE
        EXEC crm.car_select @ids = @ids, @show_money = @money;
END;
