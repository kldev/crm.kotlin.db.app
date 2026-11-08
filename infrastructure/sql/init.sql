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
