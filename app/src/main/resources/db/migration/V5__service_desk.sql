/*
  Service desk (ADR-0007): requests to the company's teams, one event stream per ticket.

  crm.ticket_events is the stream: append-only facts, (ticket_id, version) is the key, so two writers can never
  store the same version. crm.tickets is the read model (an "inline projection"): every app.desk_ticket_* procedure
  appends the event and updates the row in one transaction. The timeline of a ticket is its stream.

  The catalog (categories, subcategories, priorities with their SLA) is data seeded here; keys are stored on tickets,
  so a key is never renamed or reused. A subcategory is retired with is_active = 0, never deleted.
  Names are Polish (the identity of the catalog); the UI translates them for display.
*/

CREATE TABLE crm.desk_categories
(
    category_key varchar(40)   NOT NULL,
    name         nvarchar(100) NOT NULL,
    -- The department whose people do the work (the handler of a ticket); NULL = anybody.
    department   nvarchar(50)  NULL,
    sort_order   int           NOT NULL,
    CONSTRAINT pk_desk_categories PRIMARY KEY CLUSTERED (category_key)
);

CREATE TABLE crm.desk_subcategories
(
    subcategory_key varchar(60)   NOT NULL,
    category_key    varchar(40)   NOT NULL,
    name            nvarchar(200) NOT NULL,
    -- The market the form groups subcategories under ("Belgia"), NULL when not grouped.
    market          nvarchar(50)  NULL,
    is_active       bit           NOT NULL,
    sort_order      int           NOT NULL,
    CONSTRAINT pk_desk_subcategories PRIMARY KEY CLUSTERED (subcategory_key),
    CONSTRAINT fk_desk_subcategories_category FOREIGN KEY (category_key) REFERENCES crm.desk_categories (category_key)
);

-- Service level per priority, calendar time 24/7 (ADR-0007): deadline = reported_at + sla_minutes.
CREATE TABLE crm.desk_priorities
(
    priority    varchar(8) NOT NULL,
    sla_minutes int        NOT NULL,
    sort_order  int        NOT NULL,
    CONSTRAINT pk_desk_priorities PRIMARY KEY CLUSTERED (priority),
    CONSTRAINT ck_desk_priorities_sla CHECK (sla_minutes > 0)
);

INSERT crm.desk_priorities (priority, sla_minutes, sort_order)
VALUES ('CRITICAL', 180, 1),
       ('HIGH', 480, 2),
       ('MEDIUM', 4320, 3),
       ('LOW', 10080, 4);

-- Requesters: employees who report tickets on the public form; they never sign in. Not CRM users.
CREATE TABLE crm.people
(
    id               int IDENTITY (1, 1) NOT NULL,
    first_name       nvarchar(100)       NOT NULL,
    last_name        nvarchar(100)       NOT NULL,
    department       nvarchar(50)        NOT NULL,
    email            varchar(254)        NOT NULL,
    phone            varchar(30)         NULL,
    email_normalized AS LOWER(email) PERSISTED,
    created_at       datetime2(3)        NOT NULL CONSTRAINT df_people_created_at DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT pk_people PRIMARY KEY CLUSTERED (id),
    CONSTRAINT uq_people_email UNIQUE (email_normalized)
);

CREATE INDEX ix_people_name ON crm.people (last_name, first_name);

-- The read model of a ticket. Every column is derived from the ticket's events (crm.ticket_events).
CREATE TABLE crm.tickets
(
    id                    bigint IDENTITY (1, 1) NOT NULL,
    -- The short number a requester is given: HAL- and 8 hex digits, random, never changes.
    number                char(12)               NOT NULL,
    title                 nvarchar(200)          NOT NULL,
    description           nvarchar(4000)         NOT NULL,
    category_key          varchar(40)            NOT NULL,
    subcategory_key       varchar(60)            NOT NULL,
    priority              varchar(8)             NOT NULL,
    original_priority     varchar(8)             NOT NULL,
    reported_at           datetime2(3)           NOT NULL,
    deadline              datetime2(3)           NOT NULL,
    status                varchar(12)            NOT NULL,
    assignee_user_id      int                    NULL,
    assignee_name         nvarchar(200)          NULL,
    handler_person_id     int                    NULL,
    handler_name          nvarchar(201)          NULL,
    requester_incognito   bit                    NOT NULL,
    requester_person_id   int                    NULL,
    requester_name        nvarchar(201)          NULL,
    channel               varchar(12)            NOT NULL,
    registered_by_user_id int                    NULL,
    registered_by_name    nvarchar(200)          NULL,
    recorded_at           datetime2(3)           NOT NULL,
    resolved_at           datetime2(3)           NULL,
    resolved_late         bit                    NOT NULL CONSTRAINT df_tickets_resolved_late DEFAULT (0),
    comment_count         int                    NOT NULL CONSTRAINT df_tickets_comment_count DEFAULT (0),
    attachment_count      int                    NOT NULL CONSTRAINT df_tickets_attachment_count DEFAULT (0),
    -- The version of the last event folded into this row.
    version               int                    NOT NULL,
    last_change_at        datetime2(3)           NOT NULL,
    CONSTRAINT pk_tickets PRIMARY KEY CLUSTERED (id),
    CONSTRAINT uq_tickets_number UNIQUE (number),
    CONSTRAINT fk_tickets_subcategory FOREIGN KEY (subcategory_key) REFERENCES crm.desk_subcategories (subcategory_key),
    CONSTRAINT fk_tickets_category FOREIGN KEY (category_key) REFERENCES crm.desk_categories (category_key),
    CONSTRAINT fk_tickets_priority FOREIGN KEY (priority) REFERENCES crm.desk_priorities (priority),
    CONSTRAINT fk_tickets_assignee FOREIGN KEY (assignee_user_id) REFERENCES crm.users (id),
    CONSTRAINT fk_tickets_handler FOREIGN KEY (handler_person_id) REFERENCES crm.people (id),
    CONSTRAINT fk_tickets_requester FOREIGN KEY (requester_person_id) REFERENCES crm.people (id),
    CONSTRAINT ck_tickets_status CHECK (status IN ('IN_POOL', 'IN_PROGRESS', 'DONE')),
    CONSTRAINT ck_tickets_channel CHECK (channel IN ('AGENT', 'SELF_SERVICE')),
    CONSTRAINT ck_tickets_requester CHECK ((requester_incognito = 1 AND requester_person_id IS NULL)
        OR (requester_incognito = 0 AND requester_person_id IS NOT NULL)),
    -- In the pool nobody works on it; in progress somebody does; a resolved one keeps who resolved it.
    CONSTRAINT ck_tickets_assignee CHECK ((status = 'IN_POOL' AND assignee_user_id IS NULL)
        OR (status = 'IN_PROGRESS' AND assignee_user_id IS NOT NULL) OR status = 'DONE')
);

-- Lists (ADR-0007): open tickets by deadline, resolved ones newest first. Each list key ends with its sort key.
CREATE INDEX ix_tickets_pool ON crm.tickets (deadline, id) WHERE status = 'IN_POOL';
CREATE INDEX ix_tickets_open ON crm.tickets (deadline, id) WHERE status <> 'DONE';
CREATE INDEX ix_tickets_assignee ON crm.tickets (assignee_user_id, deadline, id) WHERE status = 'IN_PROGRESS';
CREATE INDEX ix_tickets_done ON crm.tickets (resolved_at DESC, id DESC) WHERE status = 'DONE';
CREATE INDEX ix_tickets_category ON crm.tickets (category_key, subcategory_key, reported_at);
CREATE INDEX ix_tickets_reported ON crm.tickets (reported_at);

-- The stream. data is the event as JSON; the actor columns are a snapshot (the name as it was then).
CREATE TABLE crm.ticket_events
(
    ticket_id     bigint                 NOT NULL,
    version       int                    NOT NULL,
    event_type    varchar(40)            NOT NULL,
    at            datetime2(3)           NOT NULL,
    actor_user_id int                    NULL,
    actor_name    nvarchar(201)          NULL,
    data          nvarchar(max)          NOT NULL,
    -- Global order of all events (the agents' report reads events by type and time).
    seq           bigint IDENTITY (1, 1) NOT NULL,
    CONSTRAINT pk_ticket_events PRIMARY KEY CLUSTERED (ticket_id, version),
    CONSTRAINT fk_ticket_events_ticket FOREIGN KEY (ticket_id) REFERENCES crm.tickets (id),
    CONSTRAINT ck_ticket_events_data CHECK (ISJSON(data) = 1),
    CONSTRAINT ck_ticket_events_version CHECK (version >= 1)
);

CREATE INDEX ix_ticket_events_type_at ON crm.ticket_events (event_type, at) INCLUDE (ticket_id, actor_user_id);

INSERT crm.desk_categories (category_key, name, department, sort_order)
VALUES ('it', N'Zgłoszenie do IT', NULL, 1),
       ('legal', N'Zgłoszenie do działu Prawnego', NULL, 2),
       ('marketing', N'Zgłoszenie do Marketingu', NULL, 3),
       ('recruitment', N'Zgłoszenie do rekrutacji', N'Rekrutacja', 4),
       ('finance', N'Zgłoszenie do Finansów', N'Finanse', 5),
       ('hr-abroad', N'Kadry Zagranica', N'Kadry', 6),
       ('hr-poland', N'Kadry Polska', N'Kadry', 7),
       ('legalization', N'Legalizacja', N'Kadry', 8);

INSERT crm.desk_subcategories (subcategory_key, category_key, name, market, is_active, sort_order)
VALUES ('it.hardware', 'it', N'Sprzęt', NULL, 1, 1),
       ('it.outage', 'it', N'Awaria', NULL, 1, 2),
       ('it.application', 'it', N'Problem z aplikacją', NULL, 1, 3),
       ('it.feedback', 'it', N'Feedback', NULL, 1, 4),
       ('legal.contracts', 'legal', N'Umowy', NULL, 1, 1),
       ('legal.opinion', 'legal', N'Opinia prawna', NULL, 1, 2),
       ('legal.gdpr', 'legal', N'Ochrona danych (RODO)', NULL, 1, 3),
       ('legal.disputes', 'legal', N'Spory i windykacja', NULL, 1, 4),
       ('legal.feedback', 'legal', N'Feedback', NULL, 1, 5),
       ('marketing.campaign', 'marketing', N'Kampania', NULL, 1, 1),
       ('marketing.social', 'marketing', N'Social media', NULL, 1, 2),
       ('marketing.graphics', 'marketing', N'Materiały graficzne', NULL, 1, 3),
       ('marketing.website', 'marketing', N'Strona www', NULL, 1, 4),
       ('marketing.events', 'marketing', N'Wydarzenia', NULL, 1, 5),
       ('marketing.budget', 'marketing', N'Budżet na kampanię (Facebook, TikTok…)', NULL, 1, 6),
       ('marketing.feedback', 'marketing', N'Feedback', NULL, 1, 7),
       ('recruitment.internal', 'recruitment', N'Rekrutacja do firmy', NULL, 1, 1),
       ('recruitment.client', 'recruitment', N'Rekrutacja dla klienta (agencja pracy)', NULL, 1, 2),
       ('recruitment.candidates', 'recruitment', N'Kandydaci i rozmowy', NULL, 1, 3),
       ('recruitment.feedback', 'recruitment', N'Feedback', NULL, 1, 4),
       ('finance.invoices', 'finance', N'Faktury kosztowe', NULL, 1, 1),
       ('finance.sales-invoices', 'finance', N'Faktury sprzedażowe i korekty', NULL, 1, 2),
       ('finance.expenses', 'finance', N'Rozliczenie delegacji i wydatków', NULL, 1, 3),
       ('finance.advance', 'finance', N'Zaliczka', NULL, 1, 4),
       ('finance.payments', 'finance', N'Przelewy i płatności', NULL, 1, 5),
       ('finance.budget', 'finance', N'Budżet i MPK', NULL, 1, 6),
       ('finance.feedback', 'finance', N'Feedback', NULL, 1, 7),
       ('hr-abroad.be.contract', 'hr-abroad', N'Umowa i warunki zatrudnienia', N'Belgia', 1, 1),
       ('hr-abroad.be.posting', 'hr-abroad', N'Zgłoszenie Limosa i formularz A1', N'Belgia', 1, 2),
       ('hr-abroad.be.payroll', 'hr-abroad', N'Wynagrodzenie, diety i rozliczenie', N'Belgia', 1, 3),
       ('hr-abroad.be.tax', 'hr-abroad', N'Podatki i składki', N'Belgia', 1, 4),
       ('hr-abroad.be.travel', 'hr-abroad', N'Zakwaterowanie i podróż', N'Belgia', 1, 5),
       ('hr-abroad.be.leave', 'hr-abroad', N'Urlopy, L4 i powroty', N'Belgia', 1, 6),
       ('hr-abroad.de.contract', 'hr-abroad', N'Umowa i warunki zatrudnienia', N'Niemcy', 1, 7),
       ('hr-abroad.de.posting', 'hr-abroad', N'Formularz A1 i meldunek (Anmeldung)', N'Niemcy', 1, 8),
       ('hr-abroad.de.payroll', 'hr-abroad', N'Wynagrodzenie, diety i rozliczenie', N'Niemcy', 1, 9),
       ('hr-abroad.de.tax', 'hr-abroad', N'Podatki i składki', N'Niemcy', 1, 10),
       ('hr-abroad.de.travel', 'hr-abroad', N'Zakwaterowanie i podróż', N'Niemcy', 1, 11),
       ('hr-abroad.de.leave', 'hr-abroad', N'Urlopy, L4 i powroty', N'Niemcy', 1, 12),
       ('hr-abroad.fr.contract', 'hr-abroad', N'Umowa i warunki zatrudnienia', N'Francja', 1, 13),
       ('hr-abroad.fr.posting', 'hr-abroad', N'Deklaracja SIPSI i formularz A1', N'Francja', 1, 14),
       ('hr-abroad.fr.payroll', 'hr-abroad', N'Wynagrodzenie, diety i rozliczenie', N'Francja', 1, 15),
       ('hr-abroad.fr.tax', 'hr-abroad', N'Podatki i składki', N'Francja', 1, 16),
       ('hr-abroad.fr.travel', 'hr-abroad', N'Zakwaterowanie i podróż', N'Francja', 1, 17),
       ('hr-abroad.fr.leave', 'hr-abroad', N'Urlopy, L4 i powroty', N'Francja', 1, 18),
       ('hr-abroad.feedback', 'hr-abroad', N'Feedback', NULL, 1, 19),
       ('hr-poland.pl.contract', 'hr-poland', N'Umowa, aneksy i zmiana warunków', N'Polska', 1, 1),
       ('hr-poland.pl.payroll', 'hr-poland', N'Wynagrodzenie i pasek płacowy', N'Polska', 1, 2),
       ('hr-poland.pl.leave', 'hr-poland', N'Urlopy, L4 i nieobecności', N'Polska', 1, 3),
       ('hr-poland.pl.certificates', 'hr-poland', N'Zaświadczenia i dokumenty (np. PIT-11)', N'Polska', 1, 4),
       ('hr-poland.pl.medical', 'hr-poland', N'Badania lekarskie i szkolenia BHP', N'Polska', 1, 5),
       ('hr-poland.pl.benefits', 'hr-poland', N'Benefity (opieka medyczna, karta sportowa)', N'Polska', 1, 6),
       ('hr-poland.pl.offboarding', 'hr-poland', N'Rozwiązanie umowy i świadectwo pracy', N'Polska', 1, 7),
       ('hr-poland.pl.onboarding', 'hr-poland', N'Nowy pracownik', N'Polska', 1, 8),
       ('hr-poland.feedback', 'hr-poland', N'Feedback', NULL, 1, 9),
       ('legalization.pesel', 'legalization', N'Nadanie numeru PESEL', NULL, 1, 1),
       ('legalization.lodging', 'legalization', N'Nocleg tymczasowy (przed mieszkaniem)', NULL, 1, 2),
       ('legalization.housing', 'legalization', N'Mieszkanie i zameldowanie', NULL, 1, 3),
       ('legalization.pup', 'legalization', N'Dokumenty do PUP (oświadczenie o powierzeniu pracy)', NULL, 1, 4),
       ('legalization.starosty', 'legalization', N'Zgłoszenie do starostwa', NULL, 1, 5),
       ('legalization.work-permit', 'legalization', N'Zezwolenie na pracę', NULL, 1, 6),
       ('legalization.residence', 'legalization', N'Karta pobytu i wiza', NULL, 1, 7),
       ('legalization.feedback', 'legalization', N'Feedback', NULL, 1, 8);
