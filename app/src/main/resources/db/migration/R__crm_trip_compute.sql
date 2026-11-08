/*
  Internal (ADR-0019): the settlement of a trip, stored on the trip after every change. Per diems by the length H of
  the trip at the rate valid on its first day:
    domestic - up to a day: under 8 h none, 8-12 h half, over 12 h one; longer: each full day one, the rest up to 8 h
               half, over 8 h one;
    abroad   - each full day one, the rest up to 8 h a third, 8-12 h half, over 12 h one.
  Meals provided reduce the per diems: domestic breakfast 25 %, lunch 50 %, dinner 25 % of the rate; abroad 15 %,
  30 %, 30 % - never below zero. Lump sums: a night without an invoice 150 % of the diet (abroad 25 % of the hotel
  limit); local transport without tickets 20 % of the diet per started day (abroad 10 %). Mileage of a private car:
  km x the rate of the vehicle. Expenses: the sum of the lines. Total = per diems - meals + lump sums + mileage +
  expenses; the advance is taken off on read.
*/
CREATE OR ALTER PROCEDURE crm.trip_compute
    @trip_id bigint
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @country char(2), @start datetime2(0), @end datetime2(0), @b int, @l int, @d int, @nights int, @local bit,
            @vehicle varchar(12), @km int, @transport varchar(12);
    SELECT @country = country, @start = starts_at, @end = ends_at, @b = breakfasts, @l = lunches, @d = dinners,
           @nights = lump_nights, @local = local_transport, @vehicle = vehicle, @km = kilometres, @transport = transport
    FROM crm.trips WHERE id = @trip_id;

    DECLARE @rate decimal(10, 2), @limit decimal(10, 2), @currency char(3);
    SELECT TOP (1) @rate = diet, @limit = hotel_limit, @currency = currency
    FROM crm.trip_diet_rates WHERE country = @country AND valid_from <= CAST(@start AS date) ORDER BY valid_from DESC;

    DECLARE @hours decimal(10, 4) = DATEDIFF(MINUTE, @start, @end) / 60.0;
    DECLARE @full int = FLOOR(@hours / 24), @rest decimal(10, 4) = @hours - 24 * FLOOR(@hours / 24);
    DECLARE @started_days int = CEILING(@hours / 24);
    -- Exact (a third is 0.333...); the stored count is rounded, the amount comes from the exact one.
    DECLARE @diets decimal(12, 6) =
        CASE WHEN @country = 'PL' AND @hours <= 24
                 THEN CASE WHEN @hours < 8 THEN 0 WHEN @hours <= 12 THEN 0.5 ELSE 1 END
             WHEN @country = 'PL'
                 THEN @full + CASE WHEN @rest = 0 THEN 0 WHEN @rest <= 8 THEN 0.5 ELSE 1 END
             ELSE @full + CASE WHEN @rest = 0 THEN 0 WHEN @rest <= 8 THEN CAST(1 AS decimal(12, 6)) / 3 WHEN @rest <= 12 THEN 0.5 ELSE 1 END
        END;
    DECLARE @diet_amount decimal(12, 2) = ROUND(@diets * @rate, 2);
    DECLARE @meals decimal(12, 2) = ROUND(@rate * IIF(@country = 'PL', @b * 0.25 + @l * 0.50 + @d * 0.25, @b * 0.15 + @l * 0.30 + @d * 0.30), 2);
    IF @meals > @diet_amount SET @meals = @diet_amount;
    DECLARE @lump decimal(12, 2) = ROUND(
        @nights * IIF(@country = 'PL', 1.5 * @rate, 0.25 * @limit)
        + IIF(@local = 1, @started_days * IIF(@country = 'PL', 0.2, 0.1) * @rate, 0), 2);
    DECLARE @mileage decimal(12, 2) = 0;
    IF @transport = 'PRIVATE_CAR'
        SET @mileage = ROUND(ISNULL(@km, 0) * ISNULL((SELECT TOP (1) rate FROM crm.trip_mileage_rates
                                                      WHERE vehicle = @vehicle AND valid_from <= CAST(@start AS date)
                                                      ORDER BY valid_from DESC), 0), 2);
    DECLARE @expenses decimal(12, 2) = ISNULL((SELECT SUM(amount) FROM crm.trip_expenses WHERE trip_id = @trip_id), 0);

    UPDATE crm.trips
    SET currency = @currency, diet_rate = @rate, diets = ROUND(@diets, 2), diet_amount = @diet_amount, meal_deduction = @meals,
        lump_amount = @lump, mileage_amount = @mileage, expenses_amount = @expenses,
        total = @diet_amount - @meals + @lump + @mileage + @expenses
    WHERE id = @trip_id;
END;
