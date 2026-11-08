/*
  User sessions of the server now (ADR-0012): who, from where, what they run, how long, and who blocks whom. Signed
  with the certificate crm_monitoring (VIEW SERVER STATE). The SQL text is cut to 1000 characters.
*/
CREATE OR ALTER PROCEDURE app.monitoring_db_sessions
    @actor_id int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.monitoring_require_admin @actor_id;
    SELECT s.session_id, s.login_name, s.host_name, s.program_name, s.status AS session_status,
           DB_NAME(s.database_id) AS database_name, r.status AS request_status, r.command, r.wait_type,
           r.wait_time AS wait_ms, r.blocking_session_id, r.total_elapsed_time AS elapsed_ms, s.open_transaction_count,
           s.last_request_start_time,
           CAST(IIF(EXISTS (SELECT 1 FROM sys.dm_exec_requests AS b WHERE b.blocking_session_id = s.session_id), 1, 0) AS bit) AS is_blocking,
           LEFT(t.text, 1000) AS sql_text
    FROM sys.dm_exec_sessions AS s
    LEFT JOIN sys.dm_exec_requests AS r ON r.session_id = s.session_id
    OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
    WHERE s.is_user_process = 1
    ORDER BY IIF(r.blocking_session_id <> 0, 0, 1), r.total_elapsed_time DESC, s.session_id;
END;
