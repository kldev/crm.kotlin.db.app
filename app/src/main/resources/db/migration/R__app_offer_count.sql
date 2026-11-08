-- Number of offers matching the filters of app.offer_search. Called only when the user asks for the total.
CREATE OR ALTER PROCEDURE app.offer_count
    @actor_id     int,
    @status       varchar(10)   = NULL,
    @template_key varchar(20)   = NULL,
    @legal_entity_id int        = NULL,
    @client_id    bigint        = NULL,
    @search       nvarchar(200) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @role varchar(10);
    EXEC crm.actor_require @actor_id, @role OUTPUT;
    SET @search = NULLIF(LTRIM(RTRIM(@search)), N'');
    DECLARE @pattern nvarchar(410) = N'%' + REPLACE(REPLACE(REPLACE(@search, N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%';
    SELECT COUNT_BIG(*) AS total
    FROM crm.offers AS o
    JOIN crm.clients AS c ON c.id = o.client_id
    WHERE (@role <> 'SALES' OR c.assigned_user_id = @actor_id)
      AND (@status IS NULL OR o.status = @status)
      AND (@template_key IS NULL OR o.template_key = @template_key)
      AND (@legal_entity_id IS NULL OR o.legal_entity_id = @legal_entity_id)
      AND (@client_id IS NULL OR o.client_id = @client_id)
      AND (@search IS NULL OR o.number = @search OR o.title LIKE @pattern)
    OPTION (RECOMPILE);
END;
