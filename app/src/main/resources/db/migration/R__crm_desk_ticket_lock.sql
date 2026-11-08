-- Internal (ADR-0007): the ticket's state under an update lock, inside the caller's transaction. Two writers of one
-- ticket queue up, so the second decides on the state the first one left ("already in progress with ...").
CREATE OR ALTER PROCEDURE crm.desk_ticket_lock
    @ticket_id        bigint,
    @status           varchar(12)   OUTPUT,
    @assignee_user_id int           OUTPUT,
    @assignee_name    nvarchar(200) OUTPUT,
    @version          int           OUTPUT
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    IF @@TRANCOUNT = 0
        THROW 50002, N'crm.desk_ticket_lock needs a transaction.', 1;

    SELECT @status = status, @assignee_user_id = assignee_user_id, @assignee_name = assignee_name, @version = version
    FROM crm.tickets WITH (UPDLOCK, HOLDLOCK)
    WHERE id = @ticket_id;

    IF @status IS NULL
        THROW 51410, N'Ticket not found.', 1;
END;
