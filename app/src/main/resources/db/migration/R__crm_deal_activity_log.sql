-- Internal (ADR-0017): append an activity to a deal and keep the deal's newest activity (a backdated one does not move it back).
CREATE OR ALTER PROCEDURE crm.deal_activity_log
    @deal_id       bigint,
    @activity_type varchar(12),
    @note          nvarchar(1000),
    @occurred_at   datetime2(3),
    @actor_id      int,
    @activity_id   bigint = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    INSERT crm.deal_activities (deal_id, activity_type, note, occurred_at, created_by)
    VALUES (@deal_id, @activity_type, @note, @occurred_at, @actor_id);
    SET @activity_id = SCOPE_IDENTITY();
    UPDATE crm.deals
    SET last_activity_at = @occurred_at, last_activity_type = @activity_type
    WHERE id = @deal_id AND (last_activity_at IS NULL OR last_activity_at <= @occurred_at);
END;
