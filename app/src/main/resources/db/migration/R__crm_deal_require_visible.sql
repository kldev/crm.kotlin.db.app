-- Internal (ADR-0015): the deal exists and the actor may see it - SALES only deals of their own clients (51407).
CREATE OR ALTER PROCEDURE crm.deal_require_visible
    @actor_id int,
    @deal_id  bigint
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @role varchar(10);
    EXEC crm.actor_require @actor_id, @role OUTPUT;
    IF NOT EXISTS (SELECT 1 FROM crm.deals AS d JOIN crm.clients AS c ON c.id = d.client_id
                   WHERE d.id = @deal_id AND (@role <> 'SALES' OR c.assigned_user_id = @actor_id))
        THROW 51407, N'Deal not found.', 1;
END;
