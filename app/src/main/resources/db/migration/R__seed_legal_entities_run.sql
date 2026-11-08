/*
  Seed (ADR-0016): projects seeded before multi-company all sit with the first company; spread them over the group's
  companies the way seed.run does for new ones. Once - when no project has another company - and in batches of
  200 000 rows, each its own transaction, so millions of rows never fill the log. Called by seed.desk_run.
*/
CREATE OR ALTER PROCEDURE seed.legal_entities_run
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    DECLARE @first int = (SELECT MIN(id) FROM crm.legal_entities), @count int = (SELECT COUNT(*) FROM crm.legal_entities);
    IF @count < 2 OR EXISTS (SELECT 1 FROM crm.projects WHERE legal_entity_id <> @first)
        RETURN;
    DECLARE @from bigint = (SELECT MIN(id) FROM crm.projects), @last bigint = (SELECT MAX(id) FROM crm.projects);
    WHILE @from <= @last
    BEGIN
        UPDATE crm.projects SET legal_entity_id = @first + id % @count
        WHERE id >= @from AND id < @from + 200000;
        SET @from += 200000;
    END;
END;
