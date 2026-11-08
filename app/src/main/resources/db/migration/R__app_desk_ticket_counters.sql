-- The counters of the top bar: overdue and due soon (open tickets), in the pool, and in progress with me.
CREATE OR ALTER PROCEDURE app.desk_ticket_counters
    @actor_id int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    DECLARE @now datetime2(3) = SYSUTCDATETIME();
    DECLARE @soon datetime2(3) = DATEADD(MINUTE, 60, @now);

    SELECT ISNULL(SUM(IIF(deadline <= @now, 1, 0)), 0) AS overdue,
           ISNULL(SUM(IIF(deadline > @now AND deadline < @soon, 1, 0)), 0) AS due_soon,
           ISNULL(SUM(IIF(status = 'IN_POOL', 1, 0)), 0) AS pool,
           ISNULL(SUM(IIF(status = 'IN_PROGRESS' AND assignee_user_id = @actor_id, 1, 0)), 0) AS mine
    FROM crm.tickets
    WHERE status <> 'DONE';
END;
