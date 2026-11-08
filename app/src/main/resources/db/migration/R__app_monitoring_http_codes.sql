-- HTTP answers since @from per status code, with the average time (ADR-0012).
CREATE OR ALTER PROCEDURE app.monitoring_http_codes
    @actor_id int,
    @from     datetime2(3)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.monitoring_require_admin @actor_id;
    SELECT status, COUNT_BIG(*) AS answers, AVG(CAST(elapsed_ms AS float)) AS avg_ms
    FROM crm.http_requests
    WHERE at >= @from
    GROUP BY status
    ORDER BY status;
END;
