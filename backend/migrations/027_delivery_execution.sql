-- Delivery execution is separate from dispatch, fulfillment and payment state.
ALTER TABLE delivery_jobs
    ADD COLUMN execution_state TEXT NOT NULL DEFAULT 'assigned'
        CHECK (execution_state IN (
            'assigned','arriving_at_pickup','at_pickup','picked_up','en_route','delivered',
            'pickup_failed','customer_unreachable','delivery_failed','return_required',
            'return_in_progress','returned','cancelled'
        ));

CREATE TABLE delivery_verification_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id UUID NOT NULL REFERENCES delivery_jobs(id) ON DELETE RESTRICT,
    purpose TEXT NOT NULL CHECK (purpose IN ('pickup','delivery')),
    code_hmac BYTEA NOT NULL CHECK (octet_length(code_hmac)=32),
    issued_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    issued_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    attempts INT NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 5),
    consumed_at TIMESTAMPTZ,
    invalidated_at TIMESTAMPTZ,
    CHECK (expires_at > issued_at)
);
CREATE UNIQUE INDEX delivery_verification_one_open_per_purpose
    ON delivery_verification_codes(job_id,purpose)
    WHERE consumed_at IS NULL AND invalidated_at IS NULL;
CREATE INDEX delivery_verification_expiry_idx
    ON delivery_verification_codes(expires_at)
    WHERE consumed_at IS NULL AND invalidated_at IS NULL;

CREATE TABLE delivery_execution_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id UUID NOT NULL REFERENCES delivery_jobs(id) ON DELETE RESTRICT,
    actor_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    actor_type TEXT NOT NULL CHECK (actor_type IN ('rider','merchant','customer','admin','system')),
    event_type TEXT NOT NULL CHECK (char_length(event_type) BETWEEN 2 AND 80),
    from_state TEXT,
    to_state TEXT NOT NULL,
    reason TEXT CHECK (reason IS NULL OR char_length(reason) BETWEEN 1 AND 500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX delivery_execution_events_job_idx
    ON delivery_execution_events(job_id,created_at,id);
CREATE OR REPLACE FUNCTION prevent_delivery_execution_event_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'delivery execution history is append-only';
END;
$$;
CREATE TRIGGER delivery_execution_events_immutable
    BEFORE UPDATE OR DELETE ON delivery_execution_events
    FOR EACH ROW EXECUTE FUNCTION prevent_delivery_execution_event_mutation();

CREATE TABLE delivery_exceptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id UUID NOT NULL REFERENCES delivery_jobs(id) ON DELETE RESTRICT,
    reported_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    exception_type TEXT NOT NULL CHECK (exception_type IN (
        'pickup_failed','customer_unreachable','delivery_failed','return_required'
    )),
    state TEXT NOT NULL DEFAULT 'open' CHECK (state IN ('open','resolved')),
    reason TEXT NOT NULL CHECK (char_length(btrim(reason)) BETWEEN 10 AND 500),
    resolution TEXT CHECK (resolution IS NULL OR char_length(resolution) BETWEEN 10 AND 500),
    resolved_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at TIMESTAMPTZ
);
CREATE INDEX delivery_exceptions_open_idx ON delivery_exceptions(state,created_at DESC);

-- Once goods have been picked up, legacy order cancellation must not restore stock
-- or discard the physical delivery obligation. Support must resolve via delivery operations.
CREATE OR REPLACE FUNCTION prevent_cancel_after_delivery_pickup()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE current_delivery_state TEXT;
BEGIN
    IF NEW.order_source='platform_catalog' AND NEW.status IN ('cancelled','rejected') AND OLD.status<>NEW.status THEN
        SELECT execution_state INTO current_delivery_state FROM delivery_jobs WHERE order_id=NEW.id FOR UPDATE;
        IF current_delivery_state IN ('picked_up','en_route','customer_unreachable','delivery_failed','return_required','return_in_progress','returned','delivered') THEN
            RAISE EXCEPTION 'platform delivery cannot be cancelled after pickup';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER customer_orders_prevent_cancel_after_pickup
    BEFORE UPDATE OF status ON customer_orders
    FOR EACH ROW EXECUTE FUNCTION prevent_cancel_after_delivery_pickup();

CREATE OR REPLACE FUNCTION mark_delivery_cancelled_before_pickup()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE delivery_job_id UUID; prior_state TEXT;
BEGIN
    IF NEW.order_source='platform_catalog' AND NEW.status IN ('cancelled','rejected') AND OLD.status<>NEW.status THEN
        SELECT id,execution_state INTO delivery_job_id,prior_state FROM delivery_jobs WHERE order_id=NEW.id FOR UPDATE;
        IF delivery_job_id IS NOT NULL AND prior_state NOT IN ('cancelled','delivered','returned') THEN
            UPDATE delivery_jobs SET execution_state='cancelled',updated_at=now() WHERE id=delivery_job_id;
            INSERT INTO delivery_execution_events(job_id,actor_type,event_type,from_state,to_state,reason)
            VALUES(delivery_job_id,'system','order_cancelled_before_pickup',prior_state,'cancelled','Order cancelled before physical pickup.');
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER customer_orders_record_delivery_cancellation
    AFTER UPDATE OF status ON customer_orders
    FOR EACH ROW EXECUTE FUNCTION mark_delivery_cancelled_before_pickup();
