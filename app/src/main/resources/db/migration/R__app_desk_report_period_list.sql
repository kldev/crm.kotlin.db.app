-- The periods of the agents' report (local Warsaw days, [from, to)), for the headers also when nobody worked.
CREATE OR ALTER PROCEDURE app.desk_report_period_list
    @actor_id int,
    @previous bit = 0
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    DECLARE @wf date, @wt date, @mf date, @mt date, @tf date, @tt date;
    EXEC crm.desk_report_periods @previous, @wf OUTPUT, @wt OUTPUT, @mf OUTPUT, @mt OUTPUT, @tf OUTPUT, @tt OUTPUT;
    SELECT @wf AS week_from, @wt AS week_to, @mf AS month_from, @mt AS month_to, @tf AS three_from, @tt AS three_to;
END;
