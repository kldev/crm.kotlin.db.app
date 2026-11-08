/*
  Internal (ADR-0010): the calendar periods of the agents' report in Warsaw time - this week (Monday to Sunday), this
  month, and this month with the two before - or, with @previous = 1, the ones just before them. Dates are local days,
  [from, to) half-open; the UTC instants bound the events.
*/
CREATE OR ALTER PROCEDURE crm.desk_report_periods
    @previous    bit,
    @week_from   date OUTPUT, @week_to   date OUTPUT,
    @month_from  date OUTPUT, @month_to  date OUTPUT,
    @three_from  date OUTPUT, @three_to  date OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @today date = CAST((SYSUTCDATETIME() AT TIME ZONE 'UTC') AT TIME ZONE 'Central European Standard Time' AS date);
    -- 1900-01-01 was a Monday.
    SET @week_from = DATEADD(DAY, -(DATEDIFF(DAY, '19000101', @today) % 7), @today);
    SET @month_from = DATEFROMPARTS(YEAR(@today), MONTH(@today), 1);
    IF @previous = 1
    BEGIN
        SET @week_from = DATEADD(DAY, -7, @week_from);
        SET @month_from = DATEADD(MONTH, -1, @month_from);
        SET @three_to = DATEADD(MONTH, -2, DATEFROMPARTS(YEAR(@today), MONTH(@today), 1));
        SET @three_from = DATEADD(MONTH, -3, @three_to);
    END
    ELSE
    BEGIN
        SET @three_to = DATEADD(MONTH, 1, @month_from);
        SET @three_from = DATEADD(MONTH, -2, @month_from);
    END;
    SET @week_to = DATEADD(DAY, 7, @week_from);
    SET @month_to = DATEADD(MONTH, 1, @month_from);
END;
