-- The values of choice fields, in list order; favourites are offered first by the form. Public.
CREATE OR ALTER PROCEDURE app.desk_field_option_list
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    SELECT field_key, option_value, is_favorite FROM crm.desk_field_options ORDER BY field_key, sort_order;
END;
