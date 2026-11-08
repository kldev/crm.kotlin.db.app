-- Campaigns ordered for a ticket: marketing tickets whose "related-ticket" field is this ticket's number.
CREATE OR ALTER PROCEDURE app.desk_ticket_linked_list
    @actor_id  int,
    @ticket_id bigint
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    DECLARE @number char(12) = (SELECT number FROM crm.tickets WHERE id = @ticket_id);
    IF @number IS NULL
        THROW 51410, N'Ticket not found.', 1;
    SELECT t.id, t.number, t.title, t.description, t.category_key, t.subcategory_key, t.priority, t.original_priority,
           t.reported_at, t.deadline, t.status, t.assignee_user_id, t.assignee_name, t.handler_person_id,
           t.handler_name, t.requester_incognito, t.requester_person_id, t.requester_name, t.channel,
           t.registered_by_name, t.recorded_at, t.resolved_at, t.resolved_late, t.comment_count, t.attachment_count,
           t.version, t.last_change_at
    FROM crm.ticket_fields AS tf
    JOIN crm.tickets AS t ON t.id = tf.ticket_id
    WHERE tf.field_key = 'related-ticket' AND tf.value = @number
    ORDER BY t.reported_at DESC;
END;
