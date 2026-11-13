-- Disposable Phase 2E final device acceptance fixture.
-- Load only into the tmpfs-backed grepmind-phase2e-qa database.
INSERT INTO platform_catalog_categories(vertical,slug,name,is_system,sort_order)
VALUES ('food','food','Food',true,10)
ON CONFLICT DO NOTHING;

INSERT INTO categories(slug,name,is_active)
VALUES ('restaurant','Restaurant',true)
ON CONFLICT (slug) DO UPDATE SET is_active=true;

INSERT INTO platform_districts(id,state_code,name,slug) VALUES
 ('02200000-0000-4000-8000-000000000001','OD','Cuttack','cuttack'),
 ('02200000-0000-4000-8000-000000000002','OD','Jajpur','jajpur');
INSERT INTO platform_delivery_localities(id,district_id,name,slug,delivery_enabled) VALUES
 ('02200000-0000-4000-8000-000000000101','02200000-0000-4000-8000-000000000001','Kuanpal','kuanpal',true),
 ('02200000-0000-4000-8000-000000000102','02200000-0000-4000-8000-000000000001','Jagatpur','jagatpur',false),
 ('02200000-0000-4000-8000-000000000103','02200000-0000-4000-8000-000000000001','Tangi','tangi',false),
 ('02200000-0000-4000-8000-000000000201','02200000-0000-4000-8000-000000000002','Chhatia','chhatia',true),
 ('02200000-0000-4000-8000-000000000202','02200000-0000-4000-8000-000000000002','Chandikhol','chandikhol',false);

INSERT INTO users(id,phone_e164,display_name,status) VALUES
 ('2f000000-0000-4000-8000-000000000001','+919990000011','Phase 2E QA Admin','active'),
 ('2f000000-0000-4000-8000-000000000002','+919990000012','Phase 2E QA Kuanpal Food Partner','active'),
 ('2f000000-0000-4000-8000-000000000003','+919990000013','Phase 2E QA Customer','active');

INSERT INTO user_roles(user_id,role) VALUES
 ('2f000000-0000-4000-8000-000000000001','admin'),
 ('2f000000-0000-4000-8000-000000000002','merchant'),
 ('2f000000-0000-4000-8000-000000000003','customer');

INSERT INTO businesses(id,owner_user_id,name,slug,description,category_slug,phone_e164,address_text,locality,city,postal_code,location,status,verification_status,delivery_enabled)
VALUES ('2f000000-0000-4000-8000-000000000101','2f000000-0000-4000-8000-000000000002',
 'Phase 2E Final QA Food Partner Kuanpal','phase2e-final-qa-food-kuanpal',
 'Disposable partner for final Phase 2E device acceptance.','restaurant','+919990000012',
 'QA Test Lane, Kuanpal','Kuanpal','Cuttack','754208',
 ST_SetSRID(ST_MakePoint(86.155,20.420),4326)::geography,'approved','verified',true);

INSERT INTO business_members(business_id,user_id,role,status)
VALUES ('2f000000-0000-4000-8000-000000000101','2f000000-0000-4000-8000-000000000002','owner','active');

INSERT INTO business_hours(business_id,weekday,opens_at,closes_at,is_closed)
SELECT '2f000000-0000-4000-8000-000000000101',day::smallint,'00:00','23:59',false
FROM generate_series(0,6) day;

INSERT INTO platform_partner_delivery_localities(business_id,locality_id,is_active)
VALUES ('2f000000-0000-4000-8000-000000000101','02200000-0000-4000-8000-000000000101',true);

INSERT INTO platform_partner_coverage_areas(business_id,city,locality,is_active)
VALUES ('2f000000-0000-4000-8000-000000000101','Cuttack','Kuanpal',true);

INSERT INTO platform_catalog_products(id,sku,category_id,name,description,image_urls,status,created_by,updated_by)
VALUES ('2f000000-0000-4000-8000-000000000201','P2E-FINAL-QA-FOOD-CTK',
 (SELECT id FROM platform_catalog_categories WHERE vertical='food' AND slug='food'),
 'Phase 2E QA Chicken Biryani','Temporary QA product for final order tracking acceptance.',
 ARRAY[]::text[],'active','2f000000-0000-4000-8000-000000000001','2f000000-0000-4000-8000-000000000001');

INSERT INTO platform_catalog_product_district_visibility(product_id,district_id,is_active)
VALUES ('2f000000-0000-4000-8000-000000000201','02200000-0000-4000-8000-000000000001',true);
INSERT INTO platform_catalog_product_delivery_localities(product_id,locality_id,is_active)
VALUES ('2f000000-0000-4000-8000-000000000201','02200000-0000-4000-8000-000000000101',true);

INSERT INTO platform_catalog_variants(id,product_id,sku,name,unit_label,price_minor,currency,is_active,created_by,updated_by)
VALUES ('2f000000-0000-4000-8000-000000000202','2f000000-0000-4000-8000-000000000201',
 'P2E-FINAL-QA-FOOD-CTK-1','Regular','1 serving',34500,'INR',true,
 '2f000000-0000-4000-8000-000000000001','2f000000-0000-4000-8000-000000000001');

INSERT INTO platform_partner_product_mappings(id,business_id,variant_id,status,inventory_mode,available_quantity,preparation_minutes,supply_price_minor,supply_currency,created_by,updated_by,approved_by,approved_at)
VALUES ('2f000000-0000-4000-8000-000000000203','2f000000-0000-4000-8000-000000000101',
 '2f000000-0000-4000-8000-000000000202','approved','finite',20,20,20000,'INR',
 '2f000000-0000-4000-8000-000000000001','2f000000-0000-4000-8000-000000000001',
 '2f000000-0000-4000-8000-000000000001',now());

INSERT INTO customer_addresses(id,customer_user_id,label,recipient_name,address_line1,locality,landmark,city,state,postal_code,contact_phone,is_default,delivery_locality_id)
VALUES ('2f000000-0000-4000-8000-000000000301','2f000000-0000-4000-8000-000000000003',
 'Home','Phase 2E QA Customer','QA Test Lane','Kuanpal','QA marker','Cuttack','Odisha',
 '754208','+919990000013',true,'02200000-0000-4000-8000-000000000101');
