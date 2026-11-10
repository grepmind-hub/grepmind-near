-- Grepmind platform checkout. Existing merchant orders and their items remain
-- unchanged, and platform lines and inventory reservations use dedicated tables.

ALTER TABLE customer_orders
    DROP CONSTRAINT customer_orders_order_type_check,
    ADD CONSTRAINT customer_orders_order_type_check
        CHECK (order_type IN ('food_delivery', 'table_reservation', 'hotel_booking', 'platform_order'));

ALTER TABLE customer_addresses
    ADD COLUMN delivery_locality_id UUID REFERENCES platform_delivery_localities(id) ON DELETE RESTRICT;

UPDATE customer_addresses a
SET delivery_locality_id = l.id
FROM platform_districts d
JOIN platform_delivery_localities l ON l.district_id = d.id
WHERE lower(d.name) = lower(a.city)
  AND lower(l.name) = lower(a.locality)
  AND a.delivery_locality_id IS NULL;

CREATE INDEX customer_addresses_delivery_locality_idx
    ON customer_addresses (customer_user_id, delivery_locality_id)
    WHERE delivery_locality_id IS NOT NULL;

CREATE TABLE platform_checkout_quotes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    vertical TEXT NOT NULL CHECK (vertical IN ('food', 'grocery')),
    locality_id UUID NOT NULL REFERENCES platform_delivery_localities(id) ON DELETE RESTRICT,
    service_date DATE NOT NULL,
    address_id UUID NOT NULL REFERENCES customer_addresses(id) ON DELETE RESTRICT,
    address_updated_at TIMESTAMPTZ NOT NULL,
    partner_business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    items JSONB NOT NULL CHECK (jsonb_typeof(items) = 'array' AND jsonb_array_length(items) BETWEEN 1 AND 50),
    item_subtotal_minor BIGINT NOT NULL CHECK (item_subtotal_minor >= 0),
    delivery_fee_minor BIGINT NOT NULL DEFAULT 0 CHECK (delivery_fee_minor >= 0),
    tax_minor BIGINT NOT NULL DEFAULT 0 CHECK (tax_minor >= 0),
    grand_total_minor BIGINT NOT NULL CHECK (grand_total_minor >= 0),
    currency CHAR(3) NOT NULL DEFAULT 'INR' CHECK (currency = 'INR'),
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_order_id UUID UNIQUE REFERENCES customer_orders(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (grand_total_minor = item_subtotal_minor + delivery_fee_minor + tax_minor)
);

CREATE INDEX platform_checkout_quotes_customer_expiry_idx
    ON platform_checkout_quotes(customer_user_id, expires_at DESC);

ALTER TABLE customer_orders
    ADD COLUMN order_source TEXT NOT NULL DEFAULT 'merchant_catalog'
        CHECK (order_source IN ('merchant_catalog', 'platform_catalog')),
    ADD COLUMN platform_vertical TEXT
        CHECK (platform_vertical IS NULL OR platform_vertical IN ('food', 'grocery')),
    ADD COLUMN delivery_locality_id UUID REFERENCES platform_delivery_localities(id) ON DELETE RESTRICT,
    ADD COLUMN platform_checkout_quote_id UUID UNIQUE REFERENCES platform_checkout_quotes(id) ON DELETE SET NULL,
    ADD COLUMN platform_idempotency_key UUID,
    ADD COLUMN platform_request_hash TEXT,
    ADD CONSTRAINT customer_orders_platform_identity_check CHECK (
        (order_source = 'merchant_catalog' AND platform_vertical IS NULL AND platform_checkout_quote_id IS NULL)
        OR (order_source = 'platform_catalog' AND platform_vertical IS NOT NULL AND platform_checkout_quote_id IS NOT NULL)
    );

CREATE UNIQUE INDEX customer_orders_platform_idempotency_idx
    ON customer_orders(customer_user_id, platform_idempotency_key)
    WHERE platform_idempotency_key IS NOT NULL;
CREATE INDEX customer_orders_platform_locality_idx
    ON customer_orders(delivery_locality_id, created_at DESC)
    WHERE order_source = 'platform_catalog';

CREATE TABLE platform_customer_order_items (
    order_id UUID NOT NULL REFERENCES customer_orders(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES platform_catalog_products(id) ON DELETE RESTRICT,
    variant_id UUID NOT NULL REFERENCES platform_catalog_variants(id) ON DELETE RESTRICT,
    vertical TEXT NOT NULL CHECK (vertical IN ('food', 'grocery')),
    product_name TEXT NOT NULL,
    variant_name TEXT NOT NULL,
    unit_label TEXT NOT NULL,
    unit_price_minor BIGINT NOT NULL CHECK (unit_price_minor >= 0),
    quantity INTEGER NOT NULL CHECK (quantity BETWEEN 1 AND 50),
    price_revision INTEGER NOT NULL CHECK (price_revision >= 1),
    PRIMARY KEY (order_id, variant_id)
);

CREATE INDEX platform_customer_order_items_product_idx
    ON platform_customer_order_items(product_id, variant_id);

CREATE TABLE platform_inventory_reservations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES customer_orders(id) ON DELETE CASCADE,
    mapping_id UUID NOT NULL REFERENCES platform_partner_product_mappings(id) ON DELETE RESTRICT,
    quantity INTEGER NOT NULL CHECK (quantity BETWEEN 1 AND 50),
    inventory_mode TEXT NOT NULL CHECK (inventory_mode IN ('finite', 'capacity', 'untracked')),
    service_date DATE NOT NULL,
    status TEXT NOT NULL DEFAULT 'reserved' CHECK (status IN ('reserved', 'consumed', 'released')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (order_id, mapping_id)
);

CREATE INDEX platform_inventory_reservations_capacity_idx
    ON platform_inventory_reservations(mapping_id, service_date, status)
    WHERE status IN ('reserved', 'consumed');
