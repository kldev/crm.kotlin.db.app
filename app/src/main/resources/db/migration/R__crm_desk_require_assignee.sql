-- Internal (ADR-0007): the rule of every action of the agent working on a ticket.
-- 51912 in the pool, 51911 resolved, 51310..51313 somebody else's ticket. @action: HAND_OVER, RETURN, RESOLVE, HANDLER.
CREATE OR ALTER PROCEDURE crm.desk_require_assignee
    @status           varchar(12),
    @assignee_user_id int,
    @assignee_name    nvarchar(200),
    @actor_id         int,
    @action           varchar(10)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    IF @status = 'IN_POOL'
        THROW 51912, N'The ticket is in the pool: take it first.', 1;
    IF @status = 'DONE'
        THROW 51911, N'The ticket is already resolved.', 1;
    IF @assignee_user_id <> @actor_id
    BEGIN
        DECLARE @number int = CASE @action WHEN 'HAND_OVER' THEN 51310 WHEN 'RETURN' THEN 51311
                                           WHEN 'RESOLVE' THEN 51312 ELSE 51313 END;
        DECLARE @message nvarchar(400) = FORMATMESSAGE(
            CASE @action
                WHEN 'HAND_OVER' THEN N'Only the agent working on the ticket (%s) can hand it over.'
                WHEN 'RETURN' THEN N'Only the agent working on the ticket (%s) can return it to the pool.'
                WHEN 'RESOLVE' THEN N'Only the agent working on the ticket (%s) can resolve it.'
                ELSE N'Only the agent working on the ticket (%s) can name its handler.'
            END, @assignee_name);
        THROW @number, @message, 1;
    END;
END;
