/*
  The fleet (ADR-0018), after Ambit System's fleet module: the group's cars, their status by hand with its history,
  how each is financed, and handovers - who has which car from which day to which day. Plus two deadlines Ambit
  System leaves for later: the technical inspection and the third-party insurance.
*/
CREATE TABLE crm.fleet_partners
(
    id          int IDENTITY (1, 1) NOT NULL,
    kind        varchar(12)         NOT NULL,
    name        nvarchar(120)       NOT NULL,
    -- Unique per kind ignoring case and Polish letters ("Łódź" = "lodz").
    name_key    AS CAST(LOWER(TRANSLATE(name, N'ĄĆĘŁŃÓŚŹŻąćęłńóśźż', N'ACELNOSZZacelnoszz')) AS nvarchar(120)) PERSISTED,
    phone       varchar(40)         NULL,
    note        nvarchar(400)       NULL,
    is_hidden   bit                 NOT NULL CONSTRAINT df_fleet_partners_hidden DEFAULT (0),
    row_version rowversion          NOT NULL,
    CONSTRAINT pk_fleet_partners PRIMARY KEY CLUSTERED (id),
    CONSTRAINT ck_fleet_partners_kind CHECK (kind IN ('REPAIR_SHOP', 'LEASING')),
    CONSTRAINT uq_fleet_partners_name UNIQUE (kind, name_key)
);

CREATE TABLE crm.car_statuses
(
    status        varchar(20)  NOT NULL,
    sort_order    int          NOT NULL,
    needs_shop    bit          NOT NULL,
    name_pl       nvarchar(50) NOT NULL,
    name_en       nvarchar(50) NOT NULL,
    CONSTRAINT pk_car_statuses PRIMARY KEY CLUSTERED (status)
);
INSERT crm.car_statuses (status, sort_order, needs_shop, name_pl, name_en)
VALUES ('ACTIVE', 1, 0, N'Nowy', N'New'), ('OPERATIONAL', 2, 0, N'Sprawny', N'Operational'),
       ('TO_REPAIR_SHOP', 3, 1, N'Do serwisu', N'To repair shop'), ('IN_REPAIR_SHOP', 4, 1, N'W serwisie', N'In repair shop'),
       ('READY_FOR_PICKUP', 5, 1, N'Do odbioru z serwisu', N'Ready for pickup'), ('FOR_SALE', 6, 0, N'Na sprzedaż', N'For sale'),
       ('ARCHIVED', 7, 0, N'Archiwum', N'Archived');

CREATE TABLE crm.cars
(
    id               int IDENTITY (1, 1) NOT NULL,
    name             nvarchar(100)       NOT NULL,
    make             nvarchar(60)        NULL,
    production_year  smallint            NULL,
    plate            varchar(15)         NOT NULL,
    -- The plate compared upper case without spaces and hyphens: "WA 12345" = "wa-12345".
    plate_key        AS CAST(REPLACE(REPLACE(UPPER(plate), ' ', ''), '-', '') AS varchar(15)) PERSISTED,
    vin              char(17)            NULL,
    notes            nvarchar(1000)      NULL,
    legal_entity_id  int                 NOT NULL,
    status           varchar(20)         NOT NULL CONSTRAINT df_cars_status DEFAULT ('ACTIVE'),
    status_since     date                NOT NULL,
    repair_shop_id   int                 NULL,
    -- Financing: UNKNOWN, PAID (purchase_date) or LEASING (partner, instalment, start, months, contract).
    financing        varchar(10)         NOT NULL CONSTRAINT df_cars_financing DEFAULT ('UNKNOWN'),
    purchase_date    date                NULL,
    leasing_id       int                 NULL,
    instalment       decimal(12, 2)      NULL,
    currency         char(3)             NULL,
    lease_start      date                NULL,
    lease_months     smallint            NULL,
    contract_no      nvarchar(60)        NULL,
    inspection_due   date                NULL,
    insurance_due    date                NULL,
    created_at       datetime2(3)        NOT NULL CONSTRAINT df_cars_created_at DEFAULT (SYSUTCDATETIME()),
    updated_at       datetime2(3)        NOT NULL CONSTRAINT df_cars_updated_at DEFAULT (SYSUTCDATETIME()),
    updated_by       int                 NULL,
    row_version      rowversion          NOT NULL,
    CONSTRAINT pk_cars PRIMARY KEY CLUSTERED (id),
    CONSTRAINT fk_cars_legal_entity FOREIGN KEY (legal_entity_id) REFERENCES crm.legal_entities (id),
    CONSTRAINT fk_cars_status FOREIGN KEY (status) REFERENCES crm.car_statuses (status),
    CONSTRAINT fk_cars_repair_shop FOREIGN KEY (repair_shop_id) REFERENCES crm.fleet_partners (id),
    CONSTRAINT fk_cars_leasing FOREIGN KEY (leasing_id) REFERENCES crm.fleet_partners (id),
    CONSTRAINT ck_cars_financing CHECK (financing IN ('UNKNOWN', 'PAID', 'LEASING'))
);
-- A plate is unique among the cars in use; archiving frees it. A VIN is unique for good.
CREATE UNIQUE INDEX uq_cars_plate ON crm.cars (plate_key) WHERE status <> 'ARCHIVED';
CREATE UNIQUE INDEX uq_cars_vin ON crm.cars (vin) WHERE vin IS NOT NULL;
CREATE INDEX ix_cars_status ON crm.cars (status, name) INCLUDE (plate, legal_entity_id, repair_shop_id);

CREATE TABLE crm.car_status_history
(
    id             bigint IDENTITY (1, 1) NOT NULL,
    car_id         int                    NOT NULL,
    status         varchar(20)            NOT NULL,
    effective_on   date                   NOT NULL,
    -- The shop's name as it was: renaming a partner never rewrites history.
    repair_shop    nvarchar(120)          NULL,
    note           nvarchar(400)          NULL,
    changed_by     int                    NOT NULL,
    changed_at     datetime2(3)           NOT NULL CONSTRAINT df_car_status_history_at DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT pk_car_status_history PRIMARY KEY CLUSTERED (id),
    CONSTRAINT fk_car_status_history_car FOREIGN KEY (car_id) REFERENCES crm.cars (id) ON DELETE CASCADE
);
CREATE INDEX ix_car_status_history_car ON crm.car_status_history (car_id, id DESC);

CREATE TABLE crm.car_handovers
(
    id              bigint IDENTITY (1, 1) NOT NULL,
    car_id          int                    NOT NULL,
    holder_user_id  int                    NOT NULL,
    issue_date      date                   NOT NULL,
    -- Empty: open-ended. Days are Warsaw days, both included.
    planned_return  date                   NULL,
    issue_mileage   int                    NOT NULL,
    issue_fuel      tinyint                NOT NULL,
    notes           nvarchar(1000)         NULL,
    issued_by       int                    NOT NULL,
    issued_at       datetime2(3)           NOT NULL CONSTRAINT df_car_handovers_issued_at DEFAULT (SYSUTCDATETIME()),
    returned_on     date                   NULL,
    return_mileage  int                    NULL,
    return_fuel     tinyint                NULL,
    returned_by     int                    NULL,
    cancelled_at    datetime2(3)           NULL,
    cancel_reason   nvarchar(400)          NULL,
    row_version     rowversion             NOT NULL,
    CONSTRAINT pk_car_handovers PRIMARY KEY CLUSTERED (id),
    CONSTRAINT fk_car_handovers_car FOREIGN KEY (car_id) REFERENCES crm.cars (id) ON DELETE CASCADE,
    CONSTRAINT fk_car_handovers_holder FOREIGN KEY (holder_user_id) REFERENCES crm.users (id),
    CONSTRAINT ck_car_handovers_mileage CHECK (issue_mileage BETWEEN 0 AND 5000000 AND (return_mileage IS NULL OR return_mileage >= issue_mileage)),
    CONSTRAINT ck_car_handovers_fuel CHECK (issue_fuel BETWEEN 0 AND 100 AND (return_fuel IS NULL OR return_fuel BETWEEN 0 AND 100))
);
-- Overlap checks per car and per person read the live handovers (not cancelled, not returned before the day).
CREATE INDEX ix_car_handovers_car ON crm.car_handovers (car_id, issue_date) INCLUDE (planned_return, returned_on, cancelled_at, holder_user_id);
CREATE INDEX ix_car_handovers_holder ON crm.car_handovers (holder_user_id, issue_date) INCLUDE (car_id, planned_return, returned_on, cancelled_at);
