/*
  Seed (ADR-0019): exactly @trips business trips (20 125 by default; fewer only when fifty a person would be exceeded) over the last half year and the next month - salespeople
  visiting their clients and going to trade fairs, marketing to fairs (some abroad), project owners to their projects'
  sites - with transport, meals, nights, expenses and a status that follows the date (future: planned; past: mostly
  approved and paid, some waiting or returned). Settled by crm.trip_compute. Only into an empty table; deterministic.
  Called by seed.desk_run.
*/
CREATE OR ALTER PROCEDURE seed.trips_run
    @random_seed int = 2026,
    @trips       int = 20125
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    IF EXISTS (SELECT 1 FROM crm.trips)
        RETURN;

    -- A few people of each kind: marketing and project delivery get their department.
    UPDATE u SET department = N'Marketing'
    FROM crm.users AS u WHERE u.department IS NULL AND u.is_active = 1 AND u.role = 'SALES' AND u.id % 13 = 1;
    UPDATE u SET department = N'Realizacja projektów'
    FROM crm.users AS u WHERE u.department IS NULL AND u.is_active = 1 AND u.role IN ('SALES', 'MANAGER') AND u.id % 13 = 2;

    DECLARE @visits TABLE (n int IDENTITY (0, 1) PRIMARY KEY, user_id int, client_id bigint, city nvarchar(100));
    INSERT @visits (user_id, client_id, city)
    SELECT d.owner_user_id, d.client_id, ISNULL(c.city, N'Warszawa')
    FROM (SELECT DISTINCT owner_user_id, client_id FROM crm.deals) AS d JOIN crm.clients AS c ON c.id = d.client_id;
    DECLARE @sites TABLE (n int IDENTITY (0, 1) PRIMARY KEY, user_id int, project_id bigint, city nvarchar(100), entity int);
    INSERT @sites (user_id, project_id, city, entity)
    SELECT TOP (2000) p.owner_user_id, p.id, ISNULL(c.city, N'Warszawa'), p.legal_entity_id
    FROM crm.projects AS p JOIN crm.clients AS c ON c.id = p.client_id
    WHERE p.stage IN ('ACCEPTED', 'ACTIVE') ORDER BY p.id;
    DECLARE @marketing TABLE (n int IDENTITY (0, 1) PRIMARY KEY, user_id int);
    INSERT @marketing (user_id) SELECT id FROM crm.users WHERE department = N'Marketing' AND is_active = 1 ORDER BY id;
    DECLARE @fairs TABLE (n int PRIMARY KEY, name nvarchar(200), city nvarchar(120), country char(2));
    INSERT @fairs VALUES (0, N'Targi Budma', N'Poznań', 'PL'), (1, N'Warsaw Industry Week', N'Warszawa', 'PL'),
                         (2, N'Targi Pracy i Kariery', N'Kraków', 'PL'), (3, N'Infoshare', N'Gdańsk', 'PL'),
                         (4, N'Autostrada Polska', N'Kielce', 'PL'), (5, N'Bauma', N'München', 'DE'),
                         (6, N'Hannover Messe', N'Hannover', 'DE'), (7, N'VivaTech', N'Paris', 'FR'),
                         (8, N'Batibouw', N'Bruxelles', 'BE'), (9, N'MSV Brno', N'Brno', 'CZ'), (10, N'London Build', N'London', 'GB');
    DECLARE @cars TABLE (n int IDENTITY (0, 1) PRIMARY KEY, id int);
    INSERT @cars (id) SELECT TOP (500) id FROM crm.cars WHERE status = 'OPERATIONAL' ORDER BY id;
    DECLARE @vc int = (SELECT COUNT(*) FROM @visits), @sc int = (SELECT COUNT(*) FROM @sites),
            @mc int = (SELECT COUNT(*) FROM @marketing), @cc int = (SELECT COUNT(*) FROM @cars);
    IF @vc = 0
        RETURN;
    -- Fifty trips a person at most over the seven months: a realistic number for a small team.
    DECLARE @travellers int = (SELECT COUNT(*) FROM (SELECT user_id FROM @visits UNION SELECT user_id FROM @sites UNION SELECT user_id FROM @marketing) AS x);
    IF @trips > @travellers * 50 SET @trips = @travellers * 50;
    DECLARE @now datetime2(0) = SYSUTCDATETIME();
    DECLARE @today date = CAST((@now AT TIME ZONE 'UTC') AT TIME ZONE 'Central European Standard Time' AS date);

    -- The trips as rows first: kind, who, where, when, how.
    DECLARE @plan TABLE (n int PRIMARY KEY, purpose varchar(14), user_id int, client_id bigint, project_id bigint,
        event_name nvarchar(200), destination nvarchar(120), country char(2), starts_at datetime2(0), ends_at datetime2(0),
        transport varchar(12), car_id int, vehicle varchar(12), km int, h1 int, h2 int, h3 int, h4 int, entity int);
    INSERT @plan
    SELECT s.value, k.purpose, x.user_id, x.client_id, x.project_id, x.event_name, x.destination, x.country,
           x.starts_at, DATEADD(MINUTE, x.minutes, x.starts_at),
           tr.transport, IIF(tr.transport = 'COMPANY_CAR' AND @cc > 0, (SELECT id FROM @cars WHERE n = h.h3 % NULLIF(@cc, 0)), NULL),
           IIF(tr.transport = 'PRIVATE_CAR', IIF(h.h4 % 5 = 0, 'CAR_LE_900', 'CAR_GT_900'), NULL),
           IIF(tr.transport = 'PRIVATE_CAR', 40 + h.h2 % 560, NULL), h.h1, h.h2, h.h3, h.h4, x.entity
    -- A fifth more than needed: rows without a traveller or a company drop out below, the rest is cut to @trips.
    FROM GENERATE_SERIES(0, @trips + @trips / 5) AS s
    CROSS APPLY (SELECT HASHBYTES('SHA2_256', CONCAT(@random_seed, ':trip:', s.value)) AS b) AS hb
    CROSS APPLY (SELECT CAST(SUBSTRING(hb.b, 1, 4) AS int) & 0x7FFFFFFF AS h1, CAST(SUBSTRING(hb.b, 5, 4) AS int) & 0x7FFFFFFF AS h2,
                        CAST(SUBSTRING(hb.b, 9, 4) AS int) & 0x7FFFFFFF AS h3, CAST(SUBSTRING(hb.b, 13, 4) AS int) & 0x7FFFFFFF AS h4) AS h
    -- 50% client visits, 20% fairs, 25% project sites (when there are projects), 5% other.
    CROSS APPLY (SELECT CASE WHEN h.h1 % 100 < 50 THEN 'CLIENT_VISIT' WHEN h.h1 % 100 < 70 THEN 'TRADE_FAIR'
                             WHEN h.h1 % 100 < 95 AND @sc > 0 THEN 'PROJECT_SITE' ELSE 'OTHER' END AS purpose) AS k
    CROSS APPLY (SELECT DATEADD(HOUR, 6 + h.h2 % 4, CAST(DATEADD(DAY, -180 + h.h3 % 210, @today) AS datetime2(0))) AS day_start) AS d
    OUTER APPLY (SELECT * FROM @visits WHERE n = h.h2 % @vc) AS v
    OUTER APPLY (SELECT * FROM @sites WHERE n = h.h3 % NULLIF(@sc, 0)) AS st
    OUTER APPLY (SELECT * FROM @fairs WHERE n = IIF(h.h4 % 10 < 7, h.h4 % 5, 5 + h.h4 % 6)) AS f
    CROSS APPLY (SELECT
        CASE k.purpose WHEN 'PROJECT_SITE' THEN st.user_id
                       WHEN 'TRADE_FAIR' THEN IIF(@mc > 0 AND h.h1 % 2 = 0, (SELECT user_id FROM @marketing WHERE n = h.h4 % NULLIF(@mc, 0)), v.user_id)
                       ELSE v.user_id END AS user_id,
        IIF(k.purpose = 'CLIENT_VISIT', v.client_id, NULL) AS client_id,
        IIF(k.purpose = 'PROJECT_SITE', st.project_id, NULL) AS project_id,
        IIF(k.purpose = 'TRADE_FAIR', f.name, NULL) AS event_name,
        CASE k.purpose WHEN 'PROJECT_SITE' THEN st.city WHEN 'TRADE_FAIR' THEN f.city WHEN 'CLIENT_VISIT' THEN v.city ELSE N'Warszawa' END AS destination,
        IIF(k.purpose = 'TRADE_FAIR', f.country, 'PL') AS country,
        d.day_start AS starts_at,
        -- A visit: 6-14 h, sometimes overnight; a fair: 2-4 days; a site: 1-5 days.
        CASE k.purpose WHEN 'TRADE_FAIR' THEN (2 + h.h1 % 3) * 1440 + 60 * (h.h2 % 10)
                       WHEN 'PROJECT_SITE' THEN (h.h1 % 5) * 1440 + 60 * (8 + h.h2 % 10)
                       ELSE IIF(h.h4 % 6 = 0, 1440 + 60 * (h.h2 % 10), 60 * (6 + h.h2 % 9)) END AS minutes,
        IIF(k.purpose = 'PROJECT_SITE', st.entity, 1 + h.h3 % 4) AS entity) AS x
    -- Abroad by train or plane; at home 40% company car, 25% private car, 20% train, 10% plane, 5% bus.
    CROSS APPLY (SELECT CASE WHEN x.country <> 'PL' THEN IIF(h.h3 % 3 = 0, 'TRAIN', 'PLANE')
                             WHEN h.h3 % 100 < 40 THEN 'COMPANY_CAR' WHEN h.h3 % 100 < 65 THEN 'PRIVATE_CAR'
                             WHEN h.h3 % 100 < 85 THEN 'TRAIN' WHEN h.h3 % 100 < 95 THEN 'PLANE' ELSE 'BUS' END AS transport) AS tr
    WHERE x.user_id IS NOT NULL;

    DELETE @plan WHERE entity IS NULL OR NOT EXISTS (SELECT 1 FROM crm.legal_entities WHERE id = entity);
    DELETE p FROM @plan AS p WHERE p.n NOT IN (SELECT TOP (@trips) n FROM @plan ORDER BY n);

    INSERT crm.trips (number, traveller_user_id, legal_entity_id, purpose, client_id, project_id, event_name, description,
                      destination, country, starts_at, ends_at, transport, car_id, vehicle, kilometres, breakfasts, lunches,
                      dinners, lump_nights, local_transport, advance, status, submitted_at, decided_by, decided_at,
                      decision_note, paid_at, currency, created_by, updated_by, created_at)
    -- Four digits, more from 10 000 on - as app.trip_create numbers them.
    SELECT CONCAT('DEL/', YEAR(p.starts_at), '/', RIGHT(CONCAT('000', q.seq), IIF(q.seq > 9999, LEN(q.seq), 4))),
           p.user_id, p.entity, p.purpose, p.client_id, p.project_id, p.event_name,
           CASE p.purpose WHEN 'CLIENT_VISIT' THEN N'Spotkanie handlowe u klienta.' WHEN 'TRADE_FAIR' THEN N'Stoisko firmy i spotkania z klientami.'
                          WHEN 'PROJECT_SITE' THEN N'Nadzór nad realizacją projektu.' ELSE N'Szkolenie zewnętrzne.' END,
           p.destination, p.country, DATEADD(HOUR, -1, p.starts_at), DATEADD(HOUR, -1, p.ends_at), p.transport, p.car_id,
           p.vehicle, p.km, IIF(p.purpose = 'TRADE_FAIR', 1, 0) * (p.h1 % 2), IIF(p.purpose = 'TRADE_FAIR', 2, 0) * (p.h2 % 2), 0,
           IIF(p.purpose = 'PROJECT_SITE' AND p.h4 % 4 = 0, 1, 0), IIF(p.h4 % 7 = 0, 1, 0),
           IIF(p.country <> 'PL' AND p.h2 % 2 = 0, 200, 0), s.status,
           IIF(s.status IN ('SUBMITTED', 'RETURNED', 'APPROVED', 'PAID'), DATEADD(DAY, 2, p.ends_at), NULL),
           IIF(s.status IN ('RETURNED', 'APPROVED', 'PAID'), m.id, NULL),
           IIF(s.status IN ('RETURNED', 'APPROVED', 'PAID'), DATEADD(DAY, 4, p.ends_at), NULL),
           IIF(s.status = 'RETURNED', N'Brak faktury za hotel - dołącz dokument.', NULL),
           IIF(s.status = 'PAID', DATEADD(DAY, 9, p.ends_at), NULL), 'PLN', p.user_id, p.user_id,
           DATEADD(DAY, -7, p.starts_at)
    FROM (SELECT x.*, ROW_NUMBER() OVER (PARTITION BY YEAR(x.starts_at) ORDER BY x.starts_at, x.n) AS seq FROM @plan AS x) AS p
    CROSS APPLY (SELECT p.seq) AS q
    CROSS APPLY (SELECT CASE WHEN p.ends_at > @now THEN 'PLANNED'
                             WHEN p.h4 % 100 < 10 THEN 'PLANNED' WHEN p.h4 % 100 < 25 THEN 'SUBMITTED'
                             WHEN p.h4 % 100 < 30 THEN 'RETURNED' WHEN p.h4 % 100 < 55 THEN 'APPROVED'
                             WHEN p.h4 % 100 < 98 THEN 'PAID' ELSE 'CANCELLED' END AS status) AS s
    CROSS APPLY (SELECT TOP (1) id FROM crm.users WHERE role IN ('MANAGER', 'ADMIN') AND is_active = 1 AND id <> p.user_id ORDER BY id) AS m;

    -- Expenses: a hotel for every night but the lump-sum ones, tickets, fuel and parking.
    INSERT crm.trip_expenses (trip_id, line_no, category, description, spent_on, document, amount, nights)
    SELECT t.id, ROW_NUMBER() OVER (PARTITION BY t.id ORDER BY e.ord), e.category, e.description, CAST(t.starts_at AS date),
           CONCAT('FV/', t.id, '/', e.ord), e.amount, e.nights
    FROM crm.trips AS t
    CROSS APPLY (SELECT DATEDIFF(DAY, t.starts_at, t.ends_at) - t.lump_nights AS nights,
                        CAST(SUBSTRING(HASHBYTES('SHA2_256', CONCAT(@random_seed, ':exp:', t.id)), 1, 4) AS int) & 0x7FFFFFFF AS h) AS q
    CROSS APPLY (
        SELECT 1 AS ord, 'HOTEL' AS category, N'Hotel' AS description,
               CAST(q.nights * IIF(t.country = 'PL', 260 + q.h % 200, 110 + q.h % 90) AS decimal(12, 2)) AS amount, q.nights AS nights
        WHERE q.nights > 0
        UNION ALL
        SELECT 2, 'TICKET', IIF(t.transport = 'PLANE', N'Bilet lotniczy', N'Bilet kolejowy'),
               CAST(IIF(t.transport = 'PLANE', IIF(t.country = 'PL', 420, 180) + q.h % 300, IIF(t.country = 'PL', 90, 60) + q.h % 120) AS decimal(12, 2)), NULL
        WHERE t.transport IN ('TRAIN', 'PLANE', 'BUS')
        UNION ALL
        SELECT 3, 'FUEL', N'Paliwo', CAST(120 + q.h % 260 AS decimal(12, 2)), NULL WHERE t.transport = 'COMPANY_CAR'
        UNION ALL
        SELECT 4, 'PARKING', N'Parking', CAST(15 + q.h % 60 AS decimal(12, 2)), NULL WHERE t.transport IN ('COMPANY_CAR', 'PRIVATE_CAR') AND q.h % 3 = 0
    ) AS e
    WHERE t.status <> 'CANCELLED';

    DECLARE @years TABLE (year smallint, last_used int);
    INSERT @years SELECT YEAR(starts_at), COUNT(*) FROM crm.trips GROUP BY YEAR(starts_at);
    MERGE crm.trip_numbers AS n USING @years AS y ON n.year = y.year
    WHEN MATCHED THEN UPDATE SET last_used = y.last_used
    WHEN NOT MATCHED THEN INSERT (year, last_used) VALUES (y.year, y.last_used);

    DECLARE @id bigint = (SELECT MIN(id) FROM crm.trips), @last bigint = (SELECT MAX(id) FROM crm.trips);
    WHILE @id <= @last
    BEGIN
        EXEC crm.trip_compute @id;
        SET @id += 1;
    END;
END;
