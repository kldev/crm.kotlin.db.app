/*
  Seed (ADR-0017): a salesperson's day on the seeded pipeline - one to four past activities per deal, a next step on
  most open deals (some overdue, some today, the rest this week) and three tasks of their deals per salesperson
  around today. Only once (when no activity exists); deterministic for one @random_seed. Called by seed.desk_run.
*/
CREATE OR ALTER PROCEDURE seed.sales_run
    @random_seed int = 2026
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    IF EXISTS (SELECT 1 FROM crm.deal_activities) OR NOT EXISTS (SELECT 1 FROM crm.deals)
        RETURN;

    DECLARE @notes TABLE (activity_type varchar(12), n int, note nvarchar(200), PRIMARY KEY (activity_type, n));
    INSERT @notes (activity_type, n, note)
    VALUES ('CALL', 0, N'Rozmowa z decydentem - potwierdzony budżet.'), ('CALL', 1, N'Nie odebrał, oddzwoni jutro.'),
           ('CALL', 2, N'Ustalenie zakresu i terminu startu.'), ('EMAIL', 0, N'Wysłana prezentacja firmy i referencje.'),
           ('EMAIL', 1, N'Pytania klienta o warunki płatności.'), ('EMAIL', 2, N'Przypomnienie o ofercie.'),
           ('MEETING', 0, N'Spotkanie u klienta - wizja lokalna.'), ('MEETING', 1, N'Spotkanie online z zarządem.'),
           ('MEETING', 2, N'Warsztat wymagań z zespołem klienta.'), ('PRESENTATION', 0, N'Demo rozwiązania dla działu IT.'),
           ('PRESENTATION', 1, N'Prezentacja oferty na zarządzie.'), ('PRESENTATION', 2, N'Pokaz referencyjnych realizacji.'),
           ('NOTE', 0, N'Konkurencja zaproponowała niższą cenę.'), ('NOTE', 1, N'Klient porównuje trzy oferty.'),
           ('NOTE', 2, N'Decyzja po komitecie inwestycyjnym.');
    DECLARE @types TABLE (n int PRIMARY KEY, activity_type varchar(12));
    INSERT @types VALUES (0, 'CALL'), (1, 'EMAIL'), (2, 'MEETING'), (3, 'PRESENTATION'), (4, 'NOTE'), (5, 'CALL'), (6, 'EMAIL');
    DECLARE @steps TABLE (n int PRIMARY KEY, step nvarchar(200));
    INSERT @steps VALUES (0, N'Zadzwonić po decyzję zarządu'), (1, N'Wysłać poprawioną ofertę'), (2, N'Umówić spotkanie u klienta'),
                         (3, N'Potwierdzić termin startu'), (4, N'Przesłać referencje'), (5, N'Negocjacja rabatu z dyrektorem');

    -- One to four activities per deal over the last 30 days, at office hours.
    INSERT crm.deal_activities (deal_id, activity_type, note, occurred_at, created_by)
    SELECT d.id, ty.activity_type, nt.note,
           DATEADD(MINUTE, (h.h3 % 9) * 60 + 8 * 60 + h.h4 % 60,
                   CAST(CAST(DATEADD(DAY, -(1 + h.h2 % 30), SYSUTCDATETIME()) AS date) AS datetime2(3))),
           d.owner_user_id
    FROM crm.deals AS d
    CROSS APPLY GENERATE_SERIES(1, 4) AS k
    CROSS APPLY (SELECT HASHBYTES('SHA2_256', CONCAT(@random_seed, ':act:', d.id, ':', k.value)) AS b) AS hb
    CROSS APPLY (SELECT CAST(SUBSTRING(hb.b, 1, 4) AS int) & 0x7FFFFFFF AS h1, CAST(SUBSTRING(hb.b, 5, 4) AS int) & 0x7FFFFFFF AS h2,
                        CAST(SUBSTRING(hb.b, 9, 4) AS int) & 0x7FFFFFFF AS h3, CAST(SUBSTRING(hb.b, 13, 4) AS int) & 0x7FFFFFFF AS h4) AS h
    JOIN @types AS ty ON ty.n = h.h1 % 7
    JOIN @notes AS nt ON nt.activity_type = ty.activity_type AND nt.n = h.h3 % 3
    WHERE k.value <= 1 + (CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@random_seed, ':acts:', d.id)), 1, 4) AS int) & 0x7FFFFFFF) % 4;

    UPDATE d SET last_activity_at = x.occurred_at, last_activity_type = x.activity_type
    FROM crm.deals AS d
    CROSS APPLY (SELECT TOP (1) occurred_at, activity_type FROM crm.deal_activities AS a
                 WHERE a.deal_id = d.id ORDER BY occurred_at DESC, id DESC) AS x;

    -- A next step on four of five open deals: some overdue (up to 3 days), some today, the rest within a week.
    UPDATE d
    SET next_step = st.step,
        next_step_at = DATEADD(MINUTE, (h.h2 % 8) * 60 + 8 * 60, CAST(CAST(DATEADD(DAY, -3 + h.h1 % 11, SYSUTCDATETIME()) AS date) AS datetime2(3)))
    FROM crm.deals AS d
    JOIN crm.deal_stages AS s ON s.stage = d.stage AND s.is_closed = 0
    CROSS APPLY (SELECT HASHBYTES('SHA2_256', CONCAT(@random_seed, ':next:', d.id)) AS b) AS hb
    CROSS APPLY (SELECT CAST(SUBSTRING(hb.b, 1, 4) AS int) & 0x7FFFFFFF AS h1, CAST(SUBSTRING(hb.b, 5, 4) AS int) & 0x7FFFFFFF AS h2,
                        CAST(SUBSTRING(hb.b, 9, 4) AS int) & 0x7FFFFFFF AS h3) AS h
    JOIN @steps AS st ON st.n = h.h3 % 6
    WHERE h.h2 % 5 <> 0;

    -- Three tasks of their deals per salesperson, from two days back to three ahead, a day or two long.
    DECLARE @today date = CAST((SYSUTCDATETIME() AT TIME ZONE 'UTC') AT TIME ZONE 'Central European Standard Time' AS date);
    INSERT crm.tasks (title, description, assignee_user_id, start_date, end_date, client_id, deal_id, created_by, updated_by)
    SELECT CONCAT(st.step, N' - ', d.title), N'Zadanie do szansy sprzedaży.', d.owner_user_id,
           DATEADD(DAY, -2 + d.rn, @today), DATEADD(DAY, -2 + d.rn + d.id % 2, @today), d.client_id, d.id, d.owner_user_id,
           d.owner_user_id
    FROM (SELECT x.id, x.title, x.client_id, x.owner_user_id,
                 ROW_NUMBER() OVER (PARTITION BY x.owner_user_id ORDER BY x.expected_close, x.id) AS rn
          FROM crm.deals AS x JOIN crm.deal_stages AS s ON s.stage = x.stage AND s.is_closed = 0) AS d
    JOIN @steps AS st ON st.n = d.id % 6
    WHERE d.rn <= 3;
END;
