/*
  Seed (ADR-0015): a pipeline for the board - for the first twelve salespeople with clients, ten deals each across the
  stages, open ones closing from ten days back to three months ahead, closed ones in the last four weeks. Only into an
  empty pipeline; deterministic for one @random_seed. Called by seed.desk_run.
*/
CREATE OR ALTER PROCEDURE seed.deals_run
    @random_seed int = 2026
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    IF EXISTS (SELECT 1 FROM crm.deals)
        RETURN;

    DECLARE @titles TABLE (n int IDENTITY (0, 1) PRIMARY KEY, title nvarchar(200));
    INSERT @titles (title)
    VALUES (N'Wdrożenie CRM'), (N'Dostawa laptopów dla biura'), (N'Outsourcing 5 spawaczy MIG/MAG'),
           (N'Modernizacja hali magazynowej'), (N'Audyt bezpieczeństwa IT'), (N'Licencje Microsoft 365 na rok'),
           (N'Utrzymanie systemu - umowa roczna'), (N'Rekrutacja zespołu programistów'), (N'Remont biura - II piętro'),
           (N'Migracja serwerów do chmury'), (N'Monterzy instalacji na budowę'), (N'Fundamenty pod nową halę');
    DECLARE @lost TABLE (n int IDENTITY (0, 1) PRIMARY KEY, reason nvarchar(400));
    INSERT @lost (reason)
    VALUES (N'Wybrali tańszą ofertę konkurencji.'), (N'Projekt przesunięty na przyszły rok.'),
           (N'Brak budżetu po stronie klienta.');

    DECLARE @deals TABLE (n int IDENTITY (0, 1) PRIMARY KEY, client_id bigint, owner int);
    INSERT @deals (client_id, owner)
    SELECT c.id, s.id
    FROM (SELECT TOP (12) u.id FROM crm.users AS u
          WHERE u.role = 'SALES' AND u.is_active = 1
            AND EXISTS (SELECT 1 FROM crm.clients AS x WHERE x.assigned_user_id = u.id)
          ORDER BY u.login) AS s
    CROSS APPLY (SELECT TOP (10) id FROM crm.clients WHERE assigned_user_id = s.id ORDER BY id) AS c
    ORDER BY s.id, c.id;

    DECLARE @today date = CAST((SYSUTCDATETIME() AT TIME ZONE 'UTC') AT TIME ZONE 'Central European Standard Time' AS date);
    DECLARE @title_count int = (SELECT COUNT(*) FROM @titles), @i int = (SELECT MIN(n) FROM @deals),
            @last int = (SELECT MAX(n) FROM @deals);
    WHILE @i <= @last
    BEGIN
        DECLARE @h varbinary(32) = HASHBYTES('SHA2_256', CONCAT(@random_seed, ':deal:', @i));
        DECLARE @r1 int = CAST(SUBSTRING(@h, 1, 4) AS int) & 0x7FFFFFFF, @r2 int = CAST(SUBSTRING(@h, 5, 4) AS int) & 0x7FFFFFFF,
                @r3 int = CAST(SUBSTRING(@h, 9, 4) AS int) & 0x7FFFFFFF;
        -- More deals early in the funnel than late: 30% lead, 20% qualified, 20% proposal, 15% negotiation, 10% won, 5% lost.
        DECLARE @p int = @r1 % 100;
        DECLARE @stage varchar(12) = CASE WHEN @p < 30 THEN 'LEAD' WHEN @p < 50 THEN 'QUALIFIED' WHEN @p < 70 THEN 'PROPOSAL'
                                          WHEN @p < 85 THEN 'NEGOTIATION' WHEN @p < 95 THEN 'WON' ELSE 'LOST' END;
        DECLARE @closed bit = IIF(@stage IN ('WON', 'LOST'), 1, 0);
        DECLARE @closed_at datetime2(3) = IIF(@closed = 1, DATEADD(DAY, -(@r3 % 28), SYSUTCDATETIME()), NULL);
        INSERT crm.deals (title, client_id, owner_user_id, stage, value, currency, expected_close, lost_reason,
                          stage_changed_at, closed_at, created_by, updated_by)
        SELECT (SELECT title FROM @titles WHERE n = @r2 % @title_count), d.client_id, d.owner, @stage,
               (5 + @r2 % 496) * 1000, 'PLN',
               IIF(@closed = 1, CAST(@closed_at AS date), DATEADD(DAY, -10 + @r3 % 100, @today)),
               IIF(@stage = 'LOST', (SELECT reason FROM @lost WHERE n = @r3 % 3), NULL),
               ISNULL(@closed_at, DATEADD(DAY, -(@r3 % 20), SYSUTCDATETIME())), @closed_at, d.owner, d.owner
        FROM @deals AS d WHERE d.n = @i;
        SET @i += 1;
    END;
END;
