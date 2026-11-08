-- Makes to suggest (ADR-0018): the common ones and those already used in the fleet, alphabetically.
CREATE OR ALTER PROCEDURE app.car_make_list
    @actor_id int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    SELECT make FROM (
        SELECT value AS make FROM STRING_SPLIT(N'Audi,BMW,Citroën,Dacia,Fiat,Ford,Honda,Hyundai,Iveco,Kia,Mazda,Mercedes-Benz,'
            + N'Mitsubishi,Nissan,Opel,Peugeot,Renault,Seat,Škoda,Suzuki,Tesla,Toyota,Volkswagen,Volvo', N',')
        UNION
        SELECT DISTINCT make FROM crm.cars WHERE make IS NOT NULL
    ) AS m
    ORDER BY make;
END;
