/*
  Seed (ADR-0014): departments for the ten desk agents and for every fifth active user, and @tasks tasks (10 000 by
  default) for the people with a department, from two months back to three months ahead, one to seven days long, the
  past ones mostly done. Set-based; only into an empty task list; deterministic for one @random_seed. Called by
  seed.desk_run.
*/
CREATE OR ALTER PROCEDURE seed.tasks_run
    @random_seed int = 2026,
    @tasks       int = 10000
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

    -- Every fifth active user without one gets a department, so "my department" has people to show.
    DECLARE @departments TABLE (n int IDENTITY (0, 1) PRIMARY KEY, name nvarchar(50));
    INSERT @departments (name) SELECT name FROM crm.departments ORDER BY sort_order, name;
    DECLARE @department_count int = (SELECT COUNT(*) FROM @departments);
    UPDATE u SET department = d.name
    FROM crm.users AS u
    JOIN @departments AS d ON d.n = u.id % @department_count
    WHERE u.department IS NULL AND u.is_active = 1 AND u.id % 5 = 0;

    DECLARE @people TABLE (n int IDENTITY (0, 1) PRIMARY KEY, id int, department nvarchar(50));
    INSERT @people (id, department) SELECT id, department FROM crm.users WHERE department IS NOT NULL AND is_active = 1 ORDER BY id;
    DECLARE @people_count int = (SELECT COUNT(*) FROM @people);
    IF @people_count = 0
        RETURN;

    DECLARE @titles TABLE (department nvarchar(50), n int, title nvarchar(200), PRIMARY KEY (department, n));
    INSERT @titles (department, n, title)
    VALUES (N'IT', 0, N'Aktualizacja laptopów działu sprzedaży'), (N'IT', 1, N'Migracja skrzynek pocztowych'),
           (N'IT', 2, N'Przegląd uprawnień do systemów'), (N'IT', 3, N'Wdrożenie VPN dla nowych pracowników'),
           (N'Prawny', 0, N'Przegląd umów z podwykonawcami'), (N'Prawny', 1, N'Aktualizacja regulaminu RODO'),
           (N'Prawny', 2, N'Opinia do umowy najmu biura'), (N'Prawny', 3, N'Weryfikacja pełnomocnictw'),
           (N'Marketing', 0, N'Kampania na targi branżowe'), (N'Marketing', 1, N'Nowe materiały na stronę WWW'),
           (N'Marketing', 2, N'Sesja zdjęciowa na budowie'), (N'Marketing', 3, N'Newsletter dla klientów'),
           (N'Utrzymanie ruchu', 0, N'Przegląd floty samochodów'), (N'Utrzymanie ruchu', 1, N'Serwis klimatyzacji w biurze'),
           (N'Utrzymanie ruchu', 2, N'Zamówienie materiałów biurowych'), (N'Utrzymanie ruchu', 3, N'Przegląd gaśnic'),
           (N'Kadry', 0, N'Onboarding nowych pracowników'), (N'Kadry', 1, N'Rozliczenie delegacji za miesiąc'),
           (N'Kadry', 2, N'Aktualizacja badań okresowych'), (N'Kadry', 3, N'Zgłoszenia A1 dla wyjazdu do Belgii'),
           (N'Finanse', 0, N'Zamknięcie miesiąca'), (N'Finanse', 1, N'Weryfikacja faktur kosztowych'),
           (N'Finanse', 2, N'Budżet na kolejny kwartał'), (N'Finanse', 3, N'Windykacja przeterminowanych faktur'),
           (N'Sprzedaż', 0, N'Spotkania z kluczowymi klientami'), (N'Sprzedaż', 1, N'Przygotowanie ofert na przetarg'),
           (N'Sprzedaż', 2, N'Aktualizacja cennika usług'), (N'Sprzedaż', 3, N'Raport sprzedaży za miesiąc');

    DECLARE @today date = CAST((SYSUTCDATETIME() AT TIME ZONE 'UTC') AT TIME ZONE 'Central European Standard Time' AS date);
    INSERT crm.tasks (title, description, assignee_user_id, start_date, end_date, is_done, done_at, created_by, updated_by)
    SELECT ISNULL(ti.title, N'Zadanie zespołu'), N'Zadanie z planu zespołu.', p.id, x.start_date, x.end_date, x.done,
           IIF(x.done = 1, CAST(x.end_date AS datetime2(3)), NULL), p.id, p.id
    FROM GENERATE_SERIES(1, @tasks) AS s
    CROSS APPLY (SELECT HASHBYTES('SHA2_256', CONCAT(@random_seed, ':task:', s.value)) AS b) AS hb
    CROSS APPLY (SELECT CAST(SUBSTRING(hb.b, 1, 4) AS int) & 0x7FFFFFFF AS h1, CAST(SUBSTRING(hb.b, 5, 4) AS int) & 0x7FFFFFFF AS h2,
                        CAST(SUBSTRING(hb.b, 9, 4) AS int) & 0x7FFFFFFF AS h3, CAST(SUBSTRING(hb.b, 13, 4) AS int) & 0x7FFFFFFF AS h4) AS h
    -- The ten desk agents first: they get a fuller plan than the rest.
    JOIN @people AS p ON p.n = IIF(h.h4 % 4 = 0, h.h1 % IIF(@people_count < 10, @people_count, 10), h.h1 % @people_count)
    CROSS APPLY (SELECT DATEADD(DAY, -60 + h.h2 % 150, @today) AS start_date) AS st
    CROSS APPLY (SELECT st.start_date, DATEADD(DAY, h.h3 % 7, st.start_date) AS end_date,
                        CAST(IIF(DATEADD(DAY, h.h3 % 7, st.start_date) < @today AND h.h4 % 5 <> 0, 1, 0) AS bit) AS done) AS x
    LEFT JOIN @titles AS ti ON ti.department = p.department AND ti.n = h.h3 % 4;
END;
