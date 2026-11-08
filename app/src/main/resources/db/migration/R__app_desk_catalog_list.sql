-- The catalog for the forms and filters: one row per subcategory with its category, in catalog order. Public.
CREATE OR ALTER PROCEDURE app.desk_catalog_list
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    SELECT c.category_key, c.name AS category_name, c.department, s.subcategory_key, s.name AS subcategory_name,
           s.market, s.is_active
    FROM crm.desk_categories AS c
    JOIN crm.desk_subcategories AS s ON s.category_key = c.category_key
    ORDER BY c.sort_order, s.sort_order;
END;
