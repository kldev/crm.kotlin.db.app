/*
  Multi-company (ADR-0016): the group's own companies (legal entities) that deliver projects and sign offers - not the
  clients. A company trades from active_from and, once closed, until active_to; it is kept for history. Users and
  clients do not belong to a company: anyone works for any of them.
*/
CREATE TABLE crm.legal_entities
(
    id           int IDENTITY (1, 1) NOT NULL,
    name         nvarchar(100)       NOT NULL,
    legal_name   nvarchar(200)       NOT NULL,
    tax_id       char(10)            NOT NULL,
    vat_number   varchar(20)         NULL,
    address      nvarchar(300)       NOT NULL,
    phone        varchar(30)         NULL,
    email        nvarchar(254)       NULL,
    website      nvarchar(200)       NULL,
    bank_account varchar(34)         NULL,
    active_from  date                NOT NULL,
    active_to    date                NULL,
    created_at   datetime2(3)        NOT NULL CONSTRAINT df_legal_entities_created_at DEFAULT (SYSUTCDATETIME()),
    updated_at   datetime2(3)        NOT NULL CONSTRAINT df_legal_entities_updated_at DEFAULT (SYSUTCDATETIME()),
    updated_by   int                 NULL,
    row_version  rowversion          NOT NULL,
    CONSTRAINT pk_legal_entities PRIMARY KEY CLUSTERED (id),
    CONSTRAINT uq_legal_entities_name UNIQUE (name),
    CONSTRAINT uq_legal_entities_tax_id UNIQUE (tax_id),
    CONSTRAINT ck_legal_entities_active CHECK (active_to IS NULL OR active_to >= active_from)
);

-- The company the offers used to name in settings (ADR-0013) is the first one; three companies per line of business.
INSERT crm.legal_entities (name, legal_name, tax_id, vat_number, address, phone, email, website, bank_account, active_from)
VALUES (N'Halycon Inc.', N'Halycon Inc. sp. z o.o.', '5250000015', 'PL5250000015', N'ul. Obsydianowa 12, 00-950 Warszawa',
        '+48 22 100 20 30', N'oferty@halycon.example', N'halycon.example', 'PL61109010140000071219812874', '2018-01-01'),
       (N'Halycon Budownictwo', N'Halycon Budownictwo sp. z o.o.', '5260000028', 'PL5260000028',
        N'ul. Betonowa 4, 02-100 Warszawa', '+48 22 100 20 40', N'budownictwo@halycon.example', N'bud.halycon.example',
        'PL27114020040000300201355387', '2020-03-01'),
       (N'Halycon IT', N'Halycon IT sp. z o.o.', '5270000030', 'PL5270000030', N'ul. Krzemowa 8, 50-100 Wrocław',
        '+48 71 300 40 50', N'it@halycon.example', N'it.halycon.example', 'PL83101010230000261395100000', '2021-01-01'),
       (N'Halycon Staff', N'Halycon Staff sp. z o.o.', '5280000043', 'PL5280000043', N'ul. Portowa 21, 80-800 Gdańsk',
        '+48 58 500 60 70', N'staff@halycon.example', N'staff.halycon.example', 'PL10105000997603123456789123', '2022-06-01');
GO

-- Each template signs with the company of its line of business.
ALTER TABLE crm.offer_templates ADD legal_entity_id int NULL;
GO
UPDATE t SET legal_entity_id = e.id
FROM crm.offer_templates AS t
JOIN crm.legal_entities AS e ON e.name = CASE t.template_key WHEN 'CONSTRUCTION' THEN N'Halycon Budownictwo'
                                                            WHEN 'IT' THEN N'Halycon IT'
                                                            WHEN 'OUTSOURCING' THEN N'Halycon Staff'
                                                            ELSE N'Halycon Inc.' END;
ALTER TABLE crm.offer_templates ALTER COLUMN legal_entity_id int NOT NULL;
ALTER TABLE crm.offer_templates ADD CONSTRAINT fk_offer_templates_legal_entity
    FOREIGN KEY (legal_entity_id) REFERENCES crm.legal_entities (id);

-- An offer is signed by one company; the existing ones by their template's.
ALTER TABLE crm.offers ADD legal_entity_id int NULL;
GO
UPDATE o SET legal_entity_id = t.legal_entity_id FROM crm.offers AS o JOIN crm.offer_templates AS t ON t.template_key = o.template_key;
ALTER TABLE crm.offers ALTER COLUMN legal_entity_id int NOT NULL;
ALTER TABLE crm.offers ADD CONSTRAINT fk_offers_legal_entity FOREIGN KEY (legal_entity_id) REFERENCES crm.legal_entities (id);
GO

/*
  A project is delivered by one company. The projects before multi-company were delivered by the first company: the
  default fills them in one pass (millions of rows), then it is dropped - from now on the procedures name the company.
*/
ALTER TABLE crm.projects ADD legal_entity_id int NOT NULL CONSTRAINT df_projects_legal_entity DEFAULT (1);
GO
ALTER TABLE crm.projects DROP CONSTRAINT df_projects_legal_entity;
ALTER TABLE crm.projects WITH CHECK ADD CONSTRAINT fk_projects_legal_entity
    FOREIGN KEY (legal_entity_id) REFERENCES crm.legal_entities (id);
-- The projects list filtered by company, ordered and paged like every other list.
CREATE INDEX ix_projects_legal_entity ON crm.projects (legal_entity_id, due_date, id) INCLUDE (stage, team_id, client_id, owner_user_id);
GO

ALTER VIEW crm.v_projects
AS
SELECT p.id,
       p.name,
       p.stage,
       p.start_date,
       p.due_date,
       p.budget,
       CAST(IIF(p.stage IN ('NEW', 'ACCEPTED', 'ACTIVE', 'ON_HOLD') AND p.due_date < CAST(SYSUTCDATETIME() AS date), 1, 0)
           AS bit)        AS is_overdue,
       p.stage_changed_at,
       p.client_id,
       c.name             AS client_name,
       c.city             AS client_city,
       c.assigned_user_id AS client_owner_id,
       p.team_id,
       t.name             AS team_name,
       t.lead_user_id     AS team_lead_id,
       p.owner_user_id,
       ou.login           AS owner_login,
       ou.display_name    AS owner_display_name,
       p.legal_entity_id,
       le.name            AS legal_entity_name,
       p.created_at,
       p.updated_at,
       p.row_version
FROM crm.projects AS p
JOIN crm.clients AS c ON c.id = p.client_id
JOIN crm.teams AS t ON t.id = p.team_id
JOIN crm.users AS ou ON ou.id = p.owner_user_id
JOIN crm.legal_entities AS le ON le.id = p.legal_entity_id;
