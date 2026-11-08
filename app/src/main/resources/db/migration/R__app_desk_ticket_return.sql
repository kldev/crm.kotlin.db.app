-- Give a ticket back to the pool, with an optional reason. Only the agent working on it; the deadline stays.
CREATE OR ALTER PROCEDURE app.desk_ticket_return
    @actor_id  int,
    @ticket_id bigint,
    @reason    nvarchar(4000) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @actor_name nvarchar(200), @now datetime2(3) = crm.desk_now();
    EXEC crm.desk_actor @actor_id, @actor_name OUTPUT;

    SET @reason = NULLIF(LTRIM(RTRIM(@reason)), N'');
    IF LEN(@reason) > 500
        THROW 51111, N'Reason can have at most 500 characters.', 1;

    BEGIN TRANSACTION;
    DECLARE @status varchar(12), @assignee_id int, @assignee_name nvarchar(200), @version int;
    EXEC crm.desk_ticket_lock @ticket_id, @status OUTPUT, @assignee_id OUTPUT, @assignee_name OUTPUT, @version OUTPUT;
    EXEC crm.desk_require_assignee @status, @assignee_id, @assignee_name, @actor_id, 'RETURN';

    DECLARE @data nvarchar(max) = JSON_OBJECT(
        'agent': JSON_OBJECT('id': @actor_id, 'name': @actor_name), 'reason': @reason);
    EXEC crm.desk_ticket_append @ticket_id, @version, 'TicketReturnedToPool', @now, @actor_id, @actor_name, @data;

    UPDATE crm.tickets
    SET status = 'IN_POOL', assignee_user_id = NULL, assignee_name = NULL, version = @version + 1,
        last_change_at = @now
    WHERE id = @ticket_id;
    COMMIT;

    EXEC crm.desk_ticket_select @ticket_id;
END;
