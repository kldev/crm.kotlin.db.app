/*
  Seed (ADR-0013, ADR-0016): @offers offers (10 000 by default) for the clients of the seeded deals, from the three
  templates with their lines and signing company, numbered OF/<year>/<n> on from the year's counter, in every status
  (sent ones in the last two months). Deals past the first stages get an offer of their client. Set-based; only when no
  offer exists; deterministic for one @random_seed. Called by seed.desk_run after the deals.
*/
CREATE OR ALTER PROCEDURE seed.offers_run
    @random_seed int = 2026,
    @offers      int = 10000
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    IF EXISTS (SELECT 1 FROM crm.offers) OR NOT EXISTS (SELECT 1 FROM crm.deals)
        RETURN;

    DECLARE @pool TABLE (n int IDENTITY (0, 1) PRIMARY KEY, client_id bigint, owner int);
    INSERT @pool (client_id, owner) SELECT DISTINCT client_id, owner_user_id FROM crm.deals ORDER BY client_id;
    DECLARE @pool_count int = (SELECT COUNT(*) FROM @pool);
    DECLARE @templates TABLE (n int PRIMARY KEY, template_key varchar(20));
    INSERT @templates VALUES (0, 'CONSTRUCTION'), (1, 'IT'), (2, 'OUTSOURCING');

    DECLARE @now datetime2(3) = SYSUTCDATETIME();
    DECLARE @today date = CAST((@now AT TIME ZONE 'UTC') AT TIME ZONE 'Central European Standard Time' AS date);
    DECLARE @year smallint = YEAR(@today);

    BEGIN TRANSACTION;
    DECLARE @first int = ISNULL((SELECT last_used FROM crm.offer_numbers WITH (UPDLOCK, HOLDLOCK) WHERE year = @year), 0);
    DECLARE @created TABLE (id bigint, template_key varchar(20));
    INSERT crm.offers (number, client_id, template_key, title, intro, terms, currency, valid_until, status, author_user_id,
                       sent_at, decided_at, created_at, updated_at, updated_by, legal_entity_id)
    OUTPUT inserted.id, inserted.template_key INTO @created
    SELECT CONCAT('OF/', @year, '/', RIGHT(CONCAT('000', @first + s.value + 1), IIF(@first + s.value + 1 > 9999, LEN(@first + s.value + 1), 4))),
           p.client_id, t.template_key, t.title_pl, t.intro_pl, t.terms_pl, 'PLN',
           DATEADD(DAY, t.validity_days, x.created), x.status, p.owner,
           IIF(x.status = 'DRAFT', NULL, DATEADD(DAY, 1, CAST(x.created AS datetime2(3)))),
           IIF(x.status IN ('ACCEPTED', 'REJECTED'), DATEADD(DAY, 7, CAST(x.created AS datetime2(3))), NULL),
           CAST(x.created AS datetime2(3)), @now, p.owner, t.legal_entity_id
    FROM GENERATE_SERIES(0, @offers - 1) AS s
    JOIN @pool AS p ON p.n = s.value % @pool_count
    CROSS APPLY (SELECT HASHBYTES('SHA2_256', CONCAT(@random_seed, ':offer:', s.value)) AS b) AS hb
    CROSS APPLY (SELECT CAST(SUBSTRING(hb.b, 1, 4) AS int) & 0x7FFFFFFF AS h1, CAST(SUBSTRING(hb.b, 5, 4) AS int) & 0x7FFFFFFF AS h2) AS h
    JOIN @templates AS tk ON tk.n = h.h1 % 3
    JOIN crm.offer_templates AS t ON t.template_key = tk.template_key
    -- 25% drafts, 35% sent, 25% accepted, 15% rejected; drafts are recent, the rest from the last two months.
    CROSS APPLY (SELECT CASE WHEN h.h2 % 100 < 25 THEN 'DRAFT' WHEN h.h2 % 100 < 60 THEN 'SENT'
                             WHEN h.h2 % 100 < 85 THEN 'ACCEPTED' ELSE 'REJECTED' END AS status,
                        DATEADD(DAY, -IIF(h.h2 % 100 < 25, h.h1 % 7, 7 + h.h1 % 53), @today) AS created) AS x;

    IF EXISTS (SELECT 1 FROM crm.offer_numbers WHERE year = @year)
        UPDATE crm.offer_numbers SET last_used = @first + @offers WHERE year = @year;
    ELSE
        INSERT crm.offer_numbers (year, last_used) VALUES (@year, @offers);

    INSERT crm.offer_items (offer_id, line_no, description, unit, quantity, unit_price, vat_rate)
    SELECT c.id, i.line_no, i.description, i.unit, i.quantity, i.unit_price, i.vat_rate
    FROM @created AS c
    JOIN crm.offer_template_items AS i ON i.template_key = c.template_key;
    COMMIT;

    -- A deal past the first stages names an offer of its client.
    UPDATE d SET offer_id = o.id
    FROM crm.deals AS d
    CROSS APPLY (SELECT TOP (1) id FROM crm.offers AS x WHERE x.client_id = d.client_id ORDER BY x.id) AS o
    WHERE d.stage IN ('PROPOSAL', 'NEGOTIATION', 'WON');
END;
