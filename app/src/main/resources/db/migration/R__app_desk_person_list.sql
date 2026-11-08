-- People (requesters and handlers) with their contacts, for agents. Small list, by surname.
CREATE OR ALTER PROCEDURE app.desk_person_list
    @actor_id int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    SELECT id, first_name, last_name, department, email, phone
    FROM crm.people
    ORDER BY last_name, first_name, id;
END;
