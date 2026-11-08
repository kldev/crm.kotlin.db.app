/*
  Number of clients matching the filters of app.client_search (same visibility: SALES counts only own clients).
  Not part of the list: a count reads every matching row, so the list stays keyset-only and the UI calls this
  only when the user asks for the total.
*/
CREATE OR ALTER PROCEDURE app.client_count
    @actor_id    int,
    @name_prefix nvarchar(200) = NULL,
    @nip         varchar(20)   = NULL,
    @email       varchar(254)  = NULL,
    @city        nvarchar(100) = NULL,
    @status      varchar(10)   = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE @actor_role varchar(10);
    EXEC crm.actor_require @actor_id, @actor_role OUTPUT;

    IF @status IS NOT NULL AND @status NOT IN ('LEAD', 'ACTIVE', 'INACTIVE')
        THROW 51013, N'Status must be LEAD, ACTIVE or INACTIVE.', 1;

    DECLARE @owner_id int = IIF(@actor_role = 'SALES', @actor_id, NULL);
    SET @name_prefix = NULLIF(LTRIM(RTRIM(@name_prefix)), N'');
    SET @nip = NULLIF(REPLACE(REPLACE(LTRIM(RTRIM(@nip)), N'-', N''), N' ', N''), N'');
    SET @email = NULLIF(LOWER(LTRIM(RTRIM(@email))), '');
    SET @city = NULLIF(LTRIM(RTRIM(@city)), N'');

    -- Wildcards typed by the user are literals (as in app.client_search).
    DECLARE @pattern nvarchar(400) =
        REPLACE(REPLACE(REPLACE(@name_prefix, N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%';

    SELECT COUNT_BIG(*) AS total
    FROM crm.clients AS c
    WHERE (@pattern IS NULL OR c.name LIKE @pattern)
      AND (@owner_id IS NULL OR c.assigned_user_id = @owner_id)
      AND (@nip IS NULL OR c.nip = @nip)
      AND (@email IS NULL OR c.email = @email)
      AND (@city IS NULL OR c.city = @city)
      AND (@status IS NULL OR c.status = @status)
    OPTION (RECOMPILE);
END;
