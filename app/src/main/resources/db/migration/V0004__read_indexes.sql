-- Indexes added after the first 200 VU measurement (perf/results/2026-11-08-crm-mixed-200vu/REPORT.md).

-- All projects by due date (MANAGER/ADMIN without filters): before, a scan of 100 000 pages per page of results.
CREATE INDEX ix_projects_due ON crm.projects (due_date, id) INCLUDE (stage, team_id, client_id, owner_user_id);

-- Name prefix search of a SALES user: seek on (owner, name) instead of filtering the whole prefix range.
CREATE INDEX ix_clients_assigned_user_name ON crm.clients (assigned_user_id, name, id);
