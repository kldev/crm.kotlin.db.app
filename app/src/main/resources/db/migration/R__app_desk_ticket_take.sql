-- Take a ticket from the pool (or one returned to it). Of two agents taking it at once, the second one is told
-- who was faster (51910): the row lock makes them decide one after the other.
CREATE OR ALTER PROCEDURE app.desk_ticket_take
    @actor_id  int,
    @ticket_id bigint
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @actor_name nvarchar(200), @now datetime2(3) = crm.desk_now();
    EXEC crm.desk_actor @actor_id, @actor_name OUTPUT;

    BEGIN TRANSACTION;
    DECLARE @status varchar(12), @assignee_id int, @assignee_name nvarchar(200), @version int;
    EXEC crm.desk_ticket_lock @ticket_id, @status OUTPUT, @assignee_id OUTPUT, @assignee_name OUTPUT, @version OUTPUT;

    IF @status = 'IN_PROGRESS'
    BEGIN
        DECLARE @taken nvarchar(400) = FORMATMESSAGE(N'The ticket is already in progress with %s.', @assignee_name);
        THROW 51910, @taken, 1;
    END;
    IF @status = 'DONE'
        THROW 51911, N'The ticket is already resolved.', 1;

    DECLARE @data nvarchar(max) = JSON_OBJECT('agent': JSON_OBJECT('id': @actor_id, 'name': @actor_name));
    EXEC crm.desk_ticket_append @ticket_id, @version, 'TicketTaken', @now, @actor_id, @actor_name, @data;

    UPDATE crm.tickets
    SET status = 'IN_PROGRESS', assignee_user_id = @actor_id, assignee_name = @actor_name,
        version = @version + 1, last_change_at = @now
    WHERE id = @ticket_id;
    COMMIT;

    EXEC crm.desk_ticket_select @ticket_id;
END;
