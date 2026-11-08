-- Retention (ADR-0012): deletes answers and log entries older than @before in batches, so no long lock is held.
-- Idempotent: replicas may run it at the same time.
CREATE OR ALTER PROCEDURE app.monitoring_cleanup
    @before     datetime2(3),
    @batch_size int = 5000
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    IF @before IS NULL OR @batch_size IS NULL OR @batch_size NOT BETWEEN 100 AND 100000
        THROW 51160, N'Cleanup needs a cutoff and a batch size of 100-100000.', 1;
    DECLARE @requests bigint = 0, @logs bigint = 0, @n int = 1;
    WHILE @n > 0
    BEGIN
        DELETE TOP (@batch_size) FROM crm.http_requests WHERE at < @before;
        SET @n = @@ROWCOUNT;
        SET @requests += @n;
    END;
    SET @n = 1;
    WHILE @n > 0
    BEGIN
        DELETE TOP (@batch_size) FROM crm.app_logs WHERE at < @before;
        SET @n = @@ROWCOUNT;
        SET @logs += @n;
    END;
    SELECT @requests AS requests_deleted, @logs AS logs_deleted;
END;
