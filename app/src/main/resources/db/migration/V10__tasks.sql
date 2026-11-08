/*
  Tasks (ADR-0014): who does what from which day to which day, shown on a month calendar and a timeline. No workflow
  of statuses - a task is open or done. Users get a department (set by an administrator) for the "my department" view;
  the departments are the list the desk's people use.
*/
CREATE TABLE crm.departments
(
    name       nvarchar(50) NOT NULL,
    sort_order int          NOT NULL,
    CONSTRAINT pk_departments PRIMARY KEY CLUSTERED (name)
);

INSERT crm.departments (name, sort_order)
SELECT option_value, sort_order FROM crm.desk_field_options WHERE field_key = 'department';

ALTER TABLE crm.users ADD department nvarchar(50) NULL
    CONSTRAINT fk_users_department FOREIGN KEY REFERENCES crm.departments (name);
GO

CREATE TABLE crm.tasks
(
    id               bigint IDENTITY (1, 1) NOT NULL,
    title            nvarchar(200)          NOT NULL,
    description      nvarchar(2000)         NOT NULL CONSTRAINT df_tasks_description DEFAULT (N''),
    assignee_user_id int                    NOT NULL,
    -- Calendar days in Warsaw, both included.
    start_date       date                   NOT NULL,
    end_date         date                   NOT NULL,
    is_done          bit                    NOT NULL CONSTRAINT df_tasks_is_done DEFAULT (0),
    done_at          datetime2(3)           NULL,
    client_id        bigint                 NULL,
    project_id       bigint                 NULL,
    created_by       int                    NOT NULL,
    created_at       datetime2(3)           NOT NULL CONSTRAINT df_tasks_created_at DEFAULT (SYSUTCDATETIME()),
    updated_at       datetime2(3)           NOT NULL CONSTRAINT df_tasks_updated_at DEFAULT (SYSUTCDATETIME()),
    updated_by       int                    NULL,
    row_version      rowversion             NOT NULL,
    CONSTRAINT pk_tasks PRIMARY KEY CLUSTERED (id),
    CONSTRAINT fk_tasks_assignee FOREIGN KEY (assignee_user_id) REFERENCES crm.users (id),
    CONSTRAINT fk_tasks_created_by FOREIGN KEY (created_by) REFERENCES crm.users (id),
    CONSTRAINT fk_tasks_client FOREIGN KEY (client_id) REFERENCES crm.clients (id),
    CONSTRAINT fk_tasks_project FOREIGN KEY (project_id) REFERENCES crm.projects (id),
    CONSTRAINT ck_tasks_dates CHECK (end_date >= start_date)
);

-- The calendar and the timeline read the tasks overlapping a window: start <= window end, end >= window start.
CREATE INDEX ix_tasks_start ON crm.tasks (start_date, end_date) INCLUDE (assignee_user_id, is_done);
CREATE INDEX ix_tasks_assignee ON crm.tasks (assignee_user_id, start_date) INCLUDE (end_date, is_done);
