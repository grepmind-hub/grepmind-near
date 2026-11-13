BEGIN;
INSERT INTO users(id,phone_e164,display_name,status) VALUES
('03c00000-0000-4000-8000-000000000001','+919990001171','QA Customer 3GC','active'),
('03c00000-0000-4000-8000-000000000002','+919990001172','QA Merchant 3GC','active'),
('03c00000-0000-4000-8000-000000000004','+919990001173','QA Rider A 3GC','active'),
('03c00000-0000-4000-8000-000000000005','+919990001175','QA Rider B 3GC','active');
INSERT INTO user_roles(user_id,role) VALUES
('03c00000-0000-4000-8000-000000000001','customer'),
('03c00000-0000-4000-8000-000000000002','merchant'),
('03c00000-0000-4000-8000-000000000004','rider'),
('03c00000-0000-4000-8000-000000000005','rider');
INSERT INTO user_roles(user_id,role) VALUES('40b0747c-3809-4671-bc26-c52c52f2083c','admin') ON CONFLICT DO NOTHING;
INSERT INTO businesses(id,owner_user_id,name,slug,description,category_slug,phone_e164,address_text,locality,city,postal_code,location,status,verification_status)
VALUES('03c00000-0000-4000-8000-000000000010','03c00000-0000-4000-8000-000000000002','QA 3GC Kuanpal Kitchen','qa-3gc-kuanpal-kitchen','Disposable Phase 3G-C food fulfillment partner','restaurant','+919990001172','QA pickup point, Kuanpal','Kuanpal','Cuttack','754082',ST_SetSRID(ST_MakePoint(85.75,20.45)::geography,4326),'approved','verified');
UPDATE businesses SET delivery_enabled=true,delivery_fee=0,min_order_amount=0 WHERE id='03c00000-0000-4000-8000-000000000010';
INSERT INTO business_hours(business_id,weekday,opens_at,closes_at,is_closed) SELECT '03c00000-0000-4000-8000-000000000010',d,'00:00','23:59',false FROM generate_series(0,6) d;
INSERT INTO rider_profiles(user_id,display_name,vehicle_type,status,approved_at) VALUES
('03c00000-0000-4000-8000-000000000004','QA Rider A 3GC','two_wheeler','approved',now()),
('03c00000-0000-4000-8000-000000000005','QA Rider B 3GC','bicycle','approved',now());
INSERT INTO rider_profile_localities(rider_profile_id,locality_id,status,reviewed_by,reviewed_at)
SELECT p.id,'02200000-0000-4000-8000-000000000101','approved','40b0747c-3809-4671-bc26-c52c52f2083c',now() FROM rider_profiles p WHERE p.user_id IN ('03c00000-0000-4000-8000-000000000004','03c00000-0000-4000-8000-000000000005');
INSERT INTO customer_addresses(id,customer_user_id,label,recipient_name,address_line1,locality,landmark,city,state,postal_code,contact_phone,location,is_default,delivery_locality_id)
VALUES('03c00000-0000-4000-8000-000000000020','03c00000-0000-4000-8000-000000000001','Home','QA Customer','12 QA Lane','Kuanpal','Near QA market','Cuttack','Odisha','754082','+919990001171',ST_SetSRID(ST_MakePoint(85.751,20.451)::geography,4326),true,'02200000-0000-4000-8000-000000000101');
INSERT INTO platform_catalog_products(id,sku,category_id,name,description,image_urls,status,created_by,updated_by)
SELECT '03c00000-0000-4000-8000-000000000030','QA-3GC-FOOD-01',id,'QA 3GC Chicken Biryani','Synthetic acceptance fixture; not a real listing.',ARRAY[]::text[],'active','40b0747c-3809-4671-bc26-c52c52f2083c','40b0747c-3809-4671-bc26-c52c52f2083c' FROM platform_catalog_categories WHERE vertical='food' AND slug='food';
INSERT INTO platform_catalog_variants(id,product_id,sku,name,unit_label,price_minor,currency,is_active,created_by,updated_by)
VALUES('03c00000-0000-4000-8000-000000000031','03c00000-0000-4000-8000-000000000030','QA-3GC-FOOD-01-REG','Regular','1 serving',19900,'INR',true,'40b0747c-3809-4671-bc26-c52c52f2083c','40b0747c-3809-4671-bc26-c52c52f2083c');
INSERT INTO platform_catalog_product_areas(product_id,city,locality,is_active,created_by) VALUES('03c00000-0000-4000-8000-000000000030','Cuttack','Kuanpal',true,'40b0747c-3809-4671-bc26-c52c52f2083c');
INSERT INTO platform_catalog_product_district_visibility(product_id,district_id,is_active) VALUES('03c00000-0000-4000-8000-000000000030','02200000-0000-4000-8000-000000000001',true);
INSERT INTO platform_catalog_product_delivery_localities(product_id,locality_id,is_active) VALUES('03c00000-0000-4000-8000-000000000030','02200000-0000-4000-8000-000000000101',true);
INSERT INTO platform_partner_delivery_localities(business_id,locality_id,is_active) VALUES('03c00000-0000-4000-8000-000000000010','02200000-0000-4000-8000-000000000101',true);
INSERT INTO platform_partner_product_mappings(id,business_id,variant_id,status,inventory_mode,available_quantity,supply_price_minor,supply_currency,created_by,updated_by,approved_by,approved_at)
VALUES('03c00000-0000-4000-8000-000000000032','03c00000-0000-4000-8000-000000000010','03c00000-0000-4000-8000-000000000031','approved','finite',20,12000,'INR','03c00000-0000-4000-8000-000000000002','03c00000-0000-4000-8000-000000000002','40b0747c-3809-4671-bc26-c52c52f2083c',now());
COMMIT;
