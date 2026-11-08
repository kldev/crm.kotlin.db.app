-- Internal (ADR-0015): the deal row every deal read and write returns, with the client, owner, stage and offer.
CREATE OR ALTER PROCEDURE crm.deal_select
    @deal_id bigint
AS
BEGIN
    SET NOCOUNT ON;
    SELECT d.id, d.title, d.client_id, c.name AS client_name, d.owner_user_id, o.display_name AS owner_name, d.stage,
           s.probability, s.is_closed, d.value, d.currency, d.expected_close, d.offer_id, f.number AS offer_number,
           d.lost_reason, d.stage_changed_at, d.closed_at, d.created_at, d.updated_at, d.row_version
    FROM crm.deals AS d
    JOIN crm.clients AS c ON c.id = d.client_id
    JOIN crm.users AS o ON o.id = d.owner_user_id
    JOIN crm.deal_stages AS s ON s.stage = d.stage
    LEFT JOIN crm.offers AS f ON f.id = d.offer_id
    WHERE d.id = @deal_id;
END;
