/*
  Seed (ADR-0018): a fleet of up to @cars cars (2 000 by default, never more than active people) with repair shops and
  leasing companies, statuses with their history, financing, inspection and insurance deadlines, five past handovers
  per car in two-month rounds and a current one for most operational cars - about 10 000 handovers. In each round every
  car has a different holder, so the overlap rules hold. Set-based; only into an empty fleet; deterministic for one
  @random_seed. Called by seed.desk_run.
*/
CREATE OR ALTER PROCEDURE seed.fleet_run
    @random_seed int = 2026,
    @cars        int = 2000
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    IF EXISTS (SELECT 1 FROM crm.cars)
        RETURN;

    IF NOT EXISTS (SELECT 1 FROM crm.fleet_partners)
        INSERT crm.fleet_partners (kind, name, phone)
        VALUES ('REPAIR_SHOP', N'Serwis Warszawa Wola', '+48 22 300 10 10'), ('REPAIR_SHOP', N'Auto Serwis Kraków', '+48 12 400 20 20'),
               ('REPAIR_SHOP', N'Serwis Poznań Franowo', '+48 61 500 30 30'), ('REPAIR_SHOP', N'Warsztat Gdańsk Oliwa', '+48 58 600 40 40'),
               ('REPAIR_SHOP', N'Serwis Wrocław Krzyki', '+48 71 700 50 50'), ('REPAIR_SHOP', N'Opony i Klima Łódź', '+48 42 800 60 60'),
               ('LEASING', N'Obsydian Leasing', '+48 22 111 22 33'), ('LEASING', N'Champagne Lease', '+48 22 444 55 66'),
               ('LEASING', N'Fleet Finance Polska', '+48 22 777 88 99');

    DECLARE @people TABLE (n int IDENTITY (0, 1) PRIMARY KEY, id int);
    INSERT @people (id) SELECT id FROM crm.users WHERE is_active = 1 ORDER BY id;
    DECLARE @people_count int = (SELECT COUNT(*) FROM @people);
    SET @cars = IIF(@cars < @people_count, @cars, @people_count);
    IF @cars = 0
        RETURN;

    DECLARE @models TABLE (n int PRIMARY KEY, make nvarchar(60), model nvarchar(60));
    INSERT @models VALUES (0, N'Škoda', N'Octavia Kombi'), (1, N'Toyota', N'Corolla'), (2, N'Ford', N'Transit Custom'),
                          (3, N'Volkswagen', N'Passat Variant'), (4, N'Opel', N'Astra'), (5, N'Toyota', N'Yaris'),
                          (6, N'Škoda', N'Superb'), (7, N'Renault', N'Master'), (8, N'Kia', N'Ceed SW'),
                          (9, N'Hyundai', N'Tucson'), (10, N'Volkswagen', N'Golf'), (11, N'Dacia', N'Duster');
    DECLARE @cities TABLE (n int PRIMARY KEY, prefix varchar(3));
    INSERT @cities VALUES (0, 'WA'), (1, 'KR'), (2, 'PO'), (3, 'GD'), (4, 'WR'), (5, 'EL'), (6, 'WX'), (7, 'KR');
    DECLARE @shops TABLE (n int IDENTITY (0, 1) PRIMARY KEY, id int);
    INSERT @shops (id) SELECT id FROM crm.fleet_partners WHERE kind = 'REPAIR_SHOP' ORDER BY id;
    DECLARE @leasings TABLE (n int IDENTITY (0, 1) PRIMARY KEY, id int);
    INSERT @leasings (id) SELECT id FROM crm.fleet_partners WHERE kind = 'LEASING' ORDER BY id;
    DECLARE @shop_count int = (SELECT COUNT(*) FROM @shops), @leasing_count int = (SELECT COUNT(*) FROM @leasings);
    DECLARE @entities TABLE (n int IDENTITY (0, 1) PRIMARY KEY, id int);
    INSERT @entities (id) SELECT id FROM crm.legal_entities ORDER BY id;
    DECLARE @entity_count int = (SELECT COUNT(*) FROM @entities);
    DECLARE @today date = crm.fleet_today();

    DECLARE @made TABLE (car_id int, n int, status varchar(20));
    INSERT crm.cars (name, make, production_year, plate, vin, legal_entity_id, status, status_since, repair_shop_id, financing,
                     purchase_date, leasing_id, instalment, currency, lease_start, lease_months, contract_no,
                     inspection_due, insurance_due, notes)
    OUTPUT inserted.id, CAST(SUBSTRING(inserted.plate, 4, 5) AS int) - 1, inserted.status INTO @made
    SELECT CONCAT(m.make, N' ', m.model), m.make, YEAR(@today) - s.value % 8,
           CONCAT(ci.prefix, ' ', RIGHT(CONCAT('0000', s.value + 1), 5)),
           IIF(h.h3 % 3 = 0, NULL, CONCAT('WVW', RIGHT(CONCAT('00000000000000', s.value * 7919 + 13), 14))),
           e.id, x.status, DATEADD(DAY, -(h.h2 % 200), @today), IIF(x.shop = 1, sh.id, NULL), f.financing,
           IIF(f.financing = 'PAID', DATEADD(DAY, -(h.h4 % 1500), @today), NULL),
           IIF(f.financing = 'LEASING', le.id, NULL),
           IIF(f.financing = 'LEASING', CAST(900 + h.h4 % 3100 AS decimal(12, 2)), NULL),
           IIF(f.financing = 'LEASING', 'PLN', NULL),
           IIF(f.financing = 'LEASING', DATEADD(DAY, -(h.h4 % 1000), @today), NULL),
           IIF(f.financing = 'LEASING', 24 + 12 * (h.h1 % 3), NULL),
           IIF(f.financing = 'LEASING', CONCAT('LS/', YEAR(@today) - h.h4 % 3, '/', 1000 + s.value), NULL),
           DATEADD(DAY, -10 + h.h2 % 375, @today), DATEADD(DAY, -5 + h.h3 % 370, @today),
           IIF(x.status = 'IN_REPAIR_SHOP', N'Wymiana sprzęgła', NULL)
    FROM GENERATE_SERIES(0, @cars - 1) AS s
    CROSS APPLY (SELECT HASHBYTES('SHA2_256', CONCAT(@random_seed, ':car:', s.value)) AS b) AS hb
    CROSS APPLY (SELECT CAST(SUBSTRING(hb.b, 1, 4) AS int) & 0x7FFFFFFF AS h1, CAST(SUBSTRING(hb.b, 5, 4) AS int) & 0x7FFFFFFF AS h2,
                        CAST(SUBSTRING(hb.b, 9, 4) AS int) & 0x7FFFFFFF AS h3, CAST(SUBSTRING(hb.b, 13, 4) AS int) & 0x7FFFFFFF AS h4) AS h
    JOIN @models AS m ON m.n = h.h1 % 12
    JOIN @cities AS ci ON ci.n = s.value % 8
    JOIN @entities AS e ON e.n = h.h2 % @entity_count
    JOIN @shops AS sh ON sh.n = h.h3 % @shop_count
    JOIN @leasings AS le ON le.n = h.h4 % @leasing_count
    -- 80% operational, 4% new, 5% in a repair shop, 3% on the way, 2% ready for pickup, 3% for sale, 3% archived.
    CROSS APPLY (SELECT CASE WHEN h.h1 % 100 < 80 THEN 'OPERATIONAL' WHEN h.h1 % 100 < 84 THEN 'ACTIVE'
                             WHEN h.h1 % 100 < 89 THEN 'IN_REPAIR_SHOP' WHEN h.h1 % 100 < 92 THEN 'TO_REPAIR_SHOP'
                             WHEN h.h1 % 100 < 94 THEN 'READY_FOR_PICKUP' WHEN h.h1 % 100 < 97 THEN 'FOR_SALE'
                             ELSE 'ARCHIVED' END AS status,
                        IIF(h.h1 % 100 BETWEEN 84 AND 93, 1, 0) AS shop) AS x
    -- Half on leasing, a third bought, the rest not recorded.
    CROSS APPLY (SELECT CASE WHEN h.h4 % 10 < 5 THEN 'LEASING' WHEN h.h4 % 10 < 8 THEN 'PAID' ELSE 'UNKNOWN' END AS financing) AS f;

    INSERT crm.car_status_history (car_id, status, effective_on, changed_by)
    SELECT c.id, 'ACTIVE', DATEADD(DAY, -400, @today), (SELECT MIN(id) FROM crm.users WHERE role = 'ADMIN')
    FROM crm.cars AS c;
    INSERT crm.car_status_history (car_id, status, effective_on, repair_shop, note, changed_by)
    SELECT c.id, c.status, c.status_since, p.name, c.notes, (SELECT MIN(id) FROM crm.users WHERE role = 'ADMIN')
    FROM crm.cars AS c LEFT JOIN crm.fleet_partners AS p ON p.id = c.repair_shop_id
    WHERE c.status <> 'ACTIVE';

    DECLARE @issuer int = (SELECT MIN(id) FROM crm.users WHERE role IN ('ADMIN', 'MANAGER') AND is_active = 1);
    -- Five past rounds of two months each (a month or two out, then back), every car to a different person per round.
    INSERT crm.car_handovers (car_id, holder_user_id, issue_date, planned_return, issue_mileage, issue_fuel, issued_by,
                              returned_on, return_mileage, return_fuel, returned_by)
    SELECT m.car_id, p.id, r.issue_date, DATEADD(DAY, 30 + h.h2 % 25, r.issue_date),
           20000 + k.value * 4000 + h.h3 % 3000, 40 + h.h4 % 60, @issuer,
           DATEADD(DAY, 28 + h.h2 % 28, r.issue_date), 20000 + k.value * 4000 + h.h3 % 3000 + 500 + h.h1 % 3000,
           10 + h.h4 % 90, @issuer
    FROM @made AS m
    CROSS JOIN GENERATE_SERIES(0, 4) AS k
    CROSS APPLY (SELECT HASHBYTES('SHA2_256', CONCAT(@random_seed, ':handover:', m.car_id, ':', k.value)) AS b) AS hb
    CROSS APPLY (SELECT CAST(SUBSTRING(hb.b, 1, 4) AS int) & 0x7FFFFFFF AS h1, CAST(SUBSTRING(hb.b, 5, 4) AS int) & 0x7FFFFFFF AS h2,
                        CAST(SUBSTRING(hb.b, 9, 4) AS int) & 0x7FFFFFFF AS h3, CAST(SUBSTRING(hb.b, 13, 4) AS int) & 0x7FFFFFFF AS h4) AS h
    CROSS APPLY (SELECT DATEADD(DAY, -330 + 60 * k.value, @today) AS issue_date) AS r
    JOIN @people AS p ON p.n = (m.n + k.value * 101) % @people_count
    WHERE m.status <> 'ACTIVE' AND h.h1 % 10 <> 0;

    -- The current round: most operational cars are out now, some past their planned return.
    INSERT crm.car_handovers (car_id, holder_user_id, issue_date, planned_return, issue_mileage, issue_fuel, issued_by)
    SELECT m.car_id, p.id, DATEADD(DAY, -(h.h2 % 25), @today),
           IIF(h.h3 % 5 = 0, NULL, DATEADD(DAY, -5 + h.h3 % 70, @today)),
           42000 + h.h4 % 5000, 50 + h.h1 % 50, @issuer
    FROM @made AS m
    CROSS APPLY (SELECT HASHBYTES('SHA2_256', CONCAT(@random_seed, ':current:', m.car_id)) AS b) AS hb
    CROSS APPLY (SELECT CAST(SUBSTRING(hb.b, 1, 4) AS int) & 0x7FFFFFFF AS h1, CAST(SUBSTRING(hb.b, 5, 4) AS int) & 0x7FFFFFFF AS h2,
                        CAST(SUBSTRING(hb.b, 9, 4) AS int) & 0x7FFFFFFF AS h3, CAST(SUBSTRING(hb.b, 13, 4) AS int) & 0x7FFFFFFF AS h4) AS h
    JOIN @people AS p ON p.n = (m.n + 5 * 101) % @people_count
    WHERE m.status = 'OPERATIONAL' AND h.h1 % 10 < 7;
END;
