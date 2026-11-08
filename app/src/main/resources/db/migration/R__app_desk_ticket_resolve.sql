-- Resolve a ticket. Only the agent working on it. Resolved at or after the deadline = late, kept for good.
CREATE OR ALTER PROCEDURE app.desk_ticket_resolve
    @actor_id  int,
    @ticket_id bigint
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @actor_name nvarchar(200), @now datetime2(3) = SYSUTCDATETIME();
    EXEC crm.desk_actor @actor_id, @actor_name OUTPUT;

    BEGIN TRANSACTION;
    DECLARE @status varchar(12), @assignee_id int, @assignee_name nvarchar(200), @version int;
    EXEC crm.desk_ticket_lock @ticket_id, @status OUTPUT, @assignee_id OUTPUT, @assignee_name OUTPUT, @version OUTPUT;
    EXEC crm.desk_require_assignee @status, @assignee_id, @assignee_name, @actor_id, 'RESOLVE';

    DECLARE @late bit = IIF(@now >= (SELECT deadline FROM crm.tickets WHERE id = @ticket_id), 1, 0);
    DECLARE @data nvarchar(max) = JSON_OBJECT(
        'agent': JSON_OBJECT('id': @actor_id, 'name': @actor_name), 'late': @late);
    EXEC crm.desk_ticket_append @ticket_id, @version, 'TicketResolved', @now, @actor_id, @actor_name, @data;

    UPDATE crm.tickets
    SET status = 'DONE', resolved_at = @now, resolved_late = @late,
        version = @version + 1, last_change_at = @now
    WHERE id = @ticket_id;
    COMMIT;

    EXEC crm.desk_ticket_select @ticket_id;
END;
