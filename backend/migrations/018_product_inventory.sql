-- Product stock is explicitly either untracked or finite. Existing products
-- remain untracked; this migration never invents an available quantity.
ALTER TABLE products
    ADD COLUMN inventory_mode TEXT NOT NULL DEFAULT 'untracked'
        CHECK (inventory_mode IN ('untracked', 'finite')),
    ADD COLUMN available_quantity INTEGER;

ALTER TABLE products
    ADD CONSTRAINT products_inventory_quantity_check
    CHECK (
        (inventory_mode = 'untracked' AND available_quantity IS NULL)
        OR (inventory_mode = 'finite' AND available_quantity IS NOT NULL AND available_quantity >= 0)
    );

CREATE INDEX products_finite_inventory_idx
    ON products (business_id, available_quantity)
    WHERE inventory_mode = 'finite';
