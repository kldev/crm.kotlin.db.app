-- Internal (ADR-0007): appends the next event of the stream. (ticket_id, version) is the key, so a version stored
-- by someone else meanwhile is a conflict (51913), never an overwrite.
CREATE OR ALTER PROCEDURE crm.desk_ticket_append
    @ticket_id        bigint,
    @expected_version int,
    @event_type       varchar(40),
    @at               datetime2(3),
    @actor_user_id    int,
    @actor_name       nvarchar(201),
    @data             nvarchar(max)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRY
        INSERT crm.ticket_events (ticket_id, version, event_type, at, actor_user_id, actor_name, data)
        VALUES (@ticket_id, @expected_version + 1, @event_type, @at, @actor_user_id, @actor_name, @data);
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 51913, N'Someone was faster: the ticket has just changed. Refresh and try again.', 1;
        THROW;
    END CATCH;
END;
