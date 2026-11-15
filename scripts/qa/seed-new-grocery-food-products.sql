-- Grepmind Near — Seed New Grocery & Food Products for E2E Lifecycle Testing

-- 1. Ensure Food Platform Standard Commission Policy exists and is approved
INSERT INTO merchant_commission_policies(
  id, policy_key, version, business_id, vertical, calculation_basis,
  commission_type, percentage_bps, effective_from, status,
  policy_hash, created_by, approved_by, approval_reason, created_at, approved_at
) VALUES (
  '8019290a-6d63-482a-97c2-646cdf08d799', 'food-platform-standard', 1, NULL, 'food', 'partner_supply',
  'percentage_bps', 500, '2026-01-01 00:00:00+00', 'approved',
  '\x4b0172c5210908df406380d86744bd37f626eb81f0598768b49e0ea8d2b7a42a',
  '3e000000-0000-4000-8000-000000000004', '4c000000-0000-4000-8000-000000000005',
  'Approved standard 5% food commission', now(), now()
) ON CONFLICT (id) DO UPDATE SET status = 'approved';

-- 2. Ensure Verified Bank Beneficiary for Phase 3E QA Food Partner
INSERT INTO bank_beneficiaries (
  id, beneficiary_type, business_id, account_holder_name,
  account_number_encrypted, account_number_masked, account_number_hmac,
  ifsc_code, bank_name, verification_status, verification_evidence,
  verified_at, created_by
) VALUES (
  '3e000000-0000-4000-8000-000000000301', 'merchant', '3e000000-0000-4000-8000-000000000101', 'Phase 3E QA Food Partner',
  '\x76313a7371a2d020cc4492bb320eacda044c0844a88a7c4a480465bb455bfa44c1db2da091d6b219f2325692b6f0f3', 'XXXXXXXXXXXX1234', '\x5ddb4142b7f2f7dc9c229e60727a7b85743b24e554e4fb6e5a16cb8fc092d64a',
  'SBIN0001234', 'State Bank of India', 'verified', '{}'::jsonb,
  now(), '3e000000-0000-4000-8000-000000000004'
) ON CONFLICT (id) DO UPDATE SET verification_status = 'verified', updated_at = now();

-- 3. NEW GROCERY PRODUCT: Kalinga Farm Fresh Cold-Pressed Mustard Oil (1L)
INSERT INTO platform_catalog_products(id, sku, category_id, name, description, image_urls, status)
VALUES (
  '4e300000-0000-4000-8000-000000000211', 'P4E-GROC-MUSTARD-OIL',
  'bb3fe995-94a8-4b73-8b63-cad321dd107b',
  'Kalinga Farm Fresh Cold-Pressed Mustard Oil (1L)',
  'Pure cold-pressed organic mustard oil from local Cuttack farms.',
  ARRAY[]::text[], 'active'
) ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  status = 'active';

INSERT INTO platform_catalog_variants(id, product_id, sku, name, unit_label, price_minor, currency, is_active)
VALUES (
  '4e300000-0000-4000-8000-000000000212', '4e300000-0000-4000-8000-000000000211',
  'P4E-GROC-OIL-1L', '1 Litre Bottle', '1 bottle (1 L)', 18000, 'INR', true
) ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  unit_label = EXCLUDED.unit_label,
  price_minor = 18000,
  is_active = true;

INSERT INTO platform_catalog_product_district_visibility(product_id, district_id, is_active)
VALUES ('4e300000-0000-4000-8000-000000000211', '02200000-0000-4000-8000-000000000001', true)
ON CONFLICT DO NOTHING;

INSERT INTO platform_catalog_product_delivery_localities(product_id, locality_id, is_active)
VALUES ('4e300000-0000-4000-8000-000000000211', '02200000-0000-4000-8000-000000000101', true)
ON CONFLICT DO NOTHING;

INSERT INTO platform_partner_product_mappings(
  id, business_id, variant_id, status, inventory_mode,
  available_quantity, preparation_minutes, supply_price_minor, supply_currency,
  created_by, updated_by, approved_by, approved_at
) VALUES (
  '4e300000-0000-4000-8000-000000000213', '4e300000-0000-4000-8000-000000000101',
  '4e300000-0000-4000-8000-000000000212', 'approved', 'finite',
  500, 10, 14000, 'INR',
  '3e000000-0000-4000-8000-000000000004', '3e000000-0000-4000-8000-000000000004',
  '3e000000-0000-4000-8000-000000000004', now()
) ON CONFLICT (id) DO UPDATE SET
  status = 'approved',
  available_quantity = 500,
  supply_price_minor = 14000;

-- 4. NEW FOOD PRODUCT: Cuttack Special Paneer Butter Masala Combo
INSERT INTO platform_catalog_products(id, sku, category_id, name, description, image_urls, status)
VALUES (
  '3e000000-0000-4000-8000-000000000211', 'P3E-FOOD-PANEER-COMBO',
  '8019290a-6d63-482a-97c2-646cdf08d76c',
  'Cuttack Special Paneer Butter Masala Combo',
  'Fresh cottage cheese cubes in rich spiced butter gravy served with 2 freshly baked butter naans.',
  ARRAY[]::text[], 'active'
) ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  status = 'active';

INSERT INTO platform_catalog_variants(id, product_id, sku, name, unit_label, price_minor, currency, is_active)
VALUES (
  '3e000000-0000-4000-8000-000000000212', '3e000000-0000-4000-8000-000000000211',
  'P3E-FOOD-PANEER-COMBO-STD', 'Standard Meal Box', '1 meal combo', 24000, 'INR', true
) ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  unit_label = EXCLUDED.unit_label,
  price_minor = 24000,
  is_active = true;

INSERT INTO platform_catalog_product_district_visibility(product_id, district_id, is_active)
VALUES ('3e000000-0000-4000-8000-000000000211', '02200000-0000-4000-8000-000000000001', true)
ON CONFLICT DO NOTHING;

INSERT INTO platform_catalog_product_delivery_localities(product_id, locality_id, is_active)
VALUES ('3e000000-0000-4000-8000-000000000211', '02200000-0000-4000-8000-000000000101', true)
ON CONFLICT DO NOTHING;

INSERT INTO platform_partner_product_mappings(
  id, business_id, variant_id, status, inventory_mode,
  available_quantity, preparation_minutes, supply_price_minor, supply_currency,
  created_by, updated_by, approved_by, approved_at
) VALUES (
  '3e000000-0000-4000-8000-000000000213', '3e000000-0000-4000-8000-000000000101',
  '3e000000-0000-4000-8000-000000000212', 'approved', 'finite',
  300, 15, 18000, 'INR',
  '3e000000-0000-4000-8000-000000000004', '3e000000-0000-4000-8000-000000000004',
  '3e000000-0000-4000-8000-000000000004', now()
) ON CONFLICT (id) DO UPDATE SET
  status = 'approved',
  available_quantity = 300,
  supply_price_minor = 18000;
