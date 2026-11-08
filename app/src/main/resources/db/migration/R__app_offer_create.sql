/*
  A new offer for a client from a template (ADR-0013): a draft with the template's title, introduction, terms and
  default lines, valid for the template's number of days, numbered OF/<year>/<nnnn> for the year in Warsaw time. The
  author is the actor; SALES only for their own clients. @lang chooses the template texts (pl / en). The signing
  company (ADR-0016) is @legal_entity_id or the template's, trading today (51205).
*/
CREATE OR ALTER PROCEDURE app.offer_create
    @actor_id     int,
    @client_id    bigint,
    @template_key varchar(20),
    @title        nvarchar(400) = NULL,
    @lang         char(2)       = 'pl',
    @legal_entity_id int        = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @role varchar(10);
    EXEC crm.actor_require @actor_id, @role OUTPUT;
    IF NOT EXISTS (SELECT 1 FROM crm.clients WHERE id = @client_id AND (@role <> 'SALES' OR assigned_user_id = @actor_id))
        THROW 51401, N'Client not found.', 1;
    IF NOT EXISTS (SELECT 1 FROM crm.offer_templates WHERE template_key = @template_key)
        THROW 51171, N'Choose a template from the list.', 1;
    SET @title = NULLIF(LTRIM(RTRIM(@title)), N'');
    IF LEN(@title) > 200
        THROW 51170, N'The title can have at most 200 characters.', 1;

    DECLARE @today date = CAST((SYSUTCDATETIME() AT TIME ZONE 'UTC') AT TIME ZONE 'Central European Standard Time' AS date);
    SET @legal_entity_id = ISNULL(@legal_entity_id, (SELECT legal_entity_id FROM crm.offer_templates WHERE template_key = @template_key));
    EXEC crm.legal_entity_require_active @legal_entity_id, @today;
    DECLARE @year smallint = YEAR(@today), @seq int, @offer_id bigint;

    BEGIN TRANSACTION;
    UPDATE crm.offer_numbers WITH (UPDLOCK, HOLDLOCK) SET @seq = last_used = last_used + 1 WHERE year = @year;
    IF @seq IS NULL
    BEGIN
        INSERT crm.offer_numbers (year, last_used) VALUES (@year, 1);
        SET @seq = 1;
    END;

    INSERT crm.offers (number, client_id, template_key, title, intro, terms, currency, valid_until, status,
                       author_user_id, updated_by, legal_entity_id)
    SELECT CONCAT('OF/', @year, '/', RIGHT(CONCAT('000', @seq), IIF(@seq > 9999, LEN(@seq), 4))), @client_id,
           @template_key, ISNULL(@title, IIF(@lang = 'en', t.title_en, t.title_pl)), IIF(@lang = 'en', t.intro_en, t.intro_pl),
           IIF(@lang = 'en', t.terms_en, t.terms_pl), 'PLN', DATEADD(DAY, t.validity_days, @today), 'DRAFT', @actor_id, @actor_id, @legal_entity_id
    FROM crm.offer_templates AS t
    WHERE t.template_key = @template_key;
    SET @offer_id = SCOPE_IDENTITY();

    INSERT crm.offer_items (offer_id, line_no, description, unit, quantity, unit_price, vat_rate)
    SELECT @offer_id, line_no, description, unit, quantity, unit_price, vat_rate
    FROM crm.offer_template_items WHERE template_key = @template_key;
    COMMIT;

    EXEC crm.offer_select @offer_id;
END;
