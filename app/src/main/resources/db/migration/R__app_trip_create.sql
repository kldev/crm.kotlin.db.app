/*
  Plan a business trip (ADR-0019), numbered DEL/<year>/<nnnn>. The traveller is the actor; ADMIN and MANAGER may plan
  one for somebody else. The paying company is given, else the project's, else the first. Settlement computed at once.
*/
CREATE OR ALTER PROCEDURE app.trip_create
    @actor_id          int,
    @traveller_user_id int            = NULL,
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
    @legal_entity_id   int            = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @role varchar(10);
    EXEC crm.actor_require @actor_id, @role OUTPUT;
    SET @traveller_user_id = ISNULL(@traveller_user_id, @actor_id);
    IF @traveller_user_id <> @actor_id AND @role NOT IN ('ADMIN', 'MANAGER')
        THROW 51301, N'Only a manager plans a trip for somebody else.', 1;
    IF NOT EXISTS (SELECT 1 FROM crm.users WHERE id = @traveller_user_id AND is_active = 1)
        THROW 51402, N'User not found.', 1;
    EXEC crm.trip_check @purpose, @client_id, @project_id, @event_name OUTPUT, @description OUTPUT, @destination OUTPUT,
         @country, @starts_at, @ends_at, @transport, @car_id, @vehicle, @kilometres, @breakfasts, @lunches, @dinners,
         @lump_nights, @advance;
    SET @legal_entity_id = ISNULL(@legal_entity_id, ISNULL((SELECT legal_entity_id FROM crm.projects WHERE id = @project_id), 1));
    IF NOT EXISTS (SELECT 1 FROM crm.legal_entities WHERE id = @legal_entity_id)
        THROW 51408, N'Company not found.', 1;
    DECLARE @year smallint = YEAR(CAST((SYSUTCDATETIME() AT TIME ZONE 'UTC') AT TIME ZONE 'Central European Standard Time' AS date)), @seq int;
    BEGIN TRANSACTION;
    UPDATE crm.trip_numbers WITH (UPDLOCK, HOLDLOCK) SET @seq = last_used = last_used + 1 WHERE year = @year;
    IF @seq IS NULL
    BEGIN
        INSERT crm.trip_numbers (year, last_used) VALUES (@year, 1);
        SET @seq = 1;
    END;
    INSERT crm.trips (number, traveller_user_id, legal_entity_id, purpose, client_id, project_id, event_name, description,
                      destination, country, starts_at, ends_at, transport, car_id, vehicle, kilometres, breakfasts, lunches,
                      dinners, lump_nights, local_transport, advance, status, currency, created_by, updated_by)
    VALUES (CONCAT('DEL/', @year, '/', RIGHT(CONCAT('000', @seq), IIF(@seq > 9999, LEN(@seq), 4))), @traveller_user_id,
            @legal_entity_id, @purpose, IIF(@purpose = 'CLIENT_VISIT', @client_id, NULL),
            IIF(@purpose = 'PROJECT_SITE', @project_id, NULL), IIF(@purpose = 'TRADE_FAIR', @event_name, NULL), @description,
            @destination, @country, @starts_at, @ends_at, @transport, IIF(@transport = 'COMPANY_CAR', @car_id, NULL),
            IIF(@transport = 'PRIVATE_CAR', @vehicle, NULL), IIF(@transport = 'PRIVATE_CAR', @kilometres, NULL),
            ISNULL(@breakfasts, 0), ISNULL(@lunches, 0), ISNULL(@dinners, 0), ISNULL(@lump_nights, 0),
            ISNULL(@local_transport, 0), @advance, 'PLANNED', 'PLN', @actor_id, @actor_id);
    DECLARE @id bigint = SCOPE_IDENTITY();
    EXEC crm.trip_compute @id;
    COMMIT;
    EXEC crm.trip_select @trip_id = @id;
END;
