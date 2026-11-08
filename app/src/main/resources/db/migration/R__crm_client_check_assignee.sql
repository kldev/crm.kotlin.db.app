-- Internal helper: who may own a client. SALES works only on own clients; MANAGER and ADMIN assign a client
-- to an active SALES user or leave it unassigned.
CREATE OR ALTER PROCEDURE crm.client_check_assignee
    @actor_id         int,
    @actor_role       varchar(10),
    @assigned_user_id int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;

    IF @actor_role = 'SALES'
    BEGIN
        IF @assigned_user_id IS NULL OR @assigned_user_id <> @actor_id
            THROW 51303, N'A sales user can only work on clients assigned to themselves.', 1;
        RETURN;
    END;

    IF @assigned_user_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM crm.users WHERE id = @assigned_user_id AND role = 'SALES' AND is_active = 1)
        THROW 51017, N'A client can be assigned only to an active sales user.', 1;
END;
