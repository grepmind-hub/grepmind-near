-- Phase 4D: merchant payable accounting and simulated settlement only.
-- No real transfer, live COD, or production commission policy is enabled.

ALTER TABLE financial_feature_config
    ADD COLUMN sandbox_merchant_settlement_enabled BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE platform_customer_order_items
    ADD COLUMN partner_supply_price_minor BIGINT CHECK (partner_supply_price_minor IS NULL OR partner_supply_price_minor >= 0),
    ADD COLUMN partner_supply_currency CHAR(3) CHECK (partner_supply_currency IS NULL OR partner_supply_currency = 'INR');

COMMENT ON COLUMN platform_customer_order_items.partner_supply_price_minor IS
    'Immutable order-time partner supply-price snapshot for Phase 4D; NULL on historical orders or mappings without explicit supply terms.';

CREATE FUNCTION protect_partner_supply_order_snapshot() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.partner_supply_price_minor IS DISTINCT FROM OLD.partner_supply_price_minor
       OR NEW.partner_supply_currency IS DISTINCT FROM OLD.partner_supply_currency THEN
        RAISE EXCEPTION 'partner supply price is an immutable order-time snapshot';
    END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER platform_order_partner_supply_snapshot_immutable
    BEFORE UPDATE ON platform_customer_order_items
    FOR EACH ROW EXECUTE FUNCTION protect_partner_supply_order_snapshot();

INSERT INTO financial_accounts(account_code,display_name,account_class,currency,normal_side)
VALUES ('merchant_fulfillment_cost','Merchant fulfillment cost (unclassified)','expense','INR','debit'),
       ('merchant_payable_liability','Merchant payable liability','liability','INR','credit'),
       ('platform_commission_clearing','Platform commission clearing (classification pending)','liability','INR','credit'),
       ('simulated_merchant_settlement_clearing','Simulated merchant settlement clearing (not a transfer)','liability','INR','credit')
ON CONFLICT (account_code) DO NOTHING;

CREATE TABLE merchant_commission_policies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    policy_key TEXT NOT NULL CHECK (char_length(btrim(policy_key)) BETWEEN 1 AND 100),
    version INTEGER NOT NULL CHECK (version > 0),
    business_id UUID REFERENCES businesses(id) ON DELETE RESTRICT,
    vertical TEXT NOT NULL CHECK (vertical IN ('food','grocery')),
    calculation_basis TEXT NOT NULL DEFAULT 'partner_supply' CHECK (calculation_basis='partner_supply'),
    commission_type TEXT NOT NULL CHECK (commission_type IN ('percentage_bps','fixed_minor')),
    percentage_bps INTEGER CHECK (percentage_bps IS NULL OR percentage_bps BETWEEN 0 AND 10000),
    fixed_minor BIGINT CHECK (fixed_minor IS NULL OR fixed_minor >= 0),
    effective_from TIMESTAMPTZ NOT NULL,
    effective_until TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','approved','rejected','expired')),
    policy_hash BYTEA NOT NULL CHECK (octet_length(policy_hash)=32),
    created_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    approved_by UUID REFERENCES users(id) ON DELETE RESTRICT,
    approval_reason TEXT CHECK (approval_reason IS NULL OR char_length(btrim(approval_reason)) BETWEEN 5 AND 300),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    approved_at TIMESTAMPTZ,
    UNIQUE(policy_key,version),
    CHECK (effective_until IS NULL OR effective_until > effective_from),
    CHECK ((commission_type='percentage_bps' AND percentage_bps IS NOT NULL AND fixed_minor IS NULL)
        OR (commission_type='fixed_minor' AND fixed_minor IS NOT NULL AND percentage_bps IS NULL)),
    CHECK ((status='approved' AND approved_by IS NOT NULL AND approved_at IS NOT NULL AND approval_reason IS NOT NULL)
        OR (status<>'approved' AND approved_at IS NULL))
);
CREATE INDEX merchant_commission_policy_scope_idx
    ON merchant_commission_policies(business_id,vertical,effective_from DESC) WHERE status='approved';

CREATE TABLE merchant_finance_audit_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    event_type TEXT NOT NULL CHECK (event_type IN (
        'commission_policy_created','commission_policy_approved','commission_policy_rejected',
        'payable_accrued','payable_adjustment_requested','payable_adjustment_approved','payable_adjustment_rejected',
        'qa_funding_pool_created','settlement_batch_created','settlement_batch_reviewed',
        'settlement_batch_approved','settlement_batch_simulated','settlement_batch_reconciled','reconciliation_run'
    )),
    business_id UUID REFERENCES businesses(id) ON DELETE RESTRICT,
    order_id UUID REFERENCES customer_orders(id) ON DELETE RESTRICT,
    payable_id UUID,
    policy_id UUID REFERENCES merchant_commission_policies(id) ON DELETE RESTRICT,
    batch_id UUID,
    reason TEXT NOT NULL CHECK (char_length(btrim(reason)) BETWEEN 5 AND 500),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (octet_length(metadata::text)<=4096),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX merchant_finance_audit_created_idx ON merchant_finance_audit_events(created_at DESC,id);

CREATE TABLE merchant_payable_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES customer_orders(id) ON DELETE RESTRICT,
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    policy_id UUID NOT NULL REFERENCES merchant_commission_policies(id) ON DELETE RESTRICT,
    policy_version INTEGER NOT NULL CHECK (policy_version > 0),
    currency CHAR(3) NOT NULL CHECK (currency='INR'),
    customer_gross_minor BIGINT NOT NULL CHECK (customer_gross_minor > 0),
    partner_gross_minor BIGINT NOT NULL CHECK (partner_gross_minor >= 0),
    commission_basis_minor BIGINT NOT NULL CHECK (commission_basis_minor >= 0),
    commission_minor BIGINT NOT NULL CHECK (commission_minor >= 0),
    authorized_deductions_minor BIGINT NOT NULL DEFAULT 0 CHECK (authorized_deductions_minor=0),
    net_payable_minor BIGINT NOT NULL CHECK (net_payable_minor >= 0),
    calculation_version INTEGER NOT NULL DEFAULT 1 CHECK (calculation_version=1),
    source_event_id TEXT NOT NULL CHECK (char_length(btrim(source_event_id)) BETWEEN 1 AND 160),
    source_event TEXT NOT NULL CHECK (source_event='delivered_payment_verified'),
    payment_source TEXT NOT NULL CHECK (payment_source IN ('sandbox_upi_capture','synthetic_cod_collection')),
    funding_state TEXT NOT NULL DEFAULT 'unavailable' CHECK (funding_state IN ('unavailable','synthetic_qa_only')),
    snapshot_hash BYTEA NOT NULL CHECK (octet_length(snapshot_hash)=32),
    financial_journal_id UUID NOT NULL UNIQUE REFERENCES financial_journals(id) ON DELETE RESTRICT,
    created_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(order_id,source_event),
    UNIQUE(id,business_id),
    CHECK (commission_minor <= partner_gross_minor),
    CHECK (net_payable_minor = partner_gross_minor - commission_minor - authorized_deductions_minor)
);
CREATE INDEX merchant_payable_business_created_idx ON merchant_payable_snapshots(business_id,created_at DESC);
CREATE INDEX merchant_payable_order_idx ON merchant_payable_snapshots(order_id);

CREATE TABLE merchant_payable_adjustments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payable_id UUID NOT NULL REFERENCES merchant_payable_snapshots(id) ON DELETE RESTRICT,
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    amount_minor BIGINT NOT NULL CHECK (amount_minor <> 0),
    currency CHAR(3) NOT NULL CHECK (currency='INR'),
    adjustment_type TEXT NOT NULL CHECK (adjustment_type IN ('credit','debit')),
    reason_code TEXT NOT NULL CHECK (reason_code IN ('refund_review','return_review','contract_correction','other')),
    status TEXT NOT NULL DEFAULT 'requested' CHECK (status IN ('requested','approved','rejected')),
    idempotency_key UUID NOT NULL,
    request_fingerprint BYTEA NOT NULL CHECK (octet_length(request_fingerprint)=32),
    requested_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    reviewed_by UUID REFERENCES users(id) ON DELETE RESTRICT,
    review_reason TEXT CHECK (review_reason IS NULL OR char_length(btrim(review_reason)) BETWEEN 5 AND 300),
    financial_journal_id UUID UNIQUE REFERENCES financial_journals(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    reviewed_at TIMESTAMPTZ,
    UNIQUE(requested_by,idempotency_key),
    CHECK ((status='requested' AND reviewed_by IS NULL AND reviewed_at IS NULL AND financial_journal_id IS NULL)
        OR (status='rejected' AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL AND financial_journal_id IS NULL)
        OR (status='approved' AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL AND financial_journal_id IS NOT NULL))
);
CREATE INDEX merchant_payable_adjustment_idx ON merchant_payable_adjustments(payable_id,created_at DESC);

CREATE FUNCTION protect_merchant_payable_adjustment() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='DELETE' THEN RAISE EXCEPTION 'payable adjustments cannot be deleted'; END IF;
    IF (NEW.id,NEW.payable_id,NEW.business_id,NEW.amount_minor,NEW.currency,NEW.adjustment_type,NEW.reason_code,
        NEW.idempotency_key,NEW.request_fingerprint,NEW.requested_by,NEW.created_at)
       IS DISTINCT FROM
       (OLD.id,OLD.payable_id,OLD.business_id,OLD.amount_minor,OLD.currency,OLD.adjustment_type,OLD.reason_code,
        OLD.idempotency_key,OLD.request_fingerprint,OLD.requested_by,OLD.created_at)
       OR OLD.status<>'requested' OR NEW.status NOT IN ('approved','rejected') OR NEW.reviewed_by IS NULL
       OR NEW.reviewed_by=NEW.requested_by OR NEW.reviewed_at IS NULL OR NEW.review_reason IS NULL THEN
        RAISE EXCEPTION 'payable adjustment is immutable except for one independent review decision';
    END IF;
    IF NEW.status='approved' AND NEW.financial_journal_id IS NULL THEN RAISE EXCEPTION 'approved adjustment requires a journal'; END IF;
    IF NEW.status='rejected' AND NEW.financial_journal_id IS NOT NULL THEN RAISE EXCEPTION 'rejected adjustment cannot have a journal'; END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER merchant_payable_adjustment_guard BEFORE UPDATE OR DELETE ON merchant_payable_adjustments
    FOR EACH ROW EXECUTE FUNCTION protect_merchant_payable_adjustment();
CREATE FUNCTION protect_merchant_payable_adjustment_insert() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status<>'requested' OR NEW.reviewed_by IS NOT NULL OR NEW.reviewed_at IS NOT NULL OR NEW.financial_journal_id IS NOT NULL THEN
        RAISE EXCEPTION 'new payable adjustments must start in requested state';
    END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER merchant_payable_adjustment_insert_guard BEFORE INSERT ON merchant_payable_adjustments
    FOR EACH ROW EXECUTE FUNCTION protect_merchant_payable_adjustment_insert();

CREATE TABLE merchant_settlement_qa_funding_pools (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES customer_orders(id) ON DELETE RESTRICT,
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
    currency CHAR(3) NOT NULL CHECK (currency='INR'),
    source_type TEXT NOT NULL DEFAULT 'synthetic_qa_pool' CHECK (source_type='synthetic_qa_pool'),
    funding_reference TEXT NOT NULL CHECK (char_length(btrim(funding_reference)) BETWEEN 8 AND 120),
    created_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    reason TEXT NOT NULL CHECK (char_length(btrim(reason)) BETWEEN 10 AND 300),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(order_id,funding_reference)
);
CREATE INDEX merchant_qa_funding_pool_order_idx ON merchant_settlement_qa_funding_pools(order_id,created_at);

CREATE TABLE merchant_settlement_batches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    currency CHAR(3) NOT NULL CHECK (currency='INR'),
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    payable_minor BIGINT NOT NULL CHECK (payable_minor > 0),
    adjustment_minor BIGINT NOT NULL DEFAULT 0,
    simulated_net_minor BIGINT NOT NULL CHECK (simulated_net_minor > 0),
    funding_mode TEXT NOT NULL CHECK (funding_mode IN ('synthetic_qa_pool','verified_cod_remittance')),
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','reviewed','approved','simulated','reconciled','rejected','cancelled','disputed')),
    idempotency_key UUID NOT NULL,
    request_fingerprint BYTEA NOT NULL CHECK (octet_length(request_fingerprint)=32),
    created_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    reviewed_by UUID REFERENCES users(id) ON DELETE RESTRICT,
    approved_by UUID REFERENCES users(id) ON DELETE RESTRICT,
    simulated_by UUID REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    reviewed_at TIMESTAMPTZ,
    approved_at TIMESTAMPTZ,
    simulated_at TIMESTAMPTZ,
    reconciled_at TIMESTAMPTZ,
    review_reason TEXT,
    approval_reason TEXT,
    simulation_reason TEXT,
    financial_journal_id UUID UNIQUE REFERENCES financial_journals(id) ON DELETE RESTRICT,
    UNIQUE(created_by,idempotency_key),
    UNIQUE(id,business_id),
    CHECK (period_end >= period_start),
    CHECK (simulated_net_minor = payable_minor + adjustment_minor),
    CHECK (reviewed_by IS NULL OR reviewed_by<>created_by),
    CHECK (approved_by IS NULL OR (approved_by<>created_by AND approved_by IS DISTINCT FROM reviewed_by)),
    CHECK (simulated_by IS NULL OR (simulated_by<>created_by AND simulated_by IS DISTINCT FROM reviewed_by AND simulated_by IS DISTINCT FROM approved_by))
);
CREATE INDEX merchant_settlement_business_created_idx ON merchant_settlement_batches(business_id,created_at DESC);
CREATE INDEX merchant_settlement_status_created_idx ON merchant_settlement_batches(status,created_at DESC);

CREATE TABLE merchant_settlement_batch_items (
    batch_id UUID NOT NULL REFERENCES merchant_settlement_batches(id) ON DELETE RESTRICT,
    payable_id UUID NOT NULL UNIQUE REFERENCES merchant_payable_snapshots(id) ON DELETE RESTRICT,
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
    currency CHAR(3) NOT NULL CHECK (currency='INR'),
    PRIMARY KEY(batch_id,payable_id),
    FOREIGN KEY(batch_id,business_id) REFERENCES merchant_settlement_batches(id,business_id) ON DELETE RESTRICT,
    FOREIGN KEY(payable_id,business_id) REFERENCES merchant_payable_snapshots(id,business_id) ON DELETE RESTRICT
);

CREATE TABLE merchant_settlement_funding_allocations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id UUID NOT NULL REFERENCES merchant_settlement_batches(id) ON DELETE RESTRICT,
    funding_type TEXT NOT NULL CHECK (funding_type IN ('synthetic_qa_pool','verified_cod_remittance')),
    funding_source_id UUID NOT NULL,
    amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
    currency CHAR(3) NOT NULL CHECK (currency='INR'),
    allocated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(batch_id,funding_type,funding_source_id)
);

CREATE TABLE merchant_settlement_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id UUID NOT NULL REFERENCES merchant_settlement_batches(id) ON DELETE RESTRICT,
    actor_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    event_type TEXT NOT NULL CHECK (event_type IN ('created','reviewed','approved','simulated','reconciled','rejected','cancelled')),
    reason TEXT NOT NULL CHECK (char_length(btrim(reason)) BETWEEN 5 AND 500),
    financial_journal_id UUID REFERENCES financial_journals(id) ON DELETE RESTRICT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (octet_length(metadata::text)<=4096),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX merchant_settlement_events_batch_idx ON merchant_settlement_events(batch_id,created_at);

CREATE TABLE merchant_reconciliation_exceptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_key UUID NOT NULL,
    issue_code TEXT NOT NULL CHECK (char_length(btrim(issue_code)) BETWEEN 3 AND 100),
    business_id UUID REFERENCES businesses(id) ON DELETE RESTRICT,
    order_id UUID REFERENCES customer_orders(id) ON DELETE RESTRICT,
    payable_id UUID REFERENCES merchant_payable_snapshots(id) ON DELETE RESTRICT,
    batch_id UUID REFERENCES merchant_settlement_batches(id) ON DELETE RESTRICT,
    details TEXT NOT NULL CHECK (char_length(btrim(details)) BETWEEN 1 AND 500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(run_key,issue_code,order_id,payable_id,batch_id)
);
CREATE INDEX merchant_reconciliation_created_idx ON merchant_reconciliation_exceptions(created_at DESC);

ALTER TABLE merchant_finance_audit_events
    ADD CONSTRAINT merchant_finance_audit_payable_fk FOREIGN KEY(payable_id) REFERENCES merchant_payable_snapshots(id) ON DELETE RESTRICT,
    ADD CONSTRAINT merchant_finance_audit_batch_fk FOREIGN KEY(batch_id) REFERENCES merchant_settlement_batches(id) ON DELETE RESTRICT;

CREATE FUNCTION protect_merchant_settlement_batch() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='DELETE' THEN RAISE EXCEPTION 'settlement batches cannot be deleted'; END IF;
    IF (NEW.id,NEW.business_id,NEW.currency,NEW.period_start,NEW.period_end,NEW.payable_minor,NEW.adjustment_minor,
        NEW.simulated_net_minor,NEW.funding_mode,NEW.idempotency_key,NEW.request_fingerprint,NEW.created_by,NEW.created_at)
       IS DISTINCT FROM
       (OLD.id,OLD.business_id,OLD.currency,OLD.period_start,OLD.period_end,OLD.payable_minor,OLD.adjustment_minor,
        OLD.simulated_net_minor,OLD.funding_mode,OLD.idempotency_key,OLD.request_fingerprint,OLD.created_by,OLD.created_at)
       OR NOT ((OLD.status='draft' AND NEW.status IN ('reviewed','cancelled'))
            OR (OLD.status='reviewed' AND NEW.status IN ('approved','rejected','cancelled'))
            OR (OLD.status='approved' AND NEW.status='simulated')
            OR (OLD.status='simulated' AND NEW.status='reconciled')) THEN
        RAISE EXCEPTION 'invalid or immutable settlement batch transition';
    END IF;
    IF NEW.status='reviewed' AND (NEW.reviewed_by IS NULL OR NEW.reviewed_by=NEW.created_by OR NEW.review_reason IS NULL OR NEW.reviewed_at IS NULL) THEN
        RAISE EXCEPTION 'settlement review requires an independent finance principal and reason';
    END IF;
    IF NEW.status='approved' AND (NEW.approved_by IS NULL OR NEW.approved_by IN (NEW.created_by,NEW.reviewed_by) OR NEW.approval_reason IS NULL OR NEW.approved_at IS NULL) THEN
        RAISE EXCEPTION 'settlement approval requires an independent finance principal and reason';
    END IF;
    IF NEW.status='simulated' AND (NEW.simulated_by IS NULL OR NEW.simulated_by IN (NEW.created_by,NEW.reviewed_by,NEW.approved_by) OR NEW.simulation_reason IS NULL OR NEW.simulated_at IS NULL OR NEW.financial_journal_id IS NULL) THEN
        RAISE EXCEPTION 'settlement simulation requires an independent actor, journal and reason';
    END IF;
    IF NEW.status='reconciled' AND (NEW.reconciled_at IS NULL OR OLD.status<>'simulated') THEN
        RAISE EXCEPTION 'only a simulated settlement can be reconciled';
    END IF;
    IF NEW.financial_journal_id IS DISTINCT FROM OLD.financial_journal_id AND NEW.status<>'simulated' THEN
        RAISE EXCEPTION 'settlement journal may only be attached during simulation';
    END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER merchant_settlement_batch_guard BEFORE UPDATE OR DELETE ON merchant_settlement_batches
    FOR EACH ROW EXECUTE FUNCTION protect_merchant_settlement_batch();

CREATE FUNCTION protect_merchant_settlement_children() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='INSERT' AND TG_TABLE_NAME='merchant_settlement_batch_items' THEN
        IF NOT EXISTS(SELECT 1 FROM merchant_settlement_batches b WHERE b.id=NEW.batch_id AND b.business_id=NEW.business_id AND b.status='draft') THEN
            RAISE EXCEPTION 'payables may only be added to a matching draft settlement batch';
        END IF;
        RETURN NEW;
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
END; $$;
CREATE TRIGGER merchant_settlement_batch_items_insert_guard BEFORE INSERT ON merchant_settlement_batch_items
    FOR EACH ROW EXECUTE FUNCTION protect_merchant_settlement_children();
CREATE TRIGGER merchant_settlement_batch_items_immutable BEFORE UPDATE OR DELETE ON merchant_settlement_batch_items
    FOR EACH ROW EXECUTE FUNCTION protect_merchant_settlement_children();
CREATE TRIGGER merchant_settlement_funding_allocation_insert_guard BEFORE INSERT ON merchant_settlement_funding_allocations
    FOR EACH ROW EXECUTE FUNCTION protect_merchant_settlement_children();
CREATE TRIGGER merchant_settlement_funding_allocations_immutable BEFORE UPDATE OR DELETE ON merchant_settlement_funding_allocations
    FOR EACH ROW EXECUTE FUNCTION protect_merchant_settlement_children();
CREATE TRIGGER merchant_settlement_qa_pool_insert_guard BEFORE INSERT ON merchant_settlement_qa_funding_pools
    FOR EACH ROW EXECUTE FUNCTION protect_merchant_settlement_children();
CREATE TRIGGER merchant_settlement_qa_pool_immutable BEFORE UPDATE OR DELETE ON merchant_settlement_qa_funding_pools
    FOR EACH ROW EXECUTE FUNCTION protect_merchant_settlement_children();

CREATE FUNCTION merchant_finance_audit_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'merchant financial audit is append-only'; END; $$;
CREATE TRIGGER merchant_finance_audit_no_mutation BEFORE UPDATE OR DELETE ON merchant_finance_audit_events
    FOR EACH ROW EXECUTE FUNCTION merchant_finance_audit_immutable();
CREATE TRIGGER merchant_settlement_events_no_mutation BEFORE UPDATE OR DELETE ON merchant_settlement_events
    FOR EACH ROW EXECUTE FUNCTION merchant_finance_audit_immutable();
CREATE TRIGGER merchant_reconciliation_exceptions_no_mutation BEFORE UPDATE OR DELETE ON merchant_reconciliation_exceptions
    FOR EACH ROW EXECUTE FUNCTION merchant_finance_audit_immutable();

CREATE FUNCTION protect_merchant_payable_snapshot() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'merchant payable snapshots are immutable; use an approved adjustment'; END; $$;
CREATE TRIGGER merchant_payable_snapshot_no_mutation BEFORE UPDATE OR DELETE ON merchant_payable_snapshots
    FOR EACH ROW EXECUTE FUNCTION protect_merchant_payable_snapshot();

CREATE FUNCTION protect_merchant_commission_policy() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE overlap BOOLEAN;
BEGIN
    IF TG_OP='DELETE' THEN RAISE EXCEPTION 'commission policies are immutable'; END IF;
    IF TG_OP='UPDATE' THEN
        IF (NEW.id,NEW.policy_key,NEW.version,NEW.business_id,NEW.vertical,NEW.calculation_basis,NEW.commission_type,
            NEW.percentage_bps,NEW.fixed_minor,NEW.effective_from,NEW.effective_until,NEW.policy_hash,NEW.created_by,NEW.created_at)
           IS DISTINCT FROM
           (OLD.id,OLD.policy_key,OLD.version,OLD.business_id,OLD.vertical,OLD.calculation_basis,OLD.commission_type,
            OLD.percentage_bps,OLD.fixed_minor,OLD.effective_from,OLD.effective_until,OLD.policy_hash,OLD.created_by,OLD.created_at)
           OR OLD.status<>'draft' OR NEW.status NOT IN ('approved','rejected') THEN
            RAISE EXCEPTION 'commission policy is immutable except for one approval decision';
        END IF;
        IF NEW.status='approved' THEN
            IF NEW.approved_by IS NULL OR NEW.approved_by=NEW.created_by OR NEW.approved_at IS NULL OR NEW.approval_reason IS NULL THEN
                RAISE EXCEPTION 'commission approval requires a separate authorized finance principal and reason';
            END IF;
            PERFORM pg_advisory_xact_lock(hashtext(COALESCE(NEW.business_id::text,'*')||':'||NEW.vertical)::bigint);
            SELECT EXISTS(SELECT 1 FROM merchant_commission_policies p
              WHERE p.status='approved' AND p.business_id IS NOT DISTINCT FROM NEW.business_id AND p.vertical=NEW.vertical
                AND p.id<>NEW.id AND tstzrange(p.effective_from,p.effective_until,'[)') && tstzrange(NEW.effective_from,NEW.effective_until,'[)'))
              INTO overlap;
            IF overlap THEN RAISE EXCEPTION 'approved commission policy effective periods cannot overlap'; END IF;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER merchant_commission_policy_guard BEFORE UPDATE OR DELETE ON merchant_commission_policies
    FOR EACH ROW EXECUTE FUNCTION protect_merchant_commission_policy();

CREATE OR REPLACE FUNCTION audit_financial_configuration() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.updated_by IS NULL OR NEW.change_reason IS NULL THEN RAISE EXCEPTION 'financial configuration changes require an authorized actor and reason'; END IF;
    IF NOT financial_actor_has_permission(NEW.updated_by,'finance.configure') THEN RAISE EXCEPTION 'financial configuration requires an authorized finance administrator'; END IF;
    INSERT INTO financial_audit_events(actor_user_id,event_type,reason,metadata)
    VALUES(NEW.updated_by,'configuration_changed',NEW.change_reason,
      jsonb_build_object('financial_posting_enabled',NEW.financial_posting_enabled,
        'payment_intent_creation_enabled',NEW.payment_intent_creation_enabled,
        'payment_attempt_creation_enabled',NEW.payment_attempt_creation_enabled,
        'sandbox_payment_enabled',NEW.sandbox_payment_enabled,'sandbox_cod_enabled',NEW.sandbox_cod_enabled,
        'sandbox_merchant_settlement_enabled',NEW.sandbox_merchant_settlement_enabled,
        'sandbox_webhook_max_age_seconds',NEW.sandbox_webhook_max_age_seconds,
        'upi_enabled',NEW.upi_enabled,'cod_enabled',NEW.cod_enabled,
        'merchant_settlement_enabled',NEW.merchant_settlement_enabled,'real_money_enabled',NEW.real_money_enabled));
    RETURN NEW;
END; $$;

COMMENT ON TABLE merchant_commission_policies IS 'Effective-dated commission contracts; no default/live policy is seeded. QA policies are explicitly synthetic.';
COMMENT ON TABLE merchant_payable_snapshots IS 'Immutable payable calculation snapshot. It is not funding availability or a merchant transfer.';
COMMENT ON TABLE merchant_settlement_qa_funding_pools IS 'Explicit synthetic QA-only funding; never represents gateway or bank settlement.';
COMMENT ON TABLE merchant_settlement_batches IS 'Simulated merchant settlement workflow only; simulated status is not external payment confirmation.';
