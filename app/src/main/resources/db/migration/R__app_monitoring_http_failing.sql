-- The ten most frequent failing answers (status >= 400) since @from, by method, path and status (ADR-0012).
CREATE OR ALTER PROCEDURE app.monitoring_http_failing
    @actor_id int,
    @from     datetime2(3)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.monitoring_require_admin @actor_id;
    SELECT TOP (10) method, path, status, COUNT_BIG(*) AS answers, MAX(at) AS last_at
    FROM crm.http_requests
    WHERE at >= @from AND status >= 400
    GROUP BY method, path, status
    ORDER BY answers DESC, last_at DESC;
END;
