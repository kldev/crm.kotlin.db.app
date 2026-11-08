-- An agent registers a ticket (a call, an e-mail); may date it back up to 30 days. Returns the new ticket.
CREATE OR ALTER PROCEDURE app.desk_ticket_report
    @actor_id            int,
    @title               nvarchar(4000),
    @description         nvarchar(max),
    @category_key        varchar(40),
    @subcategory_key     varchar(60),
    @priority            varchar(8),
    @reported_at         datetime2(3),
    @requester_person_id int = NULL,
    @requester_incognito bit = 0
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    IF @actor_id IS NULL
        THROW 50001, N'Actor is not set.', 1;

    DECLARE @ticket_id bigint;
    EXEC crm.desk_ticket_create @actor_id, @title, @description, @category_key, @subcategory_key, @priority,
         @reported_at, @requester_person_id, @requester_incognito, @ticket_id OUTPUT;
    EXEC crm.desk_ticket_select @ticket_id;
END;
