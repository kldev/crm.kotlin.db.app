-- The rates in force (ADR-0019): per diem and hotel limit per country, mileage per vehicle - for the forms and the settlement.
CREATE OR ALTER PROCEDURE app.trip_rate_list
    @actor_id int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    SELECT 'COUNTRY' AS kind, r.country AS code, r.name_pl, r.name_en, r.currency, r.diet AS amount, r.hotel_limit, r.valid_from
    FROM crm.trip_diet_rates AS r
    WHERE r.valid_from = (SELECT MAX(x.valid_from) FROM crm.trip_diet_rates AS x
                          WHERE x.country = r.country AND x.valid_from <= SYSUTCDATETIME())
    UNION ALL
    SELECT 'VEHICLE', m.vehicle, m.name_pl, m.name_en, 'PLN', m.rate, NULL, m.valid_from
    FROM crm.trip_mileage_rates AS m
    WHERE m.valid_from = (SELECT MAX(x.valid_from) FROM crm.trip_mileage_rates AS x
                          WHERE x.vehicle = m.vehicle AND x.valid_from <= SYSUTCDATETIME())
    ORDER BY kind, code;
END;
