-- Phase 4C: synthetic COD accountability. This migration creates no records
-- for historical orders and leaves every COD/live-money gate disabled.
ALTER TABLE financial_feature_config
    ADD COLUMN sandbox_cod_enabled BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE customer_orders
    ADD COLUMN payment_method TEXT CHECK (payment_method IS NULL OR payment_method IN ('upi','cash_on_delivery'));
COMMENT ON COLUMN customer_orders.payment_method IS
    'Payment method selected by the customer for new platform orders. NULL preserves legacy orders; COD collection remains separate from payment_status.';

CREATE FUNCTION prevent_platform_order_payment_method_change()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.order_source='platform_catalog' AND NEW.payment_method IS DISTINCT FROM OLD.payment_method THEN
        RAISE EXCEPTION 'platform order payment method is immutable after submission';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER platform_order_payment_method_immutable
    BEFORE UPDATE OF payment_method ON customer_orders
    FOR EACH ROW EXECUTE FUNCTION prevent_platform_order_payment_method_change();

CREATE TABLE cod_obligations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL UNIQUE REFERENCES customer_orders(id) ON DELETE RESTRICT,
    customer_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
    currency CHAR(3) NOT NULL CHECK (currency='INR'),
    policy_version TEXT NOT NULL CHECK (char_length(btrim(policy_version)) BETWEEN 1 AND 80),
    state TEXT NOT NULL DEFAULT 'due' CHECK (state IN ('due','collected')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(id,currency)
);
CREATE INDEX cod_obligations_state_created_idx ON cod_obligations(state,created_at DESC);

CREATE TABLE cod_collections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    obligation_id UUID NOT NULL UNIQUE REFERENCES cod_obligations(id) ON DELETE RESTRICT,
    order_id UUID NOT NULL REFERENCES customer_orders(id) ON DELETE RESTRICT,
    job_id UUID NOT NULL UNIQUE REFERENCES delivery_jobs(id) ON DELETE RESTRICT,
    assignment_id UUID NOT NULL REFERENCES delivery_assignments(id) ON DELETE RESTRICT,
    rider_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
    currency CHAR(3) NOT NULL CHECK (currency='INR'),
    idempotency_key UUID NOT NULL UNIQUE,
    financial_journal_id UUID NOT NULL UNIQUE REFERENCES financial_journals(id) ON DELETE RESTRICT,
    collected_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    environment TEXT NOT NULL DEFAULT 'synthetic_qa' CHECK (environment='synthetic_qa'),
    FOREIGN KEY (obligation_id,currency) REFERENCES cod_obligations(id,currency) ON DELETE RESTRICT
);
CREATE INDEX cod_collections_rider_time_idx ON cod_collections(rider_user_id,collected_at DESC);
CREATE INDEX cod_collections_order_idx ON cod_collections(order_id,collected_at DESC);

CREATE TABLE cod_remittances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rider_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
    currency CHAR(3) NOT NULL CHECK (currency='INR'),
    submission_reference TEXT NOT NULL CHECK (char_length(btrim(submission_reference)) BETWEEN 1 AND 120),
    idempotency_key UUID NOT NULL,
    request_fingerprint BYTEA NOT NULL CHECK (octet_length(request_fingerprint)=32),
    state TEXT NOT NULL DEFAULT 'submitted' CHECK (state IN ('submitted','verified','disputed','rejected')),
    verification_reason TEXT CHECK (verification_reason IS NULL OR char_length(btrim(verification_reason)) BETWEEN 5 AND 300),
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    reviewed_at TIMESTAMPTZ,
    reviewed_by UUID REFERENCES users(id) ON DELETE RESTRICT,
    financial_journal_id UUID UNIQUE REFERENCES financial_journals(id) ON DELETE RESTRICT,
    UNIQUE(rider_user_id,idempotency_key)
);
CREATE INDEX cod_remittances_rider_state_idx ON cod_remittances(rider_user_id,state,submitted_at DESC);
CREATE INDEX cod_remittances_review_idx ON cod_remittances(state,submitted_at);

CREATE TABLE cod_audit_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_user_id UUID REFERENCES users(id) ON DELETE RESTRICT,
    obligation_id UUID REFERENCES cod_obligations(id) ON DELETE RESTRICT,
    collection_id UUID REFERENCES cod_collections(id) ON DELETE RESTRICT,
    remittance_id UUID REFERENCES cod_remittances(id) ON DELETE RESTRICT,
    event_type TEXT NOT NULL CHECK (event_type IN ('obligation_created','collection_recorded','remittance_submitted','remittance_verified','remittance_disputed','remittance_rejected')),
    reason TEXT NOT NULL CHECK (char_length(btrim(reason)) BETWEEN 1 AND 300),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (octet_length(metadata::text)<=4096),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX cod_audit_events_created_idx ON cod_audit_events(created_at DESC,id);

INSERT INTO financial_accounts(account_code,display_name,account_class,currency,normal_side)
VALUES ('rider_cash_receivable','Synthetic rider cash receivable','asset','INR','debit'),
       ('cod_collection_clearing','Synthetic COD collection clearing','liability','INR','credit'),
       ('synthetic_cash_remittance_clearing','Synthetic remittance clearing','asset','INR','debit')
ON CONFLICT(account_code) DO NOTHING;

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
             'sandbox_cod_enabled',NEW.sandbox_cod_enabled,
             'sandbox_webhook_max_age_seconds',NEW.sandbox_webhook_max_age_seconds,
             'upi_enabled',NEW.upi_enabled,'cod_enabled',NEW.cod_enabled,
             'merchant_settlement_enabled',NEW.merchant_settlement_enabled,'real_money_enabled',NEW.real_money_enabled));
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION protect_cod_obligation()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE valid_order BOOLEAN; sandbox_allowed BOOLEAN;
BEGIN
    IF TG_OP='DELETE' THEN RAISE EXCEPTION 'COD obligation snapshots are immutable'; END IF;
    IF TG_OP='UPDATE' THEN
        IF (NEW.id,NEW.order_id,NEW.customer_user_id,NEW.amount_minor,NEW.currency,NEW.policy_version,NEW.created_at)
           IS DISTINCT FROM (OLD.id,OLD.order_id,OLD.customer_user_id,OLD.amount_minor,OLD.currency,OLD.policy_version,OLD.created_at)
           OR OLD.state<>'due' OR NEW.state<>'collected'
           OR NOT EXISTS(SELECT 1 FROM cod_collections c WHERE c.obligation_id=OLD.id) THEN
            RAISE EXCEPTION 'COD obligation snapshots are immutable except after a collection record';
        END IF;
        RETURN NEW;
    END IF;
    SELECT EXISTS(SELECT 1 FROM customer_orders o WHERE o.id=NEW.order_id AND o.customer_user_id=NEW.customer_user_id
        AND o.order_source='platform_catalog' AND o.payment_status='not_collected'
        AND o.status NOT IN ('cancelled','returned','delivered') AND o.currency='INR'
        AND NEW.amount_minor=round(o.grand_total*100)::bigint AND o.payment_method='cash_on_delivery'
        AND NOT EXISTS(SELECT 1 FROM payment_intents p WHERE p.order_id=o.id)) INTO valid_order;
    SELECT sandbox_cod_enabled AND financial_posting_enabled AND NOT upi_enabled AND NOT cod_enabled
        AND NOT merchant_settlement_enabled AND NOT real_money_enabled INTO sandbox_allowed
        FROM financial_feature_config WHERE singleton=true;
    IF NOT COALESCE(valid_order AND sandbox_allowed,false) THEN RAISE EXCEPTION 'COD obligation is not eligible or synthetic COD is disabled'; END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER cod_obligation_guard BEFORE INSERT OR UPDATE OR DELETE ON cod_obligations
    FOR EACH ROW EXECUTE FUNCTION protect_cod_obligation();

CREATE OR REPLACE FUNCTION protect_cod_collection()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE valid_record BOOLEAN; enabled BOOLEAN;
BEGIN
    IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'COD collection records are immutable'; END IF;
    SELECT EXISTS(
      SELECT 1 FROM cod_obligations ob JOIN customer_orders o ON o.id=ob.order_id
      JOIN delivery_jobs j ON j.order_id=o.id AND j.id=NEW.job_id
      JOIN delivery_assignments a ON a.id=NEW.assignment_id AND a.job_id=j.id AND a.rider_user_id=NEW.rider_user_id AND a.state='active'
      WHERE ob.id=NEW.obligation_id AND ob.order_id=NEW.order_id AND ob.customer_user_id=o.customer_user_id
        AND ob.state='due' AND ob.amount_minor=NEW.amount_minor AND ob.currency=NEW.currency
        AND o.payment_method='cash_on_delivery' AND o.status='out_for_delivery' AND j.execution_state='en_route'
        AND NOT EXISTS(SELECT 1 FROM payment_attempts pa JOIN payment_intents pi ON pi.id=pa.payment_intent_id
          WHERE pi.order_id=o.id AND pa.status='succeeded')
        AND EXISTS(SELECT 1 FROM delivery_verification_codes v WHERE v.job_id=j.id AND v.purpose='delivery' AND v.consumed_at IS NOT NULL AND v.invalidated_at IS NULL)
    ) INTO valid_record;
    SELECT sandbox_cod_enabled AND financial_posting_enabled AND NOT upi_enabled AND NOT cod_enabled
        AND NOT merchant_settlement_enabled AND NOT real_money_enabled INTO enabled FROM financial_feature_config WHERE singleton=true;
    IF NOT COALESCE(valid_record AND enabled,false) THEN RAISE EXCEPTION 'COD collection is not authorized for this active delivery'; END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER cod_collection_guard BEFORE INSERT OR UPDATE OR DELETE ON cod_collections
    FOR EACH ROW EXECUTE FUNCTION protect_cod_collection();

CREATE FUNCTION mark_cod_obligation_collected()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    UPDATE cod_obligations SET state='collected' WHERE id=NEW.obligation_id AND state='due';
    IF NOT FOUND THEN RAISE EXCEPTION 'COD obligation was already collected'; END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER cod_obligation_collected AFTER INSERT ON cod_collections
    FOR EACH ROW EXECUTE FUNCTION mark_cod_obligation_collected();

CREATE OR REPLACE FUNCTION protect_cod_remittance()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='DELETE' THEN RAISE EXCEPTION 'COD remittances are immutable'; END IF;
    IF TG_OP='INSERT' THEN
       IF NEW.state<>'submitted' OR NEW.reviewed_by IS NOT NULL OR NEW.financial_journal_id IS NOT NULL THEN RAISE EXCEPTION 'remittance must start submitted'; END IF;
       IF NOT EXISTS (SELECT 1 FROM financial_feature_config WHERE singleton=true AND sandbox_cod_enabled AND financial_posting_enabled AND NOT upi_enabled AND NOT cod_enabled AND NOT merchant_settlement_enabled AND NOT real_money_enabled) THEN RAISE EXCEPTION 'synthetic COD remittance submission is disabled'; END IF;
       RETURN NEW;
    END IF;
    IF (NEW.id,NEW.rider_user_id,NEW.amount_minor,NEW.currency,NEW.submission_reference,NEW.idempotency_key,NEW.request_fingerprint,NEW.submitted_at)
       IS DISTINCT FROM (OLD.id,OLD.rider_user_id,OLD.amount_minor,OLD.currency,OLD.submission_reference,OLD.idempotency_key,OLD.request_fingerprint,OLD.submitted_at)
       OR OLD.state<>'submitted' OR NEW.state NOT IN ('verified','disputed','rejected') THEN RAISE EXCEPTION 'invalid COD remittance transition'; END IF;
    IF NEW.state='verified' AND (NEW.reviewed_by IS NULL OR NEW.reviewed_by=NEW.rider_user_id OR NEW.reviewed_at IS NULL OR NEW.financial_journal_id IS NULL) THEN
       RAISE EXCEPTION 'verified remittance requires independent finance review and journal';
    END IF;
    IF NEW.state IN ('disputed','rejected') AND (NEW.reviewed_by IS NULL OR NEW.reviewed_by=NEW.rider_user_id OR NEW.reviewed_at IS NULL OR NEW.verification_reason IS NULL) THEN
       RAISE EXCEPTION 'remittance decision requires independent finance review and reason';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER cod_remittance_guard BEFORE INSERT OR UPDATE OR DELETE ON cod_remittances
    FOR EACH ROW EXECUTE FUNCTION protect_cod_remittance();

CREATE OR REPLACE FUNCTION prevent_cod_audit_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'COD audit history is append-only'; END;
$$;
CREATE TRIGGER cod_audit_immutable BEFORE UPDATE OR DELETE ON cod_audit_events
    FOR EACH ROW EXECUTE FUNCTION prevent_cod_audit_mutation();

-- Synthetic posting authorization is separate from the real COD switch.
CREATE OR REPLACE FUNCTION prevent_posted_financial_journal_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE journal_status TEXT; posting_enabled BOOLEAN; sandbox_payment BOOLEAN; sandbox_cod BOOLEAN;
BEGIN
    IF TG_TABLE_NAME='financial_journals' THEN
        IF TG_OP='INSERT' THEN
            IF NEW.status<>'draft' OR NEW.posted_at IS NOT NULL THEN RAISE EXCEPTION 'financial journals must be created as drafts'; END IF;
            RETURN NEW;
        END IF;
        IF OLD.status='posted' THEN RAISE EXCEPTION 'posted financial journals are immutable; create a reversal'; END IF;
        IF TG_OP='UPDATE' AND (NEW.id,NEW.currency,NEW.source_type,NEW.source_id,NEW.source_event,NEW.idempotency_key,NEW.request_fingerprint,NEW.description,NEW.reason,NEW.reverses_journal_id,NEW.actor_user_id,NEW.created_at)
           IS DISTINCT FROM (OLD.id,OLD.currency,OLD.source_type,OLD.source_id,OLD.source_event,OLD.idempotency_key,OLD.request_fingerprint,OLD.description,OLD.reason,OLD.reverses_journal_id,OLD.actor_user_id,OLD.created_at) THEN RAISE EXCEPTION 'financial journal identity is immutable'; END IF;
        IF TG_OP='UPDATE' AND NOT (OLD.status='draft' AND NEW.status='posted') THEN RAISE EXCEPTION 'only draft to posted journal transition is allowed'; END IF;
        IF TG_OP='UPDATE' AND NEW.status='posted' THEN
            SELECT financial_posting_enabled,sandbox_payment_enabled AND NOT upi_enabled AND NOT cod_enabled AND NOT merchant_settlement_enabled AND NOT real_money_enabled,
                   sandbox_cod_enabled AND NOT upi_enabled AND NOT cod_enabled AND NOT merchant_settlement_enabled AND NOT real_money_enabled
              INTO posting_enabled,sandbox_payment,sandbox_cod FROM financial_feature_config WHERE singleton=true;
            IF NEW.actor_user_id IS NULL AND NEW.source_type IN ('sandbox_payment_capture','sandbox_payment_refund') THEN
                IF NOT COALESCE(posting_enabled AND sandbox_payment,false) OR NEW.reverses_journal_id IS NOT NULL THEN RAISE EXCEPTION 'sandbox payment journal posting is disabled'; END IF;
            ELSIF NEW.actor_user_id IS NULL AND NEW.source_type IN ('sandbox_cod_collection','sandbox_cod_remittance') THEN
                IF NOT COALESCE(posting_enabled AND sandbox_cod,false) OR NEW.reverses_journal_id IS NOT NULL THEN RAISE EXCEPTION 'sandbox COD journal posting is disabled'; END IF;
            ELSE
                IF NOT financial_actor_has_permission(NEW.actor_user_id,CASE WHEN NEW.reverses_journal_id IS NULL THEN 'finance.post' ELSE 'finance.reverse' END) THEN RAISE EXCEPTION 'financial journal post requires an active authorized actor'; END IF;
                IF NOT COALESCE(posting_enabled,false) THEN RAISE EXCEPTION 'financial journal posting is disabled'; END IF;
            END IF;
        END IF;
        IF TG_OP='DELETE' THEN RAISE EXCEPTION 'financial journals cannot be deleted'; END IF;
        RETURN NEW;
    END IF;
    IF TG_OP='INSERT' AND NOT EXISTS(SELECT 1 FROM financial_accounts WHERE id=NEW.account_id AND currency=NEW.currency AND is_enabled) THEN RAISE EXCEPTION 'financial posting account must be enabled and match journal currency'; END IF;
    SELECT status INTO journal_status FROM financial_journals WHERE id=COALESCE(NEW.journal_id,OLD.journal_id) FOR UPDATE;
    IF journal_status='posted' THEN RAISE EXCEPTION 'postings for a posted financial journal are immutable'; END IF;
    IF TG_OP='DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

COMMENT ON TABLE cod_obligations IS 'Immutable synthetic QA COD amount snapshot; it is not a payment capture.';
COMMENT ON TABLE cod_collections IS 'Synthetic QA rider collection evidence with a balanced liability journal; no physical cash is handled.';
COMMENT ON TABLE cod_remittances IS 'Rider-submitted synthetic remittance claim; only independent finance verification reduces liability.';

CREATE FUNCTION prevent_payment_intent_for_cod_order() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS(SELECT 1 FROM customer_orders WHERE id=NEW.order_id AND payment_method='cash_on_delivery') THEN
        RAISE EXCEPTION 'UPI payment intent cannot be created for a COD order';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER payment_intent_cod_exclusion BEFORE INSERT ON payment_intents
    FOR EACH ROW EXECUTE FUNCTION prevent_payment_intent_for_cod_order();
