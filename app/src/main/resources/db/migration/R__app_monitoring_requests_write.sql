-- A batch of recorded HTTP answers from the in-memory queue (ADR-0012): a JSON array, one INSERT.
CREATE OR ALTER PROCEDURE app.monitoring_requests_write
    @rows nvarchar(max)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    INSERT crm.http_requests (at, method, path, status, elapsed_ms, user_login, trace_id)
    SELECT at, LEFT(method, 10), LEFT(path, 400), status, elapsed_ms, LEFT(user_login, 64), LEFT(trace_id, 64)
    FROM OPENJSON(@rows)
         WITH (at datetime2(3) '$.at', method varchar(20) '$.method', path nvarchar(2000) '$.path',
               status smallint '$.status', elapsed_ms int '$.elapsedMs', user_login varchar(200) '$.user',
               trace_id varchar(200) '$.traceId');
    SELECT @@ROWCOUNT AS written;
END;
