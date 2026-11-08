-- Change a planned trip or one returned for corrections (ADR-0019) - the traveller or a manager; recomputed. rowVersion (51901).
CREATE OR ALTER PROCEDURE app.trip_update
    @actor_id          int,
    @trip_id           bigint,
    @purpose           varchar(14),
    @client_id         bigint         = NULL,
    @project_id        bigint         = NULL,
    @event_name        nvarchar(4000) = NULL,
    @description       nvarchar(4000) = NULL,
    @destination       nvarchar(4000),
    @country           char(2)        = 'PL',
    @starts_at         datetime2(0),
    @ends_at           datetime2(0),
    @transport         varchar(12),
    @car_id            int            = NULL,
    @vehicle           varchar(12)    = NULL,
    @kilometres        int            = NULL,
    @breakfasts        int            = 0,
    @lunches           int            = 0,
    @dinners           int            = 0,
    @lump_nights       int            = 0,
    @local_transport   bit            = 0,
    @advance           decimal(20, 4) = 0,
    @legal_entity_id   int            = NULL,
    @row_version       binary(8)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.trip_require @actor_id, @trip_id, 1;
    EXEC crm.trip_check @purpose, @client_id, @project_id, @event_name OUTPUT, @description OUTPUT, @destination OUTPUT,
         @country, @starts_at, @ends_at, @transport, @car_id, @vehicle, @kilometres, @breakfasts, @lunches, @dinners,
         @lump_nights, @advance;
    SET @legal_entity_id = ISNULL(@legal_entity_id, ISNULL((SELECT legal_entity_id FROM crm.projects WHERE id = @project_id), 1));
    IF NOT EXISTS (SELECT 1 FROM crm.legal_entities WHERE id = @legal_entity_id)
        THROW 51408, N'Company not found.', 1;
    BEGIN TRANSACTION;
    UPDATE crm.trips
    SET legal_entity_id = @legal_entity_id, purpose = @purpose, client_id = IIF(@purpose = 'CLIENT_VISIT', @client_id, NULL),
        project_id = IIF(@purpose = 'PROJECT_SITE', @project_id, NULL), event_name = IIF(@purpose = 'TRADE_FAIR', @event_name, NULL),
        description = @description, destination = @destination, country = @country, starts_at = @starts_at, ends_at = @ends_at,
        transport = @transport, car_id = IIF(@transport = 'COMPANY_CAR', @car_id, NULL),
        vehicle = IIF(@transport = 'PRIVATE_CAR', @vehicle, NULL), kilometres = IIF(@transport = 'PRIVATE_CAR', @kilometres, NULL),
        breakfasts = ISNULL(@breakfasts, 0), lunches = ISNULL(@lunches, 0), dinners = ISNULL(@dinners, 0),
        lump_nights = ISNULL(@lump_nights, 0), local_transport = ISNULL(@local_transport, 0), advance = @advance,
        updated_at = SYSUTCDATETIME(), updated_by = @actor_id
    WHERE id = @trip_id AND row_version = @row_version;
    IF @@ROWCOUNT = 0
        THROW 51901, N'The record was changed by someone else. Reload it and try again.', 1;
    EXEC crm.trip_compute @trip_id;
    COMMIT;
    EXEC crm.trip_select @trip_id = @trip_id;
END;
