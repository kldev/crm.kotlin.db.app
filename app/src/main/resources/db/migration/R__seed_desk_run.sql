/*
  Seed of the service desk (ADR-0007), with the migrator login. Idempotent: agents and people are added only when
  missing (by login / e-mail), tickets only into an empty desk - run it again at any time.

  Agents: the desk team as CRM users (role SALES, the same @password_hash as the perf users); any CRM user can
  work tickets, these ten just have names to recognise. People: the requesters of the public form.
  Tickets: @tickets reported over the last 28 days through the same procedures the application calls, so every
  ticket has a real stream; about 40% are taken and half of those resolved. Deterministic for one @random_seed.
*/
CREATE OR ALTER PROCEDURE seed.desk_run
    @password_hash varchar(100),
    @tickets       int = 200,
    @random_seed   int = 2026
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    IF @password_hash IS NULL OR LEN(@password_hash) = 0
        THROW 51020, N'Password is required.', 1;
    IF @tickets IS NULL OR @tickets NOT BETWEEN 0 AND 100000
        THROW 51050, N'Seed: desk tickets must be between 0 and 100000.', 1;

    INSERT crm.users (login, display_name, role, password_hash)
    SELECT a.login, a.display_name, 'SALES', @password_hash
    FROM (VALUES ('anna.nowak', N'Anna Nowak'),
            ('piotr.kowalski', N'Piotr Kowalski'),
            ('katarzyna.wisniewska', N'Katarzyna Wiśniewska'),
            ('tomasz.wojcik', N'Tomasz Wójcik'),
            ('magdalena.kaminska', N'Magdalena Kamińska'),
            ('michal.lewandowski', N'Michał Lewandowski'),
            ('agnieszka.zielinska', N'Agnieszka Zielińska'),
            ('pawel.szymanski', N'Paweł Szymański'),
            ('joanna.wozniak', N'Joanna Woźniak'),
            ('krzysztof.dabrowski', N'Krzysztof Dąbrowski')) AS a (login, display_name)
    WHERE NOT EXISTS (SELECT 1 FROM crm.users AS u WHERE u.login = a.login);

    INSERT crm.people (first_name, last_name, department, email, phone)
    SELECT p.first_name, p.last_name, p.department, p.email, p.phone
    FROM (VALUES (N'Adam', N'Mazur', N'Sprzedaż', 'adam.mazur@company.io', '+48 600 200 201'),
            (N'Barbara', N'Krawczyk', N'Sprzedaż', 'barbara.krawczyk@company.io', NULL),
            (N'Cezary', N'Piotrowski', N'Sprzedaż', 'cezary.piotrowski@company.io', '+48 600 200 203'),
            (N'Dorota', N'Grabowska', N'Finanse', 'dorota.grabowska@company.io', '+48 600 200 204'),
            (N'Emil', N'Nowakowski', N'Finanse', 'emil.nowakowski@company.io', NULL),
            (N'Fryderyka', N'Pawłowska', N'Finanse', 'fryderyka.pawlowska@company.io', '+48 600 200 206'),
            (N'Grzegorz', N'Michalski', N'Kadry', 'grzegorz.michalski@company.io', '+48 600 200 207'),
            (N'Halina', N'Nowicka', N'Kadry', 'halina.nowicka@company.io', NULL),
            (N'Igor', N'Adamczyk', N'Logistyka', 'igor.adamczyk@company.io', '+48 600 200 209'),
            (N'Joanna', N'Dudek', N'Logistyka', 'joanna.dudek@company.io', '+48 600 200 210'),
            (N'Kamil', N'Zając', N'Logistyka', 'kamil.zajac@company.io', NULL),
            (N'Lena', N'Wieczorek', N'Zarząd', 'lena.wieczorek@company.io', '+48 600 200 212'),
            (N'Marek', N'Jabłoński', N'Zarząd', 'marek.jablonski@company.io', '+48 600 200 213'),
            (N'Natalia', N'Król', N'Obsługa klienta', 'natalia.krol@company.io', '+48 600 200 214'),
            (N'Oskar', N'Majewski', N'Obsługa klienta', 'oskar.majewski@company.io', NULL),
            (N'Patrycja', N'Olszewska', N'Obsługa klienta', 'patrycja.olszewska@company.io', '+48 600 200 216'),
            (N'Robert', N'Jaworski', N'Produkt', 'robert.jaworski@company.io', '+48 600 200 217'),
            (N'Sylwia', N'Wróbel', N'Produkt', 'sylwia.wrobel@company.io', NULL),
            (N'Tadeusz', N'Malinowski', N'Produkt', 'tadeusz.malinowski@company.io', '+48 600 200 219'),
            (N'Urszula', N'Pawlak', N'Zakupy', 'urszula.pawlak@company.io', '+48 600 200 220'),
            (N'Wiktor', N'Witkowski', N'Zakupy', 'wiktor.witkowski@company.io', NULL),
            (N'Zofia', N'Walczak', N'Administracja', 'zofia.walczak@company.io', '+48 600 200 222'),
            (N'Artur', N'Stępień', N'Administracja', 'artur.stepien@company.io', '+48 600 200 223'),
            (N'Beata', N'Górska', N'Badania i rozwój', 'beata.gorska@company.io', NULL),
            (N'Daniel', N'Rutkowski', N'Badania i rozwój', 'daniel.rutkowski@company.io', '+48 600 200 225'),
            (N'Ewa', N'Michalak', N'Badania i rozwój', 'ewa.michalak@company.io', '+48 600 200 226'),
            (N'Filip', N'Sikora', N'Jakość', 'filip.sikora@company.io', NULL),
            (N'Gabriela', N'Ostrowska', N'Jakość', 'gabriela.ostrowska@company.io', '+48 600 200 228'),
            (N'Henryk', N'Baran', N'Utrzymanie ruchu', 'henryk.baran@company.io', '+48 600 200 229'),
            (N'Iwona', N'Duda', N'Utrzymanie ruchu', 'iwona.duda@company.io', '+48 600 200 230'),
            (N'Aleksandra', N'Kubiak', N'Rekrutacja', 'aleksandra.kubiak@company.io', '+48 600 200 231'),
            (N'Bożena', N'Sadowska', N'Rekrutacja', 'bozena.sadowska@company.io', '+48 600 200 232'),
            (N'Celina', N'Mróz', N'Rekrutacja', 'celina.mroz@company.io', NULL),
            (N'Danuta', N'Czerwińska', N'Rekrutacja', 'danuta.czerwinska@company.io', '+48 600 200 234'),
            (N'Elżbieta', N'Zawadzka', N'Rekrutacja', 'elzbieta.zawadzka@company.io', '+48 600 200 235'),
            (N'Franciszka', N'Kalinowska', N'Rekrutacja', 'franciszka.kalinowska@company.io', NULL),
            (N'Hanna', N'Wysocka', N'Rekrutacja', 'hanna.wysocka@company.io', '+48 600 200 237'),
            (N'Izabela', N'Kozłowska', N'Rekrutacja', 'izabela.kozlowska@company.io', '+48 600 200 238'),
            (N'Justyna', N'Sobczak', N'Rekrutacja', 'justyna.sobczak@company.io', NULL),
            (N'Karolina', N'Wilk', N'Rekrutacja', 'karolina.wilk@company.io', '+48 600 200 240')) AS p (first_name, last_name, department, email, phone)
    WHERE NOT EXISTS (SELECT 1 FROM crm.people AS x WHERE x.email_normalized = LOWER(p.email));

    IF @tickets = 0 OR EXISTS (SELECT 1 FROM crm.tickets)
        RETURN;

    DECLARE @agents TABLE (n int IDENTITY (0, 1) PRIMARY KEY, id int NOT NULL);
    INSERT @agents (id)
    SELECT u.id FROM crm.users AS u
    WHERE u.login IN ('anna.nowak', 'piotr.kowalski', 'katarzyna.wisniewska', 'tomasz.wojcik', 'magdalena.kaminska', 'michal.lewandowski', 'agnieszka.zielinska', 'pawel.szymanski', 'joanna.wozniak', 'krzysztof.dabrowski')
    ORDER BY u.login;
    DECLARE @subs TABLE (n int IDENTITY (0, 1) PRIMARY KEY, sub varchar(60) NOT NULL, cat varchar(40) NOT NULL,
                         name nvarchar(200) NOT NULL);
    INSERT @subs (sub, cat, name)
    SELECT s.subcategory_key, s.category_key, s.name FROM crm.desk_subcategories AS s
    JOIN crm.desk_categories AS c ON c.category_key = s.category_key
    WHERE s.is_active = 1
    ORDER BY c.sort_order, s.sort_order;
    DECLARE @people TABLE (n int IDENTITY (0, 1) PRIMARY KEY, id int NOT NULL);
    INSERT @people (id) SELECT id FROM crm.people ORDER BY id;

    DECLARE @agent_count int = (SELECT COUNT(*) FROM @agents), @sub_count int = (SELECT COUNT(*) FROM @subs),
            @people_count int = (SELECT COUNT(*) FROM @people);
    DECLARE @sink TABLE (id bigint, number char(12), title nvarchar(200), description nvarchar(4000),
        category_key varchar(40), subcategory_key varchar(60), priority varchar(8), original_priority varchar(8),
        reported_at datetime2(3), deadline datetime2(3), status varchar(12), assignee_user_id int,
        assignee_name nvarchar(200), handler_person_id int, handler_name nvarchar(201), requester_incognito bit,
        requester_person_id int, requester_name nvarchar(201), channel varchar(12), registered_by_name nvarchar(200),
        recorded_at datetime2(3), resolved_at datetime2(3), resolved_late bit, comment_count int,
        attachment_count int, version int, last_change_at datetime2(3));

    DECLARE @i int = 1;
    WHILE @i <= @tickets
    BEGIN
        -- One hash per ticket, cut into 4-byte numbers (as seed.run does).
        DECLARE @h varbinary(32) = HASHBYTES('SHA2_256', CONCAT(@random_seed, ':desk:', @i));
        DECLARE @r1 bigint = CAST(SUBSTRING(@h, 1, 4) AS int) & 0x7FFFFFFF,
                @r2 bigint = CAST(SUBSTRING(@h, 5, 4) AS int) & 0x7FFFFFFF,
                @r3 bigint = CAST(SUBSTRING(@h, 9, 4) AS int) & 0x7FFFFFFF,
                @r4 bigint = CAST(SUBSTRING(@h, 13, 4) AS int) & 0x7FFFFFFF,
                @r5 bigint = CAST(SUBSTRING(@h, 17, 4) AS int) & 0x7FFFFFFF;
        DECLARE @sub varchar(60), @cat varchar(40), @sub_name nvarchar(200);
        SELECT @sub = sub, @cat = cat, @sub_name = name FROM @subs WHERE n = @r1 % @sub_count;
        DECLARE @priority varchar(8) = CASE @r2 % 10 WHEN 0 THEN 'CRITICAL' WHEN 1 THEN 'HIGH' WHEN 2 THEN 'HIGH'
                                                     WHEN 3 THEN 'LOW' WHEN 4 THEN 'LOW' ELSE 'MEDIUM' END;
        DECLARE @reported datetime2(3) = DATEADD(MINUTE, -CAST(@r3 % (28 * 24 * 60) AS int), SYSUTCDATETIME());
        DECLARE @agent int = (SELECT id FROM @agents WHERE n = @r4 % @agent_count);
        DECLARE @person int = IIF(@r5 % 10 = 0, NULL, (SELECT id FROM @people WHERE n = @r5 % @people_count));
        DECLARE @incognito bit = IIF(@person IS NULL, 1, 0);
        DECLARE @title nvarchar(200) = CONCAT(@sub_name, N' (', @i, N')');
        DECLARE @description nvarchar(4000) =
            CONCAT(N'Zgłoszenie przykładowe nr ', @i, N': ', @sub_name, N'. Szczegóły w załącznikach i komentarzach.');
        DECLARE @ticket_id bigint;

        -- Half registered by an agent (dated back), half from the public form (dated now by the procedure).
        IF @r2 % 2 = 0
            EXEC crm.desk_ticket_create @agent, @title, @description, @cat, @sub, @priority, @reported, @person,
                 @incognito, @ticket_id OUTPUT;
        ELSE
            EXEC crm.desk_ticket_create NULL, @title, @description, @cat, @sub, @priority, NULL, @person,
                 @incognito, @ticket_id OUTPUT;

        IF @r4 % 5 < 2
        BEGIN
            INSERT @sink EXEC app.desk_ticket_take @agent, @ticket_id;
            IF @r5 % 2 = 0
                INSERT @sink EXEC app.desk_ticket_resolve @agent, @ticket_id;
        END;
        SET @i += 1;
    END;
END;
