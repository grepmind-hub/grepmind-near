-- Satisfy historical migration 005's fashion reference in the disposable DB.
INSERT INTO categories(slug,name,is_active)
VALUES ('fashion','Fashion',true)
ON CONFLICT (slug) DO NOTHING;

-- Migration 008 seeds a historical Spice Garden menu for this business ID.
-- Provide a disposable owner/business beforehand so its product FK remains valid.
INSERT INTO users(id,phone_e164,display_name,status)
VALUES ('cfb375d3-543b-4bb8-8f1d-11a106596600','+919990000090','QA migration prerequisite','active')
ON CONFLICT (id) DO NOTHING;
INSERT INTO businesses(id,owner_user_id,name,slug,category_slug,address_text,city,location,status,verification_status)
VALUES (
  'cfb375d3-543b-4bb8-8f1d-11a10659661c',
  'cfb375d3-543b-4bb8-8f1d-11a106596600',
  'Disposable migration prerequisite',
  'phase3e-migration-prerequisite',
  'restaurant',
  'Disposable QA only',
  'Cuttack',
  ST_SetSRID(ST_MakePoint(86.0,20.5),4326)::geography,
  'approved',
  'verified'
)
ON CONFLICT (id) DO NOTHING;
