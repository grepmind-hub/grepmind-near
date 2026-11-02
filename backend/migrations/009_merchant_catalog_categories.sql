-- Merchant-owned catalog groups, separate from discovery taxonomy.
CREATE TABLE merchant_catalog_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name TEXT NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 80),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX merchant_catalog_category_name_idx
    ON merchant_catalog_categories (business_id, lower(name));
