-- Migration 005: Admin Analytics, KYC Review & Multi-City Listings (Puri, Cuttack, Bhubaneswar)

-- 1. Create merchant users for new pending listings
INSERT INTO users (id, phone_e164, display_name, status, preferred_language)
VALUES 
    ('de111111-1111-1111-1111-111111111111', '+919861000010', 'Manoj Mahapatra', 'active', 'en'),
    ('de222222-2222-2222-2222-222222222222', '+919861000011', 'Subrat Nayak', 'active', 'en'),
    ('ce555555-5555-5555-5555-555555555555', '+919861000012', 'Dr. Priyabrata Das', 'active', 'en'),
    ('be555555-5555-5555-5555-555555555555', '+919861000013', 'Satyajit Rout', 'active', 'en')
ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;

INSERT INTO user_roles (user_id, role)
VALUES 
    ('de111111-1111-1111-1111-111111111111', 'merchant'),
    ('de222222-2222-2222-2222-222222222222', 'merchant'),
    ('ce555555-5555-5555-5555-555555555555', 'merchant'),
    ('be555555-5555-5555-5555-555555555555', 'merchant')
ON CONFLICT DO NOTHING;

-- 2. Seed pending businesses awaiting Admin KYC verification
INSERT INTO businesses (
    id, owner_user_id, name, slug, description, category_slug, phone_e164, whatsapp_e164,
    address_text, locality, city, postal_code, location, status, verification_status, cover_photo_url
) VALUES 
    (
        'de333333-3333-3333-3333-333333333333',
        'de111111-1111-1111-1111-111111111111',
        'Jagannath Silks & Handicrafts',
        'jagannath-silks-puri',
        'Authentic handloom Sambalpuri silk sarees, palm leaf Pattachitra paintings, and stone sculptures on Grand Road.',
        'fashion',
        '+919861000010',
        '+919861000010',
        'Grand Road (Bada Danda), Near Jagannath Temple Entrance',
        'Grand Road',
        'Puri',
        '752001',
        ST_SetSRID(ST_MakePoint(85.8312, 19.8135)::geography, 4326),
        'pending',
        'pending',
        'http://localhost:9000/grepmind-near/biz-covers/retail_boutique.jpg'
    ),
    (
        'de444444-4444-4444-4444-444444444444',
        'de222222-2222-2222-2222-222222222222',
        'Konark Coastal AC & Refrigeration Care',
        'konark-coastal-ac-puri',
        'Specialist coastal anti-rust AC repair, chiller servicing, and domestic inverter installations across Puri & Sea Beach hotels.',
        'electrician',
        '+919861000011',
        '+919861000011',
        'Plot 42, VIP Road, Near Sea Beach Police Station',
        'VIP Road',
        'Puri',
        '752002',
        ST_SetSRID(ST_MakePoint(85.8245, 19.8010)::geography, 4326),
        'pending',
        'pending',
        'http://localhost:9000/grepmind-near/biz-covers/electrical_service.jpg'
    ),
    (
        'ce666666-6666-6666-6666-666666666666',
        'ce555555-5555-5555-5555-555555555555',
        'Barabati Diagnostics & Health Clinic',
        'barabati-diagnostics-cuttack',
        'Automated pathology diagnostics, digital ECG, doctor consultations, and certified medicine deliveries in Millennium City.',
        'medical',
        '+919861000012',
        '+919861000012',
        'Medical Road, Opposite SCB Medical College',
        'Mangalabag',
        'Cuttack',
        '753007',
        ST_SetSRID(ST_MakePoint(85.8920, 20.4680)::geography, 4326),
        'pending',
        'pending',
        'http://localhost:9000/grepmind-near/biz-covers/pharmacy_store.jpg'
    ),
    (
        'be666666-6666-6666-6666-666666666666',
        'be555555-5555-5555-5555-555555555555',
        'Kalinga Smart Home Automation & Security',
        'kalinga-smart-home-bbsr',
        'Smart IoT home wiring, digital CCTV camera installation, video doorbells, and rooftop solar electrical maintenance.',
        'electrician',
        '+919861000013',
        '+919861000013',
        'Infocity Avenue, Patia Silicon Tech Corridor',
        'Chandrasekharpur',
        'Bhubaneswar',
        '751024',
        ST_SetSRID(ST_MakePoint(85.8180, 20.3240)::geography, 4326),
        'pending',
        'pending',
        'http://localhost:9000/grepmind-near/biz-covers/hardware_store.jpg'
    )
ON CONFLICT (id) DO NOTHING;

-- 3. Seed pending offers for admin moderation
INSERT INTO offers (
    id, business_id, title, description, discount_percent, starts_at, ends_at, status
) VALUES 
    (
        '0e111111-1111-1111-1111-111111111111',
        'de333333-3333-3333-3333-333333333333',
        'Ratha Yatra Handloom Festival: 20% Off',
        'Special 20% discount on pure Sambalpuri silk and cotton handloom sarees during festive season.',
        20,
        now(),
        now() + interval '30 days',
        'pending'
    ),
    (
        '0e222222-2222-2222-2222-222222222222',
        'de444444-4444-4444-4444-444444444444',
        'Pre-Monsoon AC Gas & Coil Inspection @ ₹499',
        'Complete high-pressure chemical wash and anti-rust coating for seaside residential and hotel AC units.',
        15,
        now(),
        now() + interval '14 days',
        'pending'
    )
ON CONFLICT (id) DO NOTHING;
