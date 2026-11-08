/*
  Clients page with filters. Keyset pagination (no OFFSET: page 100 000 costs the same as page 1):
    - @name_prefix given: ordered by (name, id), next page after (@after_name, @after_id);
    - otherwise:          newest first (id DESC),  next page after @after_id.
  SALES sees only clients assigned to them. Returns @page_size + 1 rows so the caller knows if there is a next page.
  OPTION (RECOMPILE): optional filters get a plan for the values actually passed.
*/
CREATE OR ALTER PROCEDURE app.client_search
    @actor_id    int,
    @name_prefix nvarchar(200) = NULL,
    @nip         varchar(20)   = NULL,
    @email       varchar(254)  = NULL,
    @city        nvarchar(100) = NULL,
    @status      varchar(10)   = NULL,
    @after_id    bigint        = NULL,
    @after_name  nvarchar(200) = NULL,
    @page_size   int           = 50
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE @actor_role varchar(10);
    EXEC crm.actor_require @actor_id, @actor_role OUTPUT;

    IF @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 200
        THROW 51014, N'Page size must be between 1 and 200.', 1;
    IF @status IS NOT NULL AND @status NOT IN ('LEAD', 'ACTIVE', 'INACTIVE')
        THROW 51013, N'Status must be LEAD, ACTIVE or INACTIVE.', 1;

    DECLARE @owner_id int = IIF(@actor_role = 'SALES', @actor_id, NULL);
    SET @name_prefix = NULLIF(LTRIM(RTRIM(@name_prefix)), N'');
    SET @nip = NULLIF(REPLACE(REPLACE(LTRIM(RTRIM(@nip)), N'-', N''), N' ', N''), N'');
    SET @email = NULLIF(LOWER(LTRIM(RTRIM(@email))), '');
    SET @city = NULLIF(LTRIM(RTRIM(@city)), N'');

    IF @name_prefix IS NOT NULL
    BEGIN
        -- Wildcards typed by the user are literals.
        DECLARE @pattern nvarchar(400) =
            REPLACE(REPLACE(REPLACE(@name_prefix, N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%';

        SELECT TOP (@page_size + 1)
               c.id, c.name, c.nip, c.email, c.phone, c.city, c.status, c.assigned_user_id,
               u.login AS assigned_user_login, c.created_at, c.updated_at, c.row_version
        FROM crm.clients AS c
        LEFT JOIN crm.users AS u ON u.id = c.assigned_user_id
        WHERE c.name LIKE @pattern
          AND (@owner_id IS NULL OR c.assigned_user_id = @owner_id)
          AND (@nip IS NULL OR c.nip = @nip)
          AND (@email IS NULL OR c.email = @email)
          AND (@city IS NULL OR c.city = @city)
          AND (@status IS NULL OR c.status = @status)
          AND (@after_name IS NULL OR c.name > @after_name OR (c.name = @after_name AND c.id > @after_id))
        ORDER BY c.name, c.id
        OPTION (RECOMPILE);
        RETURN;
    END;

    SELECT TOP (@page_size + 1)
           c.id, c.name, c.nip, c.email, c.phone, c.city, c.status, c.assigned_user_id,
           u.login AS assigned_user_login, c.created_at, c.updated_at, c.row_version
    FROM crm.clients AS c
    LEFT JOIN crm.users AS u ON u.id = c.assigned_user_id
    WHERE (@owner_id IS NULL OR c.assigned_user_id = @owner_id)
      AND (@nip IS NULL OR c.nip = @nip)
      AND (@email IS NULL OR c.email = @email)
      AND (@city IS NULL OR c.city = @city)
      AND (@status IS NULL OR c.status = @status)
      AND (@after_id IS NULL OR c.id < @after_id)
    ORDER BY c.id DESC
    OPTION (RECOMPILE);
END;
