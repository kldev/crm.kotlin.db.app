/*
  Offers, newest first, keyset by id (ADR-0013). SALES sees offers of their own clients. Filters: status, template,
  client, @search (the offer number or a part of the title). Returns @page_size + 1 rows.
*/
CREATE OR ALTER PROCEDURE app.offer_search
    @actor_id     int,
    @status       varchar(10)   = NULL,
    @template_key varchar(20)   = NULL,
    @client_id    bigint        = NULL,
    @search       nvarchar(200) = NULL,
    @after_id     bigint        = NULL,
    @page_size    int           = 25
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @role varchar(10);
    EXEC crm.actor_require @actor_id, @role OUTPUT;
    IF @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 200
        THROW 51014, N'Page size must be between 1 and 200.', 1;
    IF @status IS NOT NULL AND @status NOT IN ('DRAFT', 'SENT', 'ACCEPTED', 'REJECTED')
        THROW 51178, N'Status must be DRAFT, SENT, ACCEPTED or REJECTED.', 1;
    SET @search = NULLIF(LTRIM(RTRIM(@search)), N'');
    DECLARE @pattern nvarchar(410) = N'%' + REPLACE(REPLACE(REPLACE(@search, N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]') + N'%';

    DECLARE @page TABLE (ord int IDENTITY (1, 1) PRIMARY KEY, id bigint NOT NULL);
    INSERT @page (id)
    SELECT TOP (@page_size + 1) o.id
    FROM crm.offers AS o
    JOIN crm.clients AS c ON c.id = o.client_id
    WHERE (@role <> 'SALES' OR c.assigned_user_id = @actor_id)
      AND (@status IS NULL OR o.status = @status)
      AND (@template_key IS NULL OR o.template_key = @template_key)
      AND (@client_id IS NULL OR o.client_id = @client_id)
      AND (@search IS NULL OR o.number = @search OR o.title LIKE @pattern)
      AND (@after_id IS NULL OR o.id < @after_id)
    ORDER BY o.id DESC
    OPTION (RECOMPILE);

    -- The common row (with totals) for each id of the page, in page order.
    DECLARE @i int = 1, @n int = (SELECT COUNT(*) FROM @page), @id bigint;
    DECLARE @rows TABLE (ord int, id bigint, number varchar(20), client_id bigint, client_name nvarchar(200),
        client_nip varchar(20), client_city nvarchar(100), client_email varchar(254), template_key varchar(20),
        template_name_pl nvarchar(100), template_name_en nvarchar(100), title nvarchar(200), intro nvarchar(2000),
        terms nvarchar(4000), currency char(3), valid_until date, status varchar(10), author_user_id int,
        author_name nvarchar(200), author_role varchar(10), author_job_title nvarchar(100), author_phone varchar(30),
        author_email varchar(254), sent_at datetime2(3), decided_at datetime2(3), created_at datetime2(3),
        updated_at datetime2(3), item_count int, total_net decimal(18, 2), total_vat decimal(18, 2),
        total_gross decimal(18, 2), row_version binary(8));
    WHILE @i <= @n
    BEGIN
        SELECT @id = id FROM @page WHERE ord = @i;
        INSERT @rows (id, number, client_id, client_name, client_nip, client_city, client_email, template_key,
                      template_name_pl, template_name_en, title, intro, terms, currency, valid_until, status,
                      author_user_id, author_name, author_role, author_job_title, author_phone, author_email, sent_at,
                      decided_at, created_at, updated_at, item_count, total_net, total_vat, total_gross, row_version)
        EXEC crm.offer_select @id;
        UPDATE @rows SET ord = @i WHERE id = @id;
        SET @i += 1;
    END;
    SELECT id, number, client_id, client_name, client_nip, client_city, client_email, template_key, template_name_pl,
           template_name_en, title, intro, terms, currency, valid_until, status, author_user_id, author_name,
           author_role, author_job_title, author_phone, author_email, sent_at, decided_at, created_at, updated_at,
           item_count, total_net, total_vat, total_gross, row_version
    FROM @rows ORDER BY ord;
END;
