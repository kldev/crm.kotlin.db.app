/*
  Seed (ADR-0015): a pipeline of up to @deals deals (10 000 by default) for up to 500 salespeople with clients, one
  deal on each of their first twenty clients, across the stages - open ones closing from ten days back to three months ahead, closed ones in the last four
  weeks. Set-based; only into an empty pipeline; deterministic for one @random_seed. Called by seed.desk_run.
*/
CREATE OR ALTER PROCEDURE seed.deals_run
    @random_seed int = 2026,
    @deals       int = 10000
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    IF EXISTS (SELECT 1 FROM crm.deals)
        RETURN;

    DECLARE @titles TABLE (n int PRIMARY KEY, title nvarchar(200));
    INSERT @titles (n, title)
    VALUES (0, N'Wdrożenie CRM'), (1, N'Dostawa laptopów dla biura'), (2, N'Outsourcing 5 spawaczy MIG/MAG'),
           (3, N'Modernizacja hali magazynowej'), (4, N'Audyt bezpieczeństwa IT'), (5, N'Licencje Microsoft 365 na rok'),
           (6, N'Utrzymanie systemu - umowa roczna'), (7, N'Rekrutacja zespołu programistów'), (8, N'Remont biura - II piętro'),
           (9, N'Migracja serwerów do chmury'), (10, N'Monterzy instalacji na budowę'), (11, N'Fundamenty pod nową halę');
    DECLARE @lost TABLE (n int PRIMARY KEY, reason nvarchar(400));
    INSERT @lost (n, reason)
    VALUES (0, N'Wybrali tańszą ofertę konkurencji.'), (1, N'Projekt przesunięty na przyszły rok.'),
           (2, N'Brak budżetu po stronie klienta.');

    -- Salespeople with clients and twenty clients of each: the pool the deals are drawn from.
    DECLARE @pool TABLE (n int IDENTITY (0, 1) PRIMARY KEY, client_id bigint, owner int);
    INSERT @pool (client_id, owner)
    SELECT c.id, s.id
    FROM (SELECT TOP (500) u.id FROM crm.users AS u
          WHERE u.role = 'SALES' AND u.is_active = 1
            AND EXISTS (SELECT 1 FROM crm.clients AS x WHERE x.assigned_user_id = u.id)
          ORDER BY u.login) AS s
    CROSS APPLY (SELECT TOP (20) id FROM crm.clients WHERE assigned_user_id = s.id ORDER BY id) AS c
    ORDER BY s.id, c.id;
    DECLARE @pool_count int = (SELECT COUNT(*) FROM @pool);
    IF @pool_count = 0
        RETURN;

    DECLARE @now datetime2(3) = SYSUTCDATETIME();
    DECLARE @today date = CAST((@now AT TIME ZONE 'UTC') AT TIME ZONE 'Central European Standard Time' AS date);
    INSERT crm.deals (title, client_id, owner_user_id, stage, value, currency, expected_close, lost_reason,
                      stage_changed_at, closed_at, created_by, updated_by)
    SELECT ti.title, p.client_id, p.owner, x.stage, (5 + h.h2 % 496) * 1000, IIF(h.h4 % 20 = 0, 'EUR', 'PLN'),
           IIF(x.closed = 1, CAST(x.closed_at AS date), DATEADD(DAY, -10 + h.h3 % 100, @today)),
           IIF(x.stage = 'LOST', l.reason, NULL),
           ISNULL(x.closed_at, DATEADD(DAY, -(h.h3 % 20), @now)), x.closed_at, p.owner, p.owner
    -- One deal per client of the pool: twenty per salesperson at most, a realistic book of open business.
    FROM GENERATE_SERIES(0, IIF(@deals < @pool_count, @deals, @pool_count) - 1) AS s
    JOIN @pool AS p ON p.n = s.value % @pool_count
    CROSS APPLY (SELECT HASHBYTES('SHA2_256', CONCAT(@random_seed, ':deal:', s.value)) AS b) AS hb
    CROSS APPLY (SELECT CAST(SUBSTRING(hb.b, 1, 4) AS int) & 0x7FFFFFFF AS h1, CAST(SUBSTRING(hb.b, 5, 4) AS int) & 0x7FFFFFFF AS h2,
                        CAST(SUBSTRING(hb.b, 9, 4) AS int) & 0x7FFFFFFF AS h3, CAST(SUBSTRING(hb.b, 13, 4) AS int) & 0x7FFFFFFF AS h4) AS h
    -- More deals early in the funnel than late: 30% lead, 20% qualified, 20% proposal, 15% negotiation, 10% won, 5% lost.
    CROSS APPLY (SELECT CASE WHEN h.h1 % 100 < 30 THEN 'LEAD' WHEN h.h1 % 100 < 50 THEN 'QUALIFIED'
                             WHEN h.h1 % 100 < 70 THEN 'PROPOSAL' WHEN h.h1 % 100 < 85 THEN 'NEGOTIATION'
                             WHEN h.h1 % 100 < 95 THEN 'WON' ELSE 'LOST' END AS stage) AS st
    CROSS APPLY (SELECT st.stage, CAST(IIF(st.stage IN ('WON', 'LOST'), 1, 0) AS bit) AS closed,
                        IIF(st.stage IN ('WON', 'LOST'), DATEADD(DAY, -(h.h3 % 28), @now), NULL) AS closed_at) AS x
    JOIN @titles AS ti ON ti.n = h.h2 % 12
    JOIN @lost AS l ON l.n = h.h3 % 3;
END;
