-- Internal (ADR-0007): the ticket row that every desk read and write returns.
CREATE OR ALTER PROCEDURE crm.desk_ticket_select
    @ticket_id bigint
AS
BEGIN
    SET NOCOUNT ON;
    SELECT t.id, t.number, t.title, t.description, t.category_key, t.subcategory_key, t.priority, t.original_priority,
           t.reported_at, t.deadline, t.status, t.assignee_user_id, t.assignee_name, t.handler_person_id,
           t.handler_name, t.requester_incognito, t.requester_person_id, t.requester_name, t.channel,
           t.registered_by_name, t.recorded_at, t.resolved_at, t.resolved_late, t.comment_count, t.attachment_count,
           t.version, t.last_change_at
    FROM crm.tickets AS t
    WHERE t.id = @ticket_id;
END;
