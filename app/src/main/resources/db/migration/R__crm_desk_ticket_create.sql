/*
  Internal (ADR-0007): a new ticket - the first event of its stream (TicketReported) and its row, in one transaction.
  @actor_id NULL = the public form (channel SELF_SERVICE, reported now); otherwise an agent registers it (channel
  AGENT) and may date it back up to 30 days (a phone call this morning), never more than 5 minutes ahead.
  The requester is a person from crm.people XOR incognito. A new ticket starts in the pool.
  @attachments (JSON, ADR-0009): files already stored, recorded in the same transaction as the report.
  @fields (JSON object, ADR-0010): the report data of the subcategory, checked by crm.desk_fields_check.
*/
CREATE OR ALTER PROCEDURE crm.desk_ticket_create
    @actor_id            int,
    @title               nvarchar(4000),
    @description         nvarchar(max),
    @category_key        varchar(40),
    @subcategory_key     varchar(60),
    @priority            varchar(8),
    @reported_at         datetime2(3),
    @requester_person_id int,
    @requester_incognito bit,
    @ticket_id           bigint OUTPUT,
    @attachments         nvarchar(max) = NULL,
    @fields              nvarchar(max) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    DECLARE @now datetime2(3) = crm.desk_now();
    DECLARE @actor_name nvarchar(200);
    IF @actor_id IS NOT NULL
        EXEC crm.desk_actor @actor_id, @actor_name OUTPUT;
    ELSE
        SET @reported_at = @now;

    SET @title = LTRIM(RTRIM(@title));
    SET @description = LTRIM(RTRIM(@description));
    IF @title IS NULL OR @title = N''
        THROW 51100, N'Title is required.', 1;
    IF LEN(@title) > 200
        THROW 51101, N'Title can have at most 200 characters.', 1;
    IF @description IS NULL OR @description = N''
        THROW 51102, N'Description is required.', 1;
    IF LEN(@description) > 4000
        THROW 51103, N'Description can have at most 4000 characters.', 1;

    IF NOT EXISTS (SELECT 1 FROM crm.desk_categories WHERE category_key = @category_key)
        THROW 51104, N'Choose a category from the list.', 1;
    DECLARE @sub_active bit, @sub_name nvarchar(200);
    SELECT @sub_active = is_active, @sub_name = name
    FROM crm.desk_subcategories
    WHERE subcategory_key = @subcategory_key AND category_key = @category_key;
    IF @sub_active IS NULL
        THROW 51105, N'Choose a subcategory of the chosen category.', 1;
    IF @sub_active = 0
    BEGIN
        DECLARE @retired nvarchar(400) = FORMATMESSAGE(N'Subcategory "%s" no longer takes new tickets.', @sub_name);
        THROW 51106, @retired, 1;
    END;

    DECLARE @normalized nvarchar(max);
    EXEC crm.desk_fields_check @subcategory_key, @fields, @normalized OUTPUT;

    DECLARE @sla int = (SELECT sla_minutes FROM crm.desk_priorities WHERE priority = @priority);
    IF @sla IS NULL
        THROW 51107, N'Choose a priority.', 1;
    IF @reported_at IS NULL
        THROW 51108, N'The report date is required.', 1;
    IF @reported_at > DATEADD(MINUTE, 5, @now)
        THROW 51108, N'The report date cannot be in the future.', 1;
    IF @reported_at < DATEADD(DAY, -30, @now)
        THROW 51109, N'The report date can be at most 30 days back.', 1;

    SET @requester_incognito = ISNULL(@requester_incognito, 0);
    IF (@requester_incognito = 1 AND @requester_person_id IS NOT NULL)
        OR (@requester_incognito = 0 AND @requester_person_id IS NULL)
        THROW 51110, N'Choose the requester from the list or mark "incognito".', 1;
    DECLARE @requester_name nvarchar(201);
    IF @requester_person_id IS NOT NULL
    BEGIN
        SELECT @requester_name = first_name + N' ' + last_name FROM crm.people WHERE id = @requester_person_id;
        IF @requester_name IS NULL
            THROW 51411, N'Person not found.', 1;
    END;

    -- HAL- and 8 random hex digits; a collision (1 in 4 billion) just draws again.
    DECLARE @number char(12);
    WHILE 1 = 1
    BEGIN
        SET @number = 'HAL-' + CONVERT(char(8), CRYPT_GEN_RANDOM(4), 2);
        IF NOT EXISTS (SELECT 1 FROM crm.tickets WHERE number = @number) BREAK;
    END;

    DECLARE @channel varchar(12) = IIF(@actor_id IS NULL, 'SELF_SERVICE', 'AGENT');
    DECLARE @deadline datetime2(3) = DATEADD(MINUTE, @sla, @reported_at);

    BEGIN TRANSACTION;

    INSERT crm.tickets (number, title, description, category_key, subcategory_key, priority, original_priority,
                        reported_at, deadline, status, requester_incognito, requester_person_id, requester_name,
                        channel, registered_by_user_id, registered_by_name, recorded_at, version, last_change_at)
    VALUES (@number, @title, @description, @category_key, @subcategory_key, @priority, @priority, @reported_at,
            @deadline, 'IN_POOL', @requester_incognito, @requester_person_id, @requester_name, @channel, @actor_id,
            @actor_name, @now, 1, @now);
    SET @ticket_id = SCOPE_IDENTITY();

    DECLARE @data nvarchar(max) = JSON_OBJECT(
        'number': @number, 'title': @title, 'description': @description, 'category': @category_key,
        'subcategory': @subcategory_key, 'priority': @priority, 'reportedAt': @reported_at,
        'requester': JSON_OBJECT('incognito': CAST(@requester_incognito AS bit), 'personId': @requester_person_id,
                                 'name': @requester_name),
        'channel': @channel, 'registeredBy': @actor_name,
        'fields': JSON_QUERY(IIF(@normalized = N'{}', NULL, @normalized)));
    EXEC crm.desk_ticket_append @ticket_id, 0, 'TicketReported', @now, @actor_id, @actor_name, @data;

    INSERT crm.ticket_fields (ticket_id, field_key, value)
    SELECT @ticket_id, [key], [value] FROM OPENJSON(@normalized);

    IF @attachments IS NOT NULL
    BEGIN
        DECLARE @version int = 1;
        DECLARE @added_by nvarchar(201) = COALESCE(@actor_name, @requester_name, N'incognito');
        EXEC crm.desk_ticket_add_attachments @ticket_id, @actor_id, @added_by, @attachments, @now, @version OUTPUT;
    END;

    COMMIT;
END;
