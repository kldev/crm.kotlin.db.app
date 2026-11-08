-- One ticket (any agent sees every ticket: the desk has no visibility rules, ADR-0007).
CREATE OR ALTER PROCEDURE app.desk_ticket_get
    @actor_id  int,
    @ticket_id bigint
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    IF NOT EXISTS (SELECT 1 FROM crm.tickets WHERE id = @ticket_id)
        THROW 51410, N'Ticket not found.', 1;
    EXEC crm.desk_ticket_select @ticket_id;
END;
