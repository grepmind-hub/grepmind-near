-- Phase 4B-C: synthetic refund requests and verified sandbox refund evidence.
-- This schema does not enable live UPI, COD, settlements, or real-money flow.
CREATE TABLE payment_refunds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_intent_id UUID NOT NULL REFERENCES payment_intents(id) ON DELETE RESTRICT,
    payment_attempt_id UUID NOT NULL REFERENCES payment_attempts(id) ON DELETE RESTRICT,
    order_id UUID NOT NULL REFERENCES customer_orders(id) ON DELETE RESTRICT,
    customer_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
    currency CHAR(3) NOT NULL CHECK (currency = 'INR'),
    reason_code TEXT NOT NULL CHECK (reason_code IN ('order_cancelled','items_missing','items_damaged','duplicate_payment','other')),
    status TEXT NOT NULL DEFAULT 'requested' CHECK (status IN ('requested','approved','processing','succeeded','failed','rejected','reconciliation_required')),
    idempotency_key UUID NOT NULL,
    request_fingerprint BYTEA NOT NULL CHECK (octet_length(request_fingerprint)=32),
    requested_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    approved_by UUID REFERENCES users(id) ON DELETE RESTRICT,
    provider TEXT NOT NULL DEFAULT 'grepmind_sandbox' CHECK (provider='grepmind_sandbox'),
    provider_reference TEXT UNIQUE,
    provider_event_id TEXT,
    financial_journal_id UUID REFERENCES financial_journals(id) ON DELETE RESTRICT,
    failure_code TEXT CHECK (failure_code IS NULL OR char_length(failure_code)<=80),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(customer_user_id,idempotency_key)
);
CREATE INDEX payment_refunds_order_idx ON payment_refunds(order_id,created_at DESC);
CREATE INDEX payment_refunds_capture_idx ON payment_refunds(payment_attempt_id,status);

ALTER TABLE payment_provider_events
    DROP CONSTRAINT payment_provider_events_event_type_check,
    ADD CONSTRAINT payment_provider_events_event_type_check CHECK (event_type IN (
        'payment.pending','payment.succeeded','payment.failed','payment.expired',
        'refund.pending','refund.succeeded','refund.failed'
    )),
    ADD COLUMN refund_id UUID REFERENCES payment_refunds(id) ON DELETE RESTRICT;

CREATE OR REPLACE FUNCTION protect_payment_refund()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE refunded BIGINT; captured BIGINT; allowed BOOLEAN;
BEGIN
    IF TG_OP='DELETE' THEN RAISE EXCEPTION 'refund records cannot be deleted'; END IF;
    IF TG_OP='INSERT' THEN
        IF NEW.status <> 'requested' OR NEW.approved_by IS NOT NULL OR NEW.provider_reference IS NOT NULL OR NEW.financial_journal_id IS NOT NULL THEN
            RAISE EXCEPTION 'refund requests must start in requested state';
        END IF;
        SELECT a.amount_minor INTO captured FROM payment_attempts a JOIN payment_intents i ON i.id=a.payment_intent_id
          JOIN customer_orders o ON o.id=i.order_id
          WHERE a.id=NEW.payment_attempt_id AND a.payment_intent_id=NEW.payment_intent_id AND i.order_id=NEW.order_id
            AND i.customer_user_id=NEW.customer_user_id AND o.customer_user_id=NEW.customer_user_id
            AND o.order_source='platform_catalog' AND o.payment_status='paid' AND a.status='succeeded' AND a.provider='grepmind_sandbox';
        IF NOT FOUND OR NEW.amount_minor > captured THEN RAISE EXCEPTION 'refund request exceeds a verified sandbox capture'; END IF;
        SELECT sandbox_payment_enabled AND financial_posting_enabled AND NOT upi_enabled AND NOT cod_enabled AND NOT merchant_settlement_enabled AND NOT real_money_enabled
          INTO allowed FROM financial_feature_config WHERE singleton=true;
        IF NOT COALESCE(allowed,false) THEN RAISE EXCEPTION 'sandbox refund requests are disabled'; END IF;
        RETURN NEW;
    END IF;
    IF (NEW.id,NEW.payment_intent_id,NEW.payment_attempt_id,NEW.order_id,NEW.customer_user_id,NEW.amount_minor,NEW.currency,NEW.reason_code,NEW.idempotency_key,NEW.request_fingerprint,NEW.requested_by,NEW.created_at)
       IS DISTINCT FROM (OLD.id,OLD.payment_intent_id,OLD.payment_attempt_id,OLD.order_id,OLD.customer_user_id,OLD.amount_minor,OLD.currency,OLD.reason_code,OLD.idempotency_key,OLD.request_fingerprint,OLD.requested_by,OLD.created_at) THEN
        RAISE EXCEPTION 'refund request identity is immutable';
    END IF;
    IF OLD.approved_by IS NOT NULL AND NEW.approved_by IS DISTINCT FROM OLD.approved_by THEN RAISE EXCEPTION 'refund approver is immutable'; END IF;
    IF OLD.provider_reference IS NOT NULL AND NEW.provider_reference IS DISTINCT FROM OLD.provider_reference THEN RAISE EXCEPTION 'provider refund reference is immutable'; END IF;
    IF OLD.financial_journal_id IS NOT NULL AND NEW.financial_journal_id IS DISTINCT FROM OLD.financial_journal_id THEN RAISE EXCEPTION 'refund journal reference is immutable'; END IF;
    IF NOT ((OLD.status='requested' AND NEW.status IN ('approved','rejected')) OR
            (OLD.status='approved' AND NEW.status IN ('processing','reconciliation_required')) OR
            (OLD.status='processing' AND NEW.status IN ('succeeded','failed','reconciliation_required')) OR
            (OLD.status='failed' AND NEW.status='succeeded') OR
            (OLD.status='reconciliation_required' AND NEW.status IN ('processing','succeeded','failed')))
       THEN RAISE EXCEPTION 'invalid refund state transition'; END IF;
    IF NEW.status='approved' AND (NEW.approved_by IS NULL OR NEW.approved_by=NEW.requested_by) THEN RAISE EXCEPTION 'refund approval requires a different finance principal'; END IF;
    IF NEW.status='succeeded' AND (NEW.provider_event_id IS NULL OR NEW.financial_journal_id IS NULL) THEN RAISE EXCEPTION 'verified refund success requires provider event and journal'; END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER payment_refund_guard BEFORE INSERT OR UPDATE OR DELETE ON payment_refunds FOR EACH ROW EXECUTE FUNCTION protect_payment_refund();

CREATE TABLE payment_refund_audit_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    refund_id UUID NOT NULL REFERENCES payment_refunds(id) ON DELETE RESTRICT,
    actor_user_id UUID REFERENCES users(id) ON DELETE RESTRICT,
    event_type TEXT NOT NULL CHECK (event_type IN ('requested','approved','rejected','provider_started','provider_failed','provider_succeeded','reconciliation_required','reconciled')),
    reason TEXT NOT NULL CHECK (char_length(reason) BETWEEN 1 AND 300),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE FUNCTION prevent_payment_refund_audit_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'refund audit history is append-only'; END;
$$;
CREATE TRIGGER payment_refund_audit_immutable BEFORE UPDATE OR DELETE ON payment_refund_audit_events FOR EACH ROW EXECUTE FUNCTION prevent_payment_refund_audit_mutation();

-- Refund journal posts the verified reduction in customer-receipt liability
-- against the sandbox provider-clearing asset. It never implies bank settlement.
CREATE OR REPLACE FUNCTION prevent_posted_financial_journal_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE journal_status TEXT; posting_enabled BOOLEAN; sandbox_enabled BOOLEAN;
BEGIN
    IF TG_TABLE_NAME = 'financial_journals' THEN
        IF TG_OP='INSERT' THEN
            IF NEW.status<>'draft' OR NEW.posted_at IS NOT NULL THEN RAISE EXCEPTION 'financial journals must be created as drafts'; END IF;
            RETURN NEW;
        END IF;
        IF OLD.status='posted' THEN RAISE EXCEPTION 'posted financial journals are immutable; create a reversal'; END IF;
        IF TG_OP='UPDATE' AND (NEW.id,NEW.currency,NEW.source_type,NEW.source_id,NEW.source_event,NEW.idempotency_key,NEW.request_fingerprint,NEW.description,NEW.reason,NEW.reverses_journal_id,NEW.actor_user_id,NEW.created_at)
           IS DISTINCT FROM (OLD.id,OLD.currency,OLD.source_type,OLD.source_id,OLD.source_event,OLD.idempotency_key,OLD.request_fingerprint,OLD.description,OLD.reason,OLD.reverses_journal_id,OLD.actor_user_id,OLD.created_at) THEN RAISE EXCEPTION 'financial journal identity is immutable'; END IF;
        IF TG_OP='UPDATE' AND NOT (OLD.status='draft' AND NEW.status='posted') THEN RAISE EXCEPTION 'only draft to posted journal transition is allowed'; END IF;
        IF TG_OP='UPDATE' AND NEW.status='posted' THEN
            SELECT financial_posting_enabled,sandbox_payment_enabled AND NOT upi_enabled AND NOT cod_enabled AND NOT merchant_settlement_enabled AND NOT real_money_enabled
              INTO posting_enabled,sandbox_enabled FROM financial_feature_config WHERE singleton=true;
            IF NEW.source_type IN ('sandbox_payment_capture','sandbox_payment_refund') AND NEW.actor_user_id IS NULL THEN
                IF NOT COALESCE(posting_enabled AND sandbox_enabled,false) THEN RAISE EXCEPTION 'sandbox payment journal posting is disabled'; END IF;
                IF NEW.reverses_journal_id IS NOT NULL THEN RAISE EXCEPTION 'sandbox payment journal cannot be a reversal'; END IF;
            ELSE
                IF NOT financial_actor_has_permission(NEW.actor_user_id,CASE WHEN NEW.reverses_journal_id IS NULL THEN 'finance.post' ELSE 'finance.reverse' END) THEN RAISE EXCEPTION 'financial journal post requires an active authorized actor'; END IF;
                IF NOT COALESCE(posting_enabled,false) THEN RAISE EXCEPTION 'financial journal posting is disabled'; END IF;
            END IF;
        END IF;
        IF TG_OP='DELETE' THEN RAISE EXCEPTION 'financial journals cannot be deleted'; END IF;
        RETURN NEW;
    END IF;
    IF TG_OP='INSERT' AND NOT EXISTS (SELECT 1 FROM financial_accounts WHERE id=NEW.account_id AND currency=NEW.currency AND is_enabled) THEN RAISE EXCEPTION 'financial posting account must be enabled and match journal currency'; END IF;
    SELECT status INTO journal_status FROM financial_journals WHERE id=COALESCE(NEW.journal_id,OLD.journal_id) FOR UPDATE;
    IF journal_status='posted' THEN RAISE EXCEPTION 'postings for a posted financial journal are immutable'; END IF;
    IF TG_OP='DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

COMMENT ON TABLE payment_refunds IS 'Customer refund requests and verified synthetic provider refunds; never a promise of real bank credit.';
