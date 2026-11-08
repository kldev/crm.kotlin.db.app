/*
  A car's status, set by hand (ADR-0018) - managers. From the effective day: not in the future, not before the current
  status began (51227). The repair-shop statuses need a shop of the list (51228); its name is kept in the history. FOR
  SALE and ARCHIVED only with no current or future handover (51920). Out of ARCHIVED only an administrator, only to
  OPERATIONAL, and only while the plate is free (51921, a taken plate is 2601).
*/
CREATE OR ALTER PROCEDURE app.car_change_status
    @actor_id       int,
    @car_id         int,
    @status         varchar(20),
    @effective_on   date          = NULL,
    @repair_shop_id int           = NULL,
    @note           nvarchar(400) = NULL,
    @row_version    binary(8)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @role varchar(10);
    EXEC crm.fleet_require_manager @actor_id, @role OUTPUT;
    DECLARE @current varchar(20), @since date, @today date = crm.fleet_today();
    SELECT @current = status, @since = status_since FROM crm.cars WHERE id = @car_id;
    IF @current IS NULL
        THROW 51409, N'Car not found.', 1;
    DECLARE @needs_shop bit = (SELECT needs_shop FROM crm.car_statuses WHERE status = @status);
    IF @needs_shop IS NULL OR @status = @current
        THROW 51227, N'Choose another status from the list.', 1;
    SET @effective_on = ISNULL(@effective_on, @today);
    IF @effective_on > @today OR @effective_on < @since
        THROW 51227, N'The status changes from a day between the current status start and today.', 1;
    DECLARE @shop nvarchar(120) = (SELECT name FROM crm.fleet_partners WHERE id = @repair_shop_id AND kind = 'REPAIR_SHOP' AND is_hidden = 0);
    IF @needs_shop = 1 AND @shop IS NULL
        THROW 51228, N'Choose the repair shop from the list.', 1;
    IF @status IN ('FOR_SALE', 'ARCHIVED') AND EXISTS (SELECT 1 FROM crm.car_handovers
            WHERE car_id = @car_id AND cancelled_at IS NULL AND returned_on IS NULL)
        THROW 51920, N'A car with a current or planned handover is neither sold nor archived.', 1;
    IF @current = 'ARCHIVED' AND (@role <> 'ADMIN' OR @status <> 'OPERATIONAL')
        THROW 51921, N'Only an administrator brings a car back from the archive, as operational.', 1;
    SET @note = NULLIF(LTRIM(RTRIM(@note)), N'');
    BEGIN TRANSACTION;
    UPDATE crm.cars
    SET status = @status, status_since = @effective_on, repair_shop_id = IIF(@needs_shop = 1, @repair_shop_id, NULL),
        updated_at = SYSUTCDATETIME(), updated_by = @actor_id
    WHERE id = @car_id AND row_version = @row_version;
    IF @@ROWCOUNT = 0
        THROW 51901, N'The record was changed by someone else. Reload it and try again.', 1;
    INSERT crm.car_status_history (car_id, status, effective_on, repair_shop, note, changed_by)
    VALUES (@car_id, @status, @effective_on, IIF(@needs_shop = 1, @shop, NULL), @note, @actor_id);
    COMMIT;
    DECLARE @money bit = 1;
    EXEC crm.car_select @car_id = @car_id, @show_money = @money;
END;
