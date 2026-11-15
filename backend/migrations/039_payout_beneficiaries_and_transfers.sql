-- Phase 4E.4: Bank Beneficiaries, Payout Transfers & Transfer Attempt Tracking
-- Additive migration only. Preserves all historic migrations and data.

-- 1. Sensitive Bank Beneficiaries for Merchants and Riders
CREATE TABLE bank_beneficiaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    beneficiary_type TEXT NOT NULL CHECK (beneficiary_type IN ('merchant','rider')),
    business_id UUID REFERENCES businesses(id) ON DELETE RESTRICT,
    rider_user_id UUID REFERENCES users(id) ON DELETE RESTRICT,
    account_holder_name TEXT NOT NULL CHECK (char_length(btrim(account_holder_name)) BETWEEN 3 AND 120),
    account_number_encrypted BYTEA NOT NULL,
    account_number_masked TEXT NOT NULL CHECK (account_number_masked ~ '^[X]+[0-9]{4}$'),
    account_number_hmac BYTEA NOT NULL CHECK (octet_length(account_number_hmac) = 32),
    ifsc_code TEXT NOT NULL CHECK (ifsc_code ~ '^[A-Z]{4}0[A-Z0-9]{6}$'),
    bank_name TEXT NOT NULL CHECK (char_length(btrim(bank_name)) BETWEEN 2 AND 100),
    verification_status TEXT NOT NULL DEFAULT 'pending_verification' 
        CHECK (verification_status IN ('pending_verification','verified','rejected','reverification_required','deactivated')),
    verification_evidence JSONB NOT NULL DEFAULT '{}'::jsonb,
    provider_beneficiary_id TEXT,
    verified_at TIMESTAMPTZ,
    rejection_reason TEXT,
    created_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK ((beneficiary_type = 'merchant' AND business_id IS NOT NULL AND rider_user_id IS NULL)
        OR (beneficiary_type = 'rider' AND rider_user_id IS NOT NULL AND business_id IS NULL))
);

CREATE UNIQUE INDEX bank_beneficiaries_active_merchant_idx 
    ON bank_beneficiaries(business_id) WHERE verification_status IN ('pending_verification','verified');
CREATE UNIQUE INDEX bank_beneficiaries_active_rider_idx 
    ON bank_beneficiaries(rider_user_id) WHERE verification_status IN ('pending_verification','verified');
CREATE INDEX bank_beneficiaries_hmac_idx ON bank_beneficiaries(account_number_hmac);

-- 2. Beneficiary Audit Trail (Immutable)
CREATE TABLE bank_beneficiary_audit_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    beneficiary_id UUID NOT NULL REFERENCES bank_beneficiaries(id) ON DELETE RESTRICT,
    actor_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    event_type TEXT NOT NULL CHECK (event_type IN ('created','verification_initiated','verified','rejected','reverification_flagged','deactivated')),
    reason TEXT CHECK (reason IS NULL OR char_length(reason) BETWEEN 1 AND 500),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX bank_beneficiary_audit_idx ON bank_beneficiary_audit_events(beneficiary_id, created_at DESC);

CREATE OR REPLACE FUNCTION protect_bank_beneficiary_audit() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'beneficiary audit events are immutable';
END; $$;
CREATE TRIGGER bank_beneficiary_audit_immutable BEFORE UPDATE OR DELETE ON bank_beneficiary_audit_events
    FOR EACH ROW EXECUTE FUNCTION protect_bank_beneficiary_audit();

-- 3. Enhance Merchant Settlement Allocation with Status & Concurrency Guard
ALTER TABLE merchant_settlement_batch_items 
    ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'allocated' CHECK (status IN ('allocated','released','settled'));

CREATE UNIQUE INDEX IF NOT EXISTS merchant_payable_active_allocation_idx 
    ON merchant_settlement_batch_items(payable_id) WHERE status = 'allocated';

-- 4. Unified Payout Transfers
CREATE TABLE payout_transfers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payout_type TEXT NOT NULL CHECK (payout_type IN ('merchant_settlement','rider_earnings')),
    merchant_batch_id UUID REFERENCES merchant_settlement_batches(id) ON DELETE RESTRICT,
    rider_batch_id UUID, -- Foreign key to rider_settlement_batches added in migration 040
    beneficiary_id UUID NOT NULL REFERENCES bank_beneficiaries(id) ON DELETE RESTRICT,
    amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
    currency CHAR(3) NOT NULL DEFAULT 'INR' CHECK (currency = 'INR'),
    status TEXT NOT NULL DEFAULT 'ready' 
        CHECK (status IN ('ready','processing','succeeded','failed','reversed','cancelled','reconciliation_required')),
    allocation_journal_id UUID UNIQUE REFERENCES financial_journals(id) ON DELETE RESTRICT,
    disbursement_journal_id UUID UNIQUE REFERENCES financial_journals(id) ON DELETE RESTRICT,
    reversal_journal_id UUID UNIQUE REFERENCES financial_journals(id) ON DELETE RESTRICT,
    idempotency_key UUID NOT NULL UNIQUE,
    request_fingerprint BYTEA NOT NULL CHECK (octet_length(request_fingerprint) = 32),
    requested_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    reviewed_by UUID REFERENCES users(id) ON DELETE RESTRICT,
    approved_by UUID REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ,
    UNIQUE(merchant_batch_id),
    CHECK (reviewed_by IS NULL OR reviewed_by <> requested_by),
    CHECK (approved_by IS NULL OR (approved_by <> requested_by AND approved_by IS DISTINCT FROM reviewed_by))
);

-- 5. Payout Transfer Attempts (Durable Retry & Execution History)
CREATE TABLE payout_transfer_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transfer_id UUID NOT NULL REFERENCES payout_transfers(id) ON DELETE RESTRICT,
    attempt_number INTEGER NOT NULL CHECK (attempt_number >= 1),
    idempotency_key UUID NOT NULL UNIQUE,
    provider TEXT NOT NULL CHECK (provider IN ('grepmind_qa_payout','disabled_production')),
    provider_transfer_id TEXT,
    utr_number TEXT,
    status TEXT NOT NULL DEFAULT 'initiated' 
        CHECK (status IN ('initiated','processing','succeeded','failed','timeout','reversed')),
    error_code TEXT,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ,
    UNIQUE(transfer_id, attempt_number),
    UNIQUE(provider, provider_transfer_id)
);
CREATE INDEX payout_transfer_attempts_status_idx ON payout_transfer_attempts(transfer_id, status);

-- 6. Payout Provider Events (Webhook & Callback Audit Trail)
CREATE TABLE payout_provider_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider TEXT NOT NULL,
    provider_event_id TEXT NOT NULL,
    transfer_id UUID REFERENCES payout_transfers(id) ON DELETE RESTRICT,
    attempt_id UUID REFERENCES payout_transfer_attempts(id) ON DELETE RESTRICT,
    event_type TEXT NOT NULL,
    payload_sha256 BYTEA NOT NULL CHECK (octet_length(payload_sha256) = 32),
    processing_state TEXT NOT NULL DEFAULT 'received' 
        CHECK (processing_state IN ('received','processed','duplicate','quarantined')),
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(provider, provider_event_id)
);

CREATE OR REPLACE FUNCTION protect_payout_provider_event() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF OLD.id = NEW.id 
           AND OLD.provider = NEW.provider 
           AND OLD.provider_event_id = NEW.provider_event_id 
           AND OLD.transfer_id IS NOT DISTINCT FROM NEW.transfer_id 
           AND OLD.attempt_id IS NOT DISTINCT FROM NEW.attempt_id 
           AND OLD.event_type = NEW.event_type 
           AND OLD.payload_sha256 = NEW.payload_sha256 
           AND OLD.received_at = NEW.received_at 
           AND NEW.processing_state IN ('processed','duplicate','quarantined') THEN
            RETURN NEW;
        END IF;
    END IF;
    RAISE EXCEPTION 'payout provider events are immutable';
END; $$;
CREATE TRIGGER payout_provider_events_immutable BEFORE UPDATE OR DELETE ON payout_provider_events
    FOR EACH ROW EXECUTE FUNCTION protect_payout_provider_event();

-- Update protect_merchant_settlement_children to allow item status transitions from allocated to settled/released
CREATE OR REPLACE FUNCTION public.protect_merchant_settlement_children()
  RETURNS trigger
  LANGUAGE plpgsql
AS $function$
BEGIN
    IF TG_OP='INSERT' AND TG_TABLE_NAME='merchant_settlement_batch_items' THEN
        IF NOT EXISTS(SELECT 1 FROM merchant_settlement_batches b WHERE b.id=NEW.batch_id AND b.business_id=NEW.business_id AND b.status='draft') THEN
            RAISE EXCEPTION 'payables may only be added to a matching draft settlement batch';
        END IF;
        RETURN NEW;
    ELSIF TG_OP='UPDATE' AND TG_TABLE_NAME='merchant_settlement_batch_items' THEN
        IF (NEW.batch_id, NEW.business_id, NEW.payable_id, NEW.amount_minor, NEW.currency)
           IS DISTINCT FROM
           (OLD.batch_id, OLD.business_id, OLD.payable_id, OLD.amount_minor, OLD.currency) THEN
            RAISE EXCEPTION 'merchant settlement batch item core attributes are immutable';
        END IF;
        IF OLD.status='allocated' AND NEW.status IN ('settled', 'released') THEN
            RETURN NEW;
        END IF;
        RAISE EXCEPTION 'invalid merchant settlement batch item status transition';
    ELSIF TG_OP='INSERT' AND TG_TABLE_NAME='merchant_settlement_funding_allocations' THEN
        IF NOT EXISTS(SELECT 1 FROM merchant_settlement_batches b WHERE b.id=NEW.batch_id AND b.status='reviewed'
            AND ((b.funding_mode='synthetic_qa_pool' AND NEW.funding_type='synthetic_qa_pool')
              OR (b.funding_mode='verified_cod_remittance' AND NEW.funding_type='verified_cod_remittance'))) THEN
            RAISE EXCEPTION 'funding may only be allocated during approval from the matching source type';
        END IF;
        RETURN NEW;
    ELSIF TG_OP='INSERT' AND TG_TABLE_NAME='merchant_settlement_qa_funding_pools' THEN
        IF NOT EXISTS(SELECT 1 FROM financial_feature_config WHERE singleton=true AND financial_posting_enabled AND sandbox_merchant_settlement_enabled
            AND NOT upi_enabled AND NOT cod_enabled AND NOT merchant_settlement_enabled AND NOT real_money_enabled) THEN
            RAISE EXCEPTION 'synthetic settlement funding pools require fail-closed QA simulation configuration';
        END IF;
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'settlement snapshots, funding and allocation records are immutable';
END; $function$;
