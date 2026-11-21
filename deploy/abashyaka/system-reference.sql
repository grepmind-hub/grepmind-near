-- Deployment reference categories/districts from migrations 001, 008, 021, 022.
-- No users, businesses, products, orders, locality fixtures or finance entries.
BEGIN;
INSERT INTO categories (slug, name, icon_name, description, sort_order) VALUES
('grocery', 'Grocery', 'store', 'Grocery stores and kirana shops', 1),
('hardware', 'Hardware', 'build', 'Hardware and building supplies', 2),
('medical', 'Medical & Pharmacy', 'local_pharmacy', 'Pharmacies and medical stores', 3),
('restaurant', 'Restaurant & Food', 'restaurant', 'Restaurants and eateries', 4),
('salon', 'Salon & Beauty', 'face', 'Beauty salons and parlours', 5),
('plumber', 'Plumber', 'plumbing', 'Plumbing services', 6),
('electrician', 'Electrician', 'electrical_services', 'Electrical services', 7),
('carpenter', 'Carpenter', 'carpenter', 'Carpentry services', 8),
('tailor', 'Tailor', 'face', 'Tailoring services', 9),
('general', 'General Store', 'shop', 'General provision stores', 10),
('hotel', 'Hotels & Stays', 'hotel', 'Hotels, luxury resorts, boutique stays and beach lodges', 11)
ON CONFLICT (slug) DO NOTHING;
INSERT INTO platform_catalog_categories (vertical, slug, name, is_system, sort_order)
VALUES ('food', 'food', 'Food', true, 10),
       ('grocery', 'grocery', 'Grocery', true, 20)
ON CONFLICT DO NOTHING;
INSERT INTO platform_districts(id,state_code,name,slug) VALUES
('02200000-0000-4000-8000-000000000001','OD','Cuttack','cuttack'),
('02200000-0000-4000-8000-000000000002','OD','Jajpur','jajpur')
ON CONFLICT DO NOTHING;
-- Delivery localities/coverage remain unconfigured; no service availability activation.
COMMIT;
