-- Internal (ADR-0007): the acting agent - any active CRM user - and their name as the events remember it.
CREATE OR ALTER PROCEDURE crm.desk_actor
    @actor_id   int,
    @actor_name nvarchar(200) OUTPUT
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    SELECT @actor_name = display_name FROM crm.users WHERE id = @actor_id;
END;
