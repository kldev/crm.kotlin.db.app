-- Agents (active CRM users) with the number of tickets each one has in progress. By name, keyset (name, id);
-- @search is the beginning of the name or the login. Also the list to hand a ticket over to.
CREATE OR ALTER PROCEDURE app.desk_agent_list
    @actor_id   int,
    @search     nvarchar(200) = NULL,
    @after_name nvarchar(200) = NULL,
    @after_id   int           = NULL,
    @page_size  int           = 50
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    IF @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 200
        THROW 51014, N'Page size must be between 1 and 200.', 1;
    SET @search = NULLIF(LTRIM(RTRIM(@search)), N'');
    DECLARE @pattern nvarchar(410) = REPLACE(REPLACE(REPLACE(@search, N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%';

    SELECT TOP (@page_size + 1)
           u.id, u.login, u.display_name, u.role,
           (SELECT COUNT(*) FROM crm.tickets AS t
            WHERE t.status = 'IN_PROGRESS' AND t.assignee_user_id = u.id) AS in_progress
    FROM crm.users AS u
    WHERE u.is_active = 1
      AND (@search IS NULL OR u.display_name LIKE @pattern OR u.login LIKE @pattern)
      AND (@after_name IS NULL OR u.display_name > @after_name OR (u.display_name = @after_name AND u.id > @after_id))
    ORDER BY u.display_name, u.id
    OPTION (RECOMPILE);
END;
