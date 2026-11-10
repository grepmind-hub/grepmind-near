-- Partner fulfillment states extend the existing customer order timeline.
-- Legacy merchant orders retain their existing transitions.

ALTER TABLE customer_orders
    DROP CONSTRAINT customer_orders_status_check,
    ADD CONSTRAINT customer_orders_status_check
        CHECK (status IN ('placed', 'accepted', 'confirmed', 'preparing', 'ready_for_pickup', 'rejected', 'out_for_delivery', 'delivered', 'completed', 'cancelled'));

ALTER TABLE customer_order_status_events
    DROP CONSTRAINT customer_order_status_events_status_check,
    ADD CONSTRAINT customer_order_status_events_status_check
        CHECK (status IN ('placed', 'accepted', 'confirmed', 'preparing', 'ready_for_pickup', 'rejected', 'out_for_delivery', 'delivered', 'completed', 'cancelled'));

ALTER TABLE customer_order_status_events
    DROP CONSTRAINT customer_order_status_events_event_kind_check,
    ADD CONSTRAINT customer_order_status_events_event_kind_check
        CHECK (event_kind IN ('status_change', 'history_snapshot', 'partner_accepted', 'partner_rejected', 'preparation_started', 'ready_for_pickup')),
    ADD COLUMN reason TEXT CHECK (reason IS NULL OR char_length(reason) <= 500),
    ADD CONSTRAINT customer_order_status_events_rejection_reason_check
        CHECK (event_kind <> 'partner_rejected' OR (reason IS NOT NULL AND char_length(btrim(reason)) BETWEEN 10 AND 500));

CREATE OR REPLACE FUNCTION prevent_customer_order_status_event_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'customer order status history is append-only';
END;
$$;

CREATE TRIGGER customer_order_status_events_immutable_update
    BEFORE UPDATE OR DELETE ON customer_order_status_events
    FOR EACH ROW EXECUTE FUNCTION prevent_customer_order_status_event_mutation();
