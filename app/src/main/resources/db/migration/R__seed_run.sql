/*
  The one data seed of this project (ADR-0004): users and clients for performance tests.
  Run by CRM_MODE=seed with the migrator login; the application login cannot execute schema `seed`.

  Set-based: users in one INSERT ... SELECT, clients in batches of @batch_size from GENERATE_SERIES, no row loops.
  Deterministic: every value is derived from SHA2_256(@random_seed, row number) - one hash per row, cut into 4-byte
  numbers (CHECKSUM is too weak: on consecutive numbers it gives visibly uneven distributions), so the same parameters give the same data.
  Refuses to run twice (51060): to seed again, start from an empty database (start.sh --clean).

  Users:    perf.admin.0001..,  perf.manager.0001..,  perf.sales.0001..  - all with the same @password_hash.
  Teams:    CEILING(@sales / @team_size) teams, led by managers (round robin); SALES user k is in team k % teams.
  Clients:  assigned to SALES users (spread by hash); names are "<adjective> <noun> <legal form>" from short lists,
            so a name prefix (e.g. "Zielony") matches about 1/40 of all clients.
  Projects: for a client chosen by hash, owned by the client's sales user and delivered by that user's team;
            stage, dates and budget by hash; one stage history row each.
  Comments: on projects chosen by hash, written by the project owner.
*/
CREATE OR ALTER PROCEDURE seed.run
    @clients       int,
    @admins        int,
    @managers      int,
    @sales         int,
    @password_hash varchar(100),
    @team_size     int = 5,
    @projects      int = 0,
    @comments      int = 0,
    @random_seed   int = 42,
    @batch_size    int = 500000
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    IF @clients IS NULL OR @clients < 0
        THROW 51050, N'Seed: clients must be 0 or more.', 1;
    IF @admins IS NULL OR @admins < 0 OR @managers IS NULL OR @managers < 0 OR @sales IS NULL OR @sales < 0
        THROW 51050, N'Seed: user counts must be 0 or more.', 1;
    IF @admins > 9999 OR @managers > 9999 OR @sales > 9999
        THROW 51050, N'Seed: at most 9999 users per role (login perf.<role>.NNNN).', 1;
    IF @clients > 0 AND @sales = 0
        THROW 51050, N'Seed: clients need at least one sales user to be assigned to.', 1;
    IF @projects IS NULL OR @projects < 0 OR @comments IS NULL OR @comments < 0
        THROW 51050, N'Seed: projects and comments must be 0 or more.', 1;
    IF @projects > 0 AND (@clients = 0 OR @managers = 0)
        THROW 51050, N'Seed: projects need clients and at least one manager (team lead).', 1;
    IF @comments > 0 AND @projects = 0
        THROW 51050, N'Seed: comments need projects.', 1;
    IF @team_size IS NULL OR @team_size < 1
        THROW 51050, N'Seed: team size must be 1 or more.', 1;
    IF @batch_size IS NULL OR @batch_size NOT BETWEEN 1000 AND 2000000
        THROW 51050, N'Seed: batch size must be between 1000 and 2000000.', 1;
    IF @password_hash IS NULL OR LEN(@password_hash) = 0
        THROW 51020, N'Password is required.', 1;
    IF EXISTS (SELECT 1 FROM crm.users WHERE login LIKE 'perf.%') OR EXISTS (SELECT 1 FROM crm.clients)
        THROW 51060, N'Seed: the database already has seed data or clients. Start from an empty database (start.sh --clean).', 1;

    DECLARE @started datetime2(3) = SYSUTCDATETIME();

    -- Users: one statement, identity assigned in ORDER BY order, so SALES ids are contiguous.
    INSERT crm.users (login, display_name, role, password_hash)
    SELECT u.login, u.display_name, u.role, @password_hash
    FROM (
        SELECT CONCAT('perf.admin.', FORMAT(value, '0000')) AS login,
               CONCAT(N'Perf Admin ', value) AS display_name, 'ADMIN' AS role, 1 AS role_order, value
        FROM GENERATE_SERIES(1, @admins)
        UNION ALL
        SELECT CONCAT('perf.manager.', FORMAT(value, '0000')), CONCAT(N'Perf Manager ', value), 'MANAGER', 2, value
        FROM GENERATE_SERIES(1, @managers)
        UNION ALL
        SELECT CONCAT('perf.sales.', FORMAT(value, '0000')), CONCAT(N'Perf Sales ', value), 'SALES', 3, value
        FROM GENERATE_SERIES(1, @sales)
    ) AS u
    ORDER BY u.role_order, u.value;

    DECLARE @first_sales_id int = (SELECT MIN(id) FROM crm.users WHERE login LIKE 'perf.sales.%');
    DECLARE @first_manager_id int = (SELECT MIN(id) FROM crm.users WHERE login LIKE 'perf.manager.%');
    DECLARE @team_count int = IIF(@managers = 0, 0, (@sales + @team_size - 1) / @team_size);
    DECLARE @first_team_id int;

    IF @team_count > 0
    BEGIN
        INSERT crm.teams (name, lead_user_id)
        SELECT CONCAT(N'Perf Team ', FORMAT(value, '0000')), @first_manager_id + (value - 1) % @managers
        FROM GENERATE_SERIES(1, @team_count)
        ORDER BY value;

        SET @first_team_id = (SELECT MIN(id) FROM crm.teams WHERE name LIKE N'Perf Team %');

        INSERT crm.team_members (team_id, user_id)
        SELECT @first_team_id + (value - 1) % @team_count, @first_sales_id + value - 1
        FROM GENERATE_SERIES(1, @sales);
    END;

    -- Word lists for client names and cities (synthetic data only).
    DECLARE @adjectives TABLE (i int PRIMARY KEY, word nvarchar(40));
    INSERT @adjectives (i, word)
    SELECT ordinal - 1, value
    FROM STRING_SPLIT(N'Zielony,Szybki,Nowy,Stary,Wielki,Mały,Jasny,Ciemny,Złoty,Srebrny,Polski,Północny,Południowy,'
                    + N'Wschodni,Zachodni,Górski,Morski,Leśny,Miejski,Wiejski,Cichy,Mocny,Lekki,Twardy,Ciepły,Zimny,'
                    + N'Prosty,Pewny,Wspólny,Główny,Pierwszy,Drugi,Trzeci,Dobry,Mądry,Wesoły,Spokojny,Bystry,Śmiały,'
                    + N'Zwinny', N',', 1);

    DECLARE @nouns TABLE (i int PRIMARY KEY, word nvarchar(40));
    INSERT @nouns (i, word)
    SELECT ordinal - 1, value
    FROM STRING_SPLIT(N'Most,Młyn,Dom,Port,Las,Kamień,Ogród,Rynek,Bór,Gród,Dwór,Zakład,Warsztat,Handel,Transport,'
                    + N'Serwis,Projekt,System,Rozwój,Kapitał,Budynek,Sklep,Hurt,Detal,Tartak,Browar,Piekarz,Kowal,'
                    + N'Ślusarz,Stolarz,Ogrodnik,Rybak,Rolnik,Kupiec,Inżynier,Architekt,Doradca,Partner,Lider,Mistrz',
                      N',', 1);

    DECLARE @forms TABLE (i int PRIMARY KEY, word nvarchar(20));
    INSERT @forms (i, word)
    SELECT ordinal - 1, value FROM STRING_SPLIT(N'Sp. z o.o.,S.A.,Sp.j.,Sp.k.,s.c.', N',', 1);

    DECLARE @cities TABLE (i int PRIMARY KEY, name nvarchar(100));
    INSERT @cities (i, name)
    SELECT ordinal - 1, value
    FROM STRING_SPLIT(N'Warszawa,Kraków,Łódź,Wrocław,Poznań,Gdańsk,Szczecin,Bydgoszcz,Lublin,Białystok,Katowice,'
                    + N'Gdynia,Częstochowa,Radom,Rzeszów,Toruń,Sosnowiec,Kielce,Gliwice,Olsztyn', N',', 1);

    DECLARE @adjective_count int = (SELECT COUNT(*) FROM @adjectives);
    DECLARE @noun_count int = (SELECT COUNT(*) FROM @nouns);
    DECLARE @form_count int = (SELECT COUNT(*) FROM @forms);
    DECLARE @city_count int = (SELECT COUNT(*) FROM @cities);

    DECLARE @done int = 0, @batch_end int;
    DECLARE @first_client_id bigint;

    WHILE @done < @clients
    BEGIN
        SET @batch_end = IIF(@clients - @done < @batch_size, @clients, @done + @batch_size);

        INSERT crm.clients WITH (TABLOCK)
            (name, nip, email, phone, city, status, assigned_user_id, note, created_at, updated_at)
        SELECT CONCAT(a.word, N' ', n.word, N' ', f.word),
               CAST(1000000000 + s.value AS char(10)),
               CONCAT('klient', s.value, '@example.test'),
               CONCAT('+48 5', RIGHT(CONCAT('00000000', h.h4 % 100000000), 8)),
               c.name,
               CASE WHEN h.h5 % 10 < 7 THEN 'ACTIVE' WHEN h.h5 % 10 < 9 THEN 'LEAD' ELSE 'INACTIVE' END,
               @first_sales_id + h.h6 % @sales,
               IIF(h.h7 % 20 = 0, N'Seed note: follow up in the next quarter.', NULL),
               DATEADD(MINUTE, -(h.h8 % 1051200), @started),
               @started
        FROM GENERATE_SERIES(@done + 1, @batch_end) AS s
        CROSS APPLY (SELECT HASHBYTES('SHA2_256', CONCAT(@random_seed, ':c:', s.value)) AS b) AS hb
        CROSS APPLY (SELECT CAST(SUBSTRING(hb.b, 1, 4) AS int) & 2147483647 AS h1,
                            CAST(SUBSTRING(hb.b, 5, 4) AS int) & 2147483647 AS h2,
                            CAST(SUBSTRING(hb.b, 9, 4) AS int) & 2147483647 AS h3,
                            CAST(SUBSTRING(hb.b, 13, 4) AS int) & 2147483647 AS h4,
                            CAST(SUBSTRING(hb.b, 17, 4) AS int) & 2147483647 AS h5,
                            CAST(SUBSTRING(hb.b, 21, 4) AS int) & 2147483647 AS h6,
                            CAST(SUBSTRING(hb.b, 25, 4) AS int) & 2147483647 AS h7,
                            CAST(SUBSTRING(hb.b, 29, 4) AS int) & 2147483647 AS h8) AS h
        JOIN @adjectives AS a ON a.i = h.h1 % @adjective_count
        JOIN @nouns AS n ON n.i = h.h2 % @noun_count
        JOIN @forms AS f ON f.i = h.h3 % @form_count
        -- Skewed cities: the first ones are more frequent (h % (n*n) -> sqrt-like distribution).
        JOIN @cities AS c ON c.i = @city_count - 1 - CAST(SQRT(h.h3 % (@city_count * @city_count)) AS int)
        ORDER BY s.value;

        SET @done = @batch_end;
        RAISERROR (N'seed: %d / %d clients', 0, 1, @done, @clients) WITH NOWAIT;
    END;

    -- The table was empty (checked above) and batches are inserted in order: client n has id @first_client_id + n - 1.
    SET @first_client_id = (SELECT MIN(id) FROM crm.clients);

    -- Projects: client n -> its sales user k (the same hash as the client assignment above) -> k's team.
    DECLARE @project_kinds TABLE (i int PRIMARY KEY, word nvarchar(60));
    INSERT @project_kinds (i, word)
    SELECT ordinal - 1, value
    FROM STRING_SPLIT(N'Wdrożenie CRM,Migracja danych,Audyt procesów,Szkolenie zespołu,Integracja ERP,Raportowanie,'
                    + N'Kampania marketingowa,Serwis posprzedażowy,Rozbudowa sklepu,Optymalizacja kosztów', N',', 1);
    DECLARE @kind_count int = (SELECT COUNT(*) FROM @project_kinds);
    DECLARE @first_entity_id int = (SELECT MIN(id) FROM crm.legal_entities),
            @entity_count int = (SELECT COUNT(*) FROM crm.legal_entities);
    DECLARE @first_project_id bigint = NULL;
    DECLARE @project_from bigint;

    SET @done = 0;
    WHILE @done < @projects
    BEGIN
        SET @batch_end = IIF(@projects - @done < @batch_size, @projects, @done + @batch_size);
        SET @project_from = ISNULL((SELECT MAX(id) FROM crm.projects), 0);

        INSERT crm.projects WITH (TABLOCK)
            (client_id, team_id, owner_user_id, name, stage, start_date, due_date, budget, legal_entity_id,
             stage_changed_at, created_at, updated_at)
        SELECT @first_client_id + x.client_n - 1,
               @first_team_id + x.sales_k % @team_count,
               @first_sales_id + x.sales_k,
               CONCAT(k.word, N' #', s.value),
               CASE WHEN h.h2 % 20 < 2 THEN 'NEW'
                    WHEN h.h2 % 20 < 4 THEN 'ACCEPTED'
                    WHEN h.h2 % 20 < 11 THEN 'ACTIVE'
                    WHEN h.h2 % 20 < 12 THEN 'ON_HOLD'
                    WHEN h.h2 % 20 < 18 THEN 'CLOSED'
                    ELSE 'DECLINED' END,
               x.start_date,
               DATEADD(DAY, 14 + h.h4 % 350, x.start_date),
               CAST(1000 + h.h5 % 499000 AS decimal(19, 2)) + CAST(h.h6 % 100 AS decimal(19, 2)) / 100,
               -- The group's companies (ADR-0016) in turn; each traded by 2024, when the seeded projects start.
               @first_entity_id + h.h4 % @entity_count,
               @started, @started, @started
        FROM GENERATE_SERIES(@done + 1, @batch_end) AS s
        CROSS APPLY (SELECT HASHBYTES('SHA2_256', CONCAT(@random_seed, ':p:', s.value)) AS b) AS hb
        CROSS APPLY (SELECT CAST(SUBSTRING(hb.b, 1, 4) AS int) & 2147483647 AS h1,
                            CAST(SUBSTRING(hb.b, 5, 4) AS int) & 2147483647 AS h2,
                            CAST(SUBSTRING(hb.b, 9, 4) AS int) & 2147483647 AS h3,
                            CAST(SUBSTRING(hb.b, 13, 4) AS int) & 2147483647 AS h4,
                            CAST(SUBSTRING(hb.b, 17, 4) AS int) & 2147483647 AS h5,
                            CAST(SUBSTRING(hb.b, 21, 4) AS int) & 2147483647 AS h6) AS h
        CROSS APPLY (SELECT 1 + h.h1 % @clients AS client_n,
                            DATEADD(DAY, h.h3 % 1000, CAST('2024-01-01' AS date)) AS start_date) AS x0
        CROSS APPLY (SELECT x0.client_n, x0.start_date,
                            (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@random_seed, ':c:', x0.client_n)), 21, 4) AS int) & 2147483647)
                                % @sales AS sales_k) AS x
        JOIN @project_kinds AS k ON k.i = h.h3 % @kind_count
        ORDER BY s.value;

        INSERT crm.project_stage_history WITH (TABLOCK) (project_id, from_stage, to_stage, changed_at)
        SELECT id, NULL, stage, @started
        FROM crm.projects
        WHERE id > @project_from
        ORDER BY id;

        IF @first_project_id IS NULL
            SET @first_project_id = (SELECT MIN(id) FROM crm.projects WHERE id > @project_from);

        SET @done = @batch_end;
        RAISERROR (N'seed: %d / %d projects', 0, 1, @done, @projects) WITH NOWAIT;
    END;

    -- Comments: on a project chosen by hash, by its owner, newest last.
    DECLARE @phrases TABLE (i int PRIMARY KEY, body nvarchar(200));
    INSERT @phrases (i, body)
    SELECT ordinal - 1, value
    FROM STRING_SPLIT(N'Spotkanie z klientem odbyte.|Czekamy na akceptację oferty.|Klient prosi o zmianę terminu.|'
                    + N'Wysłano harmonogram prac.|Zespół rozpoczął realizację.|Zgłoszono uwagi do zakresu.|'
                    + N'Faktura za etap wystawiona.|Ryzyko opóźnienia po stronie klienta.', N'|', 1);
    DECLARE @phrase_count int = (SELECT COUNT(*) FROM @phrases);

    SET @done = 0;
    WHILE @done < @comments
    BEGIN
        SET @batch_end = IIF(@comments - @done < @batch_size, @comments, @done + @batch_size);

        INSERT crm.project_comments WITH (TABLOCK) (project_id, author_id, body, created_at)
        SELECT p.id, p.owner_user_id, ph.body, DATEADD(SECOND, -(h.h2 % 31536000), @started)
        FROM GENERATE_SERIES(@done + 1, @batch_end) AS s
        CROSS APPLY (SELECT HASHBYTES('SHA2_256', CONCAT(@random_seed, ':m:', s.value)) AS b) AS hb
        CROSS APPLY (SELECT CAST(SUBSTRING(hb.b, 1, 4) AS int) & 2147483647 AS h1,
                            CAST(SUBSTRING(hb.b, 5, 4) AS int) & 2147483647 AS h2) AS h
        JOIN crm.projects AS p ON p.id = @first_project_id + h.h1 % @projects
        JOIN @phrases AS ph ON ph.i = h.h2 % @phrase_count
        ORDER BY p.id;

        SET @done = @batch_end;
        RAISERROR (N'seed: %d / %d comments', 0, 1, @done, @comments) WITH NOWAIT;
    END;

    -- Fresh statistics after a bulk load, so the first queries get good plans.
    UPDATE STATISTICS crm.clients;
    UPDATE STATISTICS crm.users;
    UPDATE STATISTICS crm.projects;
    UPDATE STATISTICS crm.project_comments;
    UPDATE STATISTICS crm.project_stage_history;

    SELECT (SELECT COUNT(*) FROM crm.users WHERE login LIKE 'perf.%') AS users_created,
           @team_count AS teams_created,
           @clients AS clients_created,
           @projects AS projects_created,
           @comments AS comments_created,
           DATEDIFF(SECOND, @started, SYSUTCDATETIME()) AS seconds;
END;
