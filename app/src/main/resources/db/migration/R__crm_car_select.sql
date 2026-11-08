/*
  Internal (ADR-0018): the car row every fleet read returns. Availability is computed for today in Warsaw: OVERDUE (a
  handover past its planned return), HANDED_OVER, or FREE (a planned handover leaves the car free today). The holder is
  the current handover's, else the next one's. Money (instalment, contract) only when @show_money = 1.
*/
CREATE OR ALTER PROCEDURE crm.car_select
    @car_id     int = NULL,
    @show_money bit = 0,
    @ids        nvarchar(max) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @today date = crm.fleet_today();
    SELECT c.id, c.name, c.make, c.production_year, c.plate, c.vin, c.notes, c.legal_entity_id, le.name AS legal_entity_name,
           c.status, st.name_pl AS status_name_pl, st.name_en AS status_name_en, c.status_since, c.repair_shop_id,
           rs.name AS repair_shop_name, c.financing, c.purchase_date, c.leasing_id, ls.name AS leasing_name,
           IIF(@show_money = 1, c.instalment, NULL) AS instalment, c.currency, c.lease_start, c.lease_months,
           IIF(c.lease_start IS NULL, NULL, DATEADD(DAY, -1, DATEADD(MONTH, c.lease_months, c.lease_start))) AS lease_end,
           IIF(@show_money = 1, c.contract_no, NULL) AS contract_no, c.inspection_due, c.insurance_due,
           CASE WHEN cur.id IS NULL THEN 'FREE' WHEN cur.planned_return < @today THEN 'OVERDUE' ELSE 'HANDED_OVER' END AS availability,
           h.id AS handover_id, h.holder_user_id, hu.display_name AS holder_name, h.issue_date AS holder_from,
           h.planned_return AS holder_until, CAST(IIF(cur.id IS NULL AND h.id IS NOT NULL, 1, 0) AS bit) AS holder_planned,
           c.created_at, c.updated_at, c.row_version
    FROM crm.cars AS c
    JOIN crm.legal_entities AS le ON le.id = c.legal_entity_id
    JOIN crm.car_statuses AS st ON st.status = c.status
    LEFT JOIN crm.fleet_partners AS rs ON rs.id = c.repair_shop_id
    LEFT JOIN crm.fleet_partners AS ls ON ls.id = c.leasing_id
    OUTER APPLY (SELECT TOP (1) x.id, x.planned_return FROM crm.car_handovers AS x
                 WHERE x.car_id = c.id AND x.cancelled_at IS NULL AND x.returned_on IS NULL AND x.issue_date <= @today
                 ORDER BY x.issue_date DESC) AS cur
    OUTER APPLY (SELECT TOP (1) x.id, x.holder_user_id, x.issue_date, x.planned_return FROM crm.car_handovers AS x
                 WHERE x.car_id = c.id AND x.cancelled_at IS NULL AND x.returned_on IS NULL
                   AND (x.id = cur.id OR (cur.id IS NULL AND x.issue_date > @today))
                 ORDER BY x.issue_date) AS h
    LEFT JOIN crm.users AS hu ON hu.id = h.holder_user_id
    WHERE (@car_id IS NOT NULL AND c.id = @car_id)
       OR (@ids IS NOT NULL AND c.id IN (SELECT CAST(value AS int) FROM STRING_SPLIT(@ids, ',')))
    ORDER BY c.name, c.id;
END;
