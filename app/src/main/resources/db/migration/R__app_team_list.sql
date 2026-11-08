-- Teams with lead and member count, keyset by id. Every active user may list teams (to pick a project team).
CREATE OR ALTER PROCEDURE app.team_list
    @actor_id  int,
    @after_id  int = NULL,
    @page_size int = 50
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE @actor_role varchar(10);
    EXEC crm.actor_require @actor_id, @actor_role OUTPUT;

    IF @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 200
        THROW 51014, N'Page size must be between 1 and 200.', 1;

    SELECT TOP (@page_size + 1)
           t.id, t.name, t.lead_user_id, u.login AS lead_login,
           (SELECT COUNT(*) FROM crm.team_members AS tm WHERE tm.team_id = t.id) AS member_count,
           t.created_at
    FROM crm.teams AS t
    JOIN crm.users AS u ON u.id = t.lead_user_id
    WHERE (@after_id IS NULL OR t.id > @after_id)
    ORDER BY t.id;
END;
