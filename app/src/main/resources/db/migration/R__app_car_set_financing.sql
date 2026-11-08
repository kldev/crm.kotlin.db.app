/*
  How a car is financed (ADR-0018) - managers: UNKNOWN; PAID with the purchase date; LEASING with a leasing company of
  the list, a monthly instalment > 0 with 2 decimals, a currency, the start and 1-120 months, a contract number up to 60.
  The lease ends at start + months - 1 day (computed on read). Anything else: 51226. rowVersion required.
*/
CREATE OR ALTER PROCEDURE app.car_set_financing
    @actor_id      int,
    @car_id        int,
    @financing     varchar(10),
    @purchase_date date           = NULL,
    @leasing_id    int            = NULL,
    @instalment    decimal(20, 4) = NULL,
    @currency      char(3)        = NULL,
    @lease_start   date           = NULL,
    @lease_months  int            = NULL,
    @contract_no   nvarchar(4000) = NULL,
    @row_version   binary(8)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.fleet_require_manager @actor_id;
    IF NOT EXISTS (SELECT 1 FROM crm.cars WHERE id = @car_id)
        THROW 51409, N'Car not found.', 1;
    SET @contract_no = NULLIF(LTRIM(RTRIM(@contract_no)), N'');
    IF ISNULL(@financing, '') NOT IN ('UNKNOWN', 'PAID', 'LEASING')
       OR (@financing = 'PAID' AND @purchase_date IS NULL)
       OR (@financing = 'LEASING' AND (
              NOT EXISTS (SELECT 1 FROM crm.fleet_partners WHERE id = @leasing_id AND kind = 'LEASING' AND is_hidden = 0)
              OR @instalment IS NULL OR @instalment <= 0 OR @instalment <> ROUND(@instalment, 2) OR @instalment > 9999999999
              OR @currency IS NULL OR @currency LIKE '%[^A-Z]%' OR LEN(@currency) <> 3
              OR @lease_start IS NULL OR @lease_months IS NULL OR @lease_months NOT BETWEEN 1 AND 120
              OR LEN(@contract_no) > 60))
        THROW 51226, N'Financing: unknown, paid with the purchase date, or leasing with a company, instalment, currency, start and 1-120 months.', 1;
    UPDATE crm.cars
    SET financing = @financing,
        purchase_date = IIF(@financing = 'PAID', @purchase_date, NULL),
        leasing_id = IIF(@financing = 'LEASING', @leasing_id, NULL),
        instalment = IIF(@financing = 'LEASING', @instalment, NULL),
        currency = IIF(@financing = 'LEASING', @currency, NULL),
        lease_start = IIF(@financing = 'LEASING', @lease_start, NULL),
        lease_months = IIF(@financing = 'LEASING', @lease_months, NULL),
        contract_no = IIF(@financing = 'LEASING', @contract_no, NULL),
        updated_at = SYSUTCDATETIME(), updated_by = @actor_id
    WHERE id = @car_id AND row_version = @row_version;
    IF @@ROWCOUNT = 0
        THROW 51901, N'The record was changed by someone else. Reload it and try again.', 1;
    EXEC crm.car_select @car_id = @car_id, @show_money = 1;
END;
