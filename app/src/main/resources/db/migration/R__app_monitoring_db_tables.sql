-- Tables of the database with rows and space, largest first (ADR-0012). Signed with the certificate crm_monitoring.
CREATE OR ALTER PROCEDURE app.monitoring_db_tables
    @actor_id int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.monitoring_require_admin @actor_id;
    SELECT s.name AS schema_name, t.name AS table_name,
           SUM(IIF(ps.index_id IN (0, 1), ps.row_count, 0)) AS row_count,
           SUM(ps.reserved_page_count) * 8 / 1024.0 AS reserved_mb,
           SUM(IIF(ps.index_id IN (0, 1), ps.in_row_data_page_count + ps.lob_used_page_count + ps.row_overflow_used_page_count, 0)) * 8 / 1024.0 AS data_mb,
           SUM(IIF(ps.index_id > 1, ps.used_page_count, 0)) * 8 / 1024.0 AS index_mb
    FROM sys.dm_db_partition_stats AS ps
    JOIN sys.tables AS t ON t.object_id = ps.object_id
    JOIN sys.schemas AS s ON s.schema_id = t.schema_id
    GROUP BY s.name, t.name
    ORDER BY reserved_mb DESC, s.name, t.name;
END;
