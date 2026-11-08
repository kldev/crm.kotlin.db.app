-- Hand a ticket over to another agent (an active CRM user). Only the agent working on it; the deadline stays.
CREATE OR ALTER PROCEDURE app.desk_ticket_hand_over
    @actor_id   int,
    @ticket_id  bigint,
    @to_user_id int,
    @reason     nvarchar(4000) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @actor_name nvarchar(200), @now datetime2(3) = crm.desk_now();
    EXEC crm.desk_actor @actor_id, @actor_name OUTPUT;

    SET @reason = NULLIF(LTRIM(RTRIM(@reason)), N'');
    IF LEN(@reason) > 500
        THROW 51111, N'Reason can have at most 500 characters.', 1;
    DECLARE @to_name nvarchar(200) = (SELECT display_name FROM crm.users WHERE id = @to_user_id AND is_active = 1);
    IF @to_name IS NULL
        THROW 51412, N'Agent not found or not active.', 1;

    BEGIN TRANSACTION;
    DECLARE @status varchar(12), @assignee_id int, @assignee_name nvarchar(200), @version int;
    EXEC crm.desk_ticket_lock @ticket_id, @status OUTPUT, @assignee_id OUTPUT, @assignee_name OUTPUT, @version OUTPUT;
    EXEC crm.desk_require_assignee @status, @assignee_id, @assignee_name, @actor_id, 'HAND_OVER';
    IF @to_user_id = @actor_id
        THROW 51114, N'A ticket cannot be handed over to yourself.', 1;

    DECLARE @data nvarchar(max) = JSON_OBJECT(
        'from': JSON_OBJECT('id': @actor_id, 'name': @actor_name),
        'to': JSON_OBJECT('id': @to_user_id, 'name': @to_name),
        'reason': @reason);
    EXEC crm.desk_ticket_append @ticket_id, @version, 'TicketHandedOver', @now, @actor_id, @actor_name, @data;

    UPDATE crm.tickets
    SET assignee_user_id = @to_user_id, assignee_name = @to_name, version = @version + 1, last_change_at = @now
    WHERE id = @ticket_id;
    COMMIT;

    EXEC crm.desk_ticket_select @ticket_id;
END;
