-- A ticket by its public number (HAL-XXXXXXXX, any letter case).
CREATE OR ALTER PROCEDURE app.desk_ticket_find
    @actor_id int,
    @number   varchar(20)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    DECLARE @ticket_id bigint = (SELECT id FROM crm.tickets WHERE number = UPPER(LTRIM(RTRIM(@number))));
    IF @ticket_id IS NULL
        THROW 51410, N'Ticket not found.', 1;
    EXEC crm.desk_ticket_select @ticket_id;
END;
