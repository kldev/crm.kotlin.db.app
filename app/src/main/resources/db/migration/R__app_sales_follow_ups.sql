/*
  "My day" (ADR-0017): the open deals whose next step is due by @until (UTC) - overdue ones included, oldest first.
  @scope MINE (I own them) or ALL (SALES: still only deals of their own clients). At most 200.
*/
CREATE OR ALTER PROCEDURE app.sales_follow_ups
    @actor_id int,
    @until    datetime2(3),
    @scope    varchar(10) = 'MINE'
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @role varchar(10);
    EXEC crm.actor_require @actor_id, @role OUTPUT;
    IF ISNULL(@scope, '') NOT IN ('MINE', 'ALL')
        THROW 51195, N'Scope must be MINE or ALL.', 1;
    IF @until IS NULL
        SET @until = SYSUTCDATETIME();
    SELECT TOP (200) d.id, d.title, d.client_id, c.name AS client_name, d.owner_user_id, o.display_name AS owner_name, d.stage,
           s.probability, s.is_closed, d.value, d.currency, d.expected_close, d.offer_id, f.number AS offer_number,
           d.lost_reason, d.stage_changed_at, d.closed_at, d.created_at, d.updated_at, d.row_version,
           d.next_step, d.next_step_at, d.last_activity_at, d.last_activity_type
    FROM crm.deals AS d
    JOIN crm.deal_stages AS s ON s.stage = d.stage
    JOIN crm.clients AS c ON c.id = d.client_id
    JOIN crm.users AS o ON o.id = d.owner_user_id
    LEFT JOIN crm.offers AS f ON f.id = d.offer_id
    WHERE d.next_step_at <= @until
      AND s.is_closed = 0
      AND (@role <> 'SALES' OR c.assigned_user_id = @actor_id)
      AND (@scope <> 'MINE' OR d.owner_user_id = @actor_id)
    ORDER BY d.next_step_at, d.id
    OPTION (RECOMPILE);
END;
