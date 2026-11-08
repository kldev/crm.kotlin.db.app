/*
  Seed (ADR-0014): departments for the ten desk agents and a team plan for the calendar and the timeline - about eight
  tasks per agent from three weeks back to five weeks ahead, one to seven days long, the past ones mostly done.
  Only into an empty task list; deterministic for one @random_seed. Called by seed.desk_run.
*/
CREATE OR ALTER PROCEDURE seed.tasks_run
    @random_seed int = 2026
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    UPDATE u SET department = ISNULL(u.department, d.department)
    FROM crm.users AS u
    JOIN (VALUES ('anna.nowak', N'IT'), ('piotr.kowalski', N'IT'), ('katarzyna.wisniewska', N'Prawny'),
                 ('tomasz.wojcik', N'IT'), ('magdalena.kaminska', N'Marketing'), ('michal.lewandowski', N'Utrzymanie ruchu'),
                 ('agnieszka.zielinska', N'Kadry'), ('pawel.szymanski', N'Finanse'), ('joanna.wozniak', N'Kadry'),
                 ('krzysztof.dabrowski', N'Sprzedaż')) AS d (login, department) ON d.login = u.login;

    IF EXISTS (SELECT 1 FROM crm.tasks)
        RETURN;

    DECLARE @agents TABLE (n int IDENTITY (0, 1) PRIMARY KEY, id int, department nvarchar(50));
    INSERT @agents (id, department) SELECT id, department FROM crm.users WHERE department IS NOT NULL ORDER BY login;
    DECLARE @titles TABLE (n int IDENTITY (0, 1) PRIMARY KEY, department nvarchar(50), title nvarchar(200));
    INSERT @titles (department, title)
    VALUES (N'IT', N'Aktualizacja laptopów działu sprzedaży'), (N'IT', N'Migracja skrzynek pocztowych'),
           (N'IT', N'Przegląd uprawnień do systemów'), (N'IT', N'Wdrożenie VPN dla nowych pracowników'),
           (N'IT', N'Kopia zapasowa serwera plików - test odtworzenia'), (N'Prawny', N'Przegląd umów z podwykonawcami'),
           (N'Prawny', N'Aktualizacja regulaminu RODO'), (N'Prawny', N'Opinia do umowy najmu biura'),
           (N'Marketing', N'Kampania na targi branżowe'), (N'Marketing', N'Nowe materiały na stronę WWW'),
           (N'Marketing', N'Sesja zdjęciowa na budowie'), (N'Utrzymanie ruchu', N'Przegląd floty samochodów'),
           (N'Utrzymanie ruchu', N'Serwis klimatyzacji w biurze'), (N'Kadry', N'Onboarding nowych pracowników'),
           (N'Kadry', N'Rozliczenie delegacji za miesiąc'), (N'Kadry', N'Aktualizacja badań okresowych'),
           (N'Kadry', N'Zgłoszenia A1 dla wyjazdu do Belgii'), (N'Finanse', N'Zamknięcie miesiąca'),
           (N'Finanse', N'Weryfikacja faktur kosztowych'), (N'Finanse', N'Budżet na kolejny kwartał'),
           (N'Sprzedaż', N'Spotkania z kluczowymi klientami'), (N'Sprzedaż', N'Przygotowanie ofert na przetarg'),
           (N'Sprzedaż', N'Aktualizacja cennika usług');

    DECLARE @today date = CAST((SYSUTCDATETIME() AT TIME ZONE 'UTC') AT TIME ZONE 'Central European Standard Time' AS date);
    DECLARE @agent_count int = (SELECT COUNT(*) FROM @agents), @a int = 0;
    WHILE @a < @agent_count
    BEGIN
        DECLARE @agent int, @department nvarchar(50);
        SELECT @agent = id, @department = department FROM @agents WHERE n = @a;
        DECLARE @own TABLE (n int IDENTITY (0, 1) PRIMARY KEY, title nvarchar(200));
        DELETE @own;
        INSERT @own (title) SELECT title FROM @titles WHERE department = @department ORDER BY n;
        IF NOT EXISTS (SELECT 1 FROM @own) INSERT @own (title) SELECT title FROM @titles WHERE department = N'IT';
        DECLARE @first int = (SELECT MIN(n) FROM @own), @own_count int = (SELECT COUNT(*) FROM @own), @k int = 0;
        WHILE @k < 8
        BEGIN
            DECLARE @h varbinary(32) = HASHBYTES('SHA2_256', CONCAT(@random_seed, ':task:', @a, ':', @k));
            DECLARE @r1 int = CAST(SUBSTRING(@h, 1, 4) AS int) & 0x7FFFFFFF, @r2 int = CAST(SUBSTRING(@h, 5, 4) AS int) & 0x7FFFFFFF,
                    @r3 int = CAST(SUBSTRING(@h, 9, 4) AS int) & 0x7FFFFFFF;
            DECLARE @start date = DATEADD(DAY, -21 + (@k * 7) + @r1 % 5, @today);
            DECLARE @end date = DATEADD(DAY, @r2 % 7, @start);
            DECLARE @title nvarchar(200) = (SELECT title FROM @own WHERE n = @first + (@r3 + @k) % @own_count);
            DECLARE @done bit = IIF(@end < @today AND @r3 % 5 <> 0, 1, 0);
            INSERT crm.tasks (title, description, assignee_user_id, start_date, end_date, is_done, done_at, created_by, updated_by)
            VALUES (@title, N'Zadanie z planu zespołu.', @agent, @start, @end, @done,
                    IIF(@done = 1, CAST(@end AS datetime2(3)), NULL), @agent, @agent);
            SET @k += 1;
        END;
        SET @a += 1;
    END;
END;
