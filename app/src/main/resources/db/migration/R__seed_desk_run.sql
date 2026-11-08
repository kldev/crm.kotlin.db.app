/*
  Seed of the service desk (ADR-0007), with the migrator login. Idempotent: agents and people are added only when
  missing (by login / e-mail), tickets only into an empty desk - run it again at any time.

  Agents: the desk team as CRM users (role SALES, the same @password_hash as the perf users); any CRM user can
  work tickets, these ten just have names to recognise. People: the requesters of the public form.
  Tickets (@stories, JSON, app resources desk/seed-tickets.json - Halcyon's 38 hand-written tickets and 200 generated
  ones): replayed step by step at their moments in the past by seed.desk_replay. NULL = no tickets.
*/
CREATE OR ALTER PROCEDURE seed.desk_run
    @password_hash varchar(100),
    @stories       nvarchar(max) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    IF @password_hash IS NULL OR LEN(@password_hash) = 0
        THROW 51020, N'Password is required.', 1;

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

    -- Their contact closes the offers they write (ADR-0013); only filled in where nobody set one.
    UPDATE u
    SET job_title = ISNULL(u.job_title, N'Doradca handlowy'), phone = ISNULL(u.phone, a.phone), email = ISNULL(u.email, a.email)
    FROM crm.users AS u
    JOIN (VALUES ('anna.nowak', '+48 600 100 101', 'anna.nowak@company.io'),
            ('piotr.kowalski', '+48 600 100 102', 'piotr.kowalski@company.io'),
            ('katarzyna.wisniewska', '+48 600 100 103', 'katarzyna.wisniewska@company.io'),
            ('tomasz.wojcik', '+48 600 100 104', 'tomasz.wojcik@company.io'),
            ('magdalena.kaminska', '+48 600 100 105', 'magdalena.kaminska@company.io'),
            ('michal.lewandowski', '+48 600 100 106', 'michal.lewandowski@company.io'),
            ('agnieszka.zielinska', '+48 600 100 107', 'agnieszka.zielinska@company.io'),
            ('pawel.szymanski', '+48 600 100 108', 'pawel.szymanski@company.io'),
            ('joanna.wozniak', '+48 600 100 109', 'joanna.wozniak@company.io'),
            ('krzysztof.dabrowski', '+48 600 100 110', 'krzysztof.dabrowski@company.io')) AS a (login, phone, email) ON a.login = u.login;

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

    IF @stories IS NOT NULL AND NOT EXISTS (SELECT 1 FROM crm.tickets)
        EXEC seed.desk_replay @stories;
    -- The agents' departments and their plan of tasks (ADR-0014).
    EXEC seed.tasks_run;
    -- A pipeline for the sales board (ADR-0015).
    EXEC seed.deals_run;
    -- Activities, next steps and tasks of the deals: a salesperson's day (ADR-0017).
    EXEC seed.sales_run;
    -- Offers of the deals' clients from the three templates (ADR-0013).
    EXEC seed.offers_run;
    -- The fleet: cars, repair shops, leasing, handovers (ADR-0018).
    EXEC seed.fleet_run;
    -- The group's companies on the projects seeded before them (ADR-0016).
    EXEC seed.legal_entities_run;
END;
