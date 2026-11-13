-- Explicit synthetic actors and a single Food partner for isolated Phase 3E.
-- Apply only to grepmind_3e_qa after migrations 001-027.
INSERT INTO users(id,phone_e164,display_name,status) VALUES
 ('3e000000-0000-4000-8000-000000000001','+919990000171','Phase 3E QA Customer','active'),
 ('3e000000-0000-4000-8000-000000000002','+919990000172','Phase 3E QA Merchant','active'),
 ('3e000000-0000-4000-8000-000000000003','+919990000173','Phase 3E QA Rider','active'),
 ('3e000000-0000-4000-8000-000000000004','+919990000174','Phase 3E QA Admin','active')
ON CONFLICT (id) DO NOTHING;
INSERT INTO user_roles(user_id,role) VALUES
 ('3e000000-0000-4000-8000-000000000001','customer'),
 ('3e000000-0000-4000-8000-000000000002','merchant'),
 ('3e000000-0000-4000-8000-000000000003','rider'),
 ('3e000000-0000-4000-8000-000000000004','admin')
ON CONFLICT DO NOTHING;

INSERT INTO businesses(id,owner_user_id,name,slug,description,category_slug,phone_e164,address_text,locality,city,postal_code,location,status,verification_status,delivery_enabled)
VALUES ('3e000000-0000-4000-8000-000000000101','3e000000-0000-4000-8000-000000000002',
 'Phase 3E QA Food Partner','phase3e-qa-food-partner','Disposable QA fulfillment partner.','restaurant',
 '+919990000172','QA Lane, Kuanpal','Kuanpal','Cuttack','754208',
 ST_SetSRID(ST_MakePoint(86.155,20.420),4326)::geography,'approved','verified',true)
ON CONFLICT (id) DO NOTHING;
INSERT INTO business_members(business_id,user_id,role,status)
VALUES ('3e000000-0000-4000-8000-000000000101','3e000000-0000-4000-8000-000000000002','owner','active')
ON CONFLICT (business_id,user_id) DO NOTHING;
INSERT INTO business_hours(business_id,weekday,opens_at,closes_at,is_closed)
SELECT '3e000000-0000-4000-8000-000000000101',day::smallint,'00:00','23:59',false
FROM generate_series(0,6) day
ON CONFLICT (business_id,weekday) DO UPDATE SET is_closed=false;

INSERT INTO platform_catalog_products(id,sku,category_id,name,description,image_urls,status)
SELECT '3e000000-0000-4000-8000-000000000201','P3E-QA-FOOD-KUANPAL',id,
 'Phase 3E QA Chicken Biryani','Temporary QA product for live delivery tracking acceptance.',ARRAY[]::text[],'active'
FROM platform_catalog_categories WHERE vertical='food' AND slug='food'
ON CONFLICT (id) DO NOTHING;
INSERT INTO platform_catalog_variants(id,product_id,sku,name,unit_label,price_minor,currency,is_active)
VALUES ('3e000000-0000-4000-8000-000000000202','3e000000-0000-4000-8000-000000000201',
 'P3E-QA-FOOD-KUANPAL-REG','Regular','1 serving',34500,'INR',true)
ON CONFLICT (id) DO NOTHING;
INSERT INTO platform_catalog_product_district_visibility(product_id,district_id,is_active)
VALUES ('3e000000-0000-4000-8000-000000000201','02200000-0000-4000-8000-000000000001',true)
ON CONFLICT DO NOTHING;
INSERT INTO platform_catalog_product_delivery_localities(product_id,locality_id,is_active)
VALUES ('3e000000-0000-4000-8000-000000000201','02200000-0000-4000-8000-000000000101',true)
ON CONFLICT DO NOTHING;
INSERT INTO platform_partner_delivery_localities(business_id,locality_id,is_active)
VALUES ('3e000000-0000-4000-8000-000000000101','02200000-0000-4000-8000-000000000101',true)
ON CONFLICT DO NOTHING;
INSERT INTO platform_partner_product_mappings(id,business_id,variant_id,status,inventory_mode,available_quantity,preparation_minutes,supply_price_minor,supply_currency,created_by,updated_by,approved_by,approved_at)
VALUES ('3e000000-0000-4000-8000-000000000203','3e000000-0000-4000-8000-000000000101',
 '3e000000-0000-4000-8000-000000000202','approved','finite',40,20,22000,'INR',
 '3e000000-0000-4000-8000-000000000004','3e000000-0000-4000-8000-000000000004',
 '3e000000-0000-4000-8000-000000000004',now())
ON CONFLICT (id) DO NOTHING;

INSERT INTO rider_profiles(user_id,display_name,vehicle_type,status,approved_at)
VALUES ('3e000000-0000-4000-8000-000000000003','Phase 3E QA Rider','two_wheeler','approved',now())
ON CONFLICT (user_id) DO UPDATE SET status='approved',approved_at=now();
INSERT INTO rider_profile_localities(rider_profile_id,locality_id,status,reviewed_at)
SELECT id,'02200000-0000-4000-8000-000000000101','approved',now()
FROM rider_profiles WHERE user_id='3e000000-0000-4000-8000-000000000003'
ON CONFLICT (rider_profile_id,locality_id) DO UPDATE SET status='approved',reviewed_at=now();

INSERT INTO customer_addresses(id,customer_user_id,label,recipient_name,address_line1,locality,landmark,city,state,postal_code,contact_phone,is_default,delivery_locality_id)
VALUES ('3e000000-0000-4000-8000-000000000301','3e000000-0000-4000-8000-000000000001',
 'QA Home','Phase 3E QA Customer','QA Test Lane 1','Kuanpal','QA landmark','Cuttack','Odisha',
 '754208','+919990000171',true,'02200000-0000-4000-8000-000000000101')
ON CONFLICT (id) DO NOTHING;
