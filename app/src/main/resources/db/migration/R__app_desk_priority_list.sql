-- Priorities with their SLA in minutes (the form shows the deadline before sending). Public.
CREATE OR ALTER PROCEDURE app.desk_priority_list
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    SELECT priority, sla_minutes FROM crm.desk_priorities ORDER BY sort_order;
END;
