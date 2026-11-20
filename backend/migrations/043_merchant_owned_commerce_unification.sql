-- Migration 043: Merchant-Owned Commerce Unification
-- Phase 02G: Unifies delivery dispatch and product schemas for merchant-owned food and grocery commerce.
-- Preserves existing platform catalog orders and historical database records.

-- 1. Extend products table with grocery and retail unit attributes
ALTER TABLE products
ADD COLUMN IF NOT EXISTS unit_label TEXT CHECK (unit_label IS NULL OR char_length(btrim(unit_label)) BETWEEN 1 AND 40),
ADD COLUMN IF NOT EXISTS mrp NUMERIC(12,2) CHECK (mrp IS NULL OR mrp >= 0),
ADD COLUMN IF NOT EXISTS barcode TEXT CHECK (barcode IS NULL OR char_length(btrim(barcode)) BETWEEN 1 AND 80),
ADD COLUMN IF NOT EXISTS grocery_category TEXT CHECK (grocery_category IS NULL OR char_length(btrim(grocery_category)) BETWEEN 1 AND 80);

CREATE INDEX IF NOT EXISTS products_barcode_idx ON products(barcode) WHERE barcode IS NOT NULL;
CREATE INDEX IF NOT EXISTS products_grocery_category_idx ON products(business_id, grocery_category) WHERE grocery_category IS NOT NULL;

-- 2. Broaden automated delivery job creation trigger for both platform_catalog and merchant_catalog orders
CREATE OR REPLACE FUNCTION create_delivery_job_for_platform_preparation()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    created_job_id UUID;
    target_locality_id UUID;
BEGIN
    IF NEW.order_source NOT IN ('platform_catalog', 'merchant_catalog')
       OR NEW.fulfillment_type <> 'delivery'
       OR NEW.status <> 'preparing'
       OR OLD.status = NEW.status THEN
        RETURN NEW;
    END IF;

    target_locality_id := NEW.delivery_locality_id;
    IF target_locality_id IS NULL AND NEW.delivery_address_id IS NOT NULL THEN
        SELECT a.delivery_locality_id INTO target_locality_id
        FROM customer_addresses a
        WHERE a.id = NEW.delivery_address_id;
    END IF;

    -- For platform orders, require explicit platform partner mapping.
    -- For merchant orders, require approved business with delivery_enabled.
    IF NEW.order_source = 'platform_catalog' THEN
        IF target_locality_id IS NULL
           OR NOT EXISTS (
               SELECT 1 FROM platform_delivery_localities l
               WHERE l.id=target_locality_id AND l.is_active AND l.delivery_enabled
           )
           OR NOT EXISTS (
               SELECT 1 FROM platform_partner_delivery_localities c
               JOIN businesses b ON b.id=c.business_id AND b.status='approved'
               WHERE c.business_id=NEW.business_id AND c.locality_id=target_locality_id AND c.is_active
           ) THEN
            RAISE EXCEPTION 'platform delivery job requires an approved partner with active locality coverage';
        END IF;
    ELSE
        -- merchant_catalog: require approved business with delivery_enabled
        IF NOT EXISTS (
            SELECT 1 FROM businesses b
            WHERE b.id = NEW.business_id AND b.status = 'approved' AND b.delivery_enabled = true
        ) THEN
            RAISE EXCEPTION 'merchant delivery job requires an approved business with delivery enabled';
        END IF;

        IF target_locality_id IS NULL THEN
            SELECT l.id INTO target_locality_id
            FROM platform_delivery_localities l
            WHERE l.is_active AND l.delivery_enabled
            ORDER BY l.created_at ASC LIMIT 1;
        END IF;
    END IF;

    IF target_locality_id IS NULL THEN
        RAISE EXCEPTION 'delivery job requires a valid delivery locality';
    END IF;

    INSERT INTO delivery_jobs(order_id, business_id, locality_id)
    VALUES (NEW.id, NEW.business_id, target_locality_id)
    ON CONFLICT (order_id) DO NOTHING
    RETURNING id INTO created_job_id;

    IF created_job_id IS NOT NULL THEN
        INSERT INTO delivery_events(job_id, event_type, metadata)
        VALUES (created_job_id, 'job_created', jsonb_build_object('source', CASE WHEN NEW.order_source = 'platform_catalog' THEN 'partner_preparing' ELSE 'merchant_preparing' END));
    END IF;
    RETURN NEW;
END;
$$;

-- 3. Broaden delivery job cancellation trigger to handle both platform_catalog and merchant_catalog orders
CREATE OR REPLACE FUNCTION cancel_delivery_job_with_order()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    delivery_job_id UUID;
BEGIN
    IF NEW.order_source NOT IN ('platform_catalog', 'merchant_catalog')
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

-- 4. Broaden post-pickup cancellation prevention to protect merchant delivery orders
CREATE OR REPLACE FUNCTION prevent_cancel_after_delivery_pickup()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE current_delivery_state TEXT;
BEGIN
    IF NEW.order_source IN ('platform_catalog', 'merchant_catalog') AND NEW.status IN ('cancelled','rejected') AND OLD.status<>NEW.status THEN
        SELECT execution_state INTO current_delivery_state FROM delivery_jobs WHERE order_id=NEW.id FOR UPDATE;
        IF current_delivery_state IN ('picked_up','en_route','customer_unreachable','delivery_failed','return_required','return_in_progress','returned','delivered') THEN
            RAISE EXCEPTION 'delivery cannot be cancelled after pickup';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

-- 5. Broaden pre-pickup delivery cancellation recording
CREATE OR REPLACE FUNCTION mark_delivery_cancelled_before_pickup()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE delivery_job_id UUID; prior_state TEXT;
BEGIN
    IF NEW.order_source IN ('platform_catalog', 'merchant_catalog') AND NEW.status IN ('cancelled','rejected') AND OLD.status<>NEW.status THEN
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

-- 6. Broaden COD obligation protection to cover merchant_catalog orders
CREATE OR REPLACE FUNCTION protect_cod_obligation()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE valid_order BOOLEAN; sandbox_allowed BOOLEAN;
BEGIN
    IF TG_OP='DELETE' THEN RAISE EXCEPTION 'COD obligation snapshots are immutable'; END IF;
    IF TG_OP='UPDATE' THEN
        IF (NEW.id,NEW.order_id,NEW.customer_user_id,NEW.amount_minor,NEW.currency,NEW.policy_version,NEW.created_at)
           IS DISTINCT FROM (OLD.id,OLD.order_id,OLD.customer_user_id,OLD.amount_minor,OLD.currency,OLD.policy_version,OLD.created_at)
           OR OLD.state<>'due' OR NEW.state<>'collected'
           OR NOT EXISTS(SELECT 1 FROM cod_collections c WHERE c.obligation_id=OLD.id) THEN
            RAISE EXCEPTION 'COD obligation snapshots are immutable except after a collection record';
        END IF;
        RETURN NEW;
    END IF;
    SELECT EXISTS(SELECT 1 FROM customer_orders o WHERE o.id=NEW.order_id AND o.customer_user_id=NEW.customer_user_id
        AND o.order_source IN ('platform_catalog', 'merchant_catalog') AND o.payment_status='not_collected'
        AND o.status NOT IN ('cancelled','returned','delivered') AND o.currency='INR'
        AND NEW.amount_minor=round(o.grand_total*100)::bigint AND o.payment_method='cash_on_delivery'
        AND NOT EXISTS(SELECT 1 FROM payment_intents p WHERE p.order_id=o.id)) INTO valid_order;
    SELECT sandbox_cod_enabled AND financial_posting_enabled AND NOT upi_enabled AND NOT cod_enabled
        AND NOT merchant_settlement_enabled AND NOT real_money_enabled INTO sandbox_allowed
        FROM financial_feature_config WHERE singleton=true;
    IF NOT COALESCE(valid_order AND sandbox_allowed,false) THEN RAISE EXCEPTION 'COD obligation is not eligible or synthetic COD is disabled'; END IF;
    RETURN NEW;
END;
$$;

-- 7. Broaden order payment method immutability to cover merchant_catalog orders
CREATE OR REPLACE FUNCTION prevent_platform_order_payment_method_change()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.order_source IN ('platform_catalog', 'merchant_catalog') AND NEW.payment_method IS DISTINCT FROM OLD.payment_method THEN
        RAISE EXCEPTION 'order payment method is immutable after submission';
    END IF;
    RETURN NEW;
END;
$$;

-- 8. Broaden payment intent snapshot validation to cover merchant_catalog orders
CREATE OR REPLACE FUNCTION validate_payment_intent_snapshot()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE order_customer UUID; order_source TEXT; order_status TEXT; payment_state TEXT; amount BIGINT; order_currency CHAR(3);
BEGIN
    SELECT o.customer_user_id,o.order_source,o.status,o.payment_status,
           round(o.grand_total*100)::BIGINT,o.currency
      INTO order_customer,order_source,order_status,payment_state,amount,order_currency
      FROM customer_orders AS o WHERE o.id=NEW.order_id FOR UPDATE;
    IF NOT FOUND OR order_customer IS DISTINCT FROM NEW.customer_user_id
       OR order_source NOT IN ('platform_catalog', 'merchant_catalog')
       OR order_status IN ('cancelled','returned','delivered','completed')
       OR payment_state <> 'not_collected'
       OR amount IS DISTINCT FROM NEW.amount_minor
       OR order_currency IS DISTINCT FROM NEW.currency THEN
        RAISE EXCEPTION 'payment intent must match an eligible unpaid order';
    END IF;
    RETURN NEW;
END;
$$;

-- 9. Broaden cancellation guard for paid orders to cover merchant_catalog orders
CREATE OR REPLACE FUNCTION prevent_paid_platform_order_cancellation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.order_source IN ('platform_catalog', 'merchant_catalog') AND NEW.status IN ('cancelled', 'returned') AND NEW.status IS DISTINCT FROM OLD.status THEN
        IF NEW.status = 'cancelled' THEN
            IF EXISTS (
                SELECT 1 FROM delivery_jobs j
                WHERE j.order_id = NEW.id
                  AND j.execution_state IN ('picked_up', 'en_route', 'delivered', 'returned')
            ) THEN
                RAISE EXCEPTION 'cannot cancel order after rider pickup';
            END IF;
        END IF;

        IF OLD.payment_status = 'paid' THEN
            IF NEW.status = 'cancelled' THEN
                IF NOT EXISTS (
                    SELECT 1 FROM payment_refunds pr
                    WHERE pr.order_id = NEW.id
                      AND pr.customer_user_id = NEW.customer_user_id
                      AND pr.requested_by = NEW.customer_user_id
                      AND pr.reason_code = 'order_cancelled'
                      AND pr.status IN ('requested', 'approved', 'processing', 'succeeded')
                ) THEN
                    RAISE EXCEPTION 'verified paid order requires an approved cancellation refund workflow before cancellation';
                END IF;
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
