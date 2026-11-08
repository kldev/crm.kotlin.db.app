-- The lines of an offer with their net, VAT and gross amounts (rounded per line, as the totals are).
CREATE OR ALTER PROCEDURE app.offer_item_list
    @actor_id int,
    @offer_id bigint
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.offer_require_visible @actor_id, @offer_id;
    SELECT i.line_no, i.description, i.unit, i.quantity, i.unit_price, i.vat_rate, l.net,
           ROUND(l.net * i.vat_rate / 100.0, 2) AS vat, l.net + ROUND(l.net * i.vat_rate / 100.0, 2) AS gross
    FROM crm.offer_items AS i
    CROSS APPLY (SELECT ROUND(i.quantity * i.unit_price, 2) AS net) AS l
    WHERE i.offer_id = @offer_id
    ORDER BY i.line_no;
END;
