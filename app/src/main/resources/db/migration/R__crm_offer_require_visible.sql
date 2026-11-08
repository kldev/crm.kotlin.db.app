-- Internal (ADR-0013): the offer exists and the actor may see it - SALES only offers of their own clients (51405).
CREATE OR ALTER PROCEDURE crm.offer_require_visible
    @actor_id int,
    @offer_id bigint
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @role varchar(10);
    EXEC crm.actor_require @actor_id, @role OUTPUT;
    IF NOT EXISTS (SELECT 1 FROM crm.offers AS o JOIN crm.clients AS c ON c.id = o.client_id
                   WHERE o.id = @offer_id AND (@role <> 'SALES' OR c.assigned_user_id = @actor_id))
        THROW 51405, N'Offer not found.', 1;
END;
