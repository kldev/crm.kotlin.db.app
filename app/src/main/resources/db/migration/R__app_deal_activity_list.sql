-- A deal's activities, newest first (ADR-0017); at most 500.
CREATE OR ALTER PROCEDURE app.deal_activity_list
    @actor_id int,
    @deal_id  bigint
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.deal_require_visible @actor_id, @deal_id;
    SELECT TOP (500) a.id, a.deal_id, a.activity_type, a.note, a.occurred_at, a.created_by,
           u.display_name AS created_by_name, a.created_at
    FROM crm.deal_activities AS a
    JOIN crm.users AS u ON u.id = a.created_by
    WHERE a.deal_id = @deal_id
    ORDER BY a.occurred_at DESC, a.id DESC;
END;
