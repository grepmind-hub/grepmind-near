-- Migration 001: core schema
-- Run with: goose up

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_e164 TEXT UNIQUE NOT NULL,
    display_name TEXT,
    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'suspended', 'deleted')),
    preferred_language TEXT NOT NULL DEFAULT 'en',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE user_roles (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role TEXT NOT NULL
        CHECK (role IN ('customer', 'merchant', 'professional', 'admin')),
    PRIMARY KEY (user_id, role)
);

CREATE INDEX user_roles_user_idx ON user_roles (user_id);
CREATE INDEX user_roles_role_idx ON user_roles (role);

-- OTP verification records
CREATE TABLE otp_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_e164 TEXT NOT NULL,
    code_hash TEXT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    max_attempts INTEGER NOT NULL DEFAULT 5,
    expires_at TIMESTAMPTZ NOT NULL,
    verified_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX otp_codes_phone_idx ON otp_codes (phone_e164);
CREATE INDEX otp_codes_expires_idx ON otp_codes (expires_at);

-- Sessions / refresh tokens
CREATE TABLE sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    refresh_token_hash TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    user_agent TEXT,
    ip_address TEXT
);

CREATE INDEX sessions_user_idx ON sessions (user_id);
CREATE INDEX sessions_refresh_idx ON sessions (refresh_token_hash);
CREATE INDEX sessions_expires_idx ON sessions (expires_at);

-- Categories (controlled taxonomy)
CREATE TABLE categories (
    slug TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    icon_name TEXT,
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Business profiles
CREATE TABLE businesses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    slug TEXT UNIQUE,
    description TEXT,
    category_slug TEXT NOT NULL REFERENCES categories(slug),
    phone_e164 TEXT,
    whatsapp_e164 TEXT,
    address_text TEXT NOT NULL,
    locality TEXT,
    city TEXT,
    postal_code TEXT,
    location GEOGRAPHY(POINT, 4326) NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('draft', 'pending', 'approved', 'rejected', 'suspended')),
    verification_status TEXT NOT NULL DEFAULT 'unverified'
        CHECK (verification_status IN ('unverified', 'pending', 'verified', 'rejected')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX businesses_location_gix ON businesses USING GIST (location);
CREATE INDEX businesses_category_status_idx ON businesses (category_slug, status);
CREATE INDEX businesses_owner_idx ON businesses (owner_user_id);
CREATE INDEX businesses_status_idx ON businesses (status);

-- Business hours
CREATE TABLE business_hours (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    weekday SMALLINT NOT NULL CHECK (weekday BETWEEN 0 AND 6),
    opens_at TIME,
    closes_at TIME,
    is_closed BOOLEAN NOT NULL DEFAULT false,
    CHECK (
        is_closed
        OR (opens_at IS NOT NULL AND closes_at IS NOT NULL)
    ),
    UNIQUE (business_id, weekday)
);

CREATE TABLE business_hour_exceptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    local_date DATE NOT NULL,
    is_closed BOOLEAN NOT NULL DEFAULT false,
    opens_at TIME,
    closes_at TIME,
    reason TEXT,
    UNIQUE (business_id, local_date)
);

-- Professional profiles
CREATE TABLE professional_profiles (
    business_id UUID PRIMARY KEY REFERENCES businesses(id) ON DELETE CASCADE,
    service_radius_m INTEGER NOT NULL DEFAULT 5000
        CHECK (service_radius_m BETWEEN 100 AND 100000),
    experience_years SMALLINT,
    service_description TEXT,
    accepts_requests BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Services
CREATE TABLE services (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    indicative_price_min NUMERIC(12,2),
    indicative_price_max NUMERIC(12,2),
    currency CHAR(3) NOT NULL DEFAULT 'INR',
    is_active BOOLEAN NOT NULL DEFAULT true,
    CHECK (
        indicative_price_min IS NULL OR indicative_price_min >= 0
    ),
    CHECK (
        indicative_price_max IS NULL OR indicative_price_max >= 0
    ),
    CHECK (
        indicative_price_min IS NULL OR indicative_price_max IS NULL OR indicative_price_min <= indicative_price_max
    )
);

CREATE INDEX services_business_active_idx ON services (business_id, is_active);

-- Products
CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    price NUMERIC(12,2),
    currency CHAR(3) NOT NULL DEFAULT 'INR',
    stock_status TEXT NOT NULL DEFAULT 'unknown'
        CHECK (stock_status IN ('unknown', 'in_stock', 'out_of_stock', 'limited')),
    is_published BOOLEAN NOT NULL DEFAULT false,
    image_url TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (price IS NULL OR price >= 0)
);

CREATE INDEX products_business_published_idx ON products (business_id, is_published);

-- Offers
CREATE TABLE offers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    starts_at TIMESTAMPTZ NOT NULL,
    ends_at TIMESTAMPTZ NOT NULL,
    status TEXT NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'pending', 'published', 'rejected', 'expired')),
    image_url TEXT,
    terms TEXT,
    discount_percent INTEGER CHECK (discount_percent BETWEEN 0 AND 100),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (ends_at > starts_at)
);

CREATE INDEX offers_active_lookup_idx ON offers (business_id, starts_at, ends_at);
CREATE INDEX offers_status_idx ON offers (status);

-- Availability slots
CREATE TABLE availability_slots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    starts_at TIMESTAMPTZ NOT NULL,
    ends_at TIMESTAMPTZ NOT NULL,
    capacity INTEGER NOT NULL DEFAULT 1 CHECK (capacity > 0),
    booked_count INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'closed')),
    CHECK (ends_at > starts_at),
    CHECK (booked_count >= 0 AND booked_count <= capacity)
);

CREATE INDEX availability_slots_business_idx ON availability_slots (business_id, starts_at, ends_at);

-- Service requests
CREATE TABLE service_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_user_id UUID NOT NULL REFERENCES users(id),
    business_id UUID NOT NULL REFERENCES businesses(id),
    service_id UUID REFERENCES services(id),
    slot_id UUID REFERENCES availability_slots(id),
    description TEXT,
    requested_for TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'requested'
        CHECK (status IN ('requested', 'accepted', 'declined', 'cancelled', 'completed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX service_requests_customer_idx ON service_requests (customer_user_id, created_at DESC);
CREATE INDEX service_requests_business_idx ON service_requests (business_id, status, created_at DESC);

-- Favourites
CREATE TABLE favorites (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, business_id)
);

-- Reports
CREATE TABLE reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_user_id UUID REFERENCES users(id),
    target_type TEXT NOT NULL,
    target_id UUID NOT NULL,
    reason TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'dismissed', 'action_taken')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at TIMESTAMPTZ,
    resolution_reason TEXT
);

CREATE INDEX reports_target_idx ON reports (target_type, target_id);
CREATE INDEX reports_status_idx ON reports (status);

-- Audit logs
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_user_id UUID REFERENCES users(id),
    action TEXT NOT NULL,
    target_type TEXT NOT NULL,
    target_id UUID NOT NULL,
    reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX audit_logs_actor_idx ON audit_logs (actor_user_id);
CREATE INDEX audit_logs_target_idx ON audit_logs (target_type, target_id);
CREATE INDEX audit_logs_created_idx ON audit_logs (created_at DESC);

-- Seed categories
INSERT INTO categories (slug, name, icon_name, description, sort_order) VALUES
('grocery', 'Grocery', 'store', 'Grocery stores and kirana shops', 1),
('hardware', 'Hardware', 'build', 'Hardware and building supplies', 2),
('medical', 'Medical & Pharmacy', 'local_pharmacy', 'Pharmacies and medical stores', 3),
('restaurant', 'Restaurant & Food', 'restaurant', 'Restaurants and eateries', 4),
('salon', 'Salon & Beauty', 'face', 'Beauty salons and parlours', 5),
('plumber', 'Plumber', 'plumbing', 'Plumbing services', 6),
('electrician', 'Electrician', 'electrical_services', 'Electrical services', 7),
('carpenter', 'Carpenter', 'carpenter', 'Carpentry services', 8),
('tailor', 'Tailor', 'design_services', 'Tailoring services', 9),
('general', 'General Store', 'shop', 'General provision stores', 10);

-- Seed admin user (password must be changed on first admin login)
INSERT INTO users (phone_e164, display_name, status, preferred_language)
VALUES ('+910000000000', 'Platform Admin', 'active', 'en')
ON CONFLICT (phone_e164) DO NOTHING;

INSERT INTO user_roles (user_id, role)
SELECT id, 'admin' FROM users WHERE phone_e164 = '+910000000000'
ON CONFLICT DO NOTHING;
