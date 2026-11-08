-- HTTP answers since @from per Warsaw hour (@hourly = 1) or day, by outcome, for the stacked chart (ADR-0012).
CREATE OR ALTER PROCEDURE app.monitoring_http_series
    @actor_id int,
    @from     datetime2(3),
    @hourly   bit = 1
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.monitoring_require_admin @actor_id;
    SELECT b.bucket,
           SUM(IIF(r.status BETWEEN 200 AND 399, 1, 0)) AS ok,
           SUM(IIF(r.status BETWEEN 400 AND 499, 1, 0)) AS client_error,
           SUM(IIF(r.status >= 500, 1, 0)) AS server_error
    FROM crm.http_requests AS r
    CROSS APPLY (SELECT CAST((r.at AT TIME ZONE 'UTC') AT TIME ZONE 'Central European Standard Time' AS datetime2(0)) AS local) AS l
    CROSS APPLY (SELECT IIF(@hourly = 1, DATETRUNC(HOUR, l.local), DATETRUNC(DAY, l.local)) AS bucket) AS b
    WHERE r.at >= @from
    GROUP BY b.bucket
    ORDER BY b.bucket;
END;
