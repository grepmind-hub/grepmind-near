-- Record an append-only order fulfillment timeline. Payment state remains separate.
CREATE TABLE customer_order_status_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES customer_orders(id) ON DELETE CASCADE,
    status TEXT NOT NULL CHECK (status IN ('placed', 'confirmed', 'preparing', 'out_for_delivery', 'delivered', 'completed', 'cancelled')),
    event_kind TEXT NOT NULL DEFAULT 'status_change' CHECK (event_kind IN ('status_change', 'history_snapshot')),
    actor_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX customer_order_status_events_order_idx
    ON customer_order_status_events (order_id, created_at, id);

-- Existing orders have no transition history. Record only their current known
-- state and mark it as a snapshot so clients do not present it as full history.
INSERT INTO customer_order_status_events (order_id, status, event_kind, created_at)
SELECT id, status, 'history_snapshot', updated_at
FROM customer_orders;
