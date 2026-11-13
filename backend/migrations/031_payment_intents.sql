-- Phase 4B-A: server-owned payment intent and provider-attempt foundation.
-- No provider session, payment capture, refund, COD or settlement is performed here.
ALTER TABLE financial_feature_config
    ADD COLUMN payment_intent_creation_enabled BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN payment_attempt_creation_enabled BOOLEAN NOT NULL DEFAULT false;

CREATE TABLE payment_intents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL UNIQUE REFERENCES customer_orders(id) ON DELETE RESTRICT,
    customer_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
    currency CHAR(3) NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
    status TEXT NOT NULL DEFAULT 'created' CHECK (status = 'created'),
    idempotency_key UUID NOT NULL,
    request_fingerprint BYTEA NOT NULL CHECK (octet_length(request_fingerprint)=32),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (customer_user_id,idempotency_key)
);
CREATE INDEX payment_intents_customer_created_idx
    ON payment_intents(customer_user_id,created_at DESC);

CREATE TABLE payment_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_intent_id UUID NOT NULL REFERENCES payment_intents(id) ON DELETE RESTRICT,
    attempt_number INTEGER NOT NULL CHECK (attempt_number > 0),
    provider TEXT NOT NULL CHECK (char_length(btrim(provider)) BETWEEN 2 AND 40),
    provider_reference TEXT CHECK (provider_reference IS NULL OR char_length(provider_reference) BETWEEN 1 AND 180),
    amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
    currency CHAR(3) NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
    status TEXT NOT NULL CHECK (status IN ('initialized','session_created','pending','succeeded','failed','expired','reconciliation_required')),
    provider_idempotency_key TEXT NOT NULL UNIQUE CHECK (char_length(btrim(provider_idempotency_key)) BETWEEN 8 AND 180),
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (payment_intent_id,attempt_number),
    UNIQUE (provider,provider_reference)
);
CREATE INDEX payment_attempts_intent_created_idx ON payment_attempts(payment_intent_id,created_at DESC);

CREATE FUNCTION validate_payment_intent_snapshot()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE order_customer UUID; order_source TEXT; order_status TEXT; payment_state TEXT; amount BIGINT; order_currency CHAR(3);
BEGIN
    SELECT o.customer_user_id,o.order_source,o.status,o.payment_status,
           round(o.grand_total*100)::BIGINT,o.currency
      INTO order_customer,order_source,order_status,payment_state,amount,order_currency
      FROM customer_orders AS o WHERE o.id=NEW.order_id FOR UPDATE;
    IF NOT FOUND OR order_customer IS DISTINCT FROM NEW.customer_user_id
       OR order_source <> 'platform_catalog'
       OR order_status IN ('cancelled','returned','delivered','completed')
       OR payment_state <> 'not_collected'
       OR amount IS DISTINCT FROM NEW.amount_minor
       OR order_currency IS DISTINCT FROM NEW.currency THEN
        RAISE EXCEPTION 'payment intent must match an eligible unpaid platform order';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER payment_intent_snapshot_check
    BEFORE INSERT ON payment_intents FOR EACH ROW EXECUTE FUNCTION validate_payment_intent_snapshot();

CREATE FUNCTION protect_payment_intent_identity()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='DELETE' THEN RAISE EXCEPTION 'payment intents cannot be deleted'; END IF;
    IF (NEW.id,NEW.order_id,NEW.customer_user_id,NEW.amount_minor,NEW.currency,NEW.idempotency_key,NEW.request_fingerprint,NEW.created_at)
       IS DISTINCT FROM (OLD.id,OLD.order_id,OLD.customer_user_id,OLD.amount_minor,OLD.currency,OLD.idempotency_key,OLD.request_fingerprint,OLD.created_at)
       OR OLD.status <> NEW.status THEN
        RAISE EXCEPTION 'payment intents are immutable in Phase 4B-A';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER payment_intent_immutable
    BEFORE UPDATE OR DELETE ON payment_intents FOR EACH ROW EXECUTE FUNCTION protect_payment_intent_identity();

CREATE FUNCTION protect_payment_attempt_identity()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE intent_amount BIGINT; intent_currency CHAR(3); allowed_transition BOOLEAN; attempts_enabled BOOLEAN;
BEGIN
    IF TG_OP='DELETE' THEN RAISE EXCEPTION 'payment attempts cannot be deleted'; END IF;
    IF TG_OP='UPDATE' THEN
        IF (NEW.id,NEW.payment_intent_id,NEW.attempt_number,NEW.provider,NEW.provider_reference,NEW.amount_minor,NEW.currency,NEW.provider_idempotency_key,NEW.expires_at,NEW.created_at)
           IS DISTINCT FROM (OLD.id,OLD.payment_intent_id,OLD.attempt_number,OLD.provider,OLD.provider_reference,OLD.amount_minor,OLD.currency,OLD.provider_idempotency_key,OLD.expires_at,OLD.created_at) THEN
            RAISE EXCEPTION 'payment attempt identity is immutable';
        END IF;
        allowed_transition := CASE OLD.status
            WHEN 'initialized' THEN NEW.status IN ('session_created','failed')
            WHEN 'session_created' THEN NEW.status IN ('pending','succeeded','failed','expired','reconciliation_required')
            WHEN 'pending' THEN NEW.status IN ('succeeded','failed','expired','reconciliation_required')
            WHEN 'reconciliation_required' THEN NEW.status IN ('succeeded','failed','expired')
            ELSE false
        END;
        IF NOT allowed_transition OR NEW.updated_at < OLD.updated_at THEN
            RAISE EXCEPTION 'invalid payment attempt state transition';
        END IF;
        RETURN NEW;
    END IF;
    SELECT payment_attempt_creation_enabled AND upi_enabled INTO attempts_enabled FROM financial_feature_config WHERE singleton=true;
    IF NOT COALESCE(attempts_enabled,false) THEN RAISE EXCEPTION 'provider payment attempts are disabled'; END IF;
    SELECT amount_minor,currency INTO intent_amount,intent_currency FROM payment_intents WHERE id=NEW.payment_intent_id;
    IF NOT FOUND OR NEW.amount_minor <> intent_amount OR NEW.currency <> intent_currency THEN
        RAISE EXCEPTION 'payment attempt must match its immutable intent amount and currency';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER payment_attempt_immutable
    BEFORE INSERT OR UPDATE OR DELETE ON payment_attempts FOR EACH ROW EXECUTE FUNCTION protect_payment_attempt_identity();

-- Extend the existing audited config-change record with the intent-only gate.
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
             'upi_enabled',NEW.upi_enabled,'cod_enabled',NEW.cod_enabled,
             'merchant_settlement_enabled',NEW.merchant_settlement_enabled,'real_money_enabled',NEW.real_money_enabled));
    RETURN NEW;
END;
$$;

COMMENT ON TABLE payment_intents IS 'Server-priced customer payment obligation snapshot. Creating an intent does not create a provider session or change customer_orders.payment_status.';
COMMENT ON TABLE payment_attempts IS 'Provider attempt schema for later sandbox integration; insertion is database-disabled in Phase 4B-A and no provider credentials are configured.';
