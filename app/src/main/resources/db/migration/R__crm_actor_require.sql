-- Internal helper: resolves the role of the acting user. Not executable by the application login (schema crm).
-- 50001 = the host did not pass an actor (a bug), 51302 = the user is unknown or deactivated.
CREATE OR ALTER PROCEDURE crm.actor_require
    @actor_id int,
    @role     varchar(10) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    IF @actor_id IS NULL
        THROW 50001, N'Actor is not set.', 1;

    SELECT @role = role
    FROM crm.users
    WHERE id = @actor_id
      AND is_active = 1;

    IF @role IS NULL
        THROW 51302, N'Your account is not active.', 1;
END;
