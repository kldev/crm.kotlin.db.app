/*
  Move an offer (ADR-0013): DRAFT -> SENT (with at least one line, 51176), SENT -> ACCEPTED or REJECTED, SENT -> DRAFT
  for corrections. Anything else is 51907; ACCEPTED and REJECTED are final.
*/
CREATE OR ALTER PROCEDURE app.offer_change_status
    @actor_id    int,
    @offer_id    bigint,
    @status      varchar(10),
    @row_version binary(8)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    EXEC crm.offer_require_visible @actor_id, @offer_id;

    BEGIN TRANSACTION;
    DECLARE @from varchar(10), @current binary(8);
    SELECT @from = status, @current = row_version FROM crm.offers WITH (UPDLOCK, HOLDLOCK) WHERE id = @offer_id;
    IF @current <> @row_version
        THROW 51901, N'The record was changed by someone else. Reload it and try again.', 1;
    IF NOT ((@from = 'DRAFT' AND @status = 'SENT') OR (@from = 'SENT' AND @status IN ('ACCEPTED', 'REJECTED', 'DRAFT')))
    BEGIN
        DECLARE @message nvarchar(200) = FORMATMESSAGE(N'An offer cannot go from %s to %s.', @from, ISNULL(@status, '-'));
        THROW 51907, @message, 1;
    END;
    IF @status = 'SENT' AND NOT EXISTS (SELECT 1 FROM crm.offer_items WHERE offer_id = @offer_id)
        THROW 51176, N'An offer needs at least one line before it is sent.', 1;

    UPDATE crm.offers
    SET status = @status,
        sent_at = CASE WHEN @status = 'SENT' THEN SYSUTCDATETIME() WHEN @status = 'DRAFT' THEN NULL ELSE sent_at END,
        decided_at = IIF(@status IN ('ACCEPTED', 'REJECTED'), SYSUTCDATETIME(), NULL),
        updated_at = SYSUTCDATETIME(), updated_by = @actor_id
    WHERE id = @offer_id;
    COMMIT;

    EXEC crm.offer_select @offer_id;
END;
