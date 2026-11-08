/*
  Business trips, newest start first, keyset after (@after_start, @after_id), @page_size + 1 rows (ADR-0019). @scope:
  MINE, TO_APPROVE (submitted, not mine - managers) or ALL (managers); SALES see only their own whatever the scope.
*/
CREATE OR ALTER PROCEDURE app.trip_list
    @actor_id          int,
    @scope             varchar(10) = 'MINE',
    @status            varchar(10) = NULL,
    @purpose           varchar(14) = NULL,
    @traveller_user_id int         = NULL,
    @from              date        = NULL,
    @to                date        = NULL,
    @after_start       datetime2(0) = NULL,
    @after_id          bigint       = NULL,
    @page_size         int          = 50
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @role varchar(10);
    EXEC crm.actor_require @actor_id, @role OUTPUT;
    IF ISNULL(@scope, '') NOT IN ('MINE', 'TO_APPROVE', 'ALL')
        THROW 51248, N'Scope must be MINE, TO_APPROVE or ALL.', 1;
    IF @page_size IS NULL OR @page_size NOT BETWEEN 1 AND 200
        THROW 51014, N'Page size must be between 1 and 200.', 1;
    DECLARE @ids nvarchar(max) = (
        SELECT STRING_AGG(CAST(p.id AS nvarchar(max)), ',') WITHIN GROUP (ORDER BY p.starts_at DESC, p.id DESC)
        FROM (SELECT TOP (@page_size + 1) t.id, t.starts_at
              FROM crm.trips AS t
    WHERE (@scope <> 'MINE' OR t.traveller_user_id = @actor_id)
      AND (@scope <> 'TO_APPROVE' OR (t.status = 'SUBMITTED' AND t.traveller_user_id <> @actor_id))
      AND (@role IN ('ADMIN', 'MANAGER') OR t.traveller_user_id = @actor_id)
      AND (@status IS NULL OR t.status = @status)
      AND (@purpose IS NULL OR t.purpose = @purpose)
      AND (@traveller_user_id IS NULL OR t.traveller_user_id = @traveller_user_id)
      AND (@from IS NULL OR t.starts_at >= @from)
      AND (@to IS NULL OR t.starts_at < DATEADD(DAY, 1, @to))
                AND (@after_id IS NULL OR t.starts_at < @after_start OR (t.starts_at = @after_start AND t.id < @after_id))
              ORDER BY t.starts_at DESC, t.id DESC) AS p);
    EXEC crm.trip_select @ids = @ids;
END;
