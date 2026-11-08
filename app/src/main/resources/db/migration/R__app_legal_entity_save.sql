/*
  Add a company (@legal_entity_id NULL) or change one (with @row_version, 51901) - ADMIN only (51301). Closing is
  setting active_to: the company stays for its projects and offers. A duplicate name or NIP is 2627 (409).
*/
CREATE OR ALTER PROCEDURE app.legal_entity_save
    @actor_id        int,
    @legal_entity_id int            = NULL,
    @name            nvarchar(4000),
    @legal_name      nvarchar(4000),
    @tax_id          varchar(100),
    @vat_number      varchar(20)    = NULL,
    @address         nvarchar(4000),
    @phone           varchar(100)   = NULL,
    @email           nvarchar(4000) = NULL,
    @website         nvarchar(200)  = NULL,
    @bank_account    varchar(100)   = NULL,
    @active_from     date,
    @active_to       date           = NULL,
    @row_version     binary(8)      = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @role varchar(10);
    EXEC crm.actor_require @actor_id, @role OUTPUT;
    IF @role <> 'ADMIN'
        THROW 51301, N'Only an administrator manages the companies.', 1;
    EXEC crm.legal_entity_check @name OUTPUT, @legal_name OUTPUT, @tax_id OUTPUT, @address OUTPUT, @phone OUTPUT,
         @email OUTPUT, @bank_account OUTPUT, @active_from, @active_to;
    SELECT @vat_number = NULLIF(UPPER(LTRIM(RTRIM(@vat_number))), ''), @website = NULLIF(LTRIM(RTRIM(@website)), N'');

    IF @legal_entity_id IS NULL
    BEGIN
        INSERT crm.legal_entities (name, legal_name, tax_id, vat_number, address, phone, email, website, bank_account,
                                   active_from, active_to, updated_by)
        VALUES (@name, @legal_name, @tax_id, @vat_number, @address, @phone, @email, @website, @bank_account,
                @active_from, @active_to, @actor_id);
        SET @legal_entity_id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM crm.legal_entities WHERE id = @legal_entity_id)
            THROW 51408, N'Company not found.', 1;
        UPDATE crm.legal_entities
        SET name = @name, legal_name = @legal_name, tax_id = @tax_id, vat_number = @vat_number, address = @address,
            phone = @phone, email = @email, website = @website, bank_account = @bank_account, active_from = @active_from,
            active_to = @active_to, updated_at = SYSUTCDATETIME(), updated_by = @actor_id
        WHERE id = @legal_entity_id AND row_version = @row_version;
        IF @@ROWCOUNT = 0
            THROW 51901, N'The record was changed by someone else. Reload it and try again.', 1;
    END;
    EXEC crm.legal_entity_select @legal_entity_id;
END;
