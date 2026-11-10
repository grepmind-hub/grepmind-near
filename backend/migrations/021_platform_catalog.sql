-- Grepmind-owned customer catalog and explicit local fulfillment mappings.
-- This domain is separate from merchant-owned products used for local discovery.

CREATE TABLE platform_catalog_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vertical TEXT NOT NULL CHECK (vertical IN ('food', 'grocery')),
    slug TEXT NOT NULL CHECK (slug = lower(btrim(slug)) AND char_length(slug) BETWEEN 1 AND 80),
    name TEXT NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 100),
    parent_id UUID,
    is_active BOOLEAN NOT NULL DEFAULT true,
    is_system BOOLEAN NOT NULL DEFAULT false,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (vertical, id),
    FOREIGN KEY (vertical, parent_id) REFERENCES platform_catalog_categories(vertical, id) ON DELETE RESTRICT,
    CHECK (parent_id IS NULL OR parent_id <> id)
);

CREATE UNIQUE INDEX platform_catalog_categories_slug_idx
    ON platform_catalog_categories (vertical, lower(slug));
CREATE INDEX platform_catalog_categories_parent_idx
    ON platform_catalog_categories (vertical, parent_id, sort_order, name);

-- Fixed roots identify the initial commerce verticals. They are taxonomy only,
-- not products or an assertion that products/partners are currently available.
INSERT INTO platform_catalog_categories (vertical, slug, name, is_system, sort_order)
VALUES ('food', 'food', 'Food', true, 10),
       ('grocery', 'grocery', 'Grocery', true, 20)
ON CONFLICT DO NOTHING;

CREATE TABLE platform_catalog_products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sku TEXT NOT NULL UNIQUE CHECK (char_length(btrim(sku)) BETWEEN 1 AND 80),
    category_id UUID NOT NULL REFERENCES platform_catalog_categories(id) ON DELETE RESTRICT,
    name TEXT NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 160),
    description TEXT NOT NULL DEFAULT '' CHECK (char_length(description) <= 4000),
    image_urls TEXT[] NOT NULL DEFAULT '{}',
    tax_classification TEXT CHECK (tax_classification IS NULL OR char_length(tax_classification) <= 80),
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'inactive')),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (cardinality(image_urls) <= 8)
);

CREATE INDEX platform_catalog_products_category_status_idx
    ON platform_catalog_products (category_id, status, updated_at DESC);
CREATE INDEX platform_catalog_products_name_idx
    ON platform_catalog_products USING GIN (to_tsvector('simple', name || ' ' || description));

CREATE TABLE platform_catalog_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES platform_catalog_products(id) ON DELETE CASCADE,
    sku TEXT NOT NULL UNIQUE CHECK (char_length(btrim(sku)) BETWEEN 1 AND 80),
    name TEXT NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 120),
    unit_label TEXT NOT NULL CHECK (char_length(btrim(unit_label)) BETWEEN 1 AND 40),
    price_minor BIGINT NOT NULL CHECK (price_minor >= 0),
    currency CHAR(3) NOT NULL DEFAULT 'INR' CHECK (currency = 'INR'),
    price_revision INTEGER NOT NULL DEFAULT 1 CHECK (price_revision >= 1),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (product_id, id)
);

CREATE INDEX platform_catalog_variants_product_idx
    ON platform_catalog_variants (product_id, is_active, name);

CREATE TABLE platform_catalog_product_areas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES platform_catalog_products(id) ON DELETE CASCADE,
    city TEXT NOT NULL CHECK (city IN ('Cuttack', 'Jajpur')),
    locality TEXT CHECK (locality IS NULL OR char_length(btrim(locality)) BETWEEN 1 AND 100),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX platform_catalog_product_areas_unique_idx
    ON platform_catalog_product_areas (product_id, city, (lower(COALESCE(locality, ''))));
CREATE INDEX platform_catalog_product_areas_lookup_idx
    ON platform_catalog_product_areas (city, lower(locality), product_id)
    WHERE is_active;
CREATE INDEX platform_catalog_product_areas_product_idx
    ON platform_catalog_product_areas (product_id, city, lower(locality))
    WHERE is_active;

CREATE TABLE platform_partner_coverage_areas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    city TEXT NOT NULL CHECK (city IN ('Cuttack', 'Jajpur')),
    locality TEXT CHECK (locality IS NULL OR char_length(btrim(locality)) BETWEEN 1 AND 100),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX platform_partner_coverage_unique_idx
    ON platform_partner_coverage_areas (business_id, city, (lower(COALESCE(locality, ''))));
CREATE INDEX platform_partner_coverage_lookup_idx
    ON platform_partner_coverage_areas (city, lower(locality), business_id)
    WHERE is_active;
CREATE INDEX platform_partner_coverage_business_idx
    ON platform_partner_coverage_areas (business_id, city, lower(locality))
    WHERE is_active;

CREATE TABLE platform_partner_product_mappings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    variant_id UUID NOT NULL REFERENCES platform_catalog_variants(id) ON DELETE RESTRICT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'inactive')),
    inventory_mode TEXT NOT NULL DEFAULT 'untracked' CHECK (inventory_mode IN ('finite', 'untracked', 'capacity')),
    available_quantity INTEGER,
    capacity_per_day INTEGER,
    preparation_minutes INTEGER CHECK (preparation_minutes IS NULL OR preparation_minutes BETWEEN 0 AND 1440),
    supply_price_minor BIGINT CHECK (supply_price_minor IS NULL OR supply_price_minor >= 0),
    supply_currency CHAR(3) NOT NULL DEFAULT 'INR' CHECK (supply_currency = 'INR'),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL,
    approved_by UUID REFERENCES users(id) ON DELETE SET NULL,
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (business_id, variant_id),
    CHECK (
        (inventory_mode = 'finite' AND available_quantity IS NOT NULL AND available_quantity >= 0 AND capacity_per_day IS NULL)
        OR (inventory_mode = 'untracked' AND available_quantity IS NULL AND capacity_per_day IS NULL)
        OR (inventory_mode = 'capacity' AND available_quantity IS NULL AND capacity_per_day IS NOT NULL AND capacity_per_day >= 0)
    ),
    CHECK ((status = 'approved' AND approved_by IS NOT NULL AND approved_at IS NOT NULL) OR status <> 'approved')
);

CREATE INDEX platform_partner_mappings_variant_status_idx
    ON platform_partner_product_mappings (variant_id, status, business_id);
CREATE INDEX platform_partner_mappings_business_status_idx
    ON platform_partner_product_mappings (business_id, status, updated_at DESC);
