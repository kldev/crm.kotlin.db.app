-- The number of trips for the same filters as app.trip_list (ADR-0019).
CREATE OR ALTER PROCEDURE app.trip_count
    @actor_id          int,
    @scope             varchar(10) = 'MINE',
    @status            varchar(10) = NULL,
    @purpose           varchar(14) = NULL,
    @traveller_user_id int         = NULL,
    @from              date        = NULL,
    @to                date        = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @role varchar(10);
    EXEC crm.actor_require @actor_id, @role OUTPUT;
    IF ISNULL(@scope, '') NOT IN ('MINE', 'TO_APPROVE', 'ALL')
        THROW 51248, N'Scope must be MINE, TO_APPROVE or ALL.', 1;
    SELECT COUNT_BIG(*) AS total
    FROM crm.trips AS t
    WHERE (@scope <> 'MINE' OR t.traveller_user_id = @actor_id)
      AND (@scope <> 'TO_APPROVE' OR (t.status = 'SUBMITTED' AND t.traveller_user_id <> @actor_id))
      AND (@role IN ('ADMIN', 'MANAGER') OR t.traveller_user_id = @actor_id)
      AND (@status IS NULL OR t.status = @status)
      AND (@purpose IS NULL OR t.purpose = @purpose)
      AND (@traveller_user_id IS NULL OR t.traveller_user_id = @traveller_user_id)
      AND (@from IS NULL OR t.starts_at >= @from)
      AND (@to IS NULL OR t.starts_at < DATEADD(DAY, 1, @to));
END;
