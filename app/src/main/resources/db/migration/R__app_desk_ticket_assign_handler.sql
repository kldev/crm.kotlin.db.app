/*
  Name the person (not an agent) who does the work, or take them off (@person_id NULL). Only the agent working on
  the ticket; when the category has a department, only somebody from it (51115). The same handler is a no-op.
*/
CREATE OR ALTER PROCEDURE app.desk_ticket_assign_handler
    @actor_id  int,
    @ticket_id bigint,
    @person_id int            = NULL,
    @reason    nvarchar(4000) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @actor_name nvarchar(200), @now datetime2(3) = SYSUTCDATETIME();
    EXEC crm.desk_actor @actor_id, @actor_name OUTPUT;

    SET @reason = NULLIF(LTRIM(RTRIM(@reason)), N'');
    IF LEN(@reason) > 500
        THROW 51111, N'Reason can have at most 500 characters.', 1;
    DECLARE @person_name nvarchar(201), @person_department nvarchar(50);
    IF @person_id IS NOT NULL
    BEGIN
        SELECT @person_name = first_name + N' ' + last_name, @person_department = department
        FROM crm.people WHERE id = @person_id;
        IF @person_name IS NULL
            THROW 51411, N'Person not found.', 1;
    END;

    BEGIN TRANSACTION;
    DECLARE @status varchar(12), @assignee_id int, @assignee_name nvarchar(200), @version int;
    EXEC crm.desk_ticket_lock @ticket_id, @status OUTPUT, @assignee_id OUTPUT, @assignee_name OUTPUT, @version OUTPUT;
    EXEC crm.desk_require_assignee @status, @assignee_id, @assignee_name, @actor_id, 'HANDLER';

    DECLARE @department nvarchar(50), @current int;
    SELECT @department = c.department, @current = t.handler_person_id
    FROM crm.tickets AS t
    JOIN crm.desk_categories AS c ON c.category_key = t.category_key
    WHERE t.id = @ticket_id;
    IF @person_id IS NOT NULL AND @department IS NOT NULL AND @person_department <> @department
    BEGIN
        DECLARE @wrong nvarchar(400) = FORMATMESSAGE(N'Choose a person from the department %s.', @department);
        THROW 51115, @wrong, 1;
    END;

    IF ISNULL(@current, 0) <> ISNULL(@person_id, 0)
    BEGIN
        DECLARE @data nvarchar(max) = JSON_OBJECT(
            -- JSON_QUERY keeps the nested object JSON (an IIF result alone would be escaped as a string).
            'person': JSON_QUERY(IIF(@person_id IS NULL, NULL, JSON_OBJECT('id': @person_id, 'name': @person_name))),
            'agent': JSON_OBJECT('id': @actor_id, 'name': @actor_name), 'reason': @reason);
        EXEC crm.desk_ticket_append @ticket_id, @version, 'TicketHandlerAssigned', @now, @actor_id, @actor_name, @data;

        UPDATE crm.tickets
        SET handler_person_id = @person_id, handler_name = @person_name, version = @version + 1, last_change_at = @now
        WHERE id = @ticket_id;
    END;
    COMMIT;

    EXEC crm.desk_ticket_select @ticket_id;
END;
