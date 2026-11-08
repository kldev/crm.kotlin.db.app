/*
  Business trips (ADR-0019): who travels where and why - a client, a trade fair, a project site - and the settlement
  under the Polish rules for business travel: per diems by the length of the trip less the meals provided, lump sums
  for nights and local transport, mileage for a private car, expenses with documents, less the advance. The rates are
  data with the day they apply from, so a new regulation is a new row.
*/
CREATE TABLE crm.trip_diet_rates
(
    country     char(2)        NOT NULL,
    valid_from  date           NOT NULL,
    currency    char(3)        NOT NULL,
    diet        decimal(10, 2) NOT NULL,
    -- The limit of a hotel night with an invoice; above it the settlement shows a warning.
    hotel_limit decimal(10, 2) NOT NULL,
    name_pl     nvarchar(60)   NOT NULL,
    name_en     nvarchar(60)   NOT NULL,
    CONSTRAINT pk_trip_diet_rates PRIMARY KEY CLUSTERED (country, valid_from)
);
-- Domestic: the regulation of 2022 (45 zł; a night 20 x the diet). Abroad: its annex for the countries used here.
INSERT crm.trip_diet_rates (country, valid_from, currency, diet, hotel_limit, name_pl, name_en)
VALUES ('PL', '2023-01-01', 'PLN', 45.00, 900.00, N'Polska', N'Poland'),
       ('DE', '2023-01-01', 'EUR', 49.00, 170.00, N'Niemcy', N'Germany'),
       ('FR', '2023-01-01', 'EUR', 55.00, 200.00, N'Francja', N'France'),
       ('BE', '2023-01-01', 'EUR', 55.00, 200.00, N'Belgia', N'Belgium'),
       ('CZ', '2023-01-01', 'EUR', 41.00, 120.00, N'Czechy', N'Czechia'),
       ('GB', '2023-01-01', 'GBP', 45.00, 220.00, N'Wielka Brytania', N'United Kingdom');

CREATE TABLE crm.trip_mileage_rates
(
    vehicle    varchar(12)   NOT NULL,
    valid_from date          NOT NULL,
    rate       decimal(6, 4) NOT NULL,
    name_pl    nvarchar(60)  NOT NULL,
    name_en    nvarchar(60)  NOT NULL,
    CONSTRAINT pk_trip_mileage_rates PRIMARY KEY CLUSTERED (vehicle, valid_from)
);
INSERT crm.trip_mileage_rates (vehicle, valid_from, rate, name_pl, name_en)
VALUES ('CAR_GT_900', '2023-01-17', 1.1500, N'Samochód powyżej 900 cm³', N'Car over 900 cc'),
       ('CAR_LE_900', '2023-01-17', 0.8900, N'Samochód do 900 cm³', N'Car up to 900 cc'),
       ('MOTORCYCLE', '2023-01-17', 0.6900, N'Motocykl', N'Motorcycle'),
       ('MOPED', '2023-01-17', 0.4200, N'Motorower', N'Moped');

CREATE TABLE crm.trip_numbers
(
    year      smallint NOT NULL,
    last_used int      NOT NULL,
    CONSTRAINT pk_trip_numbers PRIMARY KEY CLUSTERED (year)
);

CREATE TABLE crm.trips
(
    id                 bigint IDENTITY (1, 1) NOT NULL,
    number             varchar(20)            NOT NULL,
    traveller_user_id  int                    NOT NULL,
    legal_entity_id    int                    NOT NULL,
    -- CLIENT_VISIT (client), TRADE_FAIR (event), PROJECT_SITE (project), OTHER.
    purpose            varchar(14)            NOT NULL,
    client_id          bigint                 NULL,
    project_id         bigint                 NULL,
    event_name         nvarchar(200)          NULL,
    description        nvarchar(1000)         NOT NULL CONSTRAINT df_trips_description DEFAULT (N''),
    destination        nvarchar(120)          NOT NULL,
    country            char(2)                NOT NULL,
    -- Start and end as instants (UTC); the length decides the per diems.
    starts_at          datetime2(0)           NOT NULL,
    ends_at            datetime2(0)           NOT NULL,
    -- COMPANY_CAR (a car of the fleet), PRIVATE_CAR (vehicle and km), TRAIN, PLANE, BUS, OTHER.
    transport          varchar(12)            NOT NULL,
    car_id             int                    NULL,
    vehicle            varchar(12)            NULL,
    kilometres         int                    NULL,
    breakfasts         smallint               NOT NULL CONSTRAINT df_trips_breakfasts DEFAULT (0),
    lunches            smallint               NOT NULL CONSTRAINT df_trips_lunches DEFAULT (0),
    dinners            smallint               NOT NULL CONSTRAINT df_trips_dinners DEFAULT (0),
    -- Nights without a hotel invoice: the lump sum; local transport without tickets: the lump sum per day.
    lump_nights        smallint               NOT NULL CONSTRAINT df_trips_lump_nights DEFAULT (0),
    local_transport    bit                    NOT NULL CONSTRAINT df_trips_local_transport DEFAULT (0),
    advance            decimal(12, 2)         NOT NULL CONSTRAINT df_trips_advance DEFAULT (0),
    -- PLANNED -> SUBMITTED -> APPROVED -> PAID; SUBMITTED -> RETURNED -> SUBMITTED; PLANNED -> CANCELLED.
    status             varchar(10)            NOT NULL,
    submitted_at       datetime2(3)           NULL,
    decided_by         int                    NULL,
    decided_at         datetime2(3)           NULL,
    decision_note      nvarchar(400)          NULL,
    paid_at            datetime2(3)           NULL,
    -- The settlement as computed by crm.trip_compute on every change (currency of the country).
    currency           char(3)                NOT NULL,
    diet_rate          decimal(10, 2)         NOT NULL CONSTRAINT df_trips_diet_rate DEFAULT (0),
    diets              decimal(6, 2)          NOT NULL CONSTRAINT df_trips_diets DEFAULT (0),
    diet_amount        decimal(12, 2)         NOT NULL CONSTRAINT df_trips_diet_amount DEFAULT (0),
    meal_deduction     decimal(12, 2)         NOT NULL CONSTRAINT df_trips_meal_deduction DEFAULT (0),
    lump_amount        decimal(12, 2)         NOT NULL CONSTRAINT df_trips_lump_amount DEFAULT (0),
    mileage_amount     decimal(12, 2)         NOT NULL CONSTRAINT df_trips_mileage_amount DEFAULT (0),
    expenses_amount    decimal(12, 2)         NOT NULL CONSTRAINT df_trips_expenses_amount DEFAULT (0),
    total              decimal(12, 2)         NOT NULL CONSTRAINT df_trips_total DEFAULT (0),
    created_by         int                    NOT NULL,
    created_at         datetime2(3)           NOT NULL CONSTRAINT df_trips_created_at DEFAULT (SYSUTCDATETIME()),
    updated_at         datetime2(3)           NOT NULL CONSTRAINT df_trips_updated_at DEFAULT (SYSUTCDATETIME()),
    updated_by         int                    NULL,
    row_version        rowversion             NOT NULL,
    CONSTRAINT pk_trips PRIMARY KEY CLUSTERED (id),
    CONSTRAINT uq_trips_number UNIQUE (number),
    CONSTRAINT fk_trips_traveller FOREIGN KEY (traveller_user_id) REFERENCES crm.users (id),
    CONSTRAINT fk_trips_legal_entity FOREIGN KEY (legal_entity_id) REFERENCES crm.legal_entities (id),
    CONSTRAINT fk_trips_client FOREIGN KEY (client_id) REFERENCES crm.clients (id),
    CONSTRAINT fk_trips_project FOREIGN KEY (project_id) REFERENCES crm.projects (id),
    CONSTRAINT fk_trips_car FOREIGN KEY (car_id) REFERENCES crm.cars (id),
    CONSTRAINT ck_trips_purpose CHECK (purpose IN ('CLIENT_VISIT', 'TRADE_FAIR', 'PROJECT_SITE', 'OTHER')),
    CONSTRAINT ck_trips_transport CHECK (transport IN ('COMPANY_CAR', 'PRIVATE_CAR', 'TRAIN', 'PLANE', 'BUS', 'OTHER')),
    CONSTRAINT ck_trips_status CHECK (status IN ('PLANNED', 'SUBMITTED', 'RETURNED', 'APPROVED', 'PAID', 'CANCELLED')),
    CONSTRAINT ck_trips_dates CHECK (ends_at > starts_at)
);
CREATE INDEX ix_trips_traveller ON crm.trips (traveller_user_id, starts_at DESC) INCLUDE (status, total);
CREATE INDEX ix_trips_status ON crm.trips (status, starts_at DESC) INCLUDE (traveller_user_id, total);
CREATE INDEX ix_trips_starts ON crm.trips (starts_at DESC, id DESC) INCLUDE (status, purpose, traveller_user_id);

CREATE TABLE crm.trip_expenses
(
    id          bigint IDENTITY (1, 1) NOT NULL,
    trip_id     bigint                 NOT NULL,
    line_no     int                    NOT NULL,
    -- HOTEL, TICKET, FUEL, PARKING, TOLL, TAXI, OTHER.
    category    varchar(10)            NOT NULL,
    description nvarchar(200)          NOT NULL,
    spent_on    date                   NOT NULL,
    document    nvarchar(60)           NULL,
    amount      decimal(12, 2)         NOT NULL,
    -- A hotel line counts its nights, so the limit per night can be checked.
    nights      smallint               NULL,
    CONSTRAINT pk_trip_expenses PRIMARY KEY CLUSTERED (id),
    CONSTRAINT uq_trip_expenses_line UNIQUE (trip_id, line_no),
    CONSTRAINT fk_trip_expenses_trip FOREIGN KEY (trip_id) REFERENCES crm.trips (id) ON DELETE CASCADE,
    CONSTRAINT ck_trip_expenses_category CHECK (category IN ('HOTEL', 'TICKET', 'FUEL', 'PARKING', 'TOLL', 'TAXI', 'OTHER')),
    CONSTRAINT ck_trip_expenses_amount CHECK (amount > 0)
);

-- The operational people travel to project sites: a department for them next to the desk's ones.
IF NOT EXISTS (SELECT 1 FROM crm.departments WHERE name = N'Realizacja projektów')
    INSERT crm.departments (name, sort_order) SELECT N'Realizacja projektów', ISNULL(MAX(sort_order), 0) + 1 FROM crm.departments;
