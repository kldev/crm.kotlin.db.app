/*
  Hand a car over to a person (ADR-0018) - managers - from a day (past, today or planned), until a planned return or
  open-ended, with the mileage and fuel at issue. Not a car for sale or archived (51925). The checks and overlap rules
  are crm.handover_check's. A car at a repair shop may be handed over; the row then carries a warning.
*/
CREATE OR ALTER PROCEDURE app.car_handover_create
    @actor_id       int,
    @car_id         int,
    @holder_user_id int,
    @issue_date     date,
    @planned_return date           = NULL,
    @issue_mileage  int,
    @issue_fuel     int,
    @notes          nvarchar(4000) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.fleet_require_manager @actor_id;
    DECLARE @status varchar(20), @shop nvarchar(120);
    SELECT @status = c.status, @shop = p.name FROM crm.cars AS c LEFT JOIN crm.fleet_partners AS p ON p.id = c.repair_shop_id WHERE c.id = @car_id;
    IF @status IS NULL
        THROW 51409, N'Car not found.', 1;
    IF @status IN ('FOR_SALE', 'ARCHIVED')
        THROW 51925, N'A car for sale or archived is not handed over.', 1;
    SET @notes = NULLIF(LTRIM(RTRIM(@notes)), N'');
    IF LEN(@notes) > 1000
        THROW 51224, N'The notes have at most 1000 characters.', 1;
    BEGIN TRANSACTION;
    EXEC crm.handover_check @car_id, @holder_user_id, @issue_date, @planned_return, @issue_mileage, @issue_fuel;
    INSERT crm.car_handovers (car_id, holder_user_id, issue_date, planned_return, issue_mileage, issue_fuel, notes, issued_by)
    VALUES (@car_id, @holder_user_id, @issue_date, @planned_return, @issue_mileage, @issue_fuel, @notes, @actor_id);
    DECLARE @id bigint = SCOPE_IDENTITY();
    COMMIT;
    DECLARE @rows TABLE (id bigint, car_id int, car_name nvarchar(100), plate varchar(15), holder_user_id int,
        holder_name nvarchar(200), issue_date date, planned_return date, issue_mileage int, issue_fuel tinyint,
        notes nvarchar(1000), issued_by int, issued_by_name nvarchar(200), issued_at datetime2(3), returned_on date,
        return_mileage int, return_fuel tinyint, cancelled_at datetime2(3), cancel_reason nvarchar(400), state varchar(10),
        row_version binary(8));
    INSERT @rows EXEC crm.handover_select @handover_id = @id;
    SELECT r.*, IIF(@status IN ('TO_REPAIR_SHOP', 'IN_REPAIR_SHOP', 'READY_FOR_PICKUP'), CONCAT(N'REPAIR_SHOP:', @shop), NULL) AS warning
    FROM @rows AS r;
END;
