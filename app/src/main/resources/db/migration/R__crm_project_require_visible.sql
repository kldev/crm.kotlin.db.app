-- Internal helper: can the actor see (and work on) the project? MANAGER and ADMIN see all projects; SALES sees
-- projects they own, projects of their teams and projects of clients assigned to them. Otherwise 51403 - the
-- project's existence is not revealed.
CREATE OR ALTER PROCEDURE crm.project_require_visible
    @actor_id   int,
    @actor_role varchar(10),
    @project_id bigint
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM crm.projects AS p
        WHERE p.id = @project_id
          AND (@actor_role IN ('ADMIN', 'MANAGER')
               OR p.owner_user_id = @actor_id
               OR EXISTS (SELECT 1 FROM crm.team_members AS tm WHERE tm.team_id = p.team_id AND tm.user_id = @actor_id)
               OR EXISTS (SELECT 1 FROM crm.clients AS c WHERE c.id = p.client_id AND c.assigned_user_id = @actor_id)))
        THROW 51403, N'Project not found.', 1;
END;
