-- The attachments of a ticket, oldest first.
CREATE OR ALTER PROCEDURE app.desk_attachment_list
    @actor_id  int,
    @ticket_id bigint
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    IF NOT EXISTS (SELECT 1 FROM crm.tickets WHERE id = @ticket_id)
        THROW 51410, N'Ticket not found.', 1;
    SELECT a.attachment_id, a.file_name, a.content_type, a.size_bytes, a.added_by, a.at,
           CAST(ISNULL(t.is_inline, 0) AS bit) AS is_inline
    FROM crm.ticket_attachments AS a
    OUTER APPLY (SELECT TOP (1) x.is_inline FROM crm.desk_attachment_types AS x
                 WHERE x.content_type = a.content_type ORDER BY x.is_inline DESC) AS t
    WHERE a.ticket_id = @ticket_id
    ORDER BY a.at, a.file_name;
END;
