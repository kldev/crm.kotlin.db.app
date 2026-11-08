CREATE OR ALTER PROCEDURE app.project_stage_history_list
    @actor_id   int,
    @project_id bigint
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE @actor_role varchar(10);
    EXEC crm.actor_require @actor_id, @actor_role OUTPUT;
    EXEC crm.project_require_visible @actor_id, @actor_role, @project_id;

    SELECT h.id, h.from_stage, h.to_stage, h.changed_at, h.changed_by, u.login AS changed_by_login
    FROM crm.project_stage_history AS h
    LEFT JOIN crm.users AS u ON u.id = h.changed_by
    WHERE h.project_id = @project_id
    ORDER BY h.id DESC;
END;
