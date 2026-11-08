-- A car's statuses, newest first (ADR-0018).
CREATE OR ALTER PROCEDURE app.car_status_history
    @actor_id int,
    @car_id   int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    SELECT h.id, h.status, s.name_pl AS status_name_pl, s.name_en AS status_name_en, h.effective_on, h.repair_shop, h.note,
           h.changed_by, u.display_name AS changed_by_name, h.changed_at
    FROM crm.car_status_history AS h
    JOIN crm.car_statuses AS s ON s.status = h.status
    JOIN crm.users AS u ON u.id = h.changed_by
    WHERE h.car_id = @car_id
    ORDER BY h.id DESC;
END;
