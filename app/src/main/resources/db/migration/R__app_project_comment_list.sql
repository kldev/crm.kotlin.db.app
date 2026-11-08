-- Comments of a project, newest first, keyset by id (next page: @before_id = last id of the previous page).
CREATE OR ALTER PROCEDURE app.project_comment_list
    @actor_id   int,
    @project_id bigint,
    @before_id  bigint = NULL,
    @page_size  int    = 50
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE @actor_role varchar(10);
    EXEC crm.actor_require @actor_id, @actor_role OUTPUT;
    EXEC crm.project_require_visible @actor_id, @actor_role, @project_id;

    IF @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 200
        THROW 51014, N'Page size must be between 1 and 200.', 1;

    SELECT TOP (@page_size + 1)
           c.id, c.project_id, c.author_id, u.login AS author_login, u.display_name AS author_display_name,
           c.body, c.created_at
    FROM crm.project_comments AS c
    JOIN crm.users AS u ON u.id = c.author_id
    WHERE c.project_id = @project_id
      AND (@before_id IS NULL OR c.id < @before_id)
    ORDER BY c.id DESC;
END;
