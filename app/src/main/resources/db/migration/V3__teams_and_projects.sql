-- Teams deliver projects for clients; one CRM user owns (delivers) each project. Projects move through stages
-- and collect comments (ADR-0005).

CREATE TABLE crm.teams
(
    id           int IDENTITY (1, 1) NOT NULL,
    name         nvarchar(200)       NOT NULL,
    lead_user_id int                 NOT NULL,
    created_at   datetime2(3)        NOT NULL CONSTRAINT df_teams_created_at DEFAULT (SYSUTCDATETIME()),
    created_by   int                 NULL,
    CONSTRAINT pk_teams PRIMARY KEY CLUSTERED (id),
    CONSTRAINT uq_teams_name UNIQUE (name),
    CONSTRAINT fk_teams_lead_user FOREIGN KEY (lead_user_id) REFERENCES crm.users (id)
);

CREATE TABLE crm.team_members
(
    team_id   int          NOT NULL,
    user_id   int          NOT NULL,
    joined_at datetime2(3) NOT NULL CONSTRAINT df_team_members_joined_at DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT pk_team_members PRIMARY KEY CLUSTERED (team_id, user_id),
    CONSTRAINT fk_team_members_team FOREIGN KEY (team_id) REFERENCES crm.teams (id),
    CONSTRAINT fk_team_members_user FOREIGN KEY (user_id) REFERENCES crm.users (id)
);

-- "Which teams am I in" - part of the visibility rule of SALES users.
CREATE UNIQUE INDEX ux_team_members_user ON crm.team_members (user_id, team_id);

-- Allowed stage changes. The rule lives in data: a new transition is an INSERT, not a code release.
CREATE TABLE crm.project_stage_transitions
(
    from_stage varchar(12) NOT NULL,
    to_stage   varchar(12) NOT NULL,
    CONSTRAINT pk_project_stage_transitions PRIMARY KEY CLUSTERED (from_stage, to_stage)
);

INSERT crm.project_stage_transitions (from_stage, to_stage)
VALUES ('NEW', 'ACCEPTED'),
       ('NEW', 'DECLINED'),
       ('ACCEPTED', 'ACTIVE'),
       ('ACCEPTED', 'DECLINED'),
       ('ACTIVE', 'ON_HOLD'),
       ('ACTIVE', 'CLOSED'),
       ('ON_HOLD', 'ACTIVE'),
       ('ON_HOLD', 'CLOSED');

CREATE TABLE crm.projects
(
    id               bigint IDENTITY (1, 1) NOT NULL,
    client_id        bigint                 NOT NULL,
    team_id          int                    NOT NULL,
    owner_user_id    int                    NOT NULL,
    name             nvarchar(200)          NOT NULL,
    stage            varchar(12)            NOT NULL,
    start_date       date                   NOT NULL,
    due_date         date                   NOT NULL,
    budget           decimal(19, 2)         NOT NULL,
    stage_changed_at datetime2(3)           NOT NULL CONSTRAINT df_projects_stage_changed_at DEFAULT (SYSUTCDATETIME()),
    created_at       datetime2(3)           NOT NULL CONSTRAINT df_projects_created_at DEFAULT (SYSUTCDATETIME()),
    created_by       int                    NULL,
    updated_at       datetime2(3)           NOT NULL CONSTRAINT df_projects_updated_at DEFAULT (SYSUTCDATETIME()),
    updated_by       int                    NULL,
    row_version      rowversion             NOT NULL,
    CONSTRAINT pk_projects PRIMARY KEY CLUSTERED (id),
    CONSTRAINT ck_projects_stage CHECK (stage IN ('NEW', 'ACCEPTED', 'ACTIVE', 'ON_HOLD', 'CLOSED', 'DECLINED')),
    CONSTRAINT ck_projects_dates CHECK (due_date >= start_date),
    CONSTRAINT ck_projects_budget CHECK (budget >= 0),
    CONSTRAINT fk_projects_client FOREIGN KEY (client_id) REFERENCES crm.clients (id),
    CONSTRAINT fk_projects_team FOREIGN KEY (team_id) REFERENCES crm.teams (id),
    CONSTRAINT fk_projects_owner_user FOREIGN KEY (owner_user_id) REFERENCES crm.users (id)
);

-- Every list of projects is ordered by (due_date, id) and paged by keyset; each index ends with those columns.
CREATE INDEX ix_projects_client ON crm.projects (client_id, due_date, id) INCLUDE (stage, team_id, owner_user_id);
CREATE INDEX ix_projects_team ON crm.projects (team_id, due_date, id) INCLUDE (stage, client_id, owner_user_id);
CREATE INDEX ix_projects_owner ON crm.projects (owner_user_id, due_date, id) INCLUDE (stage, client_id, team_id);
CREATE INDEX ix_projects_stage ON crm.projects (stage, due_date, id) INCLUDE (team_id, client_id, owner_user_id);
-- Overdue = open project after its due date: a filtered index on open projects only, not on millions of closed ones.
CREATE INDEX ix_projects_open_due ON crm.projects (due_date, id) INCLUDE (stage, team_id, client_id, owner_user_id)
    WHERE stage IN ('NEW', 'ACCEPTED', 'ACTIVE', 'ON_HOLD');

CREATE TABLE crm.project_stage_history
(
    id          bigint IDENTITY (1, 1) NOT NULL,
    project_id  bigint                 NOT NULL,
    from_stage  varchar(12)            NULL,
    to_stage    varchar(12)            NOT NULL,
    changed_at  datetime2(3)           NOT NULL CONSTRAINT df_project_stage_history_changed_at DEFAULT (SYSUTCDATETIME()),
    changed_by  int                    NULL,
    CONSTRAINT pk_project_stage_history PRIMARY KEY NONCLUSTERED (id),
    CONSTRAINT fk_project_stage_history_project FOREIGN KEY (project_id) REFERENCES crm.projects (id)
);

-- History is always read per project, newest first: cluster it that way.
CREATE UNIQUE CLUSTERED INDEX cx_project_stage_history ON crm.project_stage_history (project_id, id);

CREATE TABLE crm.project_comments
(
    id         bigint IDENTITY (1, 1) NOT NULL,
    project_id bigint                 NOT NULL,
    author_id  int                    NOT NULL,
    body       nvarchar(4000)         NOT NULL,
    created_at datetime2(3)           NOT NULL CONSTRAINT df_project_comments_created_at DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT pk_project_comments PRIMARY KEY NONCLUSTERED (id),
    CONSTRAINT fk_project_comments_project FOREIGN KEY (project_id) REFERENCES crm.projects (id),
    CONSTRAINT fk_project_comments_author FOREIGN KEY (author_id) REFERENCES crm.users (id)
);

-- Comments of one project, newest first, paged by id: one range seek.
CREATE UNIQUE CLUSTERED INDEX cx_project_comments ON crm.project_comments (project_id, id);
GO

/*
  Read model of a project: one row with client, team, owner and team lead. Procedures read projects only through
  this view. A plain (not indexed) view: SQL Server expands it into the query, so filters reach the indexes of
  crm.projects and the joins are single-row seeks by primary key.
*/
CREATE VIEW crm.v_projects
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
       p.created_at,
       p.updated_at,
       p.row_version
FROM crm.projects AS p
JOIN crm.clients AS c ON c.id = p.client_id
JOIN crm.teams AS t ON t.id = p.team_id
JOIN crm.users AS ou ON ou.id = p.owner_user_id;
GO

/*
  Indexed (materialised) view: number of projects and budget per team and stage, kept up to date by SQL Server
  on every write to crm.projects. Team statistics read at most 6 rows instead of counting thousands of projects.
  Express never matches indexed views automatically - the reading procedure uses WITH (NOEXPAND).
*/
CREATE VIEW crm.v_team_project_stats
WITH SCHEMABINDING
AS
SELECT team_id,
       stage,
       COUNT_BIG(*) AS project_count,
       SUM(budget)  AS budget_total
FROM crm.projects
GROUP BY team_id, stage;
GO

CREATE UNIQUE CLUSTERED INDEX ux_v_team_project_stats ON crm.v_team_project_stats (team_id, stage);
