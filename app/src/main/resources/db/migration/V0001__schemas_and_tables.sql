-- ADR-0002: tables live in `crm`, the application calls only procedures in `app`, the seed lives in `seed`.
CREATE SCHEMA crm;
GO
CREATE SCHEMA app;
GO
CREATE SCHEMA seed;
GO

CREATE TABLE crm.users
(
    id                 int IDENTITY (1, 1) NOT NULL,
    login              varchar(64)         NOT NULL,
    display_name       nvarchar(200)       NOT NULL,
    role               varchar(10)         NOT NULL,
    password_hash      varchar(100)        NOT NULL,
    is_active          bit                 NOT NULL CONSTRAINT df_users_is_active DEFAULT (1),
    failed_login_count int                 NOT NULL CONSTRAINT df_users_failed_login_count DEFAULT (0),
    locked_until       datetime2(3)        NULL,
    last_login_at      datetime2(3)        NULL,
    created_at         datetime2(3)        NOT NULL CONSTRAINT df_users_created_at DEFAULT (SYSUTCDATETIME()),
    created_by         int                 NULL,
    updated_at         datetime2(3)        NOT NULL CONSTRAINT df_users_updated_at DEFAULT (SYSUTCDATETIME()),
    updated_by         int                 NULL,
    row_version        rowversion          NOT NULL,
    CONSTRAINT pk_users PRIMARY KEY CLUSTERED (id),
    CONSTRAINT uq_users_login UNIQUE (login),
    CONSTRAINT ck_users_role CHECK (role IN ('ADMIN', 'MANAGER', 'SALES')),
    CONSTRAINT ck_users_failed_login_count CHECK (failed_login_count >= 0)
);

CREATE INDEX ix_users_role ON crm.users (role, id) INCLUDE (is_active);

CREATE TABLE crm.clients
(
    id               bigint IDENTITY (1, 1) NOT NULL,
    name             nvarchar(200)          NOT NULL,
    nip              char(10)               NULL,
    email            varchar(254)           NULL,
    phone            varchar(30)            NULL,
    city             nvarchar(100)          NULL,
    status           varchar(10)            NOT NULL,
    assigned_user_id int                    NULL,
    note             nvarchar(2000)         NULL,
    created_at       datetime2(3)           NOT NULL CONSTRAINT df_clients_created_at DEFAULT (SYSUTCDATETIME()),
    created_by       int                    NULL,
    updated_at       datetime2(3)           NOT NULL CONSTRAINT df_clients_updated_at DEFAULT (SYSUTCDATETIME()),
    updated_by       int                    NULL,
    row_version      rowversion             NOT NULL,
    CONSTRAINT pk_clients PRIMARY KEY CLUSTERED (id),
    CONSTRAINT ck_clients_status CHECK (status IN ('LEAD', 'ACTIVE', 'INACTIVE')),
    CONSTRAINT ck_clients_nip CHECK (nip NOT LIKE '%[^0-9]%' AND LEN(nip) = 10),
    CONSTRAINT fk_clients_assigned_user FOREIGN KEY (assigned_user_id) REFERENCES crm.users (id)
);

-- Exact lookups.
CREATE UNIQUE INDEX ux_clients_nip ON crm.clients (nip) WHERE nip IS NOT NULL;
CREATE INDEX ix_clients_email ON crm.clients (email) WHERE email IS NOT NULL;
-- Keyset pages: by name (prefix search), by owner (SALES sees only own clients), by city.
CREATE INDEX ix_clients_name ON crm.clients (name, id);
CREATE INDEX ix_clients_assigned_user ON crm.clients (assigned_user_id, id);
CREATE INDEX ix_clients_city ON crm.clients (city, id);
