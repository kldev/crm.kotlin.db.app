-- Repair shops and leasing companies (ADR-0018), with how many cars use each; hidden ones too, flagged.
CREATE OR ALTER PROCEDURE app.fleet_partner_list
    @actor_id int,
    @kind     varchar(12) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    SELECT p.id, p.kind, p.name, p.phone, p.note, p.is_hidden,
           (SELECT COUNT(*) FROM crm.cars AS c WHERE c.repair_shop_id = p.id OR c.leasing_id = p.id) AS cars,
           p.row_version
    FROM crm.fleet_partners AS p
    WHERE @kind IS NULL OR p.kind = @kind
    ORDER BY p.kind, p.is_hidden, p.name;
END;
