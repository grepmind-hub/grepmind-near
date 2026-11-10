-- Rider compensation accrual only. This migration deliberately creates no
-- active policy and no payout/settlement concepts.
CREATE TABLE rider_compensation_policies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    policy_key TEXT NOT NULL CHECK (char_length(policy_key) BETWEEN 3 AND 80),
    version INTEGER NOT NULL CHECK (version > 0),
    locality_id UUID REFERENCES platform_delivery_localities(id) ON DELETE RESTRICT,
    currency CHAR(3) NOT NULL DEFAULT 'INR' CHECK (currency ~ '^[A-Z]{3}$'),
    fixed_amount_minor BIGINT NOT NULL CHECK (fixed_amount_minor > 0),
    effective_from TIMESTAMPTZ NOT NULL,
    effective_until TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','active','inactive')),
    is_synthetic BOOLEAN NOT NULL DEFAULT false,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (effective_until IS NULL OR effective_until > effective_from),
    UNIQUE(policy_key, version)
);
CREATE INDEX rider_compensation_policy_lookup_idx
    ON rider_compensation_policies(status, locality_id, effective_from DESC);
CREATE OR REPLACE FUNCTION prevent_rider_compensation_policy_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'compensation policy versions are immutable; create a new version';
END;
$$;
CREATE TRIGGER rider_compensation_policies_immutable
    BEFORE UPDATE OR DELETE ON rider_compensation_policies
    FOR EACH ROW EXECUTE FUNCTION prevent_rider_compensation_policy_mutation();

CREATE TABLE rider_earning_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rider_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    delivery_job_id UUID REFERENCES delivery_jobs(id) ON DELETE RESTRICT,
    order_id UUID REFERENCES customer_orders(id) ON DELETE RESTRICT,
    assignment_id UUID REFERENCES delivery_assignments(id) ON DELETE RESTRICT,
    policy_id UUID REFERENCES rider_compensation_policies(id) ON DELETE RESTRICT,
    policy_version INTEGER,
    rate_snapshot_minor BIGINT CHECK (rate_snapshot_minor IS NULL OR rate_snapshot_minor > 0),
    amount_minor BIGINT,
    currency CHAR(3) NOT NULL DEFAULT 'INR' CHECK (currency ~ '^[A-Z]{3}$'),
    entry_type TEXT NOT NULL CHECK (entry_type IN ('delivery_earning','bonus','manual_adjustment','reversal','correction','unpriced')),
    source_event TEXT NOT NULL CHECK (char_length(source_event) BETWEEN 3 AND 120),
    idempotency_key TEXT NOT NULL UNIQUE CHECK (char_length(idempotency_key) BETWEEN 8 AND 160),
    effective_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    actor_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    reason TEXT CHECK (reason IS NULL OR char_length(reason) BETWEEN 1 AND 500),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (octet_length(metadata::text) <= 4096),
    CHECK ((entry_type='unpriced' AND amount_minor IS NULL AND policy_id IS NULL)
        OR (entry_type<>'unpriced' AND amount_minor IS NOT NULL AND amount_minor <> 0)),
    CHECK ((policy_id IS NULL) = (policy_version IS NULL)),
    CHECK (entry_type NOT IN ('delivery_earning','unpriced') OR delivery_job_id IS NOT NULL)
);
CREATE UNIQUE INDEX rider_earning_one_delivery_effect_idx
    ON rider_earning_entries(delivery_job_id)
    WHERE entry_type IN ('delivery_earning','unpriced');
CREATE UNIQUE INDEX rider_earning_one_reversal_per_entry_idx
    ON rider_earning_entries((metadata->>'reverses_entry_id'))
    WHERE entry_type='reversal' AND metadata ? 'reverses_entry_id';
CREATE INDEX rider_earning_rider_effective_idx
    ON rider_earning_entries(rider_user_id,effective_at DESC,id DESC);
CREATE INDEX rider_earning_job_idx ON rider_earning_entries(delivery_job_id) WHERE delivery_job_id IS NOT NULL;

CREATE TABLE rider_earning_audit_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entry_id UUID REFERENCES rider_earning_entries(id) ON DELETE RESTRICT,
    rider_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    actor_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    event_type TEXT NOT NULL CHECK (event_type IN ('earning_recorded','unpriced_recorded','adjustment_recorded','reversal_recorded','policy_created','policy_activated','policy_deactivated','reconciliation_flagged')),
    reason TEXT CHECK (reason IS NULL OR char_length(reason) BETWEEN 1 AND 500),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (octet_length(metadata::text) <= 4096),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX rider_earning_audit_rider_idx ON rider_earning_audit_events(rider_user_id,created_at DESC);

CREATE OR REPLACE FUNCTION prevent_rider_earning_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'rider earning ledger and audit history are append-only';
END;
$$;
CREATE TRIGGER rider_earning_entries_immutable
    BEFORE UPDATE OR DELETE ON rider_earning_entries
    FOR EACH ROW EXECUTE FUNCTION prevent_rider_earning_mutation();
CREATE TRIGGER rider_earning_audit_immutable
    BEFORE UPDATE OR DELETE ON rider_earning_audit_events
    FOR EACH ROW EXECUTE FUNCTION prevent_rider_earning_mutation();

