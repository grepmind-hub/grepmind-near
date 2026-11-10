-- Stable Odisha delivery geography. Catalog visibility by district is kept
-- separate from delivery eligibility by locality.
CREATE TABLE platform_districts (
    id UUID PRIMARY KEY,
    state_code CHAR(2) NOT NULL CHECK (state_code = 'OD'),
    name TEXT NOT NULL UNIQUE,
    slug TEXT NOT NULL UNIQUE,
    is_active BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE platform_delivery_localities (
    id UUID PRIMARY KEY,
    district_id UUID NOT NULL REFERENCES platform_districts(id) ON DELETE RESTRICT,
    name TEXT NOT NULL,
    slug TEXT NOT NULL,
    delivery_enabled BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (district_id, slug),
    UNIQUE (district_id, id)
);
CREATE INDEX platform_delivery_localities_lookup_idx
    ON platform_delivery_localities(district_id, is_active, name);

INSERT INTO platform_districts(id,state_code,name,slug) VALUES
 ('02200000-0000-4000-8000-000000000001','OD','Cuttack','cuttack'),
 ('02200000-0000-4000-8000-000000000002','OD','Jajpur','jajpur');
INSERT INTO platform_delivery_localities(id,district_id,name,slug,delivery_enabled) VALUES
 ('02200000-0000-4000-8000-000000000101','02200000-0000-4000-8000-000000000001','Kuanpal','kuanpal',true),
 ('02200000-0000-4000-8000-000000000102','02200000-0000-4000-8000-000000000001','Jagatpur','jagatpur',false),
 ('02200000-0000-4000-8000-000000000103','02200000-0000-4000-8000-000000000001','Tangi','tangi',false),
 ('02200000-0000-4000-8000-000000000201','02200000-0000-4000-8000-000000000002','Chhatia','chhatia',true),
 ('02200000-0000-4000-8000-000000000202','02200000-0000-4000-8000-000000000002','Chandikhol','chandikhol',false);

CREATE TABLE platform_catalog_product_district_visibility (
    product_id UUID NOT NULL REFERENCES platform_catalog_products(id) ON DELETE CASCADE,
    district_id UUID NOT NULL REFERENCES platform_districts(id) ON DELETE RESTRICT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY(product_id,district_id)
);
CREATE TABLE platform_catalog_product_delivery_localities (
    product_id UUID NOT NULL REFERENCES platform_catalog_products(id) ON DELETE CASCADE,
    locality_id UUID NOT NULL REFERENCES platform_delivery_localities(id) ON DELETE RESTRICT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY(product_id,locality_id)
);
CREATE INDEX platform_catalog_product_locality_lookup_idx
    ON platform_catalog_product_delivery_localities(locality_id,product_id) WHERE is_active;

CREATE TABLE platform_partner_delivery_localities (
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    locality_id UUID NOT NULL REFERENCES platform_delivery_localities(id) ON DELETE RESTRICT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY(business_id,locality_id)
);

-- Preserve existing district visibility. Migrate recognized legacy locality
-- labels to stable IDs; unknown free text is intentionally not treated as coverage.
INSERT INTO platform_catalog_product_district_visibility(product_id,district_id,is_active)
SELECT DISTINCT a.product_id,d.id,a.is_active
FROM platform_catalog_product_areas a JOIN platform_districts d ON lower(d.name)=lower(a.city)
ON CONFLICT (product_id,district_id) DO NOTHING;
INSERT INTO platform_catalog_product_delivery_localities(product_id,locality_id,is_active)
SELECT a.product_id,l.id,a.is_active
FROM platform_catalog_product_areas a
JOIN platform_districts d ON lower(d.name)=lower(a.city)
JOIN platform_delivery_localities l ON l.district_id=d.id AND lower(l.name)=lower(a.locality)
WHERE a.locality IS NOT NULL
ON CONFLICT (product_id,locality_id) DO NOTHING;
INSERT INTO platform_partner_delivery_localities(business_id,locality_id,is_active)
SELECT a.business_id,l.id,a.is_active
FROM platform_partner_coverage_areas a
JOIN platform_districts d ON lower(d.name)=lower(a.city)
JOIN platform_delivery_localities l ON l.district_id=d.id AND lower(l.name)=lower(a.locality)
WHERE a.locality IS NOT NULL
ON CONFLICT (business_id,locality_id) DO NOTHING;
