-- Migration 003: Unserved location demand tracking & multi-city expansion (Cuttack & Jajpur)

-- 1. Table for tracking customer searches in unserved locations for expansion heatmap & demand analytics
CREATE TABLE IF NOT EXISTS unserved_location_demand (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    query TEXT,
    locality TEXT,
    city TEXT NOT NULL,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    notification_phone TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS unserved_location_demand_city_idx ON unserved_location_demand (city);
CREATE INDEX IF NOT EXISTS unserved_location_demand_created_idx ON unserved_location_demand (created_at DESC);

-- 2. Seed active service professionals & retail businesses for Cuttack (20.4625, 85.8830)
-- Merchant User for Cuttack
INSERT INTO users (id, phone_e164, display_name, status, preferred_language)
VALUES ('c1111111-1111-1111-1111-111111111111', '+919861000001', 'Mahanadi Electricals & Repair', 'active', 'en')
ON CONFLICT (phone_e164) DO NOTHING;

INSERT INTO user_roles (user_id, role)
VALUES ('c1111111-1111-1111-1111-111111111111', 'merchant')
ON CONFLICT DO NOTHING;

INSERT INTO businesses (
    id, owner_user_id, name, slug, description, category_slug, phone_e164, whatsapp_e164,
    address_text, locality, city, postal_code, location, status, verification_status, cover_photo_url
) VALUES (
    'c2222222-2222-2222-2222-222222222222',
    'c1111111-1111-1111-1111-111111111111',
    'Mahanadi Electrical & AC Care',
    'mahanadi-electrical-cuttack',
    'Expert residential wiring, inverter setup, and certified AC repairs across Millennium City Cuttack.',
    'electrician',
    '+919861000001',
    '+919861000001',
    'Badambadi Main Road, Near Bus Stand',
    'Badambadi',
    'Cuttack',
    '753012',
    ST_SetSRID(ST_MakePoint(85.8830, 20.4625)::geography, 4326),
    'approved',
    'verified',
    'http://localhost:9000/grepmind-near/biz-covers/electrical_service.jpg'
) ON CONFLICT (id) DO NOTHING;

INSERT INTO professional_profiles (business_id, service_radius_m, experience_years, service_description, accepts_requests)
VALUES (
    'c2222222-2222-2222-2222-222222222222',
    15000,
    9,
    'Certified electrical engineer specializing in home safety audits, inverter installations, and AC maintenance.',
    true
) ON CONFLICT (business_id) DO UPDATE SET accepts_requests = true;

INSERT INTO services (business_id, name, description, indicative_price_min, indicative_price_max, currency, is_active)
VALUES
('c2222222-2222-2222-2222-222222222222', 'Inverter & Battery Wiring', 'Complete inverter installation with surge protection', 499.00, 799.00, 'INR', true),
('c2222222-2222-2222-2222-222222222222', 'Split AC Deep Cleaning & Servicing', 'Pressure pump filter and coil wash with refrigerant check', 699.00, 1199.00, 'INR', true),
('c2222222-2222-2222-2222-222222222222', 'Emergency Switchboard Repair', 'Troubleshooting sparking switches and fuse replacements', 249.00, 399.00, 'INR', true)
ON CONFLICT DO NOTHING;

-- Cuttack Retail Shop
INSERT INTO users (id, phone_e164, display_name, status, preferred_language)
VALUES ('c3333333-3333-3333-3333-333333333333', '+919861000002', 'Cuttack Chandi Hardware', 'active', 'en')
ON CONFLICT (phone_e164) DO NOTHING;

INSERT INTO user_roles (user_id, role)
VALUES ('c3333333-3333-3333-3333-333333333333', 'merchant')
ON CONFLICT DO NOTHING;

INSERT INTO businesses (
    id, owner_user_id, name, slug, description, category_slug, phone_e164, whatsapp_e164,
    address_text, locality, city, postal_code, location, status, verification_status, cover_photo_url
) VALUES (
    'c4444444-4444-4444-4444-444444444444',
    'c3333333-3333-3333-3333-333333333333',
    'Cuttack Chandi Paints & Hardware',
    'cuttack-chandi-hardware',
    'Authorized distributor of Asian Paints, sanitary fittings, power tools, and plumbing equipment.',
    'hardware',
    '+919861000002',
    '+919861000002',
    'Chandi Chhak, College Square Road',
    'Chandi Chhak',
    'Cuttack',
    '753001',
    ST_SetSRID(ST_MakePoint(85.8750, 20.4690)::geography, 4326),
    'approved',
    'verified',
    'http://localhost:9000/grepmind-near/biz-covers/hardware_store.jpg'
) ON CONFLICT (id) DO NOTHING;

-- 3. Seed active service professionals & retail businesses for Jajpur (20.8447, 86.3315)
-- Merchant User for Jajpur
INSERT INTO users (id, phone_e164, display_name, status, preferred_language)
VALUES ('fa111111-1111-1111-1111-111111111111', '+919861000003', 'Biraja Plumbing & Sanitary Works', 'active', 'en')
ON CONFLICT (phone_e164) DO NOTHING;

INSERT INTO user_roles (user_id, role)
VALUES ('fa111111-1111-1111-1111-111111111111', 'merchant')
ON CONFLICT DO NOTHING;

INSERT INTO businesses (
    id, owner_user_id, name, slug, description, category_slug, phone_e164, whatsapp_e164,
    address_text, locality, city, postal_code, location, status, verification_status, cover_photo_url
) VALUES (
    'fa222222-2222-2222-2222-222222222222',
    'fa111111-1111-1111-1111-111111111111',
    'Biraja Plumbing & Motor Services',
    'biraja-plumbing-jajpur',
    'Certified plumbing contractor in Jajpur Road & Town. Borewell motor repair, pipe leakages, and bathroom fixtures.',
    'plumber',
    '+919861000003',
    '+919861000003',
    'Station Road, Near Railway Station',
    'Jajpur Road',
    'Jajpur',
    '755019',
    ST_SetSRID(ST_MakePoint(86.3315, 20.8447)::geography, 4326),
    'approved',
    'verified',
    'http://localhost:9000/grepmind-near/biz-covers/plumbing_service.jpg'
) ON CONFLICT (id) DO NOTHING;

INSERT INTO professional_profiles (business_id, service_radius_m, experience_years, service_description, accepts_requests)
VALUES (
    'fa222222-2222-2222-2222-222222222222',
    20000,
    11,
    'Experienced industrial and household plumber serving Jajpur Road steel hub and surrounding residential areas.',
    true
) ON CONFLICT (business_id) DO UPDATE SET accepts_requests = true;

INSERT INTO services (business_id, name, description, indicative_price_min, indicative_price_max, currency, is_active)
VALUES
('fa222222-2222-2222-2222-222222222222', 'Borewell Submersible Motor Repair', 'Inspection and rewinding/servicing of submersible pumps', 799.00, 1499.00, 'INR', true),
('fa222222-2222-2222-2222-222222222222', 'Overhead Tank Pipeline Fitting', 'PVC/CPVC piping with leak proof sealant and float valve', 599.00, 999.00, 'INR', true),
('fa222222-2222-2222-2222-222222222222', 'Tap & Shower Leakage Fix', 'Quick replacement of spindle, washer, and cartridge', 199.00, 349.00, 'INR', true)
ON CONFLICT DO NOTHING;
