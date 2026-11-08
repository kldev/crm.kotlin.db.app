-- The expenses of a trip, in order (ADR-0019).
CREATE OR ALTER PROCEDURE app.trip_expense_list
    @actor_id int,
    @trip_id  bigint
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.trip_require @actor_id, @trip_id;
    SELECT id, line_no, category, description, spent_on, document, amount, nights FROM crm.trip_expenses WHERE trip_id = @trip_id ORDER BY line_no;
END;
