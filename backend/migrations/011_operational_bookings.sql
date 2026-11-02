-- Persist customer orders and hospitality reservations. All totals are calculated by the API.

CREATE TABLE customer_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_user_id UUID NOT NULL REFERENCES users(id),
    business_id UUID NOT NULL REFERENCES businesses(id),
    order_type TEXT NOT NULL CHECK (order_type IN ('food_delivery', 'table_reservation', 'hotel_booking')),
    status TEXT NOT NULL DEFAULT 'placed'
        CHECK (status IN ('placed', 'confirmed', 'preparing', 'out_for_delivery', 'delivered', 'completed', 'cancelled')),
    fulfillment_type TEXT CHECK (fulfillment_type IS NULL OR fulfillment_type IN ('delivery', 'takeaway')),
    delivery_address TEXT,
    customer_notes TEXT,
    item_total NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (item_total >= 0),
    delivery_fee NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (delivery_fee >= 0),
    tax_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
    grand_total NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (grand_total >= 0),
    currency CHAR(3) NOT NULL DEFAULT 'INR',
    eta_minutes INTEGER CHECK (eta_minutes IS NULL OR eta_minutes BETWEEN 1 AND 1440),
    reservation_at TIMESTAMPTZ,
    reservation_end_at TIMESTAMPTZ,
    guest_count INTEGER CHECK (guest_count IS NULL OR guest_count BETWEEN 1 AND 50),
    seating_area TEXT,
    room_product_id UUID REFERENCES products(id),
    reference_code TEXT NOT NULL UNIQUE,
    cancelled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX customer_orders_customer_idx ON customer_orders (customer_user_id, created_at DESC);
CREATE INDEX customer_orders_business_idx ON customer_orders (business_id, status, created_at DESC);

CREATE TABLE customer_order_items (
    order_id UUID NOT NULL REFERENCES customer_orders(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id),
    product_name TEXT NOT NULL,
    unit_price NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
    quantity INTEGER NOT NULL CHECK (quantity BETWEEN 1 AND 50),
    dietary_type TEXT,
    PRIMARY KEY (order_id, product_id)
);

CREATE TABLE service_request_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id UUID NOT NULL REFERENCES service_requests(id) ON DELETE CASCADE,
    status TEXT NOT NULL,
    actor_user_id UUID REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX service_request_events_request_idx ON service_request_events (request_id, created_at ASC);

INSERT INTO service_request_events (request_id, status, actor_user_id, created_at)
SELECT id, status, customer_user_id, created_at FROM service_requests
ON CONFLICT DO NOTHING;
