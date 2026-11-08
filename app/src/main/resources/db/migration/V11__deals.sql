/*
  The sales pipeline (ADR-0015): deals - chances to sell to a client - moving through stages on a kanban board.
  The stages are data: their order, the probability that weights the forecast and whether the deal is closed.
*/
CREATE TABLE crm.deal_stages
(
    stage       varchar(12)   NOT NULL,
    sort_order  int           NOT NULL,
    probability tinyint       NOT NULL,
    is_closed   bit           NOT NULL,
    name_pl     nvarchar(50)  NOT NULL,
    name_en     nvarchar(50)  NOT NULL,
    CONSTRAINT pk_deal_stages PRIMARY KEY CLUSTERED (stage),
    CONSTRAINT ck_deal_stages_probability CHECK (probability BETWEEN 0 AND 100)
);

INSERT crm.deal_stages (stage, sort_order, probability, is_closed, name_pl, name_en)
VALUES ('LEAD', 1, 10, 0, N'Kontakt', N'Lead'),
       ('QUALIFIED', 2, 25, 0, N'Potrzeba potwierdzona', N'Qualified'),
       ('PROPOSAL', 3, 50, 0, N'Oferta', N'Proposal'),
       ('NEGOTIATION', 4, 75, 0, N'Negocjacje', N'Negotiation'),
       ('WON', 5, 100, 1, N'Wygrana', N'Won'),
       ('LOST', 6, 0, 1, N'Przegrana', N'Lost');

CREATE TABLE crm.deals
(
    id               bigint IDENTITY (1, 1) NOT NULL,
    title            nvarchar(200)          NOT NULL,
    client_id        bigint                 NOT NULL,
    -- The client's salesperson when the deal was opened (or its author): "mine" on the board.
    owner_user_id    int                    NOT NULL,
    stage            varchar(12)            NOT NULL,
    value            decimal(18, 2)         NOT NULL,
    currency         char(3)                NOT NULL CONSTRAINT df_deals_currency DEFAULT ('PLN'),
    expected_close   date                   NOT NULL,
    offer_id         bigint                 NULL,
    lost_reason      nvarchar(400)          NULL,
    stage_changed_at datetime2(3)           NOT NULL CONSTRAINT df_deals_stage_changed_at DEFAULT (SYSUTCDATETIME()),
    closed_at        datetime2(3)           NULL,
    created_by       int                    NOT NULL,
    created_at       datetime2(3)           NOT NULL CONSTRAINT df_deals_created_at DEFAULT (SYSUTCDATETIME()),
    updated_at       datetime2(3)           NOT NULL CONSTRAINT df_deals_updated_at DEFAULT (SYSUTCDATETIME()),
    updated_by       int                    NULL,
    row_version      rowversion             NOT NULL,
    CONSTRAINT pk_deals PRIMARY KEY CLUSTERED (id),
    CONSTRAINT fk_deals_client FOREIGN KEY (client_id) REFERENCES crm.clients (id),
    CONSTRAINT fk_deals_owner FOREIGN KEY (owner_user_id) REFERENCES crm.users (id),
    CONSTRAINT fk_deals_stage FOREIGN KEY (stage) REFERENCES crm.deal_stages (stage),
    CONSTRAINT fk_deals_offer FOREIGN KEY (offer_id) REFERENCES crm.offers (id),
    CONSTRAINT fk_deals_created_by FOREIGN KEY (created_by) REFERENCES crm.users (id),
    CONSTRAINT ck_deals_value CHECK (value >= 0)
);

-- The board reads open deals and the recently closed ones; a salesperson's board starts from their deals.
CREATE INDEX ix_deals_stage ON crm.deals (stage, expected_close) INCLUDE (owner_user_id, client_id, value, closed_at);
CREATE INDEX ix_deals_owner ON crm.deals (owner_user_id, stage) INCLUDE (expected_close, value, closed_at);
CREATE INDEX ix_deals_client ON crm.deals (client_id);
