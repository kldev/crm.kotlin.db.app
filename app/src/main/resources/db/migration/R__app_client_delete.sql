-- Only MANAGER and ADMIN delete clients; @row_version as in app.client_update.
CREATE OR ALTER PROCEDURE app.client_delete
    @actor_id    int,
    @id          bigint,
    @row_version binary(8)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE @actor_role varchar(10);
    EXEC crm.actor_require @actor_id, @actor_role OUTPUT;

    IF @actor_role NOT IN ('ADMIN', 'MANAGER')
        THROW 51301, N'You are not allowed to perform this operation.', 1;

    DECLARE @current binary(8);

    BEGIN TRANSACTION;

    SELECT @current = row_version FROM crm.clients WITH (UPDLOCK) WHERE id = @id;

    IF @current IS NULL
        THROW 51401, N'Client not found.', 1;
    IF @current <> @row_version
        THROW 51901, N'The client was changed by someone else. Reload it and try again.', 1;

    IF EXISTS (SELECT 1 FROM crm.projects WHERE client_id = @id)
        THROW 51904, N'The client has projects and cannot be deleted. Set its status to INACTIVE instead.', 1;

    DELETE crm.clients WHERE id = @id;

    COMMIT TRANSACTION;
END;
