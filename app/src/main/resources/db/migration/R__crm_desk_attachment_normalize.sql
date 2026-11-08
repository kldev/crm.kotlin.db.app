/*
  Internal (ADR-0009): the rules of one file. The name as stored - no folders, no control characters, at most 200
  characters (the extension kept) - and the content type from the extension. Refuses a file without a name (51120),
  of a type not on the list (51121), empty (51122) or over 20 MB (51123).
*/
CREATE OR ALTER PROCEDURE crm.desk_attachment_normalize
    @file_name    nvarchar(4000),
    @size_bytes   bigint,
    @name         nvarchar(200) OUTPUT,
    @content_type varchar(100)  OUTPUT
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @max_bytes bigint = 20 * 1024 * 1024;
    DECLARE @n nvarchar(4000) = REPLACE(ISNULL(@file_name, N''), N'\', N'/');
    IF CHARINDEX(N'/', @n) > 0
        SET @n = RIGHT(@n, CHARINDEX(N'/', REVERSE(@n)) - 1);
    DECLARE @c int = 0;
    WHILE @c < 32
    BEGIN
        SET @n = REPLACE(@n, NCHAR(@c), N'');
        SET @c += 1;
    END;
    SET @n = LTRIM(RTRIM(REPLACE(@n, NCHAR(127), N'')));
    IF @n = N''
        THROW 51120, N'The file has no name.', 1;

    DECLARE @extension varchar(10) =
        IIF(CHARINDEX(N'.', @n) = 0, NULL, LOWER(RIGHT(@n, CHARINDEX(N'.', REVERSE(@n)))));
    IF LEN(@n) > 200
        SET @n = LEFT(@n, 200 - ISNULL(LEN(@extension), 0)) + ISNULL(@extension, N'');
    SET @name = @n;

    SET @content_type = (SELECT content_type FROM crm.desk_attachment_types WHERE extension = @extension);
    DECLARE @message nvarchar(1000);
    IF @content_type IS NULL
    BEGIN
        SET @message = FORMATMESSAGE(
            N'The file "%s" has a type that is not allowed. Allowed: images (PNG, JPG, GIF, WEBP), PDF, Office documents, TXT/CSV, ZIP, MP4/MOV.',
            @n);
        THROW 51121, @message, 1;
    END;
    IF ISNULL(@size_bytes, 0) <= 0
    BEGIN
        SET @message = FORMATMESSAGE(N'The file "%s" is empty.', @n);
        THROW 51122, @message, 1;
    END;
    IF @size_bytes > @max_bytes
    BEGIN
        SET @message = FORMATMESSAGE(N'The file "%s" is too large (%s MB). The limit is 20 MB.', @n,
                                     FORMAT(@size_bytes / 1048576.0, '0.#', 'en-US'));
        THROW 51123, @message, 1;
    END;
END;
