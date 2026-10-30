-- Migration 008: Hospitality, Hotels & Food Delivery Expansion

-- 1. Extend businesses table with hospitality & delivery capabilities
ALTER TABLE businesses
ADD COLUMN IF NOT EXISTS delivery_enabled BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS delivery_time_mins INTEGER NOT NULL DEFAULT 30,
ADD COLUMN IF NOT EXISTS delivery_fee NUMERIC(10,2) NOT NULL DEFAULT 30.00,
ADD COLUMN IF NOT EXISTS min_order_amount NUMERIC(10,2) NOT NULL DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS table_booking_enabled BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS room_booking_enabled BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS amenities JSONB DEFAULT '[]'::jsonb;

-- 2. Extend products table with dietary and hospitality tags
ALTER TABLE products
ADD COLUMN IF NOT EXISTS dietary_type TEXT CHECK (dietary_type IS NULL OR dietary_type IN ('veg', 'non_veg', 'egg', 'vegan')),
ADD COLUMN IF NOT EXISTS food_category TEXT,
ADD COLUMN IF NOT EXISTS preparation_time_min INTEGER DEFAULT 20;

-- 3. Insert 'hotel' category
INSERT INTO categories (slug, name, icon_name, description, sort_order)
VALUES ('hotel', 'Hotels & Stays', 'hotel', 'Hotels, luxury resorts, boutique stays and beach lodges', 11)
ON CONFLICT (slug) DO UPDATE SET 
    name = EXCLUDED.name,
    icon_name = EXCLUDED.icon_name,
    description = EXCLUDED.description;

-- 4. Enable delivery & table reservation for Spice Garden Restaurant (Bhubaneswar)
UPDATE businesses
SET delivery_enabled = true,
    delivery_time_mins = 35,
    delivery_fee = 30.00,
    min_order_amount = 149.00,
    table_booking_enabled = true,
    amenities = '["Air Conditioned Dining", "Live Tandoor Counter", "Free Parking", "Home Delivery within 8 km", "High Chairs Available", "Pure Drinking Water RO"]'::jsonb
WHERE id = 'cfb375d3-543b-4bb8-8f1d-11a10659661c';

-- 5. Seed rich food menu products for Spice Garden Restaurant
DELETE FROM products WHERE business_id = 'cfb375d3-543b-4bb8-8f1d-11a10659661c';

INSERT INTO products (
    business_id, name, description, price, currency, stock_status, is_published, dietary_type, food_category, preparation_time_min
) VALUES
(
    'cfb375d3-543b-4bb8-8f1d-11a10659661c',
    'Mughlai Chicken Dum Biryani',
    'Aromatic long-grain basmati rice layered with succulent marinated chicken, saffron, caramelized onions, and royal spices. Served with boondi raita and mirchi ka salan.',
    290.00, 'INR', 'in_stock', true, 'non_veg', 'Main Course', 25
),
(
    'cfb375d3-543b-4bb8-8f1d-11a10659661c',
    'Paneer Butter Masala',
    'Soft homemade cottage cheese cubes simmered in a velvety buttery tomato-cashew reduction, tempered with kasuri methi and fresh cream.',
    240.00, 'INR', 'in_stock', true, 'veg', 'Main Course', 20
),
(
    'cfb375d3-543b-4bb8-8f1d-11a10659661c',
    'Murgh Malai Tikka (6 Pcs)',
    'Boneless chicken morsels steeped in cheese, cream, green cardamom, and grilled in a clay tandoor. Served with mint chutney.',
    310.00, 'INR', 'in_stock', true, 'non_veg', 'Starters', 20
),
(
    'cfb375d3-543b-4bb8-8f1d-11a10659661c',
    'Crispy Chilli Babycorn',
    'Golden fried babycorn tossed in wok with spring onions, bell peppers, cracked black pepper, and tangy Indo-Chinese sauces.',
    180.00, 'INR', 'in_stock', true, 'veg', 'Starters', 15
),
(
    'cfb375d3-543b-4bb8-8f1d-11a10659661c',
    'Butter Garlic Naan',
    'Clay-oven roasted artisan flatbread glazed with melted garlic butter and sprinkled with fresh coriander leaves.',
    55.00, 'INR', 'in_stock', true, 'veg', 'Breads & Rice', 10
),
(
    'cfb375d3-543b-4bb8-8f1d-11a10659661c',
    'Jeera Basmati Rice',
    'Aromatic steamed basmati rice tempered with golden cumin seeds and pure desi cow ghee.',
    120.00, 'INR', 'in_stock', true, 'veg', 'Breads & Rice', 12
),
(
    'cfb375d3-543b-4bb8-8f1d-11a10659661c',
    'Authentic Odia Chhena Poda',
    'Iconic caramelized baked cottage cheese dessert infused with green cardamom, roasted cashews, and caramelized sugar crust.',
    130.00, 'INR', 'in_stock', true, 'veg', 'Desserts', 5
),
(
    'cfb375d3-543b-4bb8-8f1d-11a10659661c',
    'Alphonso Mango Lassi',
    'Thick and creamy yogurt blended with Alphonso mango pulp, garnished with pistachios and saffron strands.',
    95.00, 'INR', 'in_stock', true, 'veg', 'Beverages', 5
);

-- 6. Seed premier Hotel & Resort: Mayfair Coastal Lagoon & Resort (Puri)
INSERT INTO users (id, phone_e164, display_name, status, preferred_language)
VALUES ('d1111111-1111-1111-1111-111111111110', '+919861000008', 'Mayfair Hospitality Front Desk', 'active', 'en')
ON CONFLICT (phone_e164) DO NOTHING;

INSERT INTO user_roles (user_id, role)
VALUES ('d1111111-1111-1111-1111-111111111110', 'merchant')
ON CONFLICT DO NOTHING;

INSERT INTO businesses (
    id, owner_user_id, name, slug, description, category_slug, phone_e164, whatsapp_e164,
    address_text, locality, city, postal_code, location, status, verification_status, cover_photo_url,
    delivery_enabled, room_booking_enabled, amenities
) VALUES (
    'd1111111-1111-1111-1111-111111111111',
    'd1111111-1111-1111-1111-111111111110',
    'Mayfair Coastal Lagoon & Resort',
    'mayfair-coastal-lagoon-puri',
    'Luxury 5-star beachfront resort featuring private ocean-view balconies, lagoon pool, multi-cuisine dining, and authentic Ayurvedic wellness spa on Puri Marine Drive.',
    'hotel',
    '+919861000008',
    '+919861000008',
    'Chakratirtha Beach Road, Marine Drive',
    'Chakratirtha Road',
    'Puri',
    '752002',
    ST_SetSRID(ST_MakePoint(85.8450, 19.8080)::geography, 4326),
    'approved',
    'verified',
    'http://localhost:9000/grepmind-near/biz-covers/hotel_resort.jpg',
    false,
    true,
    '["Free High-Speed Wi-Fi", "Infinity Swimming Pool", "Complimentary Buffet Breakfast", "Central Air Conditioning", "Private Ocean Balcony", "Free Valet Parking", "24/7 Room Service", "Ayurvedic Wellness Spa", "Private Beach Access"]'::jsonb
) ON CONFLICT (id) DO UPDATE SET
    room_booking_enabled = true,
    amenities = EXCLUDED.amenities;

-- Link primary owner in business_members
INSERT INTO business_members (business_id, user_id, role)
VALUES ('d1111111-1111-1111-1111-111111111111', 'd1111111-1111-1111-1111-111111111110', 'owner')
ON CONFLICT DO NOTHING;

-- Seed Hotel Rooms
DELETE FROM products WHERE business_id = 'd1111111-1111-1111-1111-111111111111';

INSERT INTO products (
    business_id, name, description, price, currency, stock_status, is_published, food_category
) VALUES
(
    'd1111111-1111-1111-1111-111111111111',
    'Deluxe Sea-Facing King Room',
    '380 sq ft elegant room with private balcony overlooking the Bay of Bengal. Features king-sized plush bedding, Italian marble bathroom, 55" 4K Smart TV, and complimentary hot buffet breakfast.',
    4800.00, 'INR', 'in_stock', true, 'Rooms'
),
(
    'd1111111-1111-1111-1111-111111111111',
    'Executive Lagoon View Suite',
    '680 sq ft luxury suite with separate living parlor, jacuzzi bath, panoramic lagoon views, complimentary airport transfer, and evening cocktail lounge access.',
    7900.00, 'INR', 'in_stock', true, 'Rooms'
),
(
    'd1111111-1111-1111-1111-111111111111',
    'Royal Heritage Beach Villa',
    '1,200 sq ft standalone private beach villa surrounded by palm groves. Features private plunge pool, outdoor rain shower, personal 24-hr butler service, and direct beach trail.',
    12500.00, 'INR', 'in_stock', true, 'Rooms'
);
