-- One car (ADR-0018); 51409 when there is none. Money only for ADMIN and MANAGER.
CREATE OR ALTER PROCEDURE app.car_get
    @actor_id int,
    @car_id   int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @role varchar(10);
    EXEC crm.actor_require @actor_id, @role OUTPUT;
    IF NOT EXISTS (SELECT 1 FROM crm.cars WHERE id = @car_id)
        THROW 51409, N'Car not found.', 1;
    DECLARE @money bit = IIF(@role IN ('ADMIN', 'MANAGER'), 1, 0);
    EXEC crm.car_select @car_id = @car_id, @show_money = @money;
END;
