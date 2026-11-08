/*
  The trip's way (ADR-0019): SUBMIT (the traveller or a manager, from PLANNED or RETURNED, once the trip has ended -
  51929), APPROVE or RETURN with a note (a manager, never on their own trip - 51930; the note 51247), PAY (a manager,
  from APPROVED), CANCEL (from PLANNED). Any other move: 51931. rowVersion (51901).
*/
CREATE OR ALTER PROCEDURE app.trip_change_status
    @actor_id    int,
    @trip_id     bigint,
    @action      varchar(10),
    @note        nvarchar(4000) = NULL,
    @row_version binary(8)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @role varchar(10), @status varchar(10), @mine bit;
    EXEC crm.trip_require @actor_id, @trip_id, 0, @role OUTPUT, @status OUTPUT, @mine OUTPUT;
    DECLARE @manager bit = IIF(@role IN ('ADMIN', 'MANAGER'), 1, 0);
    SET @note = NULLIF(LTRIM(RTRIM(@note)), N'');
    DECLARE @to varchar(10) =
        CASE WHEN @action = 'SUBMIT' AND @status IN ('PLANNED', 'RETURNED') THEN 'SUBMITTED'
             WHEN @action = 'APPROVE' AND @status = 'SUBMITTED' AND @manager = 1 THEN 'APPROVED'
             WHEN @action = 'RETURN' AND @status = 'SUBMITTED' AND @manager = 1 THEN 'RETURNED'
             WHEN @action = 'PAY' AND @status = 'APPROVED' AND @manager = 1 THEN 'PAID'
             WHEN @action = 'CANCEL' AND @status = 'PLANNED' THEN 'CANCELLED' END;
    IF @to IS NULL
        THROW 51931, N'This step is not allowed for the trip now.', 1;
    IF @to = 'SUBMITTED' AND (SELECT ends_at FROM crm.trips WHERE id = @trip_id) > SYSUTCDATETIME()
        THROW 51929, N'A trip is settled after it ends.', 1;
    IF @to IN ('APPROVED', 'RETURNED', 'PAID') AND @mine = 1
        THROW 51930, N'Nobody approves or pays their own trip.', 1;
    IF @to = 'RETURNED' AND (@note IS NULL OR LEN(@note) > 400)
        THROW 51247, N'Say what to correct (at most 400 characters).', 1;
    UPDATE crm.trips
    SET status = @to,
        submitted_at = IIF(@to = 'SUBMITTED', SYSUTCDATETIME(), submitted_at),
        decided_by = IIF(@to IN ('APPROVED', 'RETURNED'), @actor_id, decided_by),
        decided_at = IIF(@to IN ('APPROVED', 'RETURNED'), SYSUTCDATETIME(), decided_at),
        decision_note = IIF(@to IN ('APPROVED', 'RETURNED'), @note, decision_note),
        paid_at = IIF(@to = 'PAID', SYSUTCDATETIME(), paid_at),
        updated_at = SYSUTCDATETIME(), updated_by = @actor_id
    WHERE id = @trip_id AND row_version = @row_version;
    IF @@ROWCOUNT = 0
        THROW 51901, N'The record was changed by someone else. Reload it and try again.', 1;
    EXEC crm.trip_select @trip_id = @trip_id;
END;
