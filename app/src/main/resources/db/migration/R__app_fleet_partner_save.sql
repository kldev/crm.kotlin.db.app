/*
  Add or change a repair shop or a leasing company (ADR-0018) - managers: the kind (51236), a name of 1-120 unique per
  kind ignoring case and Polish letters (2627, 409), a phone up to 40, a note up to 400 (51236). Hiding keeps it for the
  cars that used it.
*/
CREATE OR ALTER PROCEDURE app.fleet_partner_save
    @actor_id    int,
    @partner_id  int            = NULL,
    @kind        varchar(12),
    @name        nvarchar(4000),
    @phone       varchar(100)   = NULL,
    @note        nvarchar(4000) = NULL,
    @hidden      bit            = 0,
    @row_version binary(8)      = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.fleet_require_manager @actor_id;
    SELECT @name = NULLIF(LTRIM(RTRIM(@name)), N''), @phone = NULLIF(LTRIM(RTRIM(@phone)), ''), @note = NULLIF(LTRIM(RTRIM(@note)), N'');
    IF ISNULL(@kind, '') NOT IN ('REPAIR_SHOP', 'LEASING') OR @name IS NULL OR LEN(@name) > 120 OR LEN(@phone) > 40 OR LEN(@note) > 400
        THROW 51236, N'A repair shop or a leasing company with a name (at most 120), phone (40) and note (400).', 1;
    IF @partner_id IS NULL
    BEGIN
        INSERT crm.fleet_partners (kind, name, phone, note, is_hidden) VALUES (@kind, @name, @phone, @note, ISNULL(@hidden, 0));
        SET @partner_id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE crm.fleet_partners SET name = @name, phone = @phone, note = @note, is_hidden = ISNULL(@hidden, 0)
        WHERE id = @partner_id AND kind = @kind AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 51901, N'The record was changed by someone else. Reload it and try again.', 1;
    END;
    SELECT p.id, p.kind, p.name, p.phone, p.note, p.is_hidden,
           (SELECT COUNT(*) FROM crm.cars AS c WHERE c.repair_shop_id = p.id OR c.leasing_id = p.id) AS cars, p.row_version
    FROM crm.fleet_partners AS p WHERE p.id = @partner_id;
END;
