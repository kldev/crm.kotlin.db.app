/*
  Seed (ADR-0007): replays ticket histories given as JSON (see seed.desk_run) at their moments in the past. Every step
  goes through the application's own procedure with the desk clock set to that moment, so the streams, the read model
  and the deadlines are exactly what the application would have written then. Steps of one ticket run oldest first.
  Agents are CRM users by login, people by e-mail; an unknown one stops the seed (a broken story is a bug).
*/
CREATE OR ALTER PROCEDURE seed.desk_replay
    @stories nvarchar(max)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @base datetime2(3) = SYSUTCDATETIME();
    DECLARE @sink TABLE (id bigint, number char(12), title nvarchar(200), description nvarchar(4000),
        category_key varchar(40), subcategory_key varchar(60), priority varchar(8), original_priority varchar(8),
        reported_at datetime2(3), deadline datetime2(3), status varchar(12), assignee_user_id int,
        assignee_name nvarchar(200), handler_person_id int, handler_name nvarchar(201), requester_incognito bit,
        requester_person_id int, requester_name nvarchar(201), channel varchar(12), registered_by_name nvarchar(200),
        recorded_at datetime2(3), resolved_at datetime2(3), resolved_late bit, comment_count int,
        attachment_count int, version int, last_change_at datetime2(3));

    DECLARE @stories_table TABLE (n int IDENTITY (1, 1) PRIMARY KEY, story_key varchar(100), title nvarchar(200),
        description nvarchar(4000), subcategory varchar(60), priority varchar(8), reported_ago int,
        requester varchar(254), registered_by varchar(64), fields nvarchar(max), steps nvarchar(max));
    INSERT @stories_table (story_key, title, description, subcategory, priority, reported_ago, requester, registered_by,
                           fields, steps)
    SELECT [key], title, description, subcategory, priority, reportedAgoMinutes, requester, registeredBy, fields, steps
    FROM OPENJSON(@stories)
         WITH ([key] varchar(100), title nvarchar(200), description nvarchar(4000), subcategory varchar(60),
               priority varchar(8), reportedAgoMinutes int, requester varchar(254), registeredBy varchar(64),
               fields nvarchar(max) AS JSON, steps nvarchar(max) AS JSON);

    DECLARE @i int = 1, @last int = (SELECT COUNT(*) FROM @stories_table);
    WHILE @i <= @last
    BEGIN
        DECLARE @key varchar(100), @title nvarchar(200), @description nvarchar(4000), @sub varchar(60),
                @priority varchar(8), @ago int, @requester varchar(254), @registered_by varchar(64),
                @fields nvarchar(max), @steps nvarchar(max), @message nvarchar(400);
        SELECT @key = story_key, @title = title, @description = description, @sub = subcategory, @priority = priority,
               @ago = reported_ago, @requester = requester, @registered_by = registered_by, @fields = fields,
               @steps = steps
        FROM @stories_table WHERE n = @i;

        DECLARE @category varchar(40) = (SELECT category_key FROM crm.desk_subcategories WHERE subcategory_key = @sub);
        DECLARE @person int = (SELECT id FROM crm.people WHERE email_normalized = LOWER(@requester));
        DECLARE @agent int = (SELECT id FROM crm.users WHERE login = @registered_by);
        IF (@requester IS NOT NULL AND @person IS NULL) OR (@registered_by IS NOT NULL AND @agent IS NULL)
        BEGIN
            SET @message = FORMATMESSAGE(N'Seed: story %s names an unknown person or agent.', @key);
            THROW 51050, @message, 1;
        END;
        DECLARE @incognito bit = IIF(@person IS NULL, 1, 0);
        DECLARE @reported datetime2(3) = DATEADD(MINUTE, -@ago, @base);
        DECLARE @ticket_id bigint;

        EXEC sys.sp_set_session_context N'desk.now', @reported;
        EXEC crm.desk_ticket_create @agent, @title, @description, @category, @sub, @priority, @reported, @person,
             @incognito, @ticket_id OUTPUT, NULL, @fields;

        DECLARE @step_rows TABLE (n int IDENTITY (1, 1) PRIMARY KEY, type varchar(20), ago int, agent varchar(64),
            target varchar(64), person varchar(254), priority varchar(8), reason nvarchar(500), text nvarchar(2000),
            [values] nvarchar(max));
        DELETE @step_rows;
        INSERT @step_rows (type, ago, agent, target, person, priority, reason, text, [values])
        -- In the story's order (oldest first): minutes are rounded, so two steps may share one.
        SELECT x.type, x.agoMinutes, x.agent, x.[to], x.person, x.priority, x.reason, x.text, x.[values]
        FROM OPENJSON(@steps) AS item
        CROSS APPLY OPENJSON(item.value)
             WITH (type varchar(20), agoMinutes int, agent varchar(64), [to] varchar(64), person varchar(254),
                   priority varchar(8), reason nvarchar(500), text nvarchar(2000), [values] nvarchar(max) AS JSON) AS x
        ORDER BY CAST(item.[key] AS int);

        -- The table variable keeps its IDENTITY across stories (DELETE does not reset it): walk this story's range.
        DECLARE @s int, @steps_end int;
        SELECT @s = MIN(n), @steps_end = MAX(n) FROM @step_rows;
        WHILE @s <= @steps_end
        BEGIN
            DECLARE @type varchar(20), @step_ago int, @step_agent varchar(64), @target varchar(64),
                    @step_person varchar(254), @step_priority varchar(8), @reason nvarchar(500), @text nvarchar(2000),
                    @values nvarchar(max);
            SELECT @type = type, @step_ago = ago, @step_agent = agent, @target = target, @step_person = person,
                   @step_priority = priority, @reason = reason, @text = text, @values = [values]
            FROM @step_rows WHERE n = @s;
            DECLARE @actor int = (SELECT id FROM crm.users WHERE login = @step_agent);
            IF @actor IS NULL
            BEGIN
                SET @message = FORMATMESSAGE(N'Seed: story %s has a step by an unknown agent.', @key);
                THROW 51050, @message, 1;
            END;
            DECLARE @step_at datetime2(3) = DATEADD(MINUTE, -@step_ago, @base);
            EXEC sys.sp_set_session_context N'desk.now', @step_at;

            IF @type = 'take'
                INSERT @sink EXEC app.desk_ticket_take @actor, @ticket_id;
            ELSE IF @type = 'handOver'
            BEGIN
                DECLARE @to int = (SELECT id FROM crm.users WHERE login = @target);
                INSERT @sink EXEC app.desk_ticket_hand_over @actor, @ticket_id, @to, @reason;
            END
            ELSE IF @type = 'return'
                INSERT @sink EXEC app.desk_ticket_return @actor, @ticket_id, @reason;
            ELSE IF @type = 'priority'
                INSERT @sink EXEC app.desk_ticket_change_priority @actor, @ticket_id, @step_priority, @reason;
            ELSE IF @type = 'resolve'
                INSERT @sink EXEC app.desk_ticket_resolve @actor, @ticket_id;
            ELSE IF @type = 'comment'
                INSERT @sink EXEC app.desk_ticket_comment @actor, @ticket_id, @text;
            ELSE IF @type = 'handler'
            BEGIN
                DECLARE @handler int = (SELECT id FROM crm.people WHERE email_normalized = LOWER(@step_person));
                INSERT @sink EXEC app.desk_ticket_assign_handler @actor, @ticket_id, @handler, @reason;
            END
            ELSE IF @type = 'fields'
                INSERT @sink EXEC app.desk_ticket_update_fields @actor, @ticket_id, @values;
            ELSE
            BEGIN
                SET @message = FORMATMESSAGE(N'Seed: unknown step %s.', @type);
                THROW 51050, @message, 1;
            END;
            SET @s += 1;
        END;
        SET @i += 1;
    END;
    DECLARE @none datetime2(3) = NULL;
    EXEC sys.sp_set_session_context N'desk.now', @none;
END;
