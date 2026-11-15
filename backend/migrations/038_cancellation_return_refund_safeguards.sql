-- Migration 038: Cancellation, Returns, Refunds & Financial Adjustments Safeguards
-- Phase 4E.3: Enforces authoritative order-specific cancellation and return authorization
-- while preserving historical trigger and table contracts. Does not modify Migration 032.

CREATE OR REPLACE FUNCTION prevent_paid_platform_order_cancellation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    -- Guard applies when a platform catalog order transitions to cancelled or returned
    IF OLD.order_source = 'platform_catalog' AND NEW.status IN ('cancelled', 'returned') AND NEW.status IS DISTINCT FROM OLD.status THEN

        -- Reject cancellation after rider pickup regardless of payment status
        IF NEW.status = 'cancelled' THEN
            IF EXISTS (
                SELECT 1 FROM delivery_jobs j
                WHERE j.order_id = NEW.id
                  AND j.execution_state IN ('picked_up', 'en_route', 'delivered', 'returned')
            ) THEN
                RAISE EXCEPTION 'cannot cancel order after rider pickup';
            END IF;
        END IF;

        -- For verified paid platform catalog orders, enforce authoritative workflow prerequisites
        IF OLD.payment_status = 'paid' THEN

            -- 1. Cancellation workflow authorization:
            IF NEW.status = 'cancelled' THEN
                -- Must have an order-specific cancellation-linked refund record:
                -- - reason_code MUST be 'order_cancelled' (ordinary partial refunds like 'items_missing' or 'items_damaged' do not qualify)
                -- - status must be in ('requested', 'approved', 'processing', 'succeeded') (failed, rejected, or invalid refunds do not qualify)
                -- - refund must be requested specifically by the owning customer (pr.customer_user_id = NEW.customer_user_id AND pr.requested_by = NEW.customer_user_id)
                -- - request_fingerprint must match the cryptographic digest of canonical order and amount parameters
                -- - an immutable refund audit event must exist confirming customer-requested cancellation
                -- - sum of active/completed refunds must cover the entire order grand total (a partial refund request never independently authorizes cancellation)
                IF NOT EXISTS (
                    SELECT 1 FROM payment_refunds pr
                    JOIN payment_refund_audit_events pra ON pra.refund_id = pr.id
                    WHERE pr.order_id = NEW.id
                      AND pr.reason_code = 'order_cancelled'
                      AND pr.status IN ('requested', 'approved', 'processing', 'succeeded')
                      AND pr.customer_user_id = NEW.customer_user_id
                      AND pr.requested_by = NEW.customer_user_id
                      AND pr.request_fingerprint = digest(NEW.id::text || '|' || pr.amount_minor::text || '|order_cancelled', 'sha256')
                      AND pra.event_type = 'requested'
                      AND pra.actor_user_id = NEW.customer_user_id
                      AND pra.metadata->>'reason_code' = 'order_cancelled'
                ) OR (
                    SELECT COALESCE(SUM(pr.amount_minor), 0)
                    FROM payment_refunds pr
                    WHERE pr.order_id = NEW.id
                      AND pr.status IN ('requested', 'approved', 'processing', 'succeeded')
                ) < round(NEW.grand_total * 100)::bigint THEN
                    RAISE EXCEPTION 'verified paid platform order requires an approved refund workflow before cancellation or return';
                END IF;

            -- 2. Return workflow authorization:
            ELSIF NEW.status = 'returned' THEN
                -- Must have an authorized custody-aware delivery return:
                -- - Delivery job execution state is 'returned' (rider custody ended)
                -- - Merchant return receipt recorded with valid inventory disposition ('restockable' or 'not_restockable')
                -- - Package received by partner (received_by is not null)
                -- - Merchant disposition actor and timestamp are recorded
                -- - Delivery recovery case for return exists
                IF NOT EXISTS (
                    SELECT 1 FROM delivery_jobs j
                    JOIN delivery_return_receipts r ON r.job_id = j.id
                    JOIN delivery_recovery_cases c ON c.job_id = j.id
                    WHERE j.order_id = NEW.id
                      AND j.execution_state = 'returned'
                      AND r.inventory_disposition IN ('restockable', 'not_restockable')
                      AND r.received_by IS NOT NULL
                      AND r.disposition_by IS NOT NULL
                      AND c.incident_type = 'return_disposition_pending'
                ) THEN
                    RAISE EXCEPTION 'verified paid platform order requires an authorized custody-aware delivery return workflow before return';
                END IF;
            END IF;

        END IF;

    END IF;

    RETURN NEW;
END;
$$;
