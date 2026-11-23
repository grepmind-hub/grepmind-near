-- PP-02 Location & PIN Code Serviceability Enhancement
-- Adds PIN codes, geographical coordinates, radius, and capability flags to platform_delivery_localities.
-- Creates location_interest_leads for customer notifications when unserved areas expand.

ALTER TABLE platform_delivery_localities
    ADD COLUMN IF NOT EXISTS pin_codes TEXT[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS service_radius_km DOUBLE PRECISION NOT NULL DEFAULT 10.0,
    ADD COLUMN IF NOT EXISTS food_delivery_enabled BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS grocery_delivery_enabled BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS medicines_delivery_enabled BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS local_services_enabled BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS transport_enabled BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS merchant_discovery_enabled BOOLEAN NOT NULL DEFAULT true;

-- Update pilot localities with accurate coordinates and PIN codes
UPDATE platform_delivery_localities SET
    pin_codes = ARRAY['754023'],
    latitude = 20.6105,
    longitude = 86.0270,
    service_radius_km = 10.0,
    delivery_enabled = true,
    is_active = true
WHERE slug = 'chhatia';

UPDATE platform_delivery_localities SET
    pin_codes = ARRAY['754204', '754200'],
    latitude = 20.5348,
    longitude = 86.0827,
    service_radius_km = 10.0,
    delivery_enabled = true,
    is_active = true
WHERE slug = 'kuanpal';

UPDATE platform_delivery_localities SET
    pin_codes = ARRAY['754021'],
    latitude = 20.5100,
    longitude = 85.9200,
    service_radius_km = 10.0
WHERE slug = 'jagatpur';

UPDATE platform_delivery_localities SET
    pin_codes = ARRAY['754022'],
    latitude = 20.5800,
    longitude = 85.9800,
    service_radius_km = 10.0
WHERE slug = 'tangi';

UPDATE platform_delivery_localities SET
    pin_codes = ARRAY['755044'],
    latitude = 20.6900,
    longitude = 86.1500,
    service_radius_km = 10.0
WHERE slug = 'chandikhol';

-- Create location interest leads if not exists
CREATE TABLE IF NOT EXISTS location_interest_leads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    phone TEXT,
    pin_code VARCHAR(10),
    locality_name TEXT,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS location_interest_leads_pin_idx ON location_interest_leads(pin_code);
