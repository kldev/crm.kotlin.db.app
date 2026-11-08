-- The offer templates (ADR-0013) with their names and default validity.
CREATE OR ALTER PROCEDURE app.offer_template_list
    @actor_id int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    SELECT template_key, name_pl, name_en, title_pl, title_en, validity_days,
           (SELECT COUNT(*) FROM crm.offer_template_items AS i WHERE i.template_key = t.template_key) AS item_count
    FROM crm.offer_templates AS t
    ORDER BY sort_order;
END;
