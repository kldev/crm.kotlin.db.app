/*
  The database at a glance (ADR-0012): server version and start, database size, sessions and requests now, and the
  desk's event store. Signed with the certificate crm_monitoring (afterMigrate callback): the DMVs need VIEW SERVER
  STATE, which only the signature brings - the application login never holds it.
*/
CREATE OR ALTER PROCEDURE app.monitoring_db_overview
    @actor_id int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.monitoring_require_admin @actor_id;
    SELECT CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(50)) AS product_version,
           CAST(SERVERPROPERTY('Edition') AS nvarchar(100)) AS edition,
           (SELECT sqlserver_start_time FROM sys.dm_os_sys_info) AS started_at_local,
           SYSDATETIMEOFFSET() AS server_now,
           (SELECT SUM(CAST(size AS bigint)) * 8 / 1024 FROM sys.database_files WHERE type = 0) AS data_mb,
           (SELECT SUM(CAST(size AS bigint)) * 8 / 1024 FROM sys.database_files WHERE type = 1) AS log_mb,
           (SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1) AS user_sessions,
           (SELECT COUNT(*) FROM sys.dm_exec_requests AS r JOIN sys.dm_exec_sessions AS s ON s.session_id = r.session_id
            WHERE s.is_user_process = 1) AS active_requests,
           (SELECT COUNT(*) FROM sys.dm_exec_requests WHERE blocking_session_id <> 0) AS blocked_requests,
           (SELECT COUNT_BIG(*) FROM crm.ticket_events) AS events,
           (SELECT MAX(seq) FROM crm.ticket_events) AS last_event_seq,
           (SELECT MAX(at) FROM crm.ticket_events) AS last_event_at,
           (SELECT COUNT_BIG(*) FROM crm.tickets) AS tickets;
END;
