-- A comment (any agent, any state, also on a resolved ticket). Comments are events: never edited or deleted.
CREATE OR ALTER PROCEDURE app.desk_ticket_comment
    @actor_id  int,
    @ticket_id bigint,
    @text      nvarchar(max)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @actor_name nvarchar(200), @now datetime2(3) = SYSUTCDATETIME();
    EXEC crm.desk_actor @actor_id, @actor_name OUTPUT;

    SET @text = LTRIM(RTRIM(@text));
    IF @text IS NULL OR @text = N''
        THROW 51112, N'Comment is required.', 1;
    IF LEN(@text) > 2000
        THROW 51113, N'Comment can have at most 2000 characters.', 1;

    BEGIN TRANSACTION;
    DECLARE @status varchar(12), @assignee_id int, @assignee_name nvarchar(200), @version int;
    EXEC crm.desk_ticket_lock @ticket_id, @status OUTPUT, @assignee_id OUTPUT, @assignee_name OUTPUT, @version OUTPUT;

    DECLARE @data nvarchar(max) = JSON_OBJECT(
        'agent': JSON_OBJECT('id': @actor_id, 'name': @actor_name), 'text': @text);
    EXEC crm.desk_ticket_append @ticket_id, @version, 'TicketCommented', @now, @actor_id, @actor_name, @data;

    UPDATE crm.tickets
    SET comment_count = comment_count + 1, version = @version + 1, last_change_at = @now
    WHERE id = @ticket_id;
    COMMIT;

    EXEC crm.desk_ticket_select @ticket_id;
END;
