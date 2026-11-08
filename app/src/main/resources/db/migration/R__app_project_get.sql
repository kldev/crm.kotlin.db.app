CREATE OR ALTER PROCEDURE app.project_get
    @actor_id int,
    @id       bigint
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE @actor_role varchar(10);
    EXEC crm.actor_require @actor_id, @actor_role OUTPUT;
    EXEC crm.project_require_visible @actor_id, @actor_role, @id;

    SELECT v.id, v.name, v.stage, v.start_date, v.due_date, v.budget, v.is_overdue, v.stage_changed_at,
           v.client_id, v.client_name, v.client_city, v.team_id, v.team_name, v.owner_user_id, v.owner_login,
           v.owner_display_name, v.legal_entity_id, v.legal_entity_name, v.updated_at, v.row_version
    FROM crm.v_projects AS v
    WHERE v.id = @id;
END;
