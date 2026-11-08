-- People for the public form: names and departments only, never the contacts (the page needs no sign-in).
CREATE OR ALTER PROCEDURE app.desk_public_person_list
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    SELECT id, first_name, last_name, department
    FROM crm.people
    ORDER BY last_name, first_name, id;
END;
