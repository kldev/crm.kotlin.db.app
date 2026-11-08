/*
  The application reports on itself (ADR-0012): every HTTP answer and the application's log from INFO up, written in
  batches from a bounded in-memory queue (never from the request), kept 14 days. Plain tables: counting by status and
  deleting by time is what they are for.
*/
CREATE TABLE crm.http_requests
(
    id          bigint IDENTITY (1, 1) NOT NULL,
    at          datetime2(3)           NOT NULL,
    method      varchar(10)            NOT NULL,
    -- Without the query string: it may carry search text.
    path        nvarchar(400)          NOT NULL,
    status      smallint               NOT NULL,
    elapsed_ms  int                    NOT NULL,
    user_login  varchar(64)            NULL,
    trace_id    varchar(64)            NULL,
    CONSTRAINT pk_http_requests PRIMARY KEY CLUSTERED (id)
);
CREATE INDEX ix_http_requests_at ON crm.http_requests (at) INCLUDE (status, elapsed_ms);
CREATE INDEX ix_http_requests_status_at ON crm.http_requests (status, at) INCLUDE (path, method);

CREATE TABLE crm.app_logs
(
    id           bigint IDENTITY (1, 1) NOT NULL,
    at           datetime2(3)           NOT NULL,
    -- INFO, WARN or ERROR (the levels written).
    level        varchar(5)             NOT NULL,
    source       nvarchar(200)          NOT NULL,
    message      nvarchar(4000)         NOT NULL,
    exception    nvarchar(max)          NULL,
    request_path nvarchar(400)          NULL,
    trace_id     varchar(64)            NULL,
    CONSTRAINT pk_app_logs PRIMARY KEY CLUSTERED (id),
    CONSTRAINT ck_app_logs_level CHECK (level IN ('INFO', 'WARN', 'ERROR'))
);
CREATE INDEX ix_app_logs_at ON crm.app_logs (at);
CREATE INDEX ix_app_logs_level_at ON crm.app_logs (level, at);
