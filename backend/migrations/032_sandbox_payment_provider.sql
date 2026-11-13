-- Phase 4B-B: deterministic sandbox payment processing only.
-- Live UPI, COD, settlement and real-money switches remain constrained off.
ALTER TABLE financial_feature_config
    ADD COLUMN sandbox_payment_enabled BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN sandbox_webhook_max_age_seconds INTEGER NOT NULL DEFAULT 300
        CHECK (sandbox_webhook_max_age_seconds BETWEEN 30 AND 900);

CREATE TABLE payment_provider_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider TEXT NOT NULL CHECK (provider = 'grepmind_sandbox'),
    provider_event_id TEXT NOT NULL CHECK (char_length(provider_event_id) BETWEEN 1 AND 180),
    provider_reference TEXT NOT NULL CHECK (char_length(provider_reference) BETWEEN 1 AND 180),
    event_type TEXT NOT NULL CHECK (event_type IN ('payment.pending','payment.succeeded','payment.failed','payment.expired')),
    amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
    currency CHAR(3) NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
    event_at TIMESTAMPTZ NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    payload_sha256 BYTEA NOT NULL CHECK (octet_length(payload_sha256)=32),
    signature_key_id TEXT NOT NULL CHECK (char_length(signature_key_id) BETWEEN 1 AND 80),
    processing_state TEXT NOT NULL DEFAULT 'received'
        CHECK (processing_state IN ('received','processed','duplicate','quarantined','reconciliation_required')),
    processing_result TEXT CHECK (processing_result IS NULL OR char_length(processing_result) <= 300),
    payment_attempt_id UUID REFERENCES payment_attempts(id) ON DELETE RESTRICT,
    financial_journal_id UUID REFERENCES financial_journals(id) ON DELETE RESTRICT,
    UNIQUE (provider,provider_event_id)
);
CREATE INDEX payment_provider_events_reference_idx ON payment_provider_events(provider,provider_reference,received_at DESC);

CREATE TABLE payment_reconciliation_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_attempt_id UUID NOT NULL REFERENCES payment_attempts(id) ON DELETE RESTRICT,
    provider TEXT NOT NULL CHECK (provider = 'grepmind_sandbox'),
    outcome TEXT NOT NULL CHECK (outcome IN ('matched','missing_webhook','late_success','amount_mismatch','currency_mismatch','unknown_reference','provider_unavailable')),
    provider_status TEXT CHECK (provider_status IS NULL OR char_length(provider_status) <= 40),
    details TEXT NOT NULL CHECK (char_length(details) BETWEEN 1 AND 300),
    actor_user_id UUID REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX payment_reconciliation_attempt_idx ON payment_reconciliation_events(payment_attempt_id,created_at DESC);

CREATE TABLE payment_ledger_account_mappings (
    purpose TEXT PRIMARY KEY CHECK (purpose IN ('provider_clearing','customer_receipts_unapplied')),
    account_id UUID NOT NULL REFERENCES financial_accounts(id) ON DELETE RESTRICT,
    configured_by UUID REFERENCES users(id) ON DELETE RESTRICT,
    configured_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (purpose <> '')
);

-- Attempts can be created only by the sandbox flag and the existing attempt
-- gate. `upi_enabled` remains false and is intentionally not required here.
CREATE OR REPLACE FUNCTION protect_payment_attempt_identity()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE intent_amount BIGINT; intent_currency CHAR(3); allowed_transition BOOLEAN; attempts_enabled BOOLEAN;
BEGIN
    IF TG_OP='DELETE' THEN RAISE EXCEPTION 'payment attempts cannot be deleted'; END IF;
    IF TG_OP='UPDATE' THEN
        IF (NEW.id,NEW.payment_intent_id,NEW.attempt_number,NEW.provider,NEW.amount_minor,NEW.currency,NEW.provider_idempotency_key,NEW.expires_at,NEW.created_at)
           IS DISTINCT FROM (OLD.id,OLD.payment_intent_id,OLD.attempt_number,OLD.provider,OLD.amount_minor,OLD.currency,OLD.provider_idempotency_key,OLD.expires_at,OLD.created_at)
           OR (OLD.provider_reference IS NOT NULL AND NEW.provider_reference IS DISTINCT FROM OLD.provider_reference) THEN
            RAISE EXCEPTION 'payment attempt identity is immutable';
        END IF;
        allowed_transition := CASE OLD.status
            WHEN 'initialized' THEN NEW.status IN ('session_created','pending','failed','reconciliation_required')
            WHEN 'session_created' THEN NEW.status IN ('pending','succeeded','failed','expired','reconciliation_required')
            WHEN 'pending' THEN NEW.status IN ('succeeded','failed','expired','reconciliation_required')
            WHEN 'failed' THEN NEW.status IN ('succeeded','reconciliation_required')
            WHEN 'expired' THEN NEW.status IN ('succeeded','reconciliation_required')
            WHEN 'reconciliation_required' THEN NEW.status IN ('session_created','succeeded','failed','expired')
            ELSE false
        END;
        IF NOT allowed_transition OR NEW.updated_at < OLD.updated_at THEN RAISE EXCEPTION 'invalid payment attempt state transition'; END IF;
        RETURN NEW;
    END IF;
    SELECT payment_attempt_creation_enabled AND sandbox_payment_enabled AND NOT upi_enabled AND NOT real_money_enabled
      INTO attempts_enabled FROM financial_feature_config WHERE singleton=true FOR SHARE;
    IF NOT COALESCE(attempts_enabled,false) THEN RAISE EXCEPTION 'sandbox payment attempts are disabled'; END IF;
    SELECT amount_minor,currency INTO intent_amount,intent_currency FROM payment_intents WHERE id=NEW.payment_intent_id;
    IF NOT FOUND OR NEW.amount_minor <> intent_amount OR NEW.currency <> intent_currency THEN RAISE EXCEPTION 'payment attempt must match immutable intent'; END IF;
    IF NEW.provider <> 'grepmind_sandbox' THEN RAISE EXCEPTION 'provider is not allowlisted for sandbox'; END IF;
    RETURN NEW;
END;
$$;

-- Payment intent transitions are backend-owned and monotonic. A verified late
-- capture is retained as paid/reconciliation_required without reopening orders.
ALTER TABLE payment_intents DROP CONSTRAINT payment_intents_status_check;
ALTER TABLE payment_intents ADD CONSTRAINT payment_intents_status_check
    CHECK (status IN ('created','pending','paid','failed','reconciliation_required'));
CREATE OR REPLACE FUNCTION protect_payment_intent_identity()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='DELETE' THEN RAISE EXCEPTION 'payment intents cannot be deleted'; END IF;
    IF (NEW.id,NEW.order_id,NEW.customer_user_id,NEW.amount_minor,NEW.currency,NEW.idempotency_key,NEW.request_fingerprint,NEW.created_at)
       IS DISTINCT FROM (OLD.id,OLD.order_id,OLD.customer_user_id,OLD.amount_minor,OLD.currency,OLD.idempotency_key,OLD.request_fingerprint,OLD.created_at) THEN
        RAISE EXCEPTION 'payment intent identity is immutable';
    END IF;
    IF NEW.status=OLD.status THEN RETURN NEW; END IF;
    IF NOT ((OLD.status='created' AND NEW.status IN ('pending','paid','failed','reconciliation_required')) OR
            (OLD.status='pending' AND NEW.status IN ('paid','failed','reconciliation_required')) OR
            (OLD.status='failed' AND NEW.status IN ('pending','paid','reconciliation_required')) OR
            (OLD.status='reconciliation_required' AND NEW.status='paid')) THEN
        RAISE EXCEPTION 'invalid payment intent state transition';
    END IF;
    RETURN NEW;
END;
$$;

-- No cancellation/return is allowed to erase the meaning of an already
-- verified platform-order capture while refunds are out of scope. If a
-- cancellation wins the row lock first, a later capture remains a recorded
-- reconciliation exception without reopening the order.
CREATE FUNCTION prevent_paid_platform_order_cancellation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.order_source='platform_catalog' AND OLD.payment_status='paid'
       AND NEW.status IN ('cancelled','returned') AND NEW.status IS DISTINCT FROM OLD.status THEN
        RAISE EXCEPTION 'verified paid platform order requires an approved refund workflow before cancellation or return';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER paid_platform_order_cancellation_guard
    BEFORE UPDATE OF status ON customer_orders FOR EACH ROW EXECUTE FUNCTION prevent_paid_platform_order_cancellation();

-- Narrow exception for synthetic payment capture journals. It is permitted
-- only while sandbox + accounting posting are enabled and live money remains off.
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
            IF NEW.source_type='sandbox_payment_capture' AND NEW.actor_user_id IS NULL THEN
                IF NOT COALESCE(posting_enabled AND sandbox_enabled,false) THEN RAISE EXCEPTION 'sandbox payment journal posting is disabled'; END IF;
                IF NEW.reverses_journal_id IS NOT NULL THEN RAISE EXCEPTION 'sandbox capture journal cannot be a reversal'; END IF;
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

CREATE OR REPLACE FUNCTION audit_financial_configuration()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.updated_by IS NULL OR NEW.change_reason IS NULL THEN RAISE EXCEPTION 'financial configuration changes require an authorized actor and reason'; END IF;
    IF NOT financial_actor_has_permission(NEW.updated_by,'finance.configure') THEN RAISE EXCEPTION 'financial configuration requires an authorized finance administrator'; END IF;
    INSERT INTO financial_audit_events(actor_user_id,event_type,reason,metadata)
    VALUES(NEW.updated_by,'configuration_changed',NEW.change_reason,
           jsonb_build_object('financial_posting_enabled',NEW.financial_posting_enabled,
             'payment_intent_creation_enabled',NEW.payment_intent_creation_enabled,
             'payment_attempt_creation_enabled',NEW.payment_attempt_creation_enabled,
             'sandbox_payment_enabled',NEW.sandbox_payment_enabled,
             'sandbox_webhook_max_age_seconds',NEW.sandbox_webhook_max_age_seconds,
             'upi_enabled',NEW.upi_enabled,'cod_enabled',NEW.cod_enabled,
             'merchant_settlement_enabled',NEW.merchant_settlement_enabled,'real_money_enabled',NEW.real_money_enabled));
    RETURN NEW;
END;
$$;

CREATE FUNCTION protect_payment_provider_event()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='DELETE' THEN RAISE EXCEPTION 'provider event evidence cannot be deleted'; END IF;
    IF (NEW.id,NEW.provider,NEW.provider_event_id,NEW.provider_reference,NEW.event_type,NEW.amount_minor,NEW.currency,NEW.event_at,NEW.received_at,NEW.payload_sha256,NEW.signature_key_id)
       IS DISTINCT FROM (OLD.id,OLD.provider,OLD.provider_event_id,OLD.provider_reference,OLD.event_type,OLD.amount_minor,OLD.currency,OLD.event_at,OLD.received_at,OLD.payload_sha256,OLD.signature_key_id) THEN
        RAISE EXCEPTION 'provider event identity and verified payload are immutable';
    END IF;
    IF OLD.processing_state<>'received' OR NEW.processing_state NOT IN ('processed','duplicate','quarantined','reconciliation_required') THEN
        RAISE EXCEPTION 'provider event processing result is immutable';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER payment_provider_event_immutable BEFORE UPDATE OR DELETE ON payment_provider_events FOR EACH ROW EXECUTE FUNCTION protect_payment_provider_event();

CREATE FUNCTION prevent_payment_reconciliation_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'payment reconciliation history is append-only';
END;
$$;
CREATE TRIGGER payment_reconciliation_immutable BEFORE UPDATE OR DELETE ON payment_reconciliation_events FOR EACH ROW EXECUTE FUNCTION prevent_payment_reconciliation_mutation();

COMMENT ON TABLE payment_provider_events IS 'Verified sandbox provider events only; raw payloads and credentials are never stored.';
COMMENT ON TABLE payment_reconciliation_events IS 'Append-only reconciliation outcomes for sandbox payment attempts; no provider settlement is implied.';
