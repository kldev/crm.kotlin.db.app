-- The application's log, newest first, keyset by id (ADR-0012). @level: the lowest level shown; @search: in the
-- message or the source.
CREATE OR ALTER PROCEDURE app.monitoring_log_list
    @actor_id  int,
    @level     varchar(5)    = NULL,
    @search    nvarchar(200) = NULL,
    @after_id  bigint        = NULL,
    @page_size int           = 50
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.monitoring_require_admin @actor_id;
    IF @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 200
        THROW 51014, N'Page size must be between 1 and 200.', 1;
    IF @level IS NOT NULL AND @level NOT IN ('INFO', 'WARN', 'ERROR')
        THROW 51116, N'Level must be INFO, WARN or ERROR.', 1;
    SET @search = NULLIF(LTRIM(RTRIM(@search)), N'');
    DECLARE @pattern nvarchar(410) = N'%' + REPLACE(REPLACE(REPLACE(@search, N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%';

    SELECT TOP (@page_size + 1) id, at, level, source, message, exception, request_path, trace_id
    FROM crm.app_logs
    WHERE (@after_id IS NULL OR id < @after_id)
      AND (@level IS NULL OR @level = 'INFO' OR (@level = 'WARN' AND level IN ('WARN', 'ERROR')) OR (@level = 'ERROR' AND level = 'ERROR'))
      AND (@search IS NULL OR message LIKE @pattern OR source LIKE @pattern)
    ORDER BY id DESC
    OPTION (RECOMPILE);
END;
