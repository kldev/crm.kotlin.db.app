/*
  Internal (ADR-0018): handover rows - one (@handover_id), a car's (@car_id) or a person's live ones (@holder_user_id),
  newest first. The state is computed for today in Warsaw: CANCELLED, RETURNED, PLANNED (starts later), OVERDUE (past
  its planned return), CURRENT.
*/
CREATE OR ALTER PROCEDURE crm.handover_select
    @handover_id    bigint = NULL,
    @car_id         int    = NULL,
    @holder_user_id int    = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @today date = crm.fleet_today();
    SELECT h.id, h.car_id, c.name AS car_name, c.plate, h.holder_user_id, hu.display_name AS holder_name, h.issue_date,
           h.planned_return, h.issue_mileage, h.issue_fuel, h.notes, h.issued_by, ib.display_name AS issued_by_name,
           h.issued_at, h.returned_on, h.return_mileage, h.return_fuel, h.cancelled_at, h.cancel_reason,
           CASE WHEN h.cancelled_at IS NOT NULL THEN 'CANCELLED' WHEN h.returned_on IS NOT NULL THEN 'RETURNED'
                WHEN h.issue_date > @today THEN 'PLANNED' WHEN h.planned_return < @today THEN 'OVERDUE'
                ELSE 'CURRENT' END AS state,
           h.row_version
    FROM crm.car_handovers AS h
    JOIN crm.cars AS c ON c.id = h.car_id
    JOIN crm.users AS hu ON hu.id = h.holder_user_id
    JOIN crm.users AS ib ON ib.id = h.issued_by
    WHERE (@handover_id IS NOT NULL AND h.id = @handover_id)
       OR (@car_id IS NOT NULL AND h.car_id = @car_id)
       OR (@holder_user_id IS NOT NULL AND h.holder_user_id = @holder_user_id AND h.cancelled_at IS NULL
           AND (h.returned_on IS NULL OR h.returned_on >= DATEADD(DAY, -30, @today)))
    ORDER BY h.issue_date DESC, h.id DESC;
END;
