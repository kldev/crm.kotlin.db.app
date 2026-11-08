-- Readiness check of the database through the same path as every other call (EXEC app.*).
CREATE OR ALTER PROCEDURE app.health_ping
AS
BEGIN
    SET NOCOUNT ON;
    SELECT CAST(1 AS bit) AS ok, SYSUTCDATETIME() AS server_time;
END;
