-- Checks one file before its bytes are stored (ADR-0009): returns the name as stored and its content type, or refuses
-- it. The same rules run again when the attachment is recorded; this call only spares an upload that would be refused.
CREATE OR ALTER PROCEDURE app.desk_attachment_check
    @file_name  nvarchar(4000),
    @size_bytes bigint
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @name nvarchar(200), @content_type varchar(100);
    EXEC crm.desk_attachment_normalize @file_name, @size_bytes, @name OUTPUT, @content_type OUTPUT;
    SELECT @name AS file_name, @content_type AS content_type;
END;
