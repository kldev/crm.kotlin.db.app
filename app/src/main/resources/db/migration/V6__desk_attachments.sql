/*
  Attachments of desk tickets (ADR-0009). The bytes live in an S3 bucket (RustFS locally); the record is the event
  TicketAttachmentAdded in the ticket's stream, and crm.ticket_attachments is its read model.
  What may be attached is data: the type comes from the extension, never from what the browser claims. SVG and HTML
  are missing on purpose - shown inline they can run scripts.
*/
CREATE TABLE crm.desk_attachment_types
(
    extension    varchar(10)  NOT NULL,
    content_type varchar(100) NOT NULL,
    -- Raster images and PDF open in the browser; everything else is downloaded.
    is_inline    bit          NOT NULL,
    CONSTRAINT pk_desk_attachment_types PRIMARY KEY CLUSTERED (extension)
);

INSERT crm.desk_attachment_types (extension, content_type, is_inline)
VALUES ('.png', 'image/png', 1),
       ('.jpg', 'image/jpeg', 1),
       ('.jpeg', 'image/jpeg', 1),
       ('.gif', 'image/gif', 1),
       ('.webp', 'image/webp', 1),
       ('.pdf', 'application/pdf', 1),
       ('.txt', 'text/plain', 0),
       ('.log', 'text/plain', 0),
       ('.csv', 'text/csv', 0),
       ('.docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 0),
       ('.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 0),
       ('.pptx', 'application/vnd.openxmlformats-officedocument.presentationml.presentation', 0),
       ('.odt', 'application/vnd.oasis.opendocument.text', 0),
       ('.ods', 'application/vnd.oasis.opendocument.spreadsheet', 0),
       ('.zip', 'application/zip', 0),
       ('.mp4', 'video/mp4', 0),
       ('.mov', 'video/quicktime', 0);

CREATE TABLE crm.ticket_attachments
(
    attachment_id    uniqueidentifier NOT NULL,
    ticket_id        bigint           NOT NULL,
    file_name        nvarchar(200)    NOT NULL,
    content_type     varchar(100)     NOT NULL,
    size_bytes       bigint           NOT NULL,
    storage_key      varchar(100)     NOT NULL,
    -- The agent's name, or the requester's on the public form (a snapshot, like the event).
    added_by         nvarchar(201)    NOT NULL,
    added_by_user_id int              NULL,
    at               datetime2(3)     NOT NULL,
    CONSTRAINT pk_ticket_attachments PRIMARY KEY NONCLUSTERED (attachment_id),
    CONSTRAINT uq_ticket_attachments_key UNIQUE (storage_key),
    CONSTRAINT fk_ticket_attachments_ticket FOREIGN KEY (ticket_id) REFERENCES crm.tickets (id),
    CONSTRAINT ck_ticket_attachments_size CHECK (size_bytes > 0)
);

CREATE CLUSTERED INDEX cx_ticket_attachments_ticket ON crm.ticket_attachments (ticket_id, at);
