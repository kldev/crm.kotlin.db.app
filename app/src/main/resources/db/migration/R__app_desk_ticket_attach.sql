-- An agent adds files to a ticket (any state). The bytes are already stored; on a refusal the caller deletes them.
CREATE OR ALTER PROCEDURE app.desk_ticket_attach
    @actor_id    int,
    @ticket_id   bigint,
    @attachments nvarchar(max)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @actor_name nvarchar(200), @now datetime2(3) = crm.desk_now();
    EXEC crm.desk_actor @actor_id, @actor_name OUTPUT;

    BEGIN TRANSACTION;
    DECLARE @status varchar(12), @assignee_id int, @assignee_name nvarchar(200), @version int;
    EXEC crm.desk_ticket_lock @ticket_id, @status OUTPUT, @assignee_id OUTPUT, @assignee_name OUTPUT, @version OUTPUT;
    EXEC crm.desk_ticket_add_attachments @ticket_id, @actor_id, @actor_name, @attachments, @now, @version OUTPUT;
    COMMIT;

    EXEC crm.desk_ticket_select @ticket_id;
END;
