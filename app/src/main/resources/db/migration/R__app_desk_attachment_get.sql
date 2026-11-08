-- One attachment for download (signed-in agents only): where its bytes are and how to send them.
CREATE OR ALTER PROCEDURE app.desk_attachment_get
    @actor_id      int,
    @ticket_id     bigint,
    @attachment_id uniqueidentifier
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    IF NOT EXISTS (SELECT 1 FROM crm.ticket_attachments WHERE ticket_id = @ticket_id AND attachment_id = @attachment_id)
        THROW 51413, N'Attachment not found.', 1;
    SELECT a.attachment_id, a.file_name, a.content_type, a.size_bytes, a.storage_key,
           CAST(ISNULL((SELECT MAX(CAST(x.is_inline AS int)) FROM crm.desk_attachment_types AS x
                        WHERE x.content_type = a.content_type), 0) AS bit) AS is_inline
    FROM crm.ticket_attachments AS a
    WHERE a.ticket_id = @ticket_id AND a.attachment_id = @attachment_id;
END;
