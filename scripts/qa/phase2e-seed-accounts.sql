INSERT INTO platform_catalog_categories(vertical,slug,name,is_system,sort_order) VALUES
 ('food','food','Food',true,10),
 ('grocery','grocery','Grocery',true,20)
ON CONFLICT DO NOTHING;

INSERT INTO platform_districts(id,state_code,name,slug) VALUES
 ('02200000-0000-4000-8000-000000000001','OD','Cuttack','cuttack'),
 ('02200000-0000-4000-8000-000000000002','OD','Jajpur','jajpur')
ON CONFLICT DO NOTHING;
INSERT INTO platform_delivery_localities(id,district_id,name,slug,delivery_enabled) VALUES
 ('02200000-0000-4000-8000-000000000101','02200000-0000-4000-8000-000000000001','Kuanpal','kuanpal',true),
 ('02200000-0000-4000-8000-000000000102','02200000-0000-4000-8000-000000000001','Jagatpur','jagatpur',false),
 ('02200000-0000-4000-8000-000000000103','02200000-0000-4000-8000-000000000001','Tangi','tangi',false),
 ('02200000-0000-4000-8000-000000000201','02200000-0000-4000-8000-000000000002','Chhatia','chhatia',true),
 ('02200000-0000-4000-8000-000000000202','02200000-0000-4000-8000-000000000002','Chandikhol','chandikhol',false)
ON CONFLICT DO NOTHING;

INSERT INTO categories (slug,name,is_active) VALUES
  ('restaurant','Restaurant',true),
  ('grocery_store','Grocery store',true)
ON CONFLICT (slug) DO UPDATE SET is_active=true;

INSERT INTO users (id,phone_e164,display_name,status) VALUES
  ('2e000000-0000-4000-8000-000000000001','+919990000001','Phase 2E QA Admin','active'),
  ('2e000000-0000-4000-8000-000000000002','+919990000002','Phase 2E QA Kuanpal Food Partner','active'),
  ('2e000000-0000-4000-8000-000000000003','+919990000003','Phase 2E QA Kuanpal Grocery Partner','active'),
  ('2e000000-0000-4000-8000-000000000004','+919990000004','Phase 2E QA Chhatia Food Partner','active'),
  ('2e000000-0000-4000-8000-000000000005','+919990000005','Phase 2E QA Chhatia Grocery Partner','active'),
  ('2e000000-0000-4000-8000-000000000006','+919990000006','Phase 2E QA Unassigned Partner','active'),
  ('2e000000-0000-4000-8000-000000000007','+919990000007','Phase 2E QA Customer','active')
ON CONFLICT (id) DO NOTHING;

INSERT INTO user_roles(user_id,role) VALUES
  ('2e000000-0000-4000-8000-000000000001','admin'),
  ('2e000000-0000-4000-8000-000000000002','merchant'),
  ('2e000000-0000-4000-8000-000000000003','merchant'),
  ('2e000000-0000-4000-8000-000000000004','merchant'),
  ('2e000000-0000-4000-8000-000000000005','merchant'),
  ('2e000000-0000-4000-8000-000000000006','merchant'),
  ('2e000000-0000-4000-8000-000000000007','customer')
ON CONFLICT DO NOTHING;

INSERT INTO businesses(id,owner_user_id,name,slug,description,category_slug,phone_e164,address_text,locality,city,postal_code,location,status,verification_status,delivery_enabled)
VALUES
  ('2e000000-0000-4000-8000-000000000101','2e000000-0000-4000-8000-000000000002','Phase 2E QA Food Partner Kuanpal','phase2e-qa-food-kuanpal','Temporary Phase 2E QA fulfillment partner.','restaurant','+919990000002','QA address, Kuanpal','Kuanpal','Cuttack','754208',ST_SetSRID(ST_MakePoint(86.155,20.420),4326)::geography,'approved','verified',true),
  ('2e000000-0000-4000-8000-000000000102','2e000000-0000-4000-8000-000000000003','Phase 2E QA Grocery Partner Kuanpal','phase2e-qa-grocery-kuanpal','Temporary Phase 2E QA fulfillment partner.','grocery_store','+919990000003','QA address, Kuanpal','Kuanpal','Cuttack','754208',ST_SetSRID(ST_MakePoint(86.156,20.421),4326)::geography,'approved','verified',true),
  ('2e000000-0000-4000-8000-000000000103','2e000000-0000-4000-8000-000000000004','Phase 2E QA Food Partner Chhatia','phase2e-qa-food-chhatia','Temporary Phase 2E QA fulfillment partner.','restaurant','+919990000004','QA address, Chhatia','Chhatia','Jajpur','755046',ST_SetSRID(ST_MakePoint(86.225,20.750),4326)::geography,'approved','verified',true),
  ('2e000000-0000-4000-8000-000000000104','2e000000-0000-4000-8000-000000000005','Phase 2E QA Grocery Partner Chhatia','phase2e-qa-grocery-chhatia','Temporary Phase 2E QA fulfillment partner.','grocery_store','+919990000005','QA address, Chhatia','Chhatia','Jajpur','755046',ST_SetSRID(ST_MakePoint(86.226,20.751),4326)::geography,'approved','verified',true),
  ('2e000000-0000-4000-8000-000000000105','2e000000-0000-4000-8000-000000000006','Phase 2E QA Unassigned Partner','phase2e-qa-unassigned-partner','Temporary Phase 2E isolation test partner.','restaurant','+919990000006','QA address, Cuttack','Kuanpal','Cuttack','754208',ST_SetSRID(ST_MakePoint(86.157,20.422),4326)::geography,'approved','verified',true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO business_members(business_id,user_id,role,status)
VALUES
 ('2e000000-0000-4000-8000-000000000101','2e000000-0000-4000-8000-000000000002','owner','active'),
 ('2e000000-0000-4000-8000-000000000102','2e000000-0000-4000-8000-000000000003','owner','active'),
 ('2e000000-0000-4000-8000-000000000103','2e000000-0000-4000-8000-000000000004','owner','active'),
 ('2e000000-0000-4000-8000-000000000104','2e000000-0000-4000-8000-000000000005','owner','active'),
 ('2e000000-0000-4000-8000-000000000105','2e000000-0000-4000-8000-000000000006','owner','active')
ON CONFLICT (business_id,user_id) DO NOTHING;

INSERT INTO platform_partner_delivery_localities(business_id,locality_id,is_active)
VALUES
 ('2e000000-0000-4000-8000-000000000101','02200000-0000-4000-8000-000000000101',true),
 ('2e000000-0000-4000-8000-000000000102','02200000-0000-4000-8000-000000000101',true),
 ('2e000000-0000-4000-8000-000000000103','02200000-0000-4000-8000-000000000201',true),
 ('2e000000-0000-4000-8000-000000000104','02200000-0000-4000-8000-000000000201',true)
ON CONFLICT (business_id,locality_id) DO UPDATE SET is_active=true;

INSERT INTO platform_partner_coverage_areas(business_id,city,locality,is_active)
VALUES
 ('2e000000-0000-4000-8000-000000000101','Cuttack','Kuanpal',true),
 ('2e000000-0000-4000-8000-000000000102','Cuttack','Kuanpal',true),
 ('2e000000-0000-4000-8000-000000000103','Jajpur','Chhatia',true),
 ('2e000000-0000-4000-8000-000000000104','Jajpur','Chhatia',true)
ON CONFLICT DO NOTHING;
