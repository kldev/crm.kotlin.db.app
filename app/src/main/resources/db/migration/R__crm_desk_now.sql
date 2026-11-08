/*
  Internal (ADR-0007): the desk's clock for writes. Always the database clock - except for a db_owner (the seed, run
  with the migrator login), which may set SESSION_CONTEXT 'desk.now' to replay a ticket's history at past moments
  through the very procedures the application calls. The application login is never db_owner, so it cannot move
  the clock.
*/
CREATE OR ALTER FUNCTION crm.desk_now ()
RETURNS datetime2(3)
AS
BEGIN
    IF IS_ROLEMEMBER('db_owner') = 1
    BEGIN
        DECLARE @at datetime2(3) = TRY_CAST(SESSION_CONTEXT(N'desk.now') AS datetime2(3));
        IF @at IS NOT NULL RETURN @at;
    END;
    RETURN SYSUTCDATETIME();
END;
