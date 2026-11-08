-- Per-procedure totals since the procedure cache was cleared before the k6 run (sys.dm_exec_procedure_stats).
SET NOCOUNT ON;
SELECT OBJECT_SCHEMA_NAME(ps.object_id, ps.database_id) + '.' + OBJECT_NAME(ps.object_id, ps.database_id) AS [procedure],
       ps.execution_count AS calls,
       CAST(ps.total_elapsed_time / 1000.0 / ps.execution_count AS decimal(10, 2)) AS avg_ms,
       CAST(ps.max_elapsed_time / 1000.0 AS decimal(10, 2)) AS max_ms,
       CAST(ps.total_worker_time / 1000.0 / ps.execution_count AS decimal(10, 2)) AS avg_cpu_ms,
       ps.total_logical_reads / ps.execution_count AS avg_logical_reads,
       ps.max_logical_reads AS max_logical_reads
FROM sys.dm_exec_procedure_stats AS ps
WHERE ps.database_id = DB_ID()
  AND OBJECT_SCHEMA_NAME(ps.object_id, ps.database_id) = 'app'
ORDER BY ps.total_elapsed_time DESC;
