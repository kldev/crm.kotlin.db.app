-- Allowed attachment types, for the file picker's accept attribute. Public.
CREATE OR ALTER PROCEDURE app.desk_attachment_type_list
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    SELECT extension, content_type FROM crm.desk_attachment_types ORDER BY extension;
END;
