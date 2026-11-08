/*
  Server bootstrap, run once as `sa` by the `db-init` container (sqlcmd) before Flyway.
  Creates the database and two logins (ADR-0002):
    - $(MIGRATOR_LOGIN): db_owner of the CRM database; used by Flyway (CRM_MODE=migrate) and the seed (CRM_MODE=seed).
    - $(APP_LOGIN):      the application; Flyway grants it only EXECUTE on schema `app`.
  Idempotent: safe to run on every `docker compose up`. Passwords must not contain a single quote.

  sqlcmd variables: DB_NAME, MIGRATOR_LOGIN, MIGRATOR_PASSWORD, APP_LOGIN, APP_PASSWORD.
*/
SET NOCOUNT ON;

IF DB_ID(N'$(DB_NAME)') IS NULL
BEGIN
    CREATE DATABASE [$(DB_NAME)];
END;
GO

-- Seeding millions of rows: keep the log small. Readers do not block writers (row versioning).
ALTER DATABASE [$(DB_NAME)] SET RECOVERY SIMPLE;
ALTER DATABASE [$(DB_NAME)] SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
ALTER DATABASE [$(DB_NAME)] SET QUERY_STORE = ON;
GO

IF SUSER_ID(N'$(MIGRATOR_LOGIN)') IS NULL
    CREATE LOGIN [$(MIGRATOR_LOGIN)] WITH PASSWORD = N'$(MIGRATOR_PASSWORD)', CHECK_POLICY = OFF, DEFAULT_DATABASE = [$(DB_NAME)];
ELSE
    ALTER LOGIN [$(MIGRATOR_LOGIN)] WITH PASSWORD = N'$(MIGRATOR_PASSWORD)';

IF SUSER_ID(N'$(APP_LOGIN)') IS NULL
    CREATE LOGIN [$(APP_LOGIN)] WITH PASSWORD = N'$(APP_PASSWORD)', CHECK_POLICY = OFF, DEFAULT_DATABASE = [$(DB_NAME)];
ELSE
    ALTER LOGIN [$(APP_LOGIN)] WITH PASSWORD = N'$(APP_PASSWORD)';
GO

USE [$(DB_NAME)];
GO

IF USER_ID(N'$(MIGRATOR_LOGIN)') IS NULL
    CREATE USER [$(MIGRATOR_LOGIN)] FOR LOGIN [$(MIGRATOR_LOGIN)];
ALTER ROLE db_owner ADD MEMBER [$(MIGRATOR_LOGIN)];

-- The database user of the application. Its only permission (EXECUTE ON SCHEMA::app) is granted by Flyway.
IF USER_ID(N'$(APP_LOGIN)') IS NULL
    CREATE USER [$(APP_LOGIN)] FOR LOGIN [$(APP_LOGIN)];
GO

/*
  Monitoring procedures (ADR-0012) read server DMVs (sessions, requests, locks), which need VIEW SERVER STATE. The
  application login never gets it: the procedures are signed with the certificate `crm_monitoring`, whose login holds
  the permission (module signing) - the signature adds it only while those procedures run. The certificate lives in
  master (for the login) and in the database (to sign with), its private key there protected by the database master
  key, so Flyway's afterMigrate callback can re-sign a procedure after it changes without any password.
  Idempotent: when either copy is missing, both are recreated with a fresh random password.
*/
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
BEGIN
    DECLARE @dmk nvarchar(100) = CONVERT(nvarchar(36), NEWID()) + N'-Dmk#1';
    EXEC (N'CREATE MASTER KEY ENCRYPTION BY PASSWORD = N''' + @dmk + N'''');
END;
GO

DECLARE @in_master bit = IIF(EXISTS (SELECT 1 FROM master.sys.certificates WHERE name = N'crm_monitoring'), 1, 0);
DECLARE @in_db bit = IIF(EXISTS (SELECT 1 FROM sys.certificates WHERE name = N'crm_monitoring'), 1, 0);
IF @in_master = 0 OR @in_db = 0
BEGIN
    DECLARE @sql nvarchar(max) = N'';
    SELECT @sql += N'DROP SIGNATURE FROM ' + QUOTENAME(OBJECT_SCHEMA_NAME(cp.major_id)) + N'.'
                 + QUOTENAME(OBJECT_NAME(cp.major_id)) + N' BY CERTIFICATE crm_monitoring; '
    FROM sys.crypt_properties AS cp
    JOIN sys.certificates AS c ON c.thumbprint = cp.thumbprint
    WHERE c.name = N'crm_monitoring';
    EXEC (@sql);
    IF USER_ID(N'crm_monitoring_signer') IS NOT NULL DROP USER crm_monitoring_signer;
    IF @in_db = 1 DROP CERTIFICATE crm_monitoring;
    EXEC master.sys.sp_executesql
        N'IF SUSER_ID(N''crm_monitoring_signer'') IS NOT NULL DROP LOGIN crm_monitoring_signer;
          IF CERT_ID(N''crm_monitoring'') IS NOT NULL DROP CERTIFICATE crm_monitoring;';

    DECLARE @pwd nvarchar(100) = CONVERT(nvarchar(36), NEWID()) + N'-Cert#1';
    DECLARE @stmt nvarchar(max) =
        N'CREATE CERTIFICATE crm_monitoring ENCRYPTION BY PASSWORD = N''' + @pwd + N'''
            WITH SUBJECT = N''CRM monitoring procedures (ADR-0012)'', EXPIRY_DATE = ''20991231'';
          CREATE LOGIN crm_monitoring_signer FROM CERTIFICATE crm_monitoring;
          GRANT VIEW SERVER STATE TO crm_monitoring_signer;';
    EXEC master.sys.sp_executesql @stmt;

    DECLARE @cert varbinary(max), @key varbinary(max);
    EXEC master.sys.sp_executesql
        N'SELECT @c = CERTENCODED(CERT_ID(N''crm_monitoring'')), @k = CERTPRIVATEKEY(CERT_ID(N''crm_monitoring''), @p, @p);',
        N'@c varbinary(max) OUTPUT, @k varbinary(max) OUTPUT, @p nvarchar(100)',
        @c = @cert OUTPUT, @k = @key OUTPUT, @p = @pwd;
    SET @stmt = N'CREATE CERTIFICATE crm_monitoring FROM BINARY = ' + CONVERT(nvarchar(max), @cert, 1)
              + N' WITH PRIVATE KEY (BINARY = ' + CONVERT(nvarchar(max), @key, 1)
              + N', DECRYPTION BY PASSWORD = N''' + @pwd + N''');';
    EXEC (@stmt);
END;
GO

-- In the database the certificate's user may read metadata and database state for the signed procedures (table sizes).
IF USER_ID(N'crm_monitoring_signer') IS NULL
    CREATE USER crm_monitoring_signer FROM CERTIFICATE crm_monitoring;
GRANT VIEW DEFINITION, VIEW DATABASE STATE TO crm_monitoring_signer;
GO
