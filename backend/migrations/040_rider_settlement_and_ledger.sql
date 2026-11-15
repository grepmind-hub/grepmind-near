-- Phase 4E.4: Rider Settlement Batches, Financial Ledger Accounts & Exactly-Once Earning Accrual
-- Additive migration only. Preserves all historic migrations and data.

-- 1. Rider Settlement Batches
CREATE TABLE rider_settlement_batches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rider_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    gross_earnings_minor BIGINT NOT NULL CHECK (gross_earnings_minor > 0),
    adjustments_minor BIGINT NOT NULL DEFAULT 0,
    net_payout_minor BIGINT NOT NULL CHECK (net_payout_minor > 0),
    status TEXT NOT NULL DEFAULT 'draft' 
        CHECK (status IN ('draft','reviewed','approved','submitted','succeeded','failed','reconciled','cancelled','disputed')),
    idempotency_key UUID NOT NULL UNIQUE,
    request_fingerprint BYTEA NOT NULL CHECK (octet_length(request_fingerprint) = 32),
    created_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    reviewed_by UUID REFERENCES users(id) ON DELETE RESTRICT,
    approved_by UUID REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    reviewed_at TIMESTAMPTZ,
    approved_at TIMESTAMPTZ,
    review_reason TEXT,
    approval_reason TEXT,
    CHECK (period_end >= period_start),
    CHECK (net_payout_minor = gross_earnings_minor + adjustments_minor),
    CHECK (reviewed_by IS NULL OR reviewed_by <> created_by),
    CHECK (approved_by IS NULL OR (approved_by <> created_by AND approved_by IS DISTINCT FROM reviewed_by))
);
CREATE INDEX rider_settlement_rider_created_idx ON rider_settlement_batches(rider_user_id, created_at DESC);
CREATE INDEX rider_settlement_status_idx ON rider_settlement_batches(status, created_at DESC);

-- Link payout_transfers to rider_settlement_batches
ALTER TABLE payout_transfers 
    ADD CONSTRAINT payout_transfers_rider_batch_fkey 
    FOREIGN KEY (rider_batch_id) REFERENCES rider_settlement_batches(id) ON DELETE RESTRICT;

CREATE UNIQUE INDEX payout_transfers_one_per_rider_batch_idx 
    ON payout_transfers(rider_batch_id) WHERE rider_batch_id IS NOT NULL;

-- 2. Rider Settlement Batch Items (with Allocation Protection)
CREATE TABLE rider_settlement_batch_items (
    batch_id UUID NOT NULL REFERENCES rider_settlement_batches(id) ON DELETE RESTRICT,
    earning_entry_id UUID NOT NULL REFERENCES rider_earning_entries(id) ON DELETE RESTRICT,
    rider_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
    status TEXT NOT NULL DEFAULT 'allocated' CHECK (status IN ('allocated','released','settled')),
    PRIMARY KEY(batch_id, earning_entry_id)
);

CREATE UNIQUE INDEX rider_earning_active_allocation_idx 
    ON rider_settlement_batch_items(earning_entry_id) WHERE status = 'allocated';

-- 3. Exactly-Once Rider Earning to General Ledger Mapping
CREATE TABLE rider_earning_financial_mappings (
    earning_entry_id UUID PRIMARY KEY REFERENCES rider_earning_entries(id) ON DELETE RESTRICT,
    financial_journal_id UUID NOT NULL UNIQUE REFERENCES financial_journals(id) ON DELETE RESTRICT,
    rider_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    amount_minor BIGINT NOT NULL CHECK (amount_minor <> 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4. Additional Financial Accounts for Settlement & Payouts
INSERT INTO financial_accounts (account_code, display_name, account_class, currency, normal_side, is_enabled)
VALUES
    ('rider_fulfillment_cost', 'Rider delivery fulfillment expense', 'expense', 'INR', 'debit', true),
    ('rider_payable_liability', 'Rider delivery earnings payable liability', 'liability', 'INR', 'credit', true),
    ('payout_clearing_liability', 'Payout funds in transit clearing', 'liability', 'INR', 'credit', true),
    ('simulated_payout_disbursement_clearing', 'Simulated settlement disbursement clearing', 'liability', 'INR', 'credit', true),
    ('bank_disbursement_clearing', 'Bank disbursement provider clearing', 'asset', 'INR', 'debit', true),
    ('payout_return_clearing', 'Payout return clearing asset', 'asset', 'INR', 'debit', true)
ON CONFLICT (account_code) DO NOTHING;

-- 5. Feature Config Extension
ALTER TABLE financial_feature_config
    ADD COLUMN IF NOT EXISTS sandbox_rider_settlement_enabled BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS payout_enabled BOOLEAN NOT NULL DEFAULT false;
