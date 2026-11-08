-- Internal (ADR-0013): the offer row every offer read and write returns, with its client, author and totals.
CREATE OR ALTER PROCEDURE crm.offer_select
    @offer_id bigint
AS
BEGIN
    SET NOCOUNT ON;
    SELECT o.id, o.number, o.client_id, c.name AS client_name, c.nip AS client_nip, c.city AS client_city,
           c.email AS client_email, o.template_key, t.name_pl AS template_name_pl, t.name_en AS template_name_en,
           o.title, o.intro, o.terms, o.currency, o.valid_until, o.status, o.author_user_id,
           u.display_name AS author_name, u.role AS author_role, u.job_title AS author_job_title,
           u.phone AS author_phone, u.email AS author_email, o.sent_at, o.decided_at, o.created_at, o.updated_at,
           ISNULL(x.item_count, 0) AS item_count, ISNULL(x.net, 0) AS total_net, ISNULL(x.vat, 0) AS total_vat,
           ISNULL(x.net, 0) + ISNULL(x.vat, 0) AS total_gross, o.row_version
    FROM crm.offers AS o
    JOIN crm.clients AS c ON c.id = o.client_id
    JOIN crm.offer_templates AS t ON t.template_key = o.template_key
    JOIN crm.users AS u ON u.id = o.author_user_id
    OUTER APPLY (
        SELECT COUNT(*) AS item_count, SUM(l.net) AS net, SUM(ROUND(l.net * i.vat_rate / 100.0, 2)) AS vat
        FROM crm.offer_items AS i
        CROSS APPLY (SELECT ROUND(i.quantity * i.unit_price, 2) AS net) AS l
        WHERE i.offer_id = o.id
    ) AS x
    WHERE o.id = @offer_id;
END;
