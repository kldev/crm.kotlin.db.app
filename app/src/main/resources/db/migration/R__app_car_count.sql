-- The number of cars for the same filters as app.car_list (ADR-0018).
CREATE OR ALTER PROCEDURE app.car_count
    @actor_id        int,
    @search          nvarchar(100) = NULL,
    @status          varchar(20)   = NULL,
    @availability    varchar(12)   = NULL,
    @legal_entity_id int           = NULL,
    @repair_shop_id  int           = NULL,
    @archived        bit           = 0,
    @due_soon        bit           = 0
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    SET @search = NULLIF(LTRIM(RTRIM(@search)), N'');
    SELECT @archived = ISNULL(@archived, 0), @due_soon = ISNULL(@due_soon, 0);
    IF @availability IS NOT NULL AND @availability NOT IN ('FREE', 'HANDED_OVER', 'OVERDUE')
        THROW 51235, N'Availability must be FREE, HANDED_OVER or OVERDUE.', 1;
    DECLARE @today date = crm.fleet_today();
    SELECT COUNT_BIG(*) AS total
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
      AND (@due_soon = 0 OR c.inspection_due <= DATEADD(DAY, 30, @today) OR c.insurance_due <= DATEADD(DAY, 30, @today));
END;
