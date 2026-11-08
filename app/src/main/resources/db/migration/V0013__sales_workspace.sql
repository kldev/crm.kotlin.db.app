/*
  The salesperson's workspace (ADR-0017): what happened on a deal (an append-only log of activities), what happens next
  (one follow-up - the next step with its date and time - on the deal), and tasks that belong to a deal.
*/
CREATE TABLE crm.deal_activity_types
(
    activity_type varchar(12)  NOT NULL,
    sort_order    int          NOT NULL,
    name_pl       nvarchar(50) NOT NULL,
    name_en       nvarchar(50) NOT NULL,
    CONSTRAINT pk_deal_activity_types PRIMARY KEY CLUSTERED (activity_type)
);

INSERT crm.deal_activity_types (activity_type, sort_order, name_pl, name_en)
VALUES ('CALL', 1, N'Telefon', N'Call'), ('EMAIL', 2, N'E-mail', N'E-mail'), ('MEETING', 3, N'Spotkanie', N'Meeting'),
       ('PRESENTATION', 4, N'Prezentacja', N'Presentation'), ('NOTE', 5, N'Notatka', N'Note'),
       ('TASK', 6, N'Zadanie', N'Task'), ('OTHER', 7, N'Inne', N'Other');

CREATE TABLE crm.deal_activities
(
    id            bigint IDENTITY (1, 1) NOT NULL,
    deal_id       bigint                 NOT NULL,
    activity_type varchar(12)            NOT NULL,
    note          nvarchar(1000)         NOT NULL,
    -- When it happened (UTC); may be earlier than created_at - a call logged in the evening.
    occurred_at   datetime2(3)           NOT NULL,
    created_by    int                    NOT NULL,
    created_at    datetime2(3)           NOT NULL CONSTRAINT df_deal_activities_created_at DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT pk_deal_activities PRIMARY KEY CLUSTERED (id),
    CONSTRAINT fk_deal_activities_deal FOREIGN KEY (deal_id) REFERENCES crm.deals (id) ON DELETE CASCADE,
    CONSTRAINT fk_deal_activities_type FOREIGN KEY (activity_type) REFERENCES crm.deal_activity_types (activity_type),
    CONSTRAINT fk_deal_activities_created_by FOREIGN KEY (created_by) REFERENCES crm.users (id)
);
CREATE INDEX ix_deal_activities_deal ON crm.deal_activities (deal_id, occurred_at DESC, id DESC);

ALTER TABLE crm.deals ADD
    -- The follow-up: the next step and when (UTC). Both or neither.
    next_step          nvarchar(400) NULL,
    next_step_at       datetime2(3)  NULL,
    -- The newest activity, for the cards and "no contact for N days".
    last_activity_at   datetime2(3)  NULL,
    last_activity_type varchar(12)   NULL,
    CONSTRAINT ck_deals_next_step CHECK ((next_step IS NULL AND next_step_at IS NULL) OR (next_step IS NOT NULL AND next_step_at IS NOT NULL));
GO
-- "My day" reads a salesperson's follow-ups due by a moment.
CREATE INDEX ix_deals_follow_up ON crm.deals (owner_user_id, next_step_at) INCLUDE (stage, client_id) WHERE next_step_at IS NOT NULL;

-- A task may belong to a deal; finishing it is logged on the deal.
ALTER TABLE crm.tasks ADD deal_id bigint NULL CONSTRAINT fk_tasks_deal FOREIGN KEY REFERENCES crm.deals (id);
GO
CREATE INDEX ix_tasks_deal ON crm.tasks (deal_id) WHERE deal_id IS NOT NULL;
-- "Today" reads a person's open tasks that have started.
CREATE INDEX ix_tasks_agenda ON crm.tasks (assignee_user_id, is_done, start_date) INCLUDE (end_date);
