-- Migration 004: Merchant Team & Staff Multi-User Access Management

CREATE TABLE IF NOT EXISTS business_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('owner', 'manager', 'staff')),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'revoked')),
    invited_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (business_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_business_members_user ON business_members(user_id);
CREATE INDEX IF NOT EXISTS idx_business_members_business ON business_members(business_id);
CREATE INDEX IF NOT EXISTS idx_business_members_role ON business_members(role);

-- 1. Backfill all existing business owners as 'owner' in business_members
INSERT INTO business_members (business_id, user_id, role, status)
SELECT id, owner_user_id, 'owner', 'active'
FROM businesses
ON CONFLICT (business_id, user_id) DO NOTHING;

-- 2. Seed demo team members for Bhubaneswar (Shree Hardware & Electricals)
-- User: Rakesh Mohapatra (Manager)
INSERT INTO users (id, phone_e164, display_name, status, preferred_language)
VALUES ('ba111111-1111-1111-1111-111111111111', '+919861000005', 'Rakesh Mohapatra', 'active', 'en')
ON CONFLICT (phone_e164) DO NOTHING;

INSERT INTO user_roles (user_id, role)
VALUES ('ba111111-1111-1111-1111-111111111111', 'merchant')
ON CONFLICT DO NOTHING;

-- User: Sunil Sahu (Staff / Dispatcher)
INSERT INTO users (id, phone_e164, display_name, status, preferred_language)
VALUES ('ba222222-2222-2222-2222-222222222222', '+919861000006', 'Sunil Sahu', 'active', 'en')
ON CONFLICT (phone_e164) DO NOTHING;

INSERT INTO user_roles (user_id, role)
VALUES ('ba222222-2222-2222-2222-222222222222', 'merchant')
ON CONFLICT DO NOTHING;

-- Assign Rakesh as Manager and Sunil as Staff for Shree Hardware & Electricals
DO $$
DECLARE
    shree_biz_id UUID;
    shree_owner_id UUID;
BEGIN
    SELECT id, owner_user_id INTO shree_biz_id, shree_owner_id 
    FROM businesses 
    WHERE name ILIKE '%Shree Hardware%' LIMIT 1;

    IF shree_biz_id IS NOT NULL THEN
        INSERT INTO business_members (business_id, user_id, role, status, invited_by)
        VALUES (shree_biz_id, 'ba111111-1111-1111-1111-111111111111', 'manager', 'active', shree_owner_id)
        ON CONFLICT (business_id, user_id) DO UPDATE SET role = 'manager', status = 'active';

        INSERT INTO business_members (business_id, user_id, role, status, invited_by)
        VALUES (shree_biz_id, 'ba222222-2222-2222-2222-222222222222', 'staff', 'active', shree_owner_id)
        ON CONFLICT (business_id, user_id) DO UPDATE SET role = 'staff', status = 'active';
    END IF;
END $$;
