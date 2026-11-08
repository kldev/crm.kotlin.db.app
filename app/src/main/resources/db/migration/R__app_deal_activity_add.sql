/*
  Log what happened on a deal (ADR-0017): the type (51210), a note of 1-1000 characters (51211), when it happened - now
  when empty, never in the future, at most 90 days back (51212). Append-only: an activity is never changed.
*/
CREATE OR ALTER PROCEDURE app.deal_activity_add
    @actor_id      int,
    @deal_id       bigint,
    @activity_type varchar(12),
    @note          nvarchar(4000),
    @occurred_at   datetime2(3) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.deal_require_visible @actor_id, @deal_id;
    IF NOT EXISTS (SELECT 1 FROM crm.deal_activity_types WHERE activity_type = @activity_type)
        THROW 51210, N'Choose a type of activity from the list.', 1;
    SET @note = NULLIF(LTRIM(RTRIM(@note)), N'');
    IF @note IS NULL OR LEN(@note) > 1000
        THROW 51211, N'Describe the activity (at most 1000 characters).', 1;
    DECLARE @now datetime2(3) = SYSUTCDATETIME();
    SET @occurred_at = ISNULL(@occurred_at, @now);
    -- A minute of slack for clocks that differ a little.
    IF @occurred_at > DATEADD(MINUTE, 1, @now) OR @occurred_at < DATEADD(DAY, -90, @now)
        THROW 51212, N'An activity happened in the last 90 days, not in the future.', 1;
    DECLARE @id bigint;
    EXEC crm.deal_activity_log @deal_id, @activity_type, @note, @occurred_at, @actor_id, @id OUTPUT;
    SELECT a.id, a.deal_id, a.activity_type, a.note, a.occurred_at, a.created_by, u.display_name AS created_by_name,
           a.created_at
    FROM crm.deal_activities AS a JOIN crm.users AS u ON u.id = a.created_by
    WHERE a.id = @id;
END;
