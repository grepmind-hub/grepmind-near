-- Archive out-of-scope local listings before removing them from active tables.
-- Immutable audit history and shared user accounts are deliberately preserved.
BEGIN;
CREATE TABLE city_scope_archive (
    table_name TEXT NOT NULL,
    row_id UUID NOT NULL,
    payload JSONB NOT NULL,
    archived_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY(table_name,row_id)
);
CREATE TEMP TABLE excluded_businesses ON COMMIT DROP AS
 SELECT id FROM businesses WHERE lower(coalesce(city,'')) NOT IN ('cuttack','jajpur');
INSERT INTO city_scope_archive SELECT 'businesses',id,to_jsonb(b),now() FROM businesses b WHERE id IN(SELECT id FROM excluded_businesses);
INSERT INTO city_scope_archive SELECT 'business_hours',id,to_jsonb(t),now() FROM business_hours t WHERE business_id IN(SELECT id FROM excluded_businesses);
INSERT INTO city_scope_archive SELECT 'business_hour_exceptions',id,to_jsonb(t),now() FROM business_hour_exceptions t WHERE business_id IN(SELECT id FROM excluded_businesses);
INSERT INTO city_scope_archive SELECT 'professional_profiles',business_id,to_jsonb(t),now() FROM professional_profiles t WHERE business_id IN(SELECT id FROM excluded_businesses);
INSERT INTO city_scope_archive SELECT 'products',id,to_jsonb(t),now() FROM products t WHERE business_id IN(SELECT id FROM excluded_businesses);
INSERT INTO city_scope_archive SELECT 'services',id,to_jsonb(t),now() FROM services t WHERE business_id IN(SELECT id FROM excluded_businesses);
INSERT INTO city_scope_archive SELECT 'offers',id,to_jsonb(t),now() FROM offers t WHERE business_id IN(SELECT id FROM excluded_businesses);
INSERT INTO city_scope_archive SELECT 'availability_slots',id,to_jsonb(t),now() FROM availability_slots t WHERE business_id IN(SELECT id FROM excluded_businesses);
INSERT INTO city_scope_archive SELECT 'service_requests',id,to_jsonb(t),now() FROM service_requests t WHERE business_id IN(SELECT id FROM excluded_businesses);
INSERT INTO city_scope_archive SELECT 'business_members',id,to_jsonb(t),now() FROM business_members t WHERE business_id IN(SELECT id FROM excluded_businesses);
INSERT INTO city_scope_archive SELECT 'merchant_catalog_categories',id,to_jsonb(t),now() FROM merchant_catalog_categories t WHERE business_id IN(SELECT id FROM excluded_businesses);
INSERT INTO city_scope_archive SELECT 'notifications',id,to_jsonb(t),now() FROM notifications t WHERE business_id IN(SELECT id FROM excluded_businesses);
INSERT INTO city_scope_archive SELECT 'reports',id,to_jsonb(t),now() FROM reports t WHERE target_type='business' AND target_id IN(SELECT id FROM excluded_businesses);
INSERT INTO city_scope_archive SELECT 'favorites', gen_random_uuid(),to_jsonb(t),now() FROM favorites t WHERE business_id IN(SELECT id FROM excluded_businesses);
DELETE FROM service_requests WHERE business_id IN(SELECT id FROM excluded_businesses);
DELETE FROM reports WHERE target_type='business' AND target_id IN(SELECT id FROM excluded_businesses);
DELETE FROM businesses WHERE id IN(SELECT id FROM excluded_businesses);
INSERT INTO city_scope_archive SELECT 'unserved_location_demand',id,to_jsonb(t),now() FROM unserved_location_demand t WHERE lower(city) NOT IN ('cuttack','jajpur');
DELETE FROM unserved_location_demand WHERE lower(city) NOT IN ('cuttack','jajpur');
ALTER TABLE businesses ADD CONSTRAINT businesses_supported_city CHECK (city IS NOT NULL AND lower(city) IN ('cuttack','jajpur'));
COMMIT;
