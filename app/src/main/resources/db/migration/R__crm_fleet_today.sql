-- Internal (ADR-0018): today in Warsaw - handovers are calendar days there.
CREATE OR ALTER FUNCTION crm.fleet_today()
RETURNS date
AS
BEGIN
    RETURN CAST((SYSUTCDATETIME() AT TIME ZONE 'UTC') AT TIME ZONE 'Central European Standard Time' AS date);
END;
