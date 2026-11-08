/*
  Change the priority of an unresolved ticket (any agent). The deadline is recomputed from the REPORT date with the
  new SLA, never from now (ADR-0007). The same priority again is a no-op: no event, the row is returned unchanged.
*/
CREATE OR ALTER PROCEDURE app.desk_ticket_change_priority
    @actor_id  int,
    @ticket_id bigint,
    @priority  varchar(8),
    @reason    nvarchar(4000) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @actor_name nvarchar(200), @now datetime2(3) = SYSUTCDATETIME();
    EXEC crm.desk_actor @actor_id, @actor_name OUTPUT;

    DECLARE @sla int = (SELECT sla_minutes FROM crm.desk_priorities WHERE priority = @priority);
    IF @sla IS NULL
        THROW 51107, N'Choose a priority.', 1;
    SET @reason = NULLIF(LTRIM(RTRIM(@reason)), N'');
    IF LEN(@reason) > 500
        THROW 51111, N'Reason can have at most 500 characters.', 1;

    BEGIN TRANSACTION;
    DECLARE @status varchar(12), @assignee_id int, @assignee_name nvarchar(200), @version int;
    EXEC crm.desk_ticket_lock @ticket_id, @status OUTPUT, @assignee_id OUTPUT, @assignee_name OUTPUT, @version OUTPUT;
    IF @status = 'DONE'
        THROW 51911, N'The ticket is already resolved.', 1;

    DECLARE @from varchar(8) = (SELECT priority FROM crm.tickets WHERE id = @ticket_id);
    IF @from <> @priority
    BEGIN
        DECLARE @data nvarchar(max) = JSON_OBJECT(
            'from': @from, 'to': @priority, 'agent': JSON_OBJECT('id': @actor_id, 'name': @actor_name),
            'reason': @reason);
        EXEC crm.desk_ticket_append @ticket_id, @version, 'TicketPriorityChanged', @now, @actor_id, @actor_name, @data;

        UPDATE crm.tickets
        SET priority = @priority, deadline = DATEADD(MINUTE, @sla, reported_at), version = @version + 1,
            last_change_at = @now
        WHERE id = @ticket_id;
    END;
    COMMIT;

    EXEC crm.desk_ticket_select @ticket_id;
END;
