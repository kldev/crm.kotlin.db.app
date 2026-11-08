-- Report fields of every subcategory, in the form's order, for the catalog. Public (the public form shows them).
CREATE OR ALTER PROCEDURE app.desk_field_list
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    SELECT sf.subcategory_key, f.field_key, f.label, f.kind, f.placeholder, sf.is_required
    FROM crm.desk_subcategory_fields AS sf
    JOIN crm.desk_fields AS f ON f.field_key = sf.field_key
    ORDER BY sf.subcategory_key, sf.sort_order;
END;
