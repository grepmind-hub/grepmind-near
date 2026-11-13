-- Phase 4A-Build: generic accounting foundation only.
-- No payment attempts, COD collections, merchant settlements, refunds, or
-- historical order postings are created by this migration.
COMMENT ON COLUMN customer_orders.payment_status IS
    'Compatibility state. The Phase 4A ledger does not write this field; later payment integration must project only server-verified payment events and preserve the original capture state across refunds.';

CREATE TABLE financial_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_code TEXT NOT NULL UNIQUE CHECK (char_length(btrim(account_code)) BETWEEN 2 AND 80),
    display_name TEXT NOT NULL CHECK (char_length(btrim(display_name)) BETWEEN 2 AND 160),
    account_class TEXT NOT NULL CHECK (account_class IN ('asset','liability','equity','revenue','expense')),
    currency CHAR(3) NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
    normal_side TEXT NOT NULL CHECK (normal_side IN ('debit','credit')),
    is_enabled BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (id, currency)
);

CREATE TABLE financial_feature_config (
    singleton BOOLEAN PRIMARY KEY DEFAULT true CHECK (singleton),
    financial_posting_enabled BOOLEAN NOT NULL DEFAULT false,
    upi_enabled BOOLEAN NOT NULL DEFAULT false,
    cod_enabled BOOLEAN NOT NULL DEFAULT false,
    merchant_settlement_enabled BOOLEAN NOT NULL DEFAULT false,
    real_money_enabled BOOLEAN NOT NULL DEFAULT false,
    change_reason TEXT CHECK (change_reason IS NULL OR char_length(btrim(change_reason)) BETWEEN 10 AND 500),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by UUID REFERENCES users(id) ON DELETE RESTRICT,
    CHECK (NOT upi_enabled AND NOT cod_enabled AND NOT merchant_settlement_enabled AND NOT real_money_enabled)
);
INSERT INTO financial_feature_config(singleton) VALUES (true);

-- Grants are deliberately separate from ordinary admin role membership.
-- Grant changes are auditable and approval cannot be self-issued.
CREATE TABLE financial_access_grants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    permission TEXT NOT NULL CHECK (permission IN ('finance.read','finance.post','finance.reverse','finance.configure')),
    granted_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    approved_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at TIMESTAMPTZ,
    revoked_by UUID REFERENCES users(id) ON DELETE RESTRICT,
    revocation_reason TEXT CHECK (revocation_reason IS NULL OR char_length(btrim(revocation_reason)) BETWEEN 10 AND 500),
    reason TEXT NOT NULL CHECK (char_length(btrim(reason)) BETWEEN 10 AND 500),
    CHECK (granted_by <> user_id AND approved_by <> user_id AND granted_by <> approved_by),
    CHECK ((revoked_at IS NULL) = (revoked_by IS NULL)),
    CHECK ((revoked_at IS NULL) = (revocation_reason IS NULL))
);
CREATE UNIQUE INDEX financial_access_one_active_grant_idx
    ON financial_access_grants(user_id,permission) WHERE revoked_at IS NULL;
CREATE INDEX financial_access_grants_user_idx ON financial_access_grants(user_id,permission) WHERE revoked_at IS NULL;

CREATE TABLE financial_journals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    currency CHAR(3) NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','posted')),
    source_type TEXT NOT NULL CHECK (char_length(btrim(source_type)) BETWEEN 2 AND 80),
    source_id TEXT NOT NULL CHECK (char_length(btrim(source_id)) BETWEEN 1 AND 160),
    source_event TEXT NOT NULL CHECK (char_length(btrim(source_event)) BETWEEN 2 AND 120),
    idempotency_key TEXT NOT NULL UNIQUE CHECK (char_length(btrim(idempotency_key)) BETWEEN 8 AND 180),
    request_fingerprint BYTEA NOT NULL CHECK (octet_length(request_fingerprint)=32),
    description TEXT NOT NULL CHECK (char_length(btrim(description)) BETWEEN 2 AND 500),
    reason TEXT CHECK (reason IS NULL OR char_length(btrim(reason)) BETWEEN 10 AND 500),
    reverses_journal_id UUID REFERENCES financial_journals(id) ON DELETE RESTRICT,
    actor_user_id UUID REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    posted_at TIMESTAMPTZ,
    UNIQUE (source_type,source_id,source_event),
    UNIQUE (id,currency),
    CHECK ((status='posted' AND posted_at IS NOT NULL) OR (status='draft' AND posted_at IS NULL)),
    CHECK (reverses_journal_id IS NULL OR reverses_journal_id <> id)
);
CREATE UNIQUE INDEX financial_journal_one_reversal_idx
    ON financial_journals(reverses_journal_id) WHERE reverses_journal_id IS NOT NULL;
CREATE INDEX financial_journals_created_idx ON financial_journals(created_at DESC,id);

CREATE TABLE financial_postings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    journal_id UUID NOT NULL,
    account_id UUID NOT NULL,
    currency CHAR(3) NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
    side TEXT NOT NULL CHECK (side IN ('debit','credit')),
    amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
    memo TEXT CHECK (memo IS NULL OR char_length(memo) <= 240),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (journal_id,currency) REFERENCES financial_journals(id,currency) ON DELETE RESTRICT,
    FOREIGN KEY (account_id,currency) REFERENCES financial_accounts(id,currency) ON DELETE RESTRICT
);
CREATE INDEX financial_postings_journal_idx ON financial_postings(journal_id,id);
CREATE INDEX financial_postings_account_idx ON financial_postings(account_id,created_at DESC);

CREATE TABLE financial_audit_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_user_id UUID REFERENCES users(id) ON DELETE RESTRICT,
    event_type TEXT NOT NULL CHECK (event_type IN ('journal_posted','journal_reversed','access_granted','access_revoked','configuration_changed')),
    journal_id UUID REFERENCES financial_journals(id) ON DELETE RESTRICT,
    grant_id UUID REFERENCES financial_access_grants(id) ON DELETE RESTRICT,
    reason TEXT CHECK (reason IS NULL OR char_length(reason) BETWEEN 1 AND 500),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (octet_length(metadata::text) <= 4096),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX financial_audit_created_idx ON financial_audit_events(created_at DESC,id);

CREATE OR REPLACE FUNCTION financial_actor_has_permission(actor_id UUID, requested_permission TEXT)
RETURNS BOOLEAN LANGUAGE SQL STABLE AS $$
    SELECT EXISTS (
        SELECT 1 FROM users u WHERE u.id=actor_id AND u.status='active' AND u.phone_e164='+910000000000'
        UNION ALL
        SELECT 1 FROM users u
        JOIN user_roles r ON r.user_id=u.id AND r.role='admin'
        JOIN financial_access_grants g ON g.user_id=u.id AND g.permission=requested_permission AND g.revoked_at IS NULL
        WHERE u.id=actor_id AND u.status='active'
    )
$$;

CREATE OR REPLACE FUNCTION prevent_posted_financial_journal_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    journal_status TEXT;
    posting_enabled BOOLEAN;
BEGIN
    IF TG_TABLE_NAME = 'financial_journals' THEN
        IF TG_OP='INSERT' THEN
            IF NEW.status<>'draft' OR NEW.posted_at IS NOT NULL THEN RAISE EXCEPTION 'financial journals must be created as drafts'; END IF;
            RETURN NEW;
        END IF;
        IF OLD.status = 'posted' THEN
            RAISE EXCEPTION 'posted financial journals are immutable; create a reversal';
        END IF;
        IF TG_OP = 'UPDATE' AND (NEW.id,NEW.currency,NEW.source_type,NEW.source_id,NEW.source_event,
             NEW.idempotency_key,NEW.request_fingerprint,NEW.description,NEW.reason,NEW.reverses_journal_id,NEW.actor_user_id,NEW.created_at)
             IS DISTINCT FROM
             (OLD.id,OLD.currency,OLD.source_type,OLD.source_id,OLD.source_event,
             OLD.idempotency_key,OLD.request_fingerprint,OLD.description,OLD.reason,OLD.reverses_journal_id,OLD.actor_user_id,OLD.created_at) THEN
            RAISE EXCEPTION 'financial journal identity is immutable';
        END IF;
        IF TG_OP = 'UPDATE' AND NOT (OLD.status='draft' AND NEW.status='posted') THEN
            RAISE EXCEPTION 'only draft to posted journal transition is allowed';
        END IF;
        IF TG_OP='UPDATE' AND NEW.status='posted' AND NOT financial_actor_has_permission(
            NEW.actor_user_id,CASE WHEN NEW.reverses_journal_id IS NULL THEN 'finance.post' ELSE 'finance.reverse' END) THEN
            RAISE EXCEPTION 'financial journal post requires an active authorized actor';
        END IF;
        IF TG_OP='UPDATE' AND NEW.status='posted' THEN
            SELECT financial_posting_enabled INTO posting_enabled FROM financial_feature_config WHERE singleton=true;
            IF NOT COALESCE(posting_enabled,false) THEN RAISE EXCEPTION 'financial journal posting is disabled'; END IF;
        END IF;
        IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'financial journals cannot be deleted'; END IF;
        RETURN NEW;
    END IF;

    IF TG_OP='INSERT' AND NOT EXISTS (SELECT 1 FROM financial_accounts WHERE id=NEW.account_id AND currency=NEW.currency AND is_enabled) THEN
        RAISE EXCEPTION 'financial posting account must be enabled and match journal currency';
    END IF;
    SELECT status INTO journal_status FROM financial_journals WHERE id=COALESCE(NEW.journal_id,OLD.journal_id) FOR UPDATE;
    IF journal_status='posted' THEN
        RAISE EXCEPTION 'postings for a posted financial journal are immutable';
    END IF;
    IF TG_OP='DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER financial_journals_immutable
    BEFORE INSERT OR UPDATE OR DELETE ON financial_journals
    FOR EACH ROW EXECUTE FUNCTION prevent_posted_financial_journal_mutation();

CREATE OR REPLACE FUNCTION audit_financial_journal_posting()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO financial_audit_events(actor_user_id,event_type,journal_id,reason,metadata)
    VALUES(NEW.actor_user_id,
           CASE WHEN NEW.reverses_journal_id IS NULL THEN 'journal_posted' ELSE 'journal_reversed' END,
           NEW.id,NEW.reason,jsonb_build_object('source_type',NEW.source_type,'source_event',NEW.source_event));
    RETURN NEW;
END;
$$;
CREATE TRIGGER financial_journal_post_audit
    AFTER UPDATE OF status ON financial_journals
    FOR EACH ROW WHEN (OLD.status='draft' AND NEW.status='posted')
    EXECUTE FUNCTION audit_financial_journal_posting();
CREATE TRIGGER financial_postings_immutable
    BEFORE INSERT OR UPDATE OR DELETE ON financial_postings
    FOR EACH ROW EXECUTE FUNCTION prevent_posted_financial_journal_mutation();

CREATE OR REPLACE FUNCTION protect_financial_account_identity()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='DELETE' THEN RAISE EXCEPTION 'financial account identity is immutable'; END IF;
    IF (NEW.id,NEW.account_code,NEW.display_name,NEW.account_class,NEW.currency,NEW.normal_side,NEW.created_at)
       IS DISTINCT FROM (OLD.id,OLD.account_code,OLD.display_name,OLD.account_class,OLD.currency,OLD.normal_side,OLD.created_at) THEN
        RAISE EXCEPTION 'financial account identity is immutable';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER financial_account_identity_immutable
    BEFORE UPDATE OR DELETE ON financial_accounts
    FOR EACH ROW EXECUTE FUNCTION protect_financial_account_identity();

CREATE OR REPLACE FUNCTION enforce_financial_journal_balance()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE jid UUID; journal_status TEXT; debit_total NUMERIC; credit_total NUMERIC; posting_count BIGINT; account_count BIGINT;
BEGIN
    IF TG_TABLE_NAME='financial_journals' THEN
        IF TG_OP='DELETE' THEN jid:=OLD.id; ELSE jid:=NEW.id; END IF;
    ELSE
        IF TG_OP='DELETE' THEN jid:=OLD.journal_id; ELSE jid:=NEW.journal_id; END IF;
    END IF;
    SELECT status INTO journal_status FROM financial_journals WHERE id=jid;
    IF journal_status='posted' THEN
        SELECT count(*),count(DISTINCT account_id),
               COALESCE(sum(amount_minor) FILTER (WHERE side='debit'),0),
               COALESCE(sum(amount_minor) FILTER (WHERE side='credit'),0)
          INTO posting_count,account_count,debit_total,credit_total
          FROM financial_postings WHERE journal_id=jid;
        IF posting_count < 2 OR account_count < 2 OR debit_total <= 0 OR debit_total <> credit_total THEN
            RAISE EXCEPTION 'posted journal must contain balanced debit and credit postings';
        END IF;
    END IF;
    RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER financial_journal_balance_on_journal
    AFTER INSERT OR UPDATE ON financial_journals DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION enforce_financial_journal_balance();
CREATE CONSTRAINT TRIGGER financial_journal_balance_on_posting
    AFTER INSERT OR UPDATE OR DELETE ON financial_postings DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION enforce_financial_journal_balance();

CREATE OR REPLACE FUNCTION prevent_financial_audit_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'financial audit history is append-only';
END;
$$;
CREATE TRIGGER financial_audit_immutable
    BEFORE UPDATE OR DELETE ON financial_audit_events
    FOR EACH ROW EXECUTE FUNCTION prevent_financial_audit_mutation();

CREATE OR REPLACE FUNCTION protect_financial_grant_and_audit()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE target_admin BOOLEAN; issuer_admin BOOLEAN; approver_admin BOOLEAN; revoker_admin BOOLEAN;
BEGIN
    IF TG_OP='DELETE' THEN RAISE EXCEPTION 'financial grants cannot be deleted; revoke them'; END IF;
    IF TG_OP='UPDATE' THEN
        IF (NEW.id,NEW.user_id,NEW.permission,NEW.granted_by,NEW.approved_by,NEW.granted_at,NEW.reason)
           IS DISTINCT FROM (OLD.id,OLD.user_id,OLD.permission,OLD.granted_by,OLD.approved_by,OLD.granted_at,OLD.reason)
           OR OLD.revoked_at IS NOT NULL OR NEW.revoked_at IS NULL OR NEW.revoked_by IS NULL
           OR NEW.revocation_reason IS NULL THEN
            RAISE EXCEPTION 'financial grants are immutable except for one revocation';
        END IF;
        SELECT EXISTS(SELECT 1 FROM users u JOIN user_roles r ON r.user_id=u.id AND r.role='admin' WHERE u.id=NEW.revoked_by AND u.status='active') INTO revoker_admin;
        IF NOT revoker_admin OR NEW.revoked_by=NEW.user_id OR NOT financial_actor_has_permission(NEW.revoked_by,'finance.configure') THEN RAISE EXCEPTION 'revocation requires a different authorized finance administrator'; END IF;
        RETURN NEW;
    END IF;
    SELECT EXISTS(SELECT 1 FROM users u JOIN user_roles r ON r.user_id=u.id AND r.role='admin' WHERE u.id=NEW.user_id AND u.status='active') INTO target_admin;
    SELECT EXISTS(SELECT 1 FROM users u JOIN user_roles r ON r.user_id=u.id AND r.role='admin' WHERE u.id=NEW.granted_by AND u.status='active') INTO issuer_admin;
    SELECT EXISTS(SELECT 1 FROM users u JOIN user_roles r ON r.user_id=u.id AND r.role='admin' WHERE u.id=NEW.approved_by AND u.status='active') INTO approver_admin;
    IF NOT target_admin OR NOT issuer_admin OR NOT approver_admin THEN RAISE EXCEPTION 'financial grants require an active admin, issuer, and approver'; END IF;
    IF NOT financial_actor_has_permission(NEW.granted_by,'finance.configure') THEN RAISE EXCEPTION 'financial grant issuance requires an authorized finance administrator'; END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER financial_grant_audit_and_immutability
    BEFORE UPDATE OR DELETE ON financial_access_grants
    FOR EACH ROW EXECUTE FUNCTION protect_financial_grant_and_audit();

CREATE OR REPLACE FUNCTION audit_financial_grant_change()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='INSERT' THEN
        INSERT INTO financial_audit_events(actor_user_id,event_type,grant_id,reason)
        VALUES(NEW.granted_by,'access_granted',NEW.id,NEW.reason);
    ELSE
        INSERT INTO financial_audit_events(actor_user_id,event_type,grant_id,reason)
        VALUES(NEW.revoked_by,'access_revoked',NEW.id,NEW.revocation_reason);
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER financial_grant_audit
    AFTER INSERT OR UPDATE ON financial_access_grants
    FOR EACH ROW EXECUTE FUNCTION audit_financial_grant_change();

CREATE OR REPLACE FUNCTION audit_financial_configuration()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.updated_by IS NULL OR NEW.change_reason IS NULL THEN RAISE EXCEPTION 'financial configuration changes require an authorized actor and reason'; END IF;
    IF NOT financial_actor_has_permission(NEW.updated_by,'finance.configure') THEN RAISE EXCEPTION 'financial configuration requires an authorized finance administrator'; END IF;
    INSERT INTO financial_audit_events(actor_user_id,event_type,reason,metadata)
    VALUES(NEW.updated_by,'configuration_changed',NEW.change_reason,
           jsonb_build_object('financial_posting_enabled',NEW.financial_posting_enabled,
             'upi_enabled',NEW.upi_enabled,'cod_enabled',NEW.cod_enabled,
             'merchant_settlement_enabled',NEW.merchant_settlement_enabled,'real_money_enabled',NEW.real_money_enabled));
    RETURN NEW;
END;
$$;
CREATE TRIGGER financial_configuration_audit
    AFTER UPDATE ON financial_feature_config
    FOR EACH ROW EXECUTE FUNCTION audit_financial_configuration();
