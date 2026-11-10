-- Delivery dispatch is separate from customer orders and partner fulfillment.
-- A job is created atomically when a platform delivery order enters preparing.

CREATE TABLE delivery_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL UNIQUE REFERENCES customer_orders(id) ON DELETE RESTRICT,
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    locality_id UUID NOT NULL REFERENCES platform_delivery_localities(id) ON DELETE RESTRICT,
    state TEXT NOT NULL DEFAULT 'pending_dispatch'
        CHECK (state IN ('pending_dispatch','offered','assigned','no_rider_available','cancelled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX delivery_jobs_dispatch_idx ON delivery_jobs(state, locality_id, created_at);

CREATE TABLE rider_availability_sessions (
    rider_user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE RESTRICT,
    is_online BOOLEAN NOT NULL DEFAULT false,
    lease_expires_at TIMESTAMPTZ,
    last_heartbeat_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK ((is_online AND lease_expires_at IS NOT NULL) OR NOT is_online)
);
CREATE INDEX rider_availability_live_idx ON rider_availability_sessions(lease_expires_at)
    WHERE is_online;

CREATE TABLE delivery_dispatch_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id UUID NOT NULL REFERENCES delivery_jobs(id) ON DELETE RESTRICT,
    run_number INT NOT NULL CHECK (run_number > 0),
    state TEXT NOT NULL DEFAULT 'searching'
        CHECK (state IN ('searching','assigned','no_rider_available','cancelled')),
    started_by UUID REFERENCES users(id) ON DELETE SET NULL,
    reason TEXT CHECK (reason IS NULL OR char_length(reason) BETWEEN 10 AND 500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ,
    UNIQUE(job_id, run_number),
    UNIQUE(job_id, id)
);
CREATE UNIQUE INDEX delivery_dispatch_one_searching_run_idx
    ON delivery_dispatch_runs(job_id) WHERE state='searching';

CREATE TABLE delivery_offers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id UUID NOT NULL REFERENCES delivery_jobs(id) ON DELETE RESTRICT,
    dispatch_run_id UUID NOT NULL REFERENCES delivery_dispatch_runs(id) ON DELETE RESTRICT,
    rider_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    sequence INT NOT NULL CHECK (sequence > 0),
    state TEXT NOT NULL DEFAULT 'offered'
        CHECK (state IN ('offered','accepted','declined','expired','cancelled')),
    offered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    responded_at TIMESTAMPTZ,
    UNIQUE(dispatch_run_id, sequence),
    UNIQUE(dispatch_run_id, rider_user_id),
    CHECK (expires_at > offered_at)
);
CREATE UNIQUE INDEX delivery_offers_one_active_per_job_idx
    ON delivery_offers(job_id) WHERE state='offered';
CREATE UNIQUE INDEX delivery_offers_one_active_per_rider_idx
    ON delivery_offers(rider_user_id) WHERE state='offered';
CREATE INDEX delivery_offers_rider_inbox_idx ON delivery_offers(rider_user_id, state, expires_at DESC);

CREATE TABLE delivery_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id UUID NOT NULL REFERENCES delivery_jobs(id) ON DELETE RESTRICT,
    rider_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    offer_id UUID REFERENCES delivery_offers(id) ON DELETE RESTRICT,
    state TEXT NOT NULL DEFAULT 'active' CHECK (state IN ('active','cancelled','released')),
    assigned_by UUID REFERENCES users(id) ON DELETE SET NULL,
    assignment_reason TEXT CHECK (assignment_reason IS NULL OR char_length(assignment_reason) BETWEEN 10 AND 500),
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at TIMESTAMPTZ,
    UNIQUE(job_id, id),
    CHECK ((state='active' AND ended_at IS NULL) OR (state<>'active' AND ended_at IS NOT NULL))
);
CREATE UNIQUE INDEX delivery_assignments_one_active_job_idx
    ON delivery_assignments(job_id) WHERE state='active';
CREATE UNIQUE INDEX delivery_assignments_one_active_rider_idx
    ON delivery_assignments(rider_user_id) WHERE state='active';

CREATE TABLE delivery_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id UUID NOT NULL REFERENCES delivery_jobs(id) ON DELETE RESTRICT,
    actor_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    event_type TEXT NOT NULL CHECK (event_type IN (
        'job_created','dispatch_started','offer_issued','offer_declined','offer_expired',
        'offer_accepted','rider_assigned','dispatch_exhausted','dispatch_retried',
        'offer_cancelled','job_cancelled','manual_assignment'
    )),
    offer_id UUID REFERENCES delivery_offers(id) ON DELETE SET NULL,
    assignment_id UUID REFERENCES delivery_assignments(id) ON DELETE SET NULL,
    reason TEXT CHECK (reason IS NULL OR char_length(reason) <= 500),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (octet_length(metadata::text) <= 4096),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX delivery_events_job_idx ON delivery_events(job_id, created_at, id);

CREATE TABLE rider_availability_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rider_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    event_type TEXT NOT NULL CHECK (event_type IN ('online','offline','lease_expired')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX rider_availability_events_user_idx ON rider_availability_events(rider_user_id, created_at DESC);
CREATE OR REPLACE FUNCTION prevent_delivery_event_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'delivery history is append-only';
END;
$$;
CREATE TRIGGER delivery_events_immutable
    BEFORE UPDATE OR DELETE ON delivery_events
    FOR EACH ROW EXECUTE FUNCTION prevent_delivery_event_mutation();
CREATE TRIGGER rider_availability_events_immutable
    BEFORE UPDATE OR DELETE ON rider_availability_events
    FOR EACH ROW EXECUTE FUNCTION prevent_delivery_event_mutation();

CREATE OR REPLACE FUNCTION create_delivery_job_for_platform_preparation()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    created_job_id UUID;
BEGIN
    IF NEW.order_source <> 'platform_catalog'
       OR NEW.fulfillment_type <> 'delivery'
       OR NEW.status <> 'preparing'
       OR OLD.status = NEW.status THEN
        RETURN NEW;
    END IF;

    IF NEW.delivery_locality_id IS NULL
       OR NOT EXISTS (
           SELECT 1 FROM platform_delivery_localities l
           WHERE l.id=NEW.delivery_locality_id AND l.is_active AND l.delivery_enabled
       )
       OR NOT EXISTS (
           SELECT 1 FROM platform_partner_delivery_localities c
           JOIN businesses b ON b.id=c.business_id AND b.status='approved'
           WHERE c.business_id=NEW.business_id AND c.locality_id=NEW.delivery_locality_id AND c.is_active
       ) THEN
        RAISE EXCEPTION 'platform delivery job requires an approved partner with active locality coverage';
    END IF;

    INSERT INTO delivery_jobs(order_id, business_id, locality_id)
    VALUES (NEW.id, NEW.business_id, NEW.delivery_locality_id)
    ON CONFLICT (order_id) DO NOTHING
    RETURNING id INTO created_job_id;

    IF created_job_id IS NOT NULL THEN
        INSERT INTO delivery_events(job_id, event_type, metadata)
        VALUES (created_job_id, 'job_created', jsonb_build_object('source','partner_preparing'));
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER customer_orders_create_delivery_job
    AFTER UPDATE OF status ON customer_orders
    FOR EACH ROW EXECUTE FUNCTION create_delivery_job_for_platform_preparation();

CREATE OR REPLACE FUNCTION cancel_delivery_job_with_order()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    delivery_job_id UUID;
BEGIN
    IF NEW.order_source <> 'platform_catalog'
       OR NEW.status NOT IN ('cancelled','rejected')
       OR OLD.status = NEW.status THEN
        RETURN NEW;
    END IF;

    SELECT id INTO delivery_job_id FROM delivery_jobs WHERE order_id=NEW.id FOR UPDATE;
    IF delivery_job_id IS NULL THEN
        RETURN NEW;
    END IF;

    UPDATE delivery_offers SET state='cancelled',responded_at=now()
      WHERE job_id=delivery_job_id AND state='offered';
    UPDATE delivery_assignments SET state='cancelled',ended_at=now()
      WHERE job_id=delivery_job_id AND state='active';
    UPDATE delivery_dispatch_runs SET state='cancelled',completed_at=now()
      WHERE job_id=delivery_job_id AND state='searching';
    UPDATE delivery_jobs SET state='cancelled',updated_at=now() WHERE id=delivery_job_id;
    INSERT INTO delivery_events(job_id,event_type,reason,metadata)
      VALUES(delivery_job_id,'job_cancelled',NULL,jsonb_build_object('order_status',NEW.status));
    RETURN NEW;
END;
$$;
CREATE TRIGGER customer_orders_cancel_delivery_job
    AFTER UPDATE OF status ON customer_orders
    FOR EACH ROW EXECUTE FUNCTION cancel_delivery_job_with_order();
