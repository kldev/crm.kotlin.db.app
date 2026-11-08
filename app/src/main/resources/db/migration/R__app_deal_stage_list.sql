-- The pipeline's stages in order, with the probability that weights the forecast (ADR-0015).
CREATE OR ALTER PROCEDURE app.deal_stage_list
    @actor_id int
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.actor_require @actor_id;
    SELECT stage, sort_order, probability, is_closed, name_pl, name_en FROM crm.deal_stages ORDER BY sort_order;
END;
