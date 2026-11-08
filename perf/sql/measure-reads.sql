/*
  Logical reads and CPU/elapsed time of each read procedure on the seeded database (SET STATISTICS IO, TIME).
  Run as the migrator after ./start.sh --seed:  perf/sql/measure-reads.sh <results dir>
  Every call runs twice; the second (warm cache, compiled plan) is the one to read.
  Two comparisons show why the procedures look the way they do: OFFSET paging vs keyset, and team statistics
  counted from the table vs read from the indexed view.
*/
SET NOCOUNT ON;

DECLARE @sales int = (SELECT id FROM crm.users WHERE login = 'perf.sales.0001');
DECLARE @manager int = (SELECT id FROM crm.users WHERE login = 'perf.manager.0001');
DECLARE @client bigint = (SELECT MAX(id) FROM crm.clients WHERE assigned_user_id = @sales);
DECLARE @project bigint = (SELECT MAX(id) FROM crm.projects WHERE owner_user_id = @sales);
DECLARE @team int = (SELECT team_id FROM crm.team_members WHERE user_id = @sales);
DECLARE @nip varchar(20) = (SELECT nip FROM crm.clients WHERE id = 2500000);
DECLARE @i int = 1;

WHILE @i <= 2
BEGIN
    IF @i = 2 BEGIN SET STATISTICS IO ON; SET STATISTICS TIME ON; END;

    PRINT '==== client_search: newest first (MANAGER, 5M rows)';
    EXEC app.client_search @actor_id = @manager, @page_size = 20;
    PRINT '==== client_search: name prefix Zielony (MANAGER)';
    EXEC app.client_search @actor_id = @manager, @name_prefix = N'Zielony', @page_size = 20;
    PRINT '==== client_search: name prefix Zielony (SALES, own clients)';
    EXEC app.client_search @actor_id = @sales, @name_prefix = N'Zielony', @page_size = 20;
    PRINT '==== client_search: city + status (MANAGER)';
    EXEC app.client_search @actor_id = @manager, @city = N'Gdańsk', @status = 'ACTIVE', @page_size = 20;
    PRINT '==== client_search: exact NIP (MANAGER)';
    EXEC app.client_search @actor_id = @manager, @nip = @nip, @page_size = 20;
    PRINT '==== client_get';
    EXEC app.client_get @actor_id = @sales, @id = @client;

    PRINT '==== project_search: all by due date (MANAGER, 5M rows)';
    EXEC app.project_search @actor_id = @manager, @page_size = 20;
    PRINT '==== project_search: overdue (MANAGER, filtered index)';
    EXEC app.project_search @actor_id = @manager, @overdue_only = 1, @page_size = 20;
    PRINT '==== project_search: stage ACTIVE (MANAGER)';
    EXEC app.project_search @actor_id = @manager, @stage = 'ACTIVE', @page_size = 20;
    PRINT '==== project_search: team (MANAGER)';
    EXEC app.project_search @actor_id = @manager, @team_id = @team, @page_size = 20;
    PRINT '==== project_search: visible to SALES (own + team + clients)';
    EXEC app.project_search @actor_id = @sales, @page_size = 20;
    PRINT '==== project_search: overdue visible to SALES';
    EXEC app.project_search @actor_id = @sales, @overdue_only = 1, @page_size = 20;
    PRINT '==== project_get';
    EXEC app.project_get @actor_id = @sales, @id = @project;
    PRINT '==== project_stage_history_list';
    EXEC app.project_stage_history_list @actor_id = @sales, @project_id = @project;
    PRINT '==== project_comment_list';
    EXEC app.project_comment_list @actor_id = @sales, @project_id = @project, @page_size = 20;
    PRINT '==== team_project_stats (indexed view, NOEXPAND)';
    EXEC app.team_project_stats @actor_id = @manager, @team_id = @team;

    PRINT '==== COMPARISON team stats counted from crm.projects (what the indexed view saves)';
    SELECT stage, COUNT_BIG(*), SUM(budget) FROM crm.projects WHERE team_id = @team GROUP BY stage;
    PRINT '==== COMPARISON OFFSET paging, page 200 000 of clients (what keyset paging avoids)';
    SELECT id, name FROM crm.clients ORDER BY id DESC OFFSET 4000000 ROWS FETCH NEXT 20 ROWS ONLY;
    PRINT '==== COMPARISON keyset paging, the same page';
    DECLARE @after bigint = (SELECT MAX(id) FROM crm.clients) - 4000000 + 1;
    EXEC app.client_search @actor_id = @manager, @after_id = @after, @page_size = 20;

    SET STATISTICS IO OFF; SET STATISTICS TIME OFF;
    SET @i += 1;
END;
