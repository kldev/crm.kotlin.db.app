/*
  The public form (no sign-in): a person reports a ticket for themselves or incognito; reported now.
  Picking a name is not authentication (ADR-0007) - the form only creates tickets, so it returns just the number.
*/
CREATE OR ALTER PROCEDURE app.desk_ticket_report_public
    @title               nvarchar(4000),
    @description         nvarchar(max),
    @category_key        varchar(40),
    @subcategory_key     varchar(60),
    @priority            varchar(8),
    @requester_person_id int = NULL,
    @requester_incognito bit = 0
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @ticket_id bigint;
    EXEC crm.desk_ticket_create NULL, @title, @description, @category_key, @subcategory_key, @priority, NULL,
         @requester_person_id, @requester_incognito, @ticket_id OUTPUT;
    SELECT id, number, deadline FROM crm.tickets WHERE id = @ticket_id;
END;
