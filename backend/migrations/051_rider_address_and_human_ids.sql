-- Migration 051: Rider complete address, human-readable tracking IDs (AR-1000, AM-1000),
-- and Admin-managed Field Executives (AFE-1000) with Self vs Field Executive onboarding attribution.

CREATE SEQUENCE IF NOT EXISTS rider_code_seq START WITH 1000 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS merchant_code_seq START WITH 1000 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS field_executive_code_seq START WITH 1000 INCREMENT BY 1;

CREATE TABLE IF NOT EXISTS field_executives (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  executive_code text NOT NULL UNIQUE DEFAULT ('AFE-' || nextval('field_executive_code_seq')::text),
  display_name text NOT NULL,
  is_active boolean NOT NULL DEFAULT TRUE,
  granted_by_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  granted_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_field_executives_active
  ON field_executives (is_active, executive_code);

ALTER TABLE rider_profiles
  ADD COLUMN IF NOT EXISTS rider_code text,
  ADD COLUMN IF NOT EXISTS address text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS onboarding_source text NOT NULL DEFAULT 'self',
  ADD COLUMN IF NOT EXISTS field_executive_id uuid REFERENCES field_executives(id) ON DELETE SET NULL;

ALTER TABLE rider_profiles
  ALTER COLUMN rider_code SET DEFAULT ('AR-' || nextval('rider_code_seq')::text);

UPDATE rider_profiles
SET rider_code = 'AR-' || nextval('rider_code_seq')::text
WHERE rider_code IS NULL OR btrim(rider_code) = '';

ALTER TABLE rider_profiles
  ALTER COLUMN rider_code SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'rider_profiles_rider_code_key'
  ) THEN
    ALTER TABLE rider_profiles ADD CONSTRAINT rider_profiles_rider_code_key UNIQUE (rider_code);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'rider_profiles_onboarding_source_check'
  ) THEN
    ALTER TABLE rider_profiles
      ADD CONSTRAINT rider_profiles_onboarding_source_check
      CHECK (onboarding_source IN ('self', 'field_executive'));
  END IF;
END $$;

ALTER TABLE businesses
  ADD COLUMN IF NOT EXISTS merchant_code text,
  ADD COLUMN IF NOT EXISTS onboarding_source text NOT NULL DEFAULT 'self',
  ADD COLUMN IF NOT EXISTS field_executive_id uuid REFERENCES field_executives(id) ON DELETE SET NULL;

ALTER TABLE businesses
  ALTER COLUMN merchant_code SET DEFAULT ('AM-' || nextval('merchant_code_seq')::text);

UPDATE businesses
SET merchant_code = 'AM-' || nextval('merchant_code_seq')::text
WHERE merchant_code IS NULL OR btrim(merchant_code) = '';

ALTER TABLE businesses
  ALTER COLUMN merchant_code SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'businesses_merchant_code_key'
  ) THEN
    ALTER TABLE businesses ADD CONSTRAINT businesses_merchant_code_key UNIQUE (merchant_code);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'businesses_onboarding_source_check'
  ) THEN
    ALTER TABLE businesses
      ADD CONSTRAINT businesses_onboarding_source_check
      CHECK (onboarding_source IN ('self', 'field_executive'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_rider_profiles_field_executive
  ON rider_profiles (onboarding_source, field_executive_id);

CREATE INDEX IF NOT EXISTS idx_businesses_field_executive
  ON businesses (onboarding_source, field_executive_id);
