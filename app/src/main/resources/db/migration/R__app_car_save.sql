/*
  Add a car (@car_id NULL; status ACTIVE from today, the first row of its history) or change its data (rowVersion,
  51901) - managers (51301). A plate taken by a car in use is 2601 (409). A VIN is given once; changing one already
  given is an administrator's correction with a reason (51301 / 51225).
*/
CREATE OR ALTER PROCEDURE app.car_save
    @actor_id        int,
    @car_id          int            = NULL,
    @name            nvarchar(4000),
    @make            nvarchar(4000) = NULL,
    @production_year int            = NULL,
    @plate           varchar(100),
    @vin             varchar(100)   = NULL,
    @notes           nvarchar(4000) = NULL,
    @legal_entity_id int,
    @inspection_due  date           = NULL,
    @insurance_due   date           = NULL,
    @vin_reason      nvarchar(400)  = NULL,
    @row_version     binary(8)      = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @role varchar(10);
    EXEC crm.fleet_require_manager @actor_id, @role OUTPUT;
    EXEC crm.car_check @name OUTPUT, @make OUTPUT, @production_year, @plate OUTPUT, @vin OUTPUT, @notes OUTPUT, @legal_entity_id;
    DECLARE @today date = crm.fleet_today();
    IF @car_id IS NULL
    BEGIN
        BEGIN TRANSACTION;
        INSERT crm.cars (name, make, production_year, plate, vin, notes, legal_entity_id, status, status_since,
                         inspection_due, insurance_due, updated_by)
        VALUES (@name, @make, @production_year, @plate, @vin, @notes, @legal_entity_id, 'ACTIVE', @today,
                @inspection_due, @insurance_due, @actor_id);
        SET @car_id = SCOPE_IDENTITY();
        INSERT crm.car_status_history (car_id, status, effective_on, changed_by) VALUES (@car_id, 'ACTIVE', @today, @actor_id);
        COMMIT;
    END
    ELSE
    BEGIN
        DECLARE @old_vin char(17) = (SELECT vin FROM crm.cars WHERE id = @car_id);
        IF NOT EXISTS (SELECT 1 FROM crm.cars WHERE id = @car_id)
            THROW 51409, N'Car not found.', 1;
        IF @old_vin IS NOT NULL AND ISNULL(@vin, '') <> @old_vin
        BEGIN
            IF @role <> 'ADMIN'
                THROW 51301, N'Only an administrator corrects a VIN.', 1;
            IF NULLIF(LTRIM(RTRIM(@vin_reason)), N'') IS NULL
                THROW 51225, N'Say why the VIN is corrected.', 1;
        END;
        UPDATE crm.cars
        SET name = @name, make = @make, production_year = @production_year, plate = @plate, vin = @vin, notes = @notes,
            legal_entity_id = @legal_entity_id, inspection_due = @inspection_due, insurance_due = @insurance_due,
            updated_at = SYSUTCDATETIME(), updated_by = @actor_id
        WHERE id = @car_id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 51901, N'The record was changed by someone else. Reload it and try again.', 1;
        IF @old_vin IS NOT NULL AND ISNULL(@vin, '') <> @old_vin
            INSERT crm.car_status_history (car_id, status, effective_on, note, changed_by)
            SELECT id, status, @today, CONCAT(N'Korekta VIN ', @old_vin, N' -> ', ISNULL(@vin, N'-'), N': ', @vin_reason), @actor_id
            FROM crm.cars WHERE id = @car_id;
    END;
    EXEC crm.car_select @car_id = @car_id, @show_money = 1;
END;
