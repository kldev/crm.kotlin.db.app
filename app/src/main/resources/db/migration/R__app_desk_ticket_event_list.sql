-- The timeline of a ticket: its stream, oldest first. The UI renders each event type from its JSON.
CREATE OR ALTER PROCEDURE app.desk_ticket_event_list
    @actor_id  int,
    @ticket_id bigint
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    IF NOT EXISTS (SELECT 1 FROM crm.tickets WHERE id = @ticket_id)
        THROW 51410, N'Ticket not found.', 1;

    SELECT version, event_type, at, actor_user_id, actor_name, data
    FROM crm.ticket_events
    WHERE ticket_id = @ticket_id
    ORDER BY version;
END;
