-- New project in stage NEW. SALES creates projects only for own clients (otherwise 51401, as if the client
-- did not exist). The first row of the stage history (NULL -> NEW) is written in the same transaction.
CREATE OR ALTER PROCEDURE app.project_create
    @actor_id      int,
    @client_id     bigint,
    @team_id       int,
    @owner_user_id int,
    @name          nvarchar(200),
    @start_date    date,
    @due_date      date,
    @budget        decimal(19, 2),
    @legal_entity_id int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE @actor_role varchar(10);
    EXEC crm.actor_require @actor_id, @actor_role OUTPUT;

    SET @name = NULLIF(LTRIM(RTRIM(@name)), N'');

    IF NOT EXISTS (SELECT 1 FROM crm.clients
                   WHERE id = @client_id AND (@actor_role <> 'SALES' OR assigned_user_id = @actor_id))
        THROW 51401, N'Client not found.', 1;

    EXEC crm.project_validate @name, @team_id, @owner_user_id, @start_date, @due_date, @budget;
    -- The delivering company must trade when the project starts (ADR-0016).
    EXEC crm.legal_entity_require_active @legal_entity_id, @start_date;

    DECLARE @id bigint;

    BEGIN TRANSACTION;

    INSERT crm.projects (client_id, team_id, owner_user_id, name, stage, start_date, due_date, budget, legal_entity_id,
                         created_by, updated_by)
    VALUES (@client_id, @team_id, @owner_user_id, @name, 'NEW', @start_date, @due_date, @budget, @legal_entity_id,
            @actor_id, @actor_id);
    SET @id = SCOPE_IDENTITY();

    INSERT crm.project_stage_history (project_id, from_stage, to_stage, changed_by)
    VALUES (@id, NULL, 'NEW', @actor_id);

    COMMIT TRANSACTION;

    SELECT v.id, v.name, v.stage, v.start_date, v.due_date, v.budget, v.is_overdue, v.stage_changed_at,
           v.client_id, v.client_name, v.client_city, v.team_id, v.team_name, v.owner_user_id, v.owner_login,
           v.owner_display_name, v.legal_entity_id, v.legal_entity_name, v.updated_at, v.row_version
    FROM crm.v_projects AS v
    WHERE v.id = @id;
END;
