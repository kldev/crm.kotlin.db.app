-- A batch of log entries from the in-memory queue (ADR-0012): a JSON array, one INSERT; long texts are cut.
CREATE OR ALTER PROCEDURE app.monitoring_logs_write
    @rows nvarchar(max)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    INSERT crm.app_logs (at, level, source, message, exception, request_path, trace_id)
    SELECT at, level, LEFT(source, 200), LEFT(message, 4000), LEFT(exception, 16000), LEFT(request_path, 400),
           LEFT(trace_id, 64)
    FROM OPENJSON(@rows)
         WITH (at datetime2(3) '$.at', level varchar(5) '$.level', source nvarchar(400) '$.source',
               message nvarchar(max) '$.message', exception nvarchar(max) '$.exception',
               request_path nvarchar(2000) '$.requestPath', trace_id varchar(200) '$.traceId')
    WHERE level IN ('INFO', 'WARN', 'ERROR');
    SELECT @@ROWCOUNT AS written;
END;
