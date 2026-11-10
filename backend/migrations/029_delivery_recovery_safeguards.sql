-- Phase 3G-B: recovery is an audited overlay around existing dispatch and
-- execution state. It must never silently transfer physical custody.

-- Composite keys let recovery records prove they refer to the same job/order,
-- assignment, and business instead of relying only on independently valid IDs.
ALTER TABLE delivery_jobs
    ADD CONSTRAINT delivery_jobs_id_order_recovery_key UNIQUE (id, order_id),
    ADD CONSTRAINT delivery_jobs_id_business_recovery_key UNIQUE (id, business_id);

ALTER TABLE user_roles DROP CONSTRAINT IF EXISTS user_roles_role_check;
ALTER TABLE user_roles ADD CONSTRAINT user_roles_role_check
    CHECK (role IN ('customer','merchant','professional','admin','rider','delivery_operator'));

-- Delivery operators are separately assignable by the existing protected
-- primary-superadmin user-access workflow. The API also allows the root account.

CREATE TABLE delivery_recovery_cases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id UUID NOT NULL,
    order_id UUID NOT NULL REFERENCES customer_orders(id) ON DELETE RESTRICT,
    assignment_id UUID,
    rider_user_id UUID REFERENCES users(id) ON DELETE RESTRICT,
    incident_type TEXT NOT NULL CHECK (incident_type IN (
        'assignment_heartbeat_stale','rider_reports_unable_to_continue',
        'pickup_failed','partner_handover_not_completed','return_disposition_pending','dispatch_exhausted'
    )),
    state TEXT NOT NULL DEFAULT 'open' CHECK (state IN ('open','investigating','action_pending','resolved','escalated')),
    reason TEXT NOT NULL CHECK (char_length(btrim(reason)) BETWEEN 10 AND 500),
    resolution_code TEXT CHECK (resolution_code IS NULL OR char_length(resolution_code) BETWEEN 2 AND 80),
    resolution_reason TEXT CHECK (resolution_reason IS NULL OR char_length(resolution_reason) BETWEEN 10 AND 500),
    reported_by UUID REFERENCES users(id) ON DELETE SET NULL,
    resolved_by UUID REFERENCES users(id) ON DELETE SET NULL,
    opened_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at TIMESTAMPTZ,
    CHECK ((state='resolved' AND resolved_at IS NOT NULL AND resolved_by IS NOT NULL)
        OR (state<>'resolved' AND resolved_at IS NULL)),
    UNIQUE (id, job_id),
    FOREIGN KEY (job_id, order_id) REFERENCES delivery_jobs(id, order_id) ON DELETE RESTRICT,
    FOREIGN KEY (job_id, assignment_id) REFERENCES delivery_assignments(job_id, id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX delivery_recovery_one_open_assignment_incident_idx
    ON delivery_recovery_cases(job_id,assignment_id,incident_type)
    WHERE state IN ('open','investigating','action_pending','escalated');
CREATE INDEX delivery_recovery_queue_idx
    ON delivery_recovery_cases(state,opened_at DESC,id);
CREATE INDEX delivery_recovery_job_history_idx
    ON delivery_recovery_cases(job_id,opened_at,id);

CREATE TABLE delivery_recovery_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id UUID NOT NULL,
    job_id UUID NOT NULL,
    assignment_id UUID,
    actor_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    actor_type TEXT NOT NULL CHECK (actor_type IN ('rider','merchant','admin','system')),
    event_type TEXT NOT NULL CHECK (char_length(event_type) BETWEEN 2 AND 80),
    reason TEXT CHECK (reason IS NULL OR char_length(reason) BETWEEN 1 AND 500),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (octet_length(metadata::text)<=4096),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (case_id, job_id) REFERENCES delivery_recovery_cases(id, job_id) ON DELETE RESTRICT,
    FOREIGN KEY (job_id, assignment_id) REFERENCES delivery_assignments(job_id, id) ON DELETE RESTRICT
);
CREATE INDEX delivery_recovery_events_case_idx ON delivery_recovery_events(case_id,created_at,id);

CREATE OR REPLACE FUNCTION prevent_delivery_recovery_event_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'delivery recovery history is append-only';
END;
$$;
CREATE TRIGGER delivery_recovery_events_immutable
    BEFORE UPDATE OR DELETE ON delivery_recovery_events
    FOR EACH ROW EXECUTE FUNCTION prevent_delivery_recovery_event_mutation();

-- Keys/results are committed in the same transaction as the recovery effect.
-- A rolled-back action leaves no consumed key; same-key/different-payload is a 409.
CREATE TABLE delivery_recovery_idempotency (
    actor_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    idempotency_key TEXT NOT NULL CHECK (char_length(idempotency_key) BETWEEN 8 AND 128),
    operation TEXT NOT NULL CHECK (char_length(operation) BETWEEN 3 AND 80),
    request_hash BYTEA NOT NULL CHECK (octet_length(request_hash)=32),
    response JSONB NOT NULL CHECK (jsonb_typeof(response)='object'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY(actor_user_id,idempotency_key)
);

CREATE TABLE delivery_return_receipts (
    job_id UUID PRIMARY KEY,
    order_id UUID NOT NULL UNIQUE REFERENCES customer_orders(id) ON DELETE RESTRICT,
    business_id UUID NOT NULL,
    received_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    inventory_disposition TEXT NOT NULL DEFAULT 'pending'
        CHECK (inventory_disposition IN ('pending','restockable','not_restockable')),
    disposition_reason TEXT CHECK (disposition_reason IS NULL OR char_length(disposition_reason) BETWEEN 10 AND 500),
    disposition_by UUID REFERENCES users(id) ON DELETE SET NULL,
    disposition_at TIMESTAMPTZ,
    finalized_by UUID REFERENCES users(id) ON DELETE SET NULL,
    finalized_at TIMESTAMPTZ,
    CHECK ((inventory_disposition='pending' AND disposition_by IS NULL AND disposition_at IS NULL)
        OR (inventory_disposition<>'pending' AND disposition_by IS NOT NULL AND disposition_at IS NOT NULL)),
    CHECK ((finalized_at IS NULL AND finalized_by IS NULL) OR (finalized_at IS NOT NULL AND finalized_by IS NOT NULL)),
    FOREIGN KEY (job_id, order_id) REFERENCES delivery_jobs(id, order_id) ON DELETE RESTRICT,
    FOREIGN KEY (job_id, business_id) REFERENCES delivery_jobs(id, business_id) ON DELETE RESTRICT
);

CREATE TABLE delivery_recovery_partner_confirmations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id UUID NOT NULL,
    assignment_id UUID NOT NULL,
    business_id UUID NOT NULL,
    confirmed_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    confirmation TEXT NOT NULL CHECK (confirmation='goods_not_handed_over'),
    reason TEXT NOT NULL CHECK (char_length(btrim(reason)) BETWEEN 10 AND 500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(job_id,assignment_id),
    FOREIGN KEY (job_id,assignment_id) REFERENCES delivery_assignments(job_id,id) ON DELETE RESTRICT,
    FOREIGN KEY (job_id,business_id) REFERENCES delivery_jobs(id,business_id) ON DELETE RESTRICT
);

ALTER TABLE delivery_exceptions DROP CONSTRAINT IF EXISTS delivery_exceptions_exception_type_check;
ALTER TABLE delivery_exceptions ADD CONSTRAINT delivery_exceptions_exception_type_check
    CHECK (exception_type IN ('pickup_failed','customer_unreachable','delivery_failed','return_required','rider_unable_to_continue'));

ALTER TABLE customer_orders DROP CONSTRAINT IF EXISTS customer_orders_status_check;
ALTER TABLE customer_orders ADD CONSTRAINT customer_orders_status_check
    CHECK (status IN ('placed','accepted','confirmed','preparing','ready_for_pickup','rejected','out_for_delivery','delivered','completed','cancelled','returned'));
ALTER TABLE customer_order_status_events DROP CONSTRAINT IF EXISTS customer_order_status_events_status_check;
ALTER TABLE customer_order_status_events ADD CONSTRAINT customer_order_status_events_status_check
    CHECK (status IN ('placed','accepted','confirmed','preparing','ready_for_pickup','rejected','out_for_delivery','delivered','completed','cancelled','returned'));
ALTER TABLE customer_order_status_events DROP CONSTRAINT IF EXISTS customer_order_status_events_event_kind_check;
ALTER TABLE customer_order_status_events ADD CONSTRAINT customer_order_status_events_event_kind_check
    CHECK (event_kind IN ('status_change','history_snapshot','partner_accepted','partner_rejected','preparation_started','ready_for_pickup','delivery_returned'));
