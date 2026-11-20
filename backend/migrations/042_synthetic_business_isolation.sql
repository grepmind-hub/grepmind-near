-- 042_synthetic_business_isolation.sql
-- Enforce production exclusion of synthetic QA test businesses and fixtures.

ALTER TABLE businesses ADD COLUMN IF NOT EXISTS is_synthetic BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX IF NOT EXISTS businesses_is_synthetic_idx ON businesses(is_synthetic);

-- Backfill existing synthetic QA test fixtures deterministically
UPDATE businesses
SET is_synthetic = true
WHERE name ILIKE 'QA Fixture%'
   OR name ILIKE 'QA PREVIEW%'
   OR owner_user_id IN (
     SELECT id FROM users WHERE display_name ILIKE 'validation-%'
   );
