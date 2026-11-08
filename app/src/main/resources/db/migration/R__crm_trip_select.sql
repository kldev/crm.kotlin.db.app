/*
  Internal (ADR-0019): trip rows - one (@trip_id) or a page (@ids, in that order). With the traveller and their
  department, what the trip is for, the car, the settlement, what is left to pay (negative: to give back) and whether
  a hotel night is above the limit.
*/
CREATE OR ALTER PROCEDURE crm.trip_select
    @trip_id bigint        = NULL,
    @ids     nvarchar(max) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT t.id, t.number, t.traveller_user_id, u.display_name AS traveller_name, u.department AS traveller_department,
           t.legal_entity_id, le.name AS legal_entity_name, t.purpose, t.client_id, c.name AS client_name, t.project_id,
           p.name AS project_name, t.event_name, t.description, t.destination, t.country, r.name_pl AS country_name_pl,
           r.name_en AS country_name_en, t.starts_at, t.ends_at, t.transport, t.car_id, car.plate AS car_plate, t.vehicle,
           t.kilometres, t.breakfasts, t.lunches, t.dinners, t.lump_nights, t.local_transport, t.advance, t.status,
           t.submitted_at, t.decided_by, db.display_name AS decided_by_name, t.decided_at, t.decision_note, t.paid_at,
           t.currency, t.diet_rate, t.diets, t.diet_amount, t.meal_deduction, t.lump_amount, t.mileage_amount,
           t.expenses_amount, t.total, t.total - t.advance AS to_pay,
           CAST(IIF(EXISTS (SELECT 1 FROM crm.trip_expenses AS e
                            WHERE e.trip_id = t.id AND e.category = 'HOTEL' AND e.nights > 0
                              AND e.amount / e.nights > rl.hotel_limit), 1, 0) AS bit) AS hotel_over_limit,
           t.created_by, t.created_at, t.updated_at, t.row_version
    FROM crm.trips AS t
    JOIN crm.users AS u ON u.id = t.traveller_user_id
    JOIN crm.legal_entities AS le ON le.id = t.legal_entity_id
    OUTER APPLY (SELECT TOP (1) name_pl, name_en FROM crm.trip_diet_rates AS x WHERE x.country = t.country ORDER BY x.valid_from DESC) AS r
    OUTER APPLY (SELECT TOP (1) hotel_limit FROM crm.trip_diet_rates AS x
                 WHERE x.country = t.country AND x.valid_from <= CAST(t.starts_at AS date) ORDER BY x.valid_from DESC) AS rl
    LEFT JOIN crm.clients AS c ON c.id = t.client_id
    LEFT JOIN crm.projects AS p ON p.id = t.project_id
    LEFT JOIN crm.cars AS car ON car.id = t.car_id
    LEFT JOIN crm.users AS db ON db.id = t.decided_by
    LEFT JOIN (SELECT CAST(value AS bigint) AS id, ordinal FROM STRING_SPLIT(@ids, ',', 1)) AS o ON o.id = t.id
    WHERE (@trip_id IS NOT NULL AND t.id = @trip_id) OR (@ids IS NOT NULL AND o.id IS NOT NULL)
    ORDER BY o.ordinal;
END;
