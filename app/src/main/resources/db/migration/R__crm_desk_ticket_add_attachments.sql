/*
  Internal (ADR-0009): records stored files as TicketAttachmentAdded events of one ticket and as rows of its read model,
  inside the caller's transaction, after crm.desk_ticket_lock (or the INSERT of a new ticket). @attachments is a JSON
  array of {id, fileName, size, storageKey}; every file is checked again, and a ticket has at most 10 attachments
  (51124). Allowed in any state, like a comment. @version is the ticket's version before and after.
*/
CREATE OR ALTER PROCEDURE crm.desk_ticket_add_attachments
    @ticket_id   bigint,
    @actor_id    int,
    @added_by    nvarchar(201),
    @attachments nvarchar(max),
    @at          datetime2(3),
    @version     int OUTPUT
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    IF @@TRANCOUNT = 0
        THROW 50002, N'crm.desk_ticket_add_attachments needs a transaction.', 1;
    IF @attachments IS NULL OR ISJSON(@attachments) = 0
        THROW 50003, N'Attachments must be a JSON array.', 1;

    DECLARE @files TABLE (n int IDENTITY (1, 1) PRIMARY KEY, id uniqueidentifier NOT NULL, file_name nvarchar(4000),
                          size_bytes bigint, storage_key varchar(100) NOT NULL);
    INSERT @files (id, file_name, size_bytes, storage_key)
    SELECT id, file_name, size_bytes, storage_key
    FROM OPENJSON(@attachments)
         WITH (id uniqueidentifier '$.id', file_name nvarchar(4000) '$.fileName', size_bytes bigint '$.size',
               storage_key varchar(100) '$.storageKey');

    DECLARE @count int = (SELECT attachment_count FROM crm.tickets WHERE id = @ticket_id);
    IF @count + (SELECT COUNT(*) FROM @files) > 10
        THROW 51124, N'A ticket can have at most 10 attachments.', 1;

    DECLARE @agent_name nvarchar(200) = IIF(@actor_id IS NULL, NULL, @added_by);
    DECLARE @i int = 1, @last int = (SELECT COUNT(*) FROM @files);
    WHILE @i <= @last
    BEGIN
        DECLARE @id uniqueidentifier, @raw nvarchar(4000), @size bigint, @key varchar(100),
                @name nvarchar(200), @content_type varchar(100);
        SELECT @id = id, @raw = file_name, @size = size_bytes, @key = storage_key FROM @files WHERE n = @i;
        EXEC crm.desk_attachment_normalize @raw, @size, @name OUTPUT, @content_type OUTPUT;

        DECLARE @data nvarchar(max) = JSON_OBJECT(
            'attachmentId': @id, 'fileName': @name, 'contentType': @content_type, 'size': @size,
            'addedBy': @added_by,
            'agent': JSON_QUERY(IIF(@actor_id IS NULL, NULL, JSON_OBJECT('id': @actor_id, 'name': @agent_name))));
        EXEC crm.desk_ticket_append @ticket_id, @version, 'TicketAttachmentAdded', @at, @actor_id, @added_by, @data;
        SET @version += 1;

        INSERT crm.ticket_attachments (attachment_id, ticket_id, file_name, content_type, size_bytes, storage_key,
                                       added_by, added_by_user_id, at)
        VALUES (@id, @ticket_id, @name, @content_type, @size, @key, @added_by, @actor_id, @at);
        SET @i += 1;
    END;

    UPDATE crm.tickets
    SET attachment_count = attachment_count + @last, version = @version, last_change_at = @at
    WHERE id = @ticket_id;
END;
