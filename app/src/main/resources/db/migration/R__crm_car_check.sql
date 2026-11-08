/*
  Internal (ADR-0018): a car's data. Name 1-100 (51220), production year 1900..next year (51221), plate of letters,
  digits, spaces and hyphens up to 15, stored upper case (51222), VIN of 17 letters and digits without I, O, Q (51223),
  notes up to 1000, make up to 60 (51224), a company of the group (51408), deadlines (none).
*/
CREATE OR ALTER PROCEDURE crm.car_check
    @name            nvarchar(4000) OUTPUT,
    @make            nvarchar(4000) OUTPUT,
    @production_year int,
    @plate           varchar(100)   OUTPUT,
    @vin             varchar(100)   OUTPUT,
    @notes           nvarchar(4000) OUTPUT,
    @legal_entity_id int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    SELECT @name = NULLIF(LTRIM(RTRIM(@name)), N''), @make = NULLIF(LTRIM(RTRIM(@make)), N''),
           @plate = UPPER(NULLIF(LTRIM(RTRIM(@plate)), '')), @vin = UPPER(NULLIF(REPLACE(@vin, ' ', ''), '')),
           @notes = NULLIF(LTRIM(RTRIM(@notes)), N'');
    IF @name IS NULL OR LEN(@name) > 100
        THROW 51220, N'The name is required (at most 100 characters).', 1;
    IF @production_year IS NOT NULL AND (@production_year < 1900 OR @production_year > YEAR(crm.fleet_today()) + 1)
        THROW 51221, N'The production year is between 1900 and next year.', 1;
    IF @plate IS NULL OR LEN(@plate) > 15 OR @plate LIKE '[^A-Z0-9]%' OR @plate LIKE '%[^A-Z0-9 -]%'
        THROW 51222, N'The registration number: letters, digits, spaces and hyphens, at most 15.', 1;
    IF @vin IS NOT NULL AND (LEN(@vin) <> 17 OR @vin LIKE '%[^A-HJ-NPR-Z0-9]%')
        THROW 51223, N'The VIN has 17 letters and digits, without I, O and Q.', 1;
    IF LEN(@notes) > 1000 OR LEN(@make) > 60
        THROW 51224, N'The notes have at most 1000 characters, the make 60.', 1;
    IF NOT EXISTS (SELECT 1 FROM crm.legal_entities WHERE id = @legal_entity_id)
        THROW 51408, N'Company not found.', 1;
END;
