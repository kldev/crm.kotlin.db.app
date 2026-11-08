/*
  Internal (ADR-0018): a handover's terms and the overlap rules. The planned return not before the issue (51230),
  mileage 0-5 000 000 km and fuel 0-100 % (51231), an active holder (51402). One handover per car at a time (51923) and
  one car per person at a time (51924): days are inclusive - "until the 12th" then "from the 13th" is fine, "from the
  12th" is not; no planned return is open-ended; a returned handover ends on its return day.
*/
CREATE OR ALTER PROCEDURE crm.handover_check
    @car_id         int,
    @holder_user_id int,
    @issue_date     date,
    @planned_return date,
    @issue_mileage  int,
    @issue_fuel     int,
    @except_id      bigint = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    IF @issue_date IS NULL OR @planned_return < @issue_date
        THROW 51230, N'The planned return is not before the issue day.', 1;
    IF @issue_mileage IS NULL OR @issue_mileage NOT BETWEEN 0 AND 5000000 OR @issue_fuel IS NULL OR @issue_fuel NOT BETWEEN 0 AND 100
        THROW 51231, N'Mileage is 0 to 5 000 000 km and fuel 0 to 100 %.', 1;
    IF NOT EXISTS (SELECT 1 FROM crm.users WHERE id = @holder_user_id AND is_active = 1)
        THROW 51402, N'User not found.', 1;
    DECLARE @to date = ISNULL(@planned_return, '9999-12-31');
    IF EXISTS (SELECT 1 FROM crm.car_handovers WITH (UPDLOCK, HOLDLOCK)
               WHERE car_id = @car_id AND cancelled_at IS NULL AND id <> ISNULL(@except_id, 0)
                 AND issue_date <= @to AND ISNULL(returned_on, ISNULL(planned_return, '9999-12-31')) >= @issue_date)
        THROW 51923, N'The car is handed over to someone else in that time.', 1;
    IF EXISTS (SELECT 1 FROM crm.car_handovers WITH (UPDLOCK, HOLDLOCK)
               WHERE holder_user_id = @holder_user_id AND cancelled_at IS NULL AND id <> ISNULL(@except_id, 0)
                 AND issue_date <= @to AND ISNULL(returned_on, ISNULL(planned_return, '9999-12-31')) >= @issue_date)
        THROW 51924, N'That person has another car in that time.', 1;
END;
