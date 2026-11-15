-- Seed new synthetic QA identities for Grocery Merchant, new Customer, and new Rider
-- Target database: grepmind_3e_qa (isolated QA only)

-- 1. Users
INSERT INTO users(id, phone_e164, display_name, status, preferred_language) VALUES
  ('4e300000-0000-4000-8000-000000000001', '+919990000181', 'Priyanka Mishra', 'active', 'en'),
  ('4e300000-0000-4000-8000-000000000002', '+919990000182', 'Deepak Patra', 'active', 'en'),
  ('4e300000-0000-4000-8000-000000000003', '+919990000183', 'Ashok Samal', 'active', 'en')
ON CONFLICT (id) DO UPDATE SET 
  phone_e164 = EXCLUDED.phone_e164,
  display_name = EXCLUDED.display_name,
  status = EXCLUDED.status;

-- 2. User Roles
INSERT INTO user_roles(user_id, role) VALUES
  ('4e300000-0000-4000-8000-000000000001', 'customer'),
  ('4e300000-0000-4000-8000-000000000002', 'customer'),
  ('4e300000-0000-4000-8000-000000000002', 'merchant'),
  ('4e300000-0000-4000-8000-000000000003', 'customer'),
  ('4e300000-0000-4000-8000-000000000003', 'rider')
ON CONFLICT (user_id, role) DO NOTHING;

-- 3. Customer Delivery Address
INSERT INTO customer_addresses(id, customer_user_id, label, recipient_name, address_line1, locality, landmark, city, state, postal_code, contact_phone, is_default, delivery_locality_id)
VALUES ('4e300000-0000-4000-8000-000000000301', '4e300000-0000-4000-8000-000000000001',
  'Home', 'Priyanka Mishra', 'Plot 42, Kuanpal Market Road', 'Kuanpal', 'Near Market Temple', 'Cuttack', 'Odisha',
  '754208', '+919990000181', true, '02200000-0000-4000-8000-000000000101')
ON CONFLICT (id) DO UPDATE SET
  recipient_name = EXCLUDED.recipient_name,
  contact_phone = EXCLUDED.contact_phone,
  is_default = true;

-- 4. New Grocery Merchant Business
INSERT INTO businesses(id, owner_user_id, name, slug, description, category_slug, phone_e164, address_text, locality, city, postal_code, location, status, verification_status, delivery_enabled)
VALUES ('4e300000-0000-4000-8000-000000000101', '4e300000-0000-4000-8000-000000000002',
  'Kalinga Fresh Grocery', 'kalinga-fresh-grocery', 'Fresh grains, organic pulses, pantry staples, and daily essentials in Kuanpal.',
  'grocery', '+919990000182', 'Shop 7, Main Kuanpal Market, Kuanpal, Cuttack 754208',
  'Kuanpal', 'Cuttack', '754208',
  ST_SetSRID(ST_MakePoint(86.155, 20.420), 4326)::geography, 'approved', 'verified', true)
ON CONFLICT (id) DO UPDATE SET
  owner_user_id = EXCLUDED.owner_user_id,
  name = EXCLUDED.name,
  category_slug = 'grocery',
  status = 'approved',
  verification_status = 'verified',
  delivery_enabled = true;

INSERT INTO business_members(business_id, user_id, role, status)
VALUES ('4e300000-0000-4000-8000-000000000101', '4e300000-0000-4000-8000-000000000002', 'owner', 'active')
ON CONFLICT (business_id, user_id) DO NOTHING;

INSERT INTO business_hours(business_id, weekday, opens_at, closes_at, is_closed)
SELECT '4e300000-0000-4000-8000-000000000101', day::smallint, '00:00', '23:59', false
FROM generate_series(0, 6) day
ON CONFLICT (business_id, weekday) DO UPDATE SET is_closed = false;

INSERT INTO platform_partner_delivery_localities(business_id, locality_id, is_active)
VALUES ('4e300000-0000-4000-8000-000000000101', '02200000-0000-4000-8000-000000000101', true)
ON CONFLICT DO NOTHING;

-- 5. New Grocery Product (Platform Catalog)
INSERT INTO platform_catalog_products(id, sku, category_id, name, description, image_urls, status)
VALUES ('4e300000-0000-4000-8000-000000000201', 'P4E-GROC-RICE-KUANPAL',
  'bb3fe995-94a8-4b73-8b63-cad321dd107b', -- Grocery category ID
  'Kalinga Premium Basmati Rice', '5 kg bag of premium aged aromatic basmati rice.', ARRAY[]::text[], 'active')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  status = 'active';

INSERT INTO platform_catalog_variants(id, product_id, sku, name, unit_label, price_minor, currency, is_active)
VALUES ('4e300000-0000-4000-8000-000000000202', '4e300000-0000-4000-8000-000000000201',
  'P4E-GROC-RICE-5KG', '5 kg Pack', '1 bag (5 kg)', 28000, 'INR', true)
ON CONFLICT (id) DO UPDATE SET
  price_minor = 28000,
  is_active = true;

INSERT INTO platform_catalog_product_district_visibility(product_id, district_id, is_active)
VALUES ('4e300000-0000-4000-8000-000000000201', '02200000-0000-4000-8000-000000000001', true)
ON CONFLICT DO NOTHING;

INSERT INTO platform_catalog_product_delivery_localities(product_id, locality_id, is_active)
VALUES ('4e300000-0000-4000-8000-000000000201', '02200000-0000-4000-8000-000000000101', true)
ON CONFLICT DO NOTHING;

INSERT INTO platform_partner_product_mappings(id, business_id, variant_id, status, inventory_mode, available_quantity, preparation_minutes, supply_price_minor, supply_currency, created_by, updated_by, approved_by, approved_at)
VALUES ('4e300000-0000-4000-8000-000000000203', '4e300000-0000-4000-8000-000000000101',
  '4e300000-0000-4000-8000-000000000202', 'approved', 'finite', 50, 15, 21000, 'INR',
  '3e000000-0000-4000-8000-000000000004', '3e000000-0000-4000-8000-000000000004',
  '3e000000-0000-4000-8000-000000000004', now())
ON CONFLICT (id) DO UPDATE SET
  status = 'approved',
  available_quantity = 50,
  supply_price_minor = 21000;

-- 6. New Rider Profile & Locality Approval
INSERT INTO rider_profiles(user_id, display_name, vehicle_type, status, approved_at)
VALUES ('4e300000-0000-4000-8000-000000000003', 'Ashok Samal', 'two_wheeler', 'approved', now())
ON CONFLICT (user_id) DO UPDATE SET status = 'approved', approved_at = now();

INSERT INTO rider_profile_localities(rider_profile_id, locality_id, status, reviewed_at)
SELECT id, '02200000-0000-4000-8000-000000000101', 'approved', now()
FROM rider_profiles WHERE user_id = '4e300000-0000-4000-8000-000000000003'
ON CONFLICT (rider_profile_id, locality_id) DO UPDATE SET status = 'approved', reviewed_at = now();

INSERT INTO rider_availability_sessions(rider_user_id, is_online, lease_expires_at, last_heartbeat_at)
VALUES ('4e300000-0000-4000-8000-000000000003', true, now() + interval '12 hours', now())
ON CONFLICT (rider_user_id) DO UPDATE SET is_online = true, lease_expires_at = now() + interval '12 hours';
