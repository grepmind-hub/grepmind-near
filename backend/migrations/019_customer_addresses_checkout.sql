-- Customer-owned fulfillment addresses and server-issued checkout quotes.
-- Quotes are read-only pricing snapshots; inventory is reserved only when the
-- corresponding order is submitted.

CREATE TABLE customer_addresses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    label TEXT NOT NULL CHECK (char_length(label) BETWEEN 1 AND 40),
    recipient_name TEXT NOT NULL CHECK (char_length(recipient_name) BETWEEN 1 AND 100),
    address_line1 TEXT NOT NULL CHECK (char_length(address_line1) BETWEEN 3 AND 200),
    locality TEXT NOT NULL CHECK (char_length(locality) BETWEEN 1 AND 100),
    landmark TEXT NOT NULL DEFAULT '' CHECK (char_length(landmark) <= 120),
    city TEXT NOT NULL CHECK (char_length(city) BETWEEN 1 AND 80),
    state TEXT NOT NULL CHECK (char_length(state) BETWEEN 1 AND 80),
    postal_code TEXT NOT NULL CHECK (postal_code ~ '^[0-9]{6}$'),
    contact_phone TEXT NOT NULL CHECK (char_length(contact_phone) BETWEEN 8 AND 16),
    location GEOGRAPHY(POINT, 4326),
    is_default BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (city IN ('Cuttack', 'Jajpur'))
);

CREATE INDEX customer_addresses_owner_idx
    ON customer_addresses (customer_user_id, is_default DESC, updated_at DESC);
CREATE UNIQUE INDEX customer_addresses_one_default_per_customer_idx
    ON customer_addresses (customer_user_id) WHERE is_default;
CREATE INDEX customer_addresses_location_gix
    ON customer_addresses USING GIST (location) WHERE location IS NOT NULL;

CREATE TABLE checkout_quotes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    fulfillment_type TEXT NOT NULL CHECK (fulfillment_type IN ('delivery', 'takeaway')),
    address_id UUID REFERENCES customer_addresses(id) ON DELETE CASCADE,
    address_updated_at TIMESTAMPTZ,
    items JSONB NOT NULL CHECK (jsonb_typeof(items) = 'array'),
    item_subtotal_minor BIGINT NOT NULL CHECK (item_subtotal_minor >= 0),
    minimum_order_minor BIGINT NOT NULL CHECK (minimum_order_minor >= 0),
    delivery_fee_minor BIGINT NOT NULL CHECK (delivery_fee_minor >= 0),
    tax_minor BIGINT NOT NULL CHECK (tax_minor >= 0),
    grand_total_minor BIGINT NOT NULL CHECK (grand_total_minor >= 0),
    currency CHAR(3) NOT NULL DEFAULT 'INR',
    serviceability_method TEXT CHECK (serviceability_method IS NULL OR serviceability_method IN ('radius', 'city_match', 'not_required')),
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK ((fulfillment_type = 'delivery' AND address_id IS NOT NULL AND address_updated_at IS NOT NULL) OR (fulfillment_type = 'takeaway' AND address_id IS NULL AND address_updated_at IS NULL))
);

CREATE INDEX checkout_quotes_customer_expiry_idx
    ON checkout_quotes (customer_user_id, expires_at DESC);

ALTER TABLE customer_orders
    ADD COLUMN delivery_address_id UUID REFERENCES customer_addresses(id) ON DELETE SET NULL,
    ADD COLUMN delivery_address_snapshot JSONB,
    ADD COLUMN checkout_quote_id UUID UNIQUE REFERENCES checkout_quotes(id) ON DELETE SET NULL,
    ADD COLUMN checkout_idempotency_key UUID,
    ADD COLUMN checkout_request_hash TEXT,
    ADD COLUMN payment_status TEXT NOT NULL DEFAULT 'not_collected'
        CHECK (payment_status IN ('not_collected', 'pending', 'paid', 'failed'));

CREATE UNIQUE INDEX customer_orders_idempotency_idx
    ON customer_orders (customer_user_id, checkout_idempotency_key)
    WHERE checkout_idempotency_key IS NOT NULL;
CREATE INDEX customer_orders_delivery_address_idx
    ON customer_orders (delivery_address_id) WHERE delivery_address_id IS NOT NULL;

ALTER TABLE checkout_quotes
    ADD COLUMN consumed_order_id UUID REFERENCES customer_orders(id) ON DELETE SET NULL;

CREATE INDEX checkout_quotes_consumed_order_idx
    ON checkout_quotes (consumed_order_id) WHERE consumed_order_id IS NOT NULL;
