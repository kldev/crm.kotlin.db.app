/*
  HTTP answers since @from (ADR-0012): how many, by outcome - 2xx, 3xx, 403, 404, other 4xx (401 among them), 5xx -
  the average and the 95th percentile of the time to answer. Administrators only.
*/
CREATE OR ALTER PROCEDURE app.monitoring_http_summary
    @actor_id int,
    @from     datetime2(3)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.monitoring_require_admin @actor_id;
    DECLARE @p95 float = (SELECT TOP (1) PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY elapsed_ms) OVER ()
                          FROM crm.http_requests WHERE at >= @from);
    SELECT COUNT_BIG(*) AS total,
           ISNULL(SUM(IIF(status BETWEEN 200 AND 299, 1, 0)), 0) AS ok,
           ISNULL(SUM(IIF(status BETWEEN 300 AND 399, 1, 0)), 0) AS redirect,
           ISNULL(SUM(IIF(status = 403, 1, 0)), 0) AS forbidden,
           ISNULL(SUM(IIF(status = 404, 1, 0)), 0) AS not_found,
           ISNULL(SUM(IIF(status BETWEEN 400 AND 499 AND status NOT IN (403, 404), 1, 0)), 0) AS client_error,
           ISNULL(SUM(IIF(status >= 500, 1, 0)), 0) AS server_error,
           AVG(CAST(elapsed_ms AS float)) AS avg_ms,
           @p95 AS p95_ms
    FROM crm.http_requests
    WHERE at >= @from;
END;
