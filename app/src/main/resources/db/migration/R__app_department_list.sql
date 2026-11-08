-- The departments (ADR-0014), with how many active users each has.
CREATE OR ALTER PROCEDURE app.department_list
    @actor_id int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    SELECT d.name, (SELECT COUNT(*) FROM crm.users AS u WHERE u.department = d.name AND u.is_active = 1) AS users
    FROM crm.departments AS d
    ORDER BY d.sort_order;
END;
