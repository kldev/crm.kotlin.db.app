CREATE OR ALTER PROCEDURE app.project_comment_add
    @actor_id   int,
    @project_id bigint,
    @body       nvarchar(4000)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE @actor_role varchar(10);
    EXEC crm.actor_require @actor_id, @actor_role OUTPUT;
    EXEC crm.project_require_visible @actor_id, @actor_role, @project_id;

    SET @body = NULLIF(LTRIM(RTRIM(@body)), N'');
    IF @body IS NULL
        THROW 51034, N'Comment text is required.', 1;

    DECLARE @id bigint;
    INSERT crm.project_comments (project_id, author_id, body) VALUES (@project_id, @actor_id, @body);
    SET @id = SCOPE_IDENTITY();

    SELECT c.id, c.project_id, c.author_id, u.login AS author_login, u.display_name AS author_display_name,
           c.body, c.created_at
    FROM crm.project_comments AS c
    JOIN crm.users AS u ON u.id = c.author_id
    WHERE c.project_id = @project_id AND c.id = @id;
END;
