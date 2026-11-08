/*
  Internal (ADR-0014): the rules of a task's fields. Title 1-200 (51180), description up to 2000 (51184), the end not
  before the start and at most a year long (51181), an active assignee (51402), an existing client and project (51401 /
  51403). Normalizes @title and @description.
*/
CREATE OR ALTER PROCEDURE crm.task_check
    @title            nvarchar(4000) OUTPUT,
    @description      nvarchar(max)  OUTPUT,
    @assignee_user_id int,
    @start_date       date,
    @end_date         date,
    @client_id        bigint,
    @project_id       bigint
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    SET @title = LTRIM(RTRIM(@title));
    SET @description = LTRIM(RTRIM(ISNULL(@description, N'')));
    IF @title IS NULL OR @title = N'' OR LEN(@title) > 200
        THROW 51180, N'The title is required and can have at most 200 characters.', 1;
    IF LEN(@description) > 2000
        THROW 51184, N'The description can have at most 2000 characters.', 1;
    IF @start_date IS NULL OR @end_date IS NULL OR @end_date < @start_date OR DATEDIFF(DAY, @start_date, @end_date) > 365
        THROW 51181, N'The end must not be before the start, and a task can last at most a year.', 1;
    IF NOT EXISTS (SELECT 1 FROM crm.users WHERE id = @assignee_user_id AND is_active = 1)
        THROW 51402, N'User not found.', 1;
    IF @client_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM crm.clients WHERE id = @client_id)
        THROW 51401, N'Client not found.', 1;
    IF @project_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM crm.projects WHERE id = @project_id)
        THROW 51403, N'Project not found.', 1;
END;
