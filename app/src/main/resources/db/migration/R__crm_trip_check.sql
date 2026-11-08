/*
  Internal (ADR-0019): a trip's data. The purpose and what it needs - a client (51237), the event's name (51238), a
  project (51239); a destination of 1-120 and a country with a rate (51240); the end after the start, at most 60 days
  (51241); the transport - a car of the fleet, or for a private car the vehicle and 1-10 000 km, domestic only (51242);
  meals and lump-sum nights not more than the trip has days and nights (51243); an advance of 0 or more (51244); a
  description up to 1000 (51245).
*/
CREATE OR ALTER PROCEDURE crm.trip_check
    @purpose     varchar(14),
    @client_id   bigint,
    @project_id  bigint,
    @event_name  nvarchar(4000) OUTPUT,
    @description nvarchar(4000) OUTPUT,
    @destination nvarchar(4000) OUTPUT,
    @country     char(2),
    @starts_at   datetime2(0),
    @ends_at     datetime2(0),
    @transport   varchar(12),
    @car_id      int,
    @vehicle     varchar(12),
    @kilometres  int,
    @breakfasts  int,
    @lunches     int,
    @dinners     int,
    @lump_nights int,
    @advance     decimal(20, 4)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    SELECT @event_name = NULLIF(LTRIM(RTRIM(@event_name)), N''), @description = LTRIM(RTRIM(ISNULL(@description, N''))),
           @destination = NULLIF(LTRIM(RTRIM(@destination)), N'');
    IF ISNULL(@purpose, '') NOT IN ('CLIENT_VISIT', 'TRADE_FAIR', 'PROJECT_SITE', 'OTHER')
       OR (@purpose = 'CLIENT_VISIT' AND NOT EXISTS (SELECT 1 FROM crm.clients WHERE id = @client_id))
        THROW 51237, N'A visit is to a client of the list.', 1;
    IF @purpose = 'TRADE_FAIR' AND (@event_name IS NULL OR LEN(@event_name) > 200)
        THROW 51238, N'Name the trade fair or event (at most 200 characters).', 1;
    IF (@purpose = 'PROJECT_SITE' AND NOT EXISTS (SELECT 1 FROM crm.projects WHERE id = @project_id))
        THROW 51239, N'A project-site trip names a project.', 1;
    IF @destination IS NULL OR LEN(@destination) > 120 OR NOT EXISTS (SELECT 1 FROM crm.trip_diet_rates WHERE country = @country)
        THROW 51240, N'The destination (at most 120 characters) and a country of the list.', 1;
    IF @starts_at IS NULL OR @ends_at IS NULL OR @ends_at <= @starts_at OR DATEDIFF(DAY, @starts_at, @ends_at) > 60
        THROW 51241, N'The trip ends after it starts and lasts at most 60 days.', 1;
    IF ISNULL(@transport, '') NOT IN ('COMPANY_CAR', 'PRIVATE_CAR', 'TRAIN', 'PLANE', 'BUS', 'OTHER')
       OR (@transport = 'COMPANY_CAR' AND @car_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM crm.cars WHERE id = @car_id))
       OR (@transport = 'PRIVATE_CAR' AND (@country <> 'PL'
           OR NOT EXISTS (SELECT 1 FROM crm.trip_mileage_rates WHERE vehicle = @vehicle)
           OR @kilometres IS NULL OR @kilometres NOT BETWEEN 1 AND 10000))
        THROW 51242, N'The transport: a car of the fleet, or a private car with the vehicle and 1-10 000 km (domestic trips).', 1;
    DECLARE @days int = CEILING(DATEDIFF(MINUTE, @starts_at, @ends_at) / 1440.0);
    IF ISNULL(@breakfasts, 0) NOT BETWEEN 0 AND @days OR ISNULL(@lunches, 0) NOT BETWEEN 0 AND @days
       OR ISNULL(@dinners, 0) NOT BETWEEN 0 AND @days OR ISNULL(@lump_nights, 0) NOT BETWEEN 0 AND @days
        THROW 51243, N'Meals and nights: from 0 to the number of the trip''s days.', 1;
    IF @advance IS NULL OR @advance < 0 OR @advance <> ROUND(@advance, 2) OR @advance > 1000000
        THROW 51244, N'The advance is 0 or more, with at most 2 decimals.', 1;
    IF LEN(@description) > 1000
        THROW 51245, N'The description has at most 1000 characters.', 1;
END;
