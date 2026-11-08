/*
  ADR-0012: signs the procedures that read server DMVs with the certificate crm_monitoring (created by
  infrastructure/sql/init.sql). CREATE OR ALTER drops a signature, so this runs after every migration and signs what
  is not signed. Without the certificate (a database set up by other means) nothing is signed and those procedures
  answer with what the caller may see.
*/
IF EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'crm_monitoring')
BEGIN
    DECLARE @thumbprint varbinary(32) = (SELECT thumbprint FROM sys.certificates WHERE name = N'crm_monitoring');
    DECLARE @sql nvarchar(max) = N'';
    SELECT @sql += N'ADD SIGNATURE TO ' + QUOTENAME(s.name) + N'.' + QUOTENAME(p.name) + N' BY CERTIFICATE crm_monitoring; '
    FROM sys.procedures AS p
    JOIN sys.schemas AS s ON s.schema_id = p.schema_id
    WHERE s.name = N'app'
      AND p.name IN (N'monitoring_db_overview', N'monitoring_db_sessions', N'monitoring_db_tables')
      AND NOT EXISTS (SELECT 1 FROM sys.crypt_properties AS cp WHERE cp.major_id = p.object_id AND cp.thumbprint = @thumbprint);
    EXEC (@sql);
END;
