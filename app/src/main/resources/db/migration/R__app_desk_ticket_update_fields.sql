/*
  Fill in or correct the report data of a ticket (ADR-0010): @values is the whole new set - a missing or empty value
  clears the field (a required one cannot be cleared). Any agent, any state, like a comment: numbers often arrive
  after the work is done. The event lists only the changed fields with their label at that moment; nothing changed
  stores nothing. 51146 when the subcategory has no report data.
*/
CREATE OR ALTER PROCEDURE app.desk_ticket_update_fields
    @actor_id  int,
    @ticket_id bigint,
    @values    nvarchar(max)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @actor_name nvarchar(200), @now datetime2(3) = SYSUTCDATETIME();
    EXEC crm.desk_actor @actor_id, @actor_name OUTPUT;

    BEGIN TRANSACTION;
    DECLARE @status varchar(12), @assignee_id int, @assignee_name nvarchar(200), @version int;
    EXEC crm.desk_ticket_lock @ticket_id, @status OUTPUT, @assignee_id OUTPUT, @assignee_name OUTPUT, @version OUTPUT;

    DECLARE @sub varchar(60) = (SELECT subcategory_key FROM crm.tickets WHERE id = @ticket_id);
    IF NOT EXISTS (SELECT 1 FROM crm.desk_subcategory_fields WHERE subcategory_key = @sub)
        THROW 51146, N'This subcategory has no report data.', 1;

    DECLARE @normalized nvarchar(max);
    EXEC crm.desk_fields_check @sub, @values, @normalized OUTPUT;

    DECLARE @changes TABLE (n int IDENTITY (1, 1), field_key varchar(40), label nvarchar(200), old_value nvarchar(200),
                            new_value nvarchar(200));
    INSERT @changes (field_key, label, old_value, new_value)
    SELECT sf.field_key, f.label, cur.value, nxt.value
    FROM crm.desk_subcategory_fields AS sf
    JOIN crm.desk_fields AS f ON f.field_key = sf.field_key
    LEFT JOIN crm.ticket_fields AS cur ON cur.ticket_id = @ticket_id AND cur.field_key = sf.field_key
    OUTER APPLY (SELECT CAST(JSON_VALUE(@normalized, '$."' + sf.field_key + '"') AS nvarchar(200)) AS value) AS nxt
    WHERE sf.subcategory_key = @sub
      AND ISNULL(cur.value, N'') COLLATE Latin1_General_BIN2 <> ISNULL(nxt.value, N'') COLLATE Latin1_General_BIN2
    ORDER BY sf.sort_order;

    IF EXISTS (SELECT 1 FROM @changes)
    BEGIN
        DECLARE @data nvarchar(max) = JSON_OBJECT(
            'changes': JSON_QUERY((SELECT field_key AS [key], label, old_value AS [from], new_value AS [to]
                                   FROM @changes ORDER BY n FOR JSON PATH, INCLUDE_NULL_VALUES)),
            'agent': JSON_OBJECT('id': @actor_id, 'name': @actor_name));
        EXEC crm.desk_ticket_append @ticket_id, @version, 'TicketFieldsUpdated', @now, @actor_id, @actor_name, @data;

        DELETE tf FROM crm.ticket_fields AS tf
        JOIN @changes AS c ON c.field_key = tf.field_key
        WHERE tf.ticket_id = @ticket_id;
        INSERT crm.ticket_fields (ticket_id, field_key, value)
        SELECT @ticket_id, field_key, new_value FROM @changes WHERE new_value IS NOT NULL;

        UPDATE crm.tickets SET version = @version + 1, last_change_at = @now WHERE id = @ticket_id;
    END;
    COMMIT;

    EXEC crm.desk_ticket_select @ticket_id;
END;
