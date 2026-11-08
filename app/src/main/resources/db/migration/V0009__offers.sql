/*
  Offers (ADR-0013): a priced proposal for a CRM client, made from one of three templates, printed as a PDF in the
  Obsidian look. The author's contact (job title, phone, e-mail) closes the PDF when the author is a salesperson, so
  users get contact fields; any user may fill in their own, an administrator anyone's.
*/
ALTER TABLE crm.users ADD
    job_title nvarchar(100) NULL,
    phone     varchar(30)   NULL,
    email     varchar(254)  NULL;
GO

/*
  Templates are data: a new template is an INSERT, a changed text a migration. Texts in Polish and English - the PDF is
  printed in the language the user chose. The default lines are copied into a new offer and edited there.
*/
CREATE TABLE crm.offer_templates
(
    template_key  varchar(20)    NOT NULL,
    name_pl       nvarchar(100)  NOT NULL,
    name_en       nvarchar(100)  NOT NULL,
    title_pl      nvarchar(200)  NOT NULL,
    title_en      nvarchar(200)  NOT NULL,
    intro_pl      nvarchar(2000) NOT NULL,
    intro_en      nvarchar(2000) NOT NULL,
    terms_pl      nvarchar(4000) NOT NULL,
    terms_en      nvarchar(4000) NOT NULL,
    validity_days int            NOT NULL,
    sort_order    int            NOT NULL,
    CONSTRAINT pk_offer_templates PRIMARY KEY CLUSTERED (template_key),
    CONSTRAINT ck_offer_templates_validity CHECK (validity_days BETWEEN 1 AND 365)
);

CREATE TABLE crm.offer_template_items
(
    template_key varchar(20)    NOT NULL,
    line_no      int            NOT NULL,
    description  nvarchar(400)  NOT NULL,
    unit         nvarchar(20)   NOT NULL,
    quantity     decimal(12, 3) NOT NULL,
    unit_price   decimal(14, 2) NOT NULL,
    vat_rate     tinyint        NOT NULL,
    CONSTRAINT pk_offer_template_items PRIMARY KEY CLUSTERED (template_key, line_no),
    CONSTRAINT fk_offer_template_items_template FOREIGN KEY (template_key) REFERENCES crm.offer_templates (template_key)
);

-- Offer numbers per year: OF/2026/0001. The row of a year is locked while a number is taken.
CREATE TABLE crm.offer_numbers
(
    year      smallint NOT NULL,
    last_used int      NOT NULL,
    CONSTRAINT pk_offer_numbers PRIMARY KEY CLUSTERED (year)
);

CREATE TABLE crm.offers
(
    id             bigint IDENTITY (1, 1) NOT NULL,
    number         varchar(20)            NOT NULL,
    client_id      bigint                 NOT NULL,
    template_key   varchar(20)            NOT NULL,
    title          nvarchar(200)          NOT NULL,
    intro          nvarchar(2000)         NOT NULL,
    terms          nvarchar(4000)         NOT NULL,
    currency       char(3)                NOT NULL,
    valid_until    date                   NOT NULL,
    -- DRAFT -> SENT -> ACCEPTED | REJECTED; SENT may go back to DRAFT for corrections.
    status         varchar(10)            NOT NULL,
    author_user_id int                    NOT NULL,
    sent_at        datetime2(3)           NULL,
    decided_at     datetime2(3)           NULL,
    created_at     datetime2(3)           NOT NULL CONSTRAINT df_offers_created_at DEFAULT (SYSUTCDATETIME()),
    updated_at     datetime2(3)           NOT NULL CONSTRAINT df_offers_updated_at DEFAULT (SYSUTCDATETIME()),
    updated_by     int                    NULL,
    row_version    rowversion             NOT NULL,
    CONSTRAINT pk_offers PRIMARY KEY CLUSTERED (id),
    CONSTRAINT uq_offers_number UNIQUE (number),
    CONSTRAINT fk_offers_client FOREIGN KEY (client_id) REFERENCES crm.clients (id),
    CONSTRAINT fk_offers_template FOREIGN KEY (template_key) REFERENCES crm.offer_templates (template_key),
    CONSTRAINT fk_offers_author FOREIGN KEY (author_user_id) REFERENCES crm.users (id),
    CONSTRAINT ck_offers_status CHECK (status IN ('DRAFT', 'SENT', 'ACCEPTED', 'REJECTED')),
    CONSTRAINT ck_offers_currency CHECK (currency IN ('PLN', 'EUR', 'USD'))
);

-- The offers list: newest first, per client, per status.
CREATE INDEX ix_offers_client ON crm.offers (client_id, id DESC);
CREATE INDEX ix_offers_status ON crm.offers (status, id DESC);

CREATE TABLE crm.offer_items
(
    offer_id    bigint         NOT NULL,
    line_no     int            NOT NULL,
    description nvarchar(400)  NOT NULL,
    unit        nvarchar(20)   NOT NULL,
    quantity    decimal(12, 3) NOT NULL,
    unit_price  decimal(14, 2) NOT NULL,
    -- 23, 8, 5 or 0 percent.
    vat_rate    tinyint        NOT NULL,
    CONSTRAINT pk_offer_items PRIMARY KEY CLUSTERED (offer_id, line_no),
    CONSTRAINT fk_offer_items_offer FOREIGN KEY (offer_id) REFERENCES crm.offers (id) ON DELETE CASCADE,
    CONSTRAINT ck_offer_items_quantity CHECK (quantity > 0),
    CONSTRAINT ck_offer_items_price CHECK (unit_price >= 0),
    CONSTRAINT ck_offer_items_vat CHECK (vat_rate IN (0, 5, 8, 23))
);
GO

INSERT crm.offer_templates (template_key, name_pl, name_en, title_pl, title_en, intro_pl, intro_en, terms_pl, terms_en,
                            validity_days, sort_order)
VALUES
('CONSTRUCTION', N'Sales Budownictwo', N'Sales Construction',
 N'Oferta na prace budowlane', N'Offer for construction works',
 N'Dziękujemy za zapytanie. Przedstawiamy ofertę wykonania prac budowlanych w zakresie opisanym poniżej. Ceny obejmują materiały i robociznę, chyba że przy pozycji zaznaczono inaczej. Prace prowadzi nasz kierownik budowy z uprawnieniami, a postęp raportujemy co tydzień.',
 N'Thank you for your enquiry. Please find below our offer for the construction works described. Prices include materials and labour unless stated otherwise at an item. The works are led by our licensed site manager and progress is reported weekly.',
 N'Termin realizacji: do uzgodnienia w ciągu 7 dni od akceptacji oferty.
Płatność: 30% zaliczki po podpisaniu umowy, pozostała kwota po odbiorze protokołem, przelew 14 dni.
Gwarancja: 36 miesięcy na wykonane prace, zgodnie z umową.
Prace dodatkowe wyceniamy osobno po uzgodnieniu z Inwestorem.',
 N'Lead time: to be agreed within 7 days of accepting the offer.
Payment: 30% advance on signing the contract, the rest after the acceptance report, bank transfer within 14 days.
Warranty: 36 months on the works performed, as set out in the contract.
Additional works are priced separately after agreement with the Client.',
 30, 1),
('IT', N'Sales IT', N'Sales IT',
 N'Oferta na usługi IT', N'Offer for IT services',
 N'Dziękujemy za zainteresowanie naszymi usługami. Proponujemy wdrożenie w etapach: analiza, konfiguracja, uruchomienie i wsparcie po starcie. Zespół pracuje w sprintach, a każdy etap kończy się odbiorem z Państwa udziałem.',
 N'Thank you for your interest in our services. We propose a staged implementation: analysis, configuration, go-live and support afterwards. The team works in sprints and every stage ends with an acceptance meeting with you.',
 N'Harmonogram: start prac w ciągu 10 dni roboczych od akceptacji oferty.
Rozliczenie: prace analityczne i wdrożeniowe według faktycznie przepracowanych godzin, licencje i wsparcie z góry za okres.
Płatność: przelew 14 dni od daty faktury.
SLA wsparcia: zgłoszenia krytyczne podjęte w ciągu 4 godzin roboczych.',
 N'Schedule: work starts within 10 working days of accepting the offer.
Billing: analysis and implementation by the hours actually worked, licences and support in advance for the period.
Payment: bank transfer within 14 days of the invoice date.
Support SLA: critical issues picked up within 4 working hours.',
 21, 2),
('OUTSOURCING', N'Sales Outsourcing', N'Sales Outsourcing',
 N'Oferta outsourcingu pracowników', N'Offer for staff outsourcing',
 N'Dziękujemy za zaufanie. Oferujemy wykwalifikowanych pracowników z doświadczeniem na budowach w Polsce i za granicą. Zapewniamy legalizację zatrudnienia, delegowanie (A1, Limosa, SIPSI), zakwaterowanie i koordynatora na miejscu.',
 N'Thank you for your trust. We offer qualified workers experienced on sites in Poland and abroad. We take care of the legal employment, the posting (A1, Limosa, SIPSI), accommodation and a coordinator on site.',
 N'Rozliczenie: według przepracowanych godzin potwierdzonych kartą pracy, faktura miesięczna.
Płatność: przelew 21 dni od daty faktury.
Zastępstwo: zastąpienie pracownika w ciągu 5 dni roboczych od zgłoszenia.
Minimalny okres współpracy: 3 miesiące.',
 N'Billing: by the hours worked as confirmed by the timesheet, monthly invoice.
Payment: bank transfer within 21 days of the invoice date.
Replacement: a worker is replaced within 5 working days of the request.
Minimum term: 3 months.',
 14, 3);

INSERT crm.offer_template_items (template_key, line_no, description, unit, quantity, unit_price, vat_rate)
VALUES ('CONSTRUCTION', 1, N'Prace przygotowawcze i zabezpieczenie terenu budowy', N'ryczałt', 1, 8500.00, 23),
       ('CONSTRUCTION', 2, N'Roboty murowe ścian nośnych', N'm²', 120, 185.00, 8),
       ('CONSTRUCTION', 3, N'Instalacja elektryczna wraz z pomiarami', N'kpl', 1, 24000.00, 8),
       ('CONSTRUCTION', 4, N'Wywóz i utylizacja odpadów budowlanych', N'kontener', 4, 950.00, 23),
       ('IT', 1, N'Analiza przedwdrożeniowa i projekt rozwiązania', N'h', 24, 240.00, 23),
       ('IT', 2, N'Wdrożenie i konfiguracja systemu', N'h', 80, 220.00, 23),
       ('IT', 3, N'Licencje użytkowników (12 miesięcy)', N'szt.', 15, 480.00, 23),
       ('IT', 4, N'Wsparcie powdrożeniowe', N'mies.', 3, 2400.00, 23),
       ('OUTSOURCING', 1, N'Spawacz MIG/MAG z uprawnieniami', N'h', 1600, 62.00, 23),
       ('OUTSOURCING', 2, N'Monter konstrukcji stalowych', N'h', 1600, 55.00, 23),
       ('OUTSOURCING', 3, N'Koordynator na budowie', N'mies.', 3, 9500.00, 23),
       ('OUTSOURCING', 4, N'Zakwaterowanie pracowników', N'os./mies.', 12, 1200.00, 23);
