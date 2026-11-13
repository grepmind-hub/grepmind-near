-- Phase 4D QA blocker recovery: two-person workflow for narrowly scoped
-- financial access grants. This migration is additive and must only be
-- applied to the isolated QA database during this recovery.
CREATE TABLE financial_access_grant_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    permission TEXT NOT NULL CHECK (permission IN ('finance.read','finance.post')),
    requested_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    reason TEXT NOT NULL CHECK (char_length(btrim(reason)) BETWEEN 10 AND 500),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
    decided_by UUID REFERENCES users(id) ON DELETE RESTRICT,
    decision_reason TEXT CHECK (decision_reason IS NULL OR char_length(btrim(decision_reason)) BETWEEN 10 AND 500),
    grant_id UUID REFERENCES financial_access_grants(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    decided_at TIMESTAMPTZ,
    CHECK (requested_by <> target_user_id),
    CHECK (decided_by IS NULL OR (decided_by <> requested_by AND decided_by <> target_user_id)),
    CHECK ((status='pending' AND decided_by IS NULL AND decided_at IS NULL AND decision_reason IS NULL AND grant_id IS NULL)
        OR (status='approved' AND decided_by IS NOT NULL AND decided_at IS NOT NULL AND decision_reason IS NOT NULL AND grant_id IS NOT NULL)
        OR (status='rejected' AND decided_by IS NOT NULL AND decided_at IS NOT NULL AND decision_reason IS NOT NULL AND grant_id IS NULL))
);
CREATE UNIQUE INDEX financial_access_pending_request_idx
    ON financial_access_grant_requests(target_user_id,permission) WHERE status='pending';
CREATE INDEX financial_access_requests_created_idx
    ON financial_access_grant_requests(created_at DESC,id);

ALTER TABLE financial_audit_events
    ADD COLUMN grant_request_id UUID REFERENCES financial_access_grant_requests(id) ON DELETE RESTRICT;
ALTER TABLE financial_audit_events
    DROP CONSTRAINT financial_audit_events_event_type_check;
ALTER TABLE financial_audit_events
    ADD CONSTRAINT financial_audit_events_event_type_check CHECK (event_type IN (
        'journal_posted','journal_reversed','access_granted','access_revoked','configuration_changed',
        'access_grant_requested','access_grant_approved','access_grant_rejected'
    ));
CREATE INDEX financial_audit_grant_request_idx
    ON financial_audit_events(grant_request_id,created_at DESC) WHERE grant_request_id IS NOT NULL;

CREATE FUNCTION protect_financial_access_grant_request() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE target_admin BOOLEAN; requester_allowed BOOLEAN; decider_allowed BOOLEAN; grant_matches BOOLEAN;
BEGIN
    IF TG_OP='DELETE' THEN RAISE EXCEPTION 'financial access requests cannot be deleted'; END IF;
    IF TG_OP='INSERT' THEN
        IF NEW.status<>'pending' OR NEW.decided_by IS NOT NULL OR NEW.decided_at IS NOT NULL OR NEW.grant_id IS NOT NULL THEN
            RAISE EXCEPTION 'financial access requests must start pending';
        END IF;
        SELECT EXISTS(SELECT 1 FROM users u JOIN user_roles r ON r.user_id=u.id AND r.role='admin'
          WHERE u.id=NEW.target_user_id AND u.status='active') INTO target_admin;
        SELECT financial_actor_has_permission(NEW.requested_by,'finance.configure') INTO requester_allowed;
        IF NOT target_admin OR NOT requester_allowed THEN RAISE EXCEPTION 'access request requires an active Admin target and authorized finance issuer'; END IF;
        RETURN NEW;
    END IF;
    IF OLD.status<>'pending' OR NEW.status NOT IN ('approved','rejected')
       OR (NEW.id,NEW.target_user_id,NEW.permission,NEW.requested_by,NEW.reason,NEW.created_at)
          IS DISTINCT FROM (OLD.id,OLD.target_user_id,OLD.permission,OLD.requested_by,OLD.reason,OLD.created_at)
       OR NEW.decided_by IS NULL OR NEW.decided_at IS NULL OR NEW.decision_reason IS NULL
       OR NEW.decided_by IN (OLD.requested_by,OLD.target_user_id) THEN
        RAISE EXCEPTION 'finance access request permits one immutable independent decision';
    END IF;
    SELECT financial_actor_has_permission(NEW.decided_by,'finance.configure') INTO decider_allowed;
    SELECT EXISTS(SELECT 1 FROM users u JOIN user_roles r ON r.user_id=u.id AND r.role='admin'
      WHERE u.id=OLD.target_user_id AND u.status='active') INTO target_admin;
    IF NOT decider_allowed OR NOT target_admin THEN RAISE EXCEPTION 'decision requires a different authorized Finance administrator and active Admin target'; END IF;
    IF NEW.status='approved' THEN
        SELECT EXISTS(SELECT 1 FROM financial_access_grants g WHERE g.id=NEW.grant_id
          AND g.user_id=OLD.target_user_id AND g.permission=OLD.permission
          AND g.granted_by=OLD.requested_by AND g.approved_by=NEW.decided_by AND g.revoked_at IS NULL)
          INTO grant_matches;
        IF NOT grant_matches THEN RAISE EXCEPTION 'approved request must reference the corresponding two-person grant'; END IF;
    ELSIF NEW.grant_id IS NOT NULL THEN
        RAISE EXCEPTION 'rejected request cannot reference a grant';
    END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER financial_access_grant_requests_guard
    BEFORE INSERT OR UPDATE OR DELETE ON financial_access_grant_requests
    FOR EACH ROW EXECUTE FUNCTION protect_financial_access_grant_request();

COMMENT ON TABLE financial_access_grant_requests IS
    'Audited two-person requests for limited finance.read/finance.post access; permission becomes effective only after a distinct finance.configure approver accepts.';
