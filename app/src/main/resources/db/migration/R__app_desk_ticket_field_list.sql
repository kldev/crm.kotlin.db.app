-- The report data of a ticket: its current values, in the subcategory's order.
CREATE OR ALTER PROCEDURE app.desk_ticket_field_list
    @actor_id  int,
    @ticket_id bigint
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    IF NOT EXISTS (SELECT 1 FROM crm.tickets WHERE id = @ticket_id)
        THROW 51410, N'Ticket not found.', 1;
    SELECT tf.field_key, tf.value
    FROM crm.ticket_fields AS tf
    JOIN crm.tickets AS t ON t.id = tf.ticket_id
    LEFT JOIN crm.desk_subcategory_fields AS sf ON sf.subcategory_key = t.subcategory_key AND sf.field_key = tf.field_key
    WHERE tf.ticket_id = @ticket_id
    ORDER BY ISNULL(sf.sort_order, 999), tf.field_key;
END;
