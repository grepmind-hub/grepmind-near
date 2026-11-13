-- Disposable Phase 3G-D QA actors and one Kuanpal Food partner/catalog item.
-- Apply only to grepmind_3e_qa (tmpfs) after migrations through 029.
INSERT INTO users(id,phone_e164,display_name,status) VALUES
 ('3d000000-0000-4000-8000-000000000001','+919990000181','Phase 3G-D QA Customer','active'),
 ('3d000000-0000-4000-8000-000000000002','+919990000182','Phase 3G-D QA Merchant','active'),
 ('3d000000-0000-4000-8000-000000000003','+919990000183','Phase 3G-D QA Rider A','active'),
 ('3d000000-0000-4000-8000-000000000004','+919990000184','Phase 3G-D QA Admin','active'),
 ('3d000000-0000-4000-8000-000000000005','+919990000185','Phase 3G-D QA Rider B','active')
ON CONFLICT (id) DO NOTHING;
INSERT INTO user_roles(user_id,role) VALUES
 ('3d000000-0000-4000-8000-000000000001','customer'),
 ('3d000000-0000-4000-8000-000000000002','merchant'),
 ('3d000000-0000-4000-8000-000000000003','rider'),
 ('3d000000-0000-4000-8000-000000000004','admin'),
 ('3d000000-0000-4000-8000-000000000004','delivery_operator'),
 ('3d000000-0000-4000-8000-000000000005','rider')
ON CONFLICT DO NOTHING;

INSERT INTO businesses(id,owner_user_id,name,slug,description,category_slug,phone_e164,address_text,locality,city,postal_code,location,status,verification_status,delivery_enabled)
VALUES ('3d000000-0000-4000-8000-000000000101','3d000000-0000-4000-8000-000000000002',
 'Phase 3G-D QA Food Partner','phase3gd-qa-food-partner','Temporary isolated recovery-validation partner.','restaurant',
 '+919990000182','QA Lane, Kuanpal','Kuanpal','Cuttack','754208',
 ST_SetSRID(ST_MakePoint(86.155,20.420),4326)::geography,'approved','verified',true)
ON CONFLICT (id) DO NOTHING;
INSERT INTO business_members(business_id,user_id,role,status)
VALUES ('3d000000-0000-4000-8000-000000000101','3d000000-0000-4000-8000-000000000002','owner','active')
ON CONFLICT (business_id,user_id) DO NOTHING;
INSERT INTO business_hours(business_id,weekday,opens_at,closes_at,is_closed)
SELECT '3d000000-0000-4000-8000-000000000101',day::smallint,'00:00','23:59',false FROM generate_series(0,6) day
ON CONFLICT (business_id,weekday) DO UPDATE SET is_closed=false;

INSERT INTO platform_catalog_products(id,sku,category_id,name,description,image_urls,status)
SELECT '3d000000-0000-4000-8000-000000000201','P3GD-QA-FOOD-KUANPAL',id,
 'QA 3G-D Biryani','Temporary test item; not a public or production product.',ARRAY[]::text[],'active'
FROM platform_catalog_categories WHERE vertical='food' AND slug='food'
ON CONFLICT (id) DO NOTHING;
INSERT INTO platform_catalog_variants(id,product_id,sku,name,unit_label,price_minor,currency,is_active)
VALUES ('3d000000-0000-4000-8000-000000000202','3d000000-0000-4000-8000-000000000201',
 'P3GD-QA-FOOD-KUANPAL-REG','QA serving','1 serving',100,'INR',true)
ON CONFLICT (id) DO NOTHING;
INSERT INTO platform_catalog_product_district_visibility(product_id,district_id,is_active)
VALUES ('3d000000-0000-4000-8000-000000000201','02200000-0000-4000-8000-000000000001',true) ON CONFLICT DO NOTHING;
INSERT INTO platform_catalog_product_delivery_localities(product_id,locality_id,is_active)
VALUES ('3d000000-0000-4000-8000-000000000201','02200000-0000-4000-8000-000000000101',true) ON CONFLICT DO NOTHING;
INSERT INTO platform_partner_delivery_localities(business_id,locality_id,is_active)
VALUES ('3d000000-0000-4000-8000-000000000101','02200000-0000-4000-8000-000000000101',true) ON CONFLICT DO NOTHING;
INSERT INTO platform_partner_product_mappings(id,business_id,variant_id,status,inventory_mode,available_quantity,preparation_minutes,supply_price_minor,supply_currency,created_by,updated_by,approved_by,approved_at)
VALUES ('3d000000-0000-4000-8000-000000000203','3d000000-0000-4000-8000-000000000101',
 '3d000000-0000-4000-8000-000000000202','approved','finite',20,5,75,'INR',
 '3d000000-0000-4000-8000-000000000004','3d000000-0000-4000-8000-000000000004',
 '3d000000-0000-4000-8000-000000000004',now()) ON CONFLICT (id) DO NOTHING;

INSERT INTO rider_profiles(user_id,display_name,vehicle_type,status,approved_at) VALUES
 ('3d000000-0000-4000-8000-000000000003','Phase 3G-D QA Rider A','two_wheeler','approved',now()),
 ('3d000000-0000-4000-8000-000000000005','Phase 3G-D QA Rider B','two_wheeler','approved',now())
ON CONFLICT (user_id) DO UPDATE SET status='approved',approved_at=now();
INSERT INTO rider_profile_localities(rider_profile_id,locality_id,status,reviewed_at)
SELECT id,'02200000-0000-4000-8000-000000000101','approved',now() FROM rider_profiles WHERE user_id IN (
 '3d000000-0000-4000-8000-000000000003','3d000000-0000-4000-8000-000000000005')
ON CONFLICT (rider_profile_id,locality_id) DO UPDATE SET status='approved',reviewed_at=now();
INSERT INTO customer_addresses(id,customer_user_id,label,recipient_name,address_line1,locality,landmark,city,state,postal_code,contact_phone,is_default,delivery_locality_id)
VALUES ('3d000000-0000-4000-8000-000000000301','3d000000-0000-4000-8000-000000000001',
 'QA Home','Phase 3G-D QA Customer','QA Test Lane 1','Kuanpal','QA landmark','Cuttack','Odisha',
 '754208','+919990000181',true,'02200000-0000-4000-8000-000000000101') ON CONFLICT (id) DO NOTHING;
