/*
  Recorded HTTP answers, newest first, keyset by id (ADR-0012). @outcome: OK (2xx), REDIRECT (3xx), FORBIDDEN (403),
  NOT_FOUND (404), CLIENT (other 4xx), SERVER (5xx); @path: a part of the path.
*/
CREATE OR ALTER PROCEDURE app.monitoring_request_list
    @actor_id  int,
    @outcome   varchar(10)   = NULL,
    @path      nvarchar(200) = NULL,
    @after_id  bigint        = NULL,
    @page_size int           = 50
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.monitoring_require_admin @actor_id;
    IF @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 200
        THROW 51014, N'Page size must be between 1 and 200.', 1;
    IF @outcome IS NOT NULL AND @outcome NOT IN ('OK', 'REDIRECT', 'FORBIDDEN', 'NOT_FOUND', 'CLIENT', 'SERVER')
        THROW 51116, N'Outcome must be OK, REDIRECT, FORBIDDEN, NOT_FOUND, CLIENT or SERVER.', 1;
    SET @path = NULLIF(LTRIM(RTRIM(@path)), N'');
    DECLARE @pattern nvarchar(410) = N'%' + REPLACE(REPLACE(REPLACE(@path, N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%';

    SELECT TOP (@page_size + 1) id, at, method, path, status, elapsed_ms, user_login, trace_id
    FROM crm.http_requests
    WHERE (@after_id IS NULL OR id < @after_id)
      AND (@path IS NULL OR path LIKE @pattern)
      AND (@outcome IS NULL
           OR (@outcome = 'OK' AND status BETWEEN 200 AND 299)
           OR (@outcome = 'REDIRECT' AND status BETWEEN 300 AND 399)
           OR (@outcome = 'FORBIDDEN' AND status = 403)
           OR (@outcome = 'NOT_FOUND' AND status = 404)
           OR (@outcome = 'CLIENT' AND status BETWEEN 400 AND 499 AND status NOT IN (403, 404))
           OR (@outcome = 'SERVER' AND status >= 500))
    ORDER BY id DESC
    OPTION (RECOMPILE);
END;
