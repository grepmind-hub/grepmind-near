-- Migration 007: Real-time notifications and extended service request stages

-- 1. Extend service_requests status check to include 'in_progress' and 'rescheduled'
ALTER TABLE service_requests DROP CONSTRAINT IF EXISTS service_requests_status_check;
ALTER TABLE service_requests ADD CONSTRAINT service_requests_status_check
    CHECK (status IN ('requested', 'accepted', 'in_progress', 'declined', 'rescheduled', 'cancelled', 'completed'));

-- 2. Create notifications table for in-app and merchant alerts
CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    business_id UUID REFERENCES businesses(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    event_type TEXT NOT NULL,
    reference_id TEXT,
    payload JSONB DEFAULT '{}',
    is_read BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS notifications_user_idx ON notifications (user_id, is_read, created_at DESC);
CREATE INDEX IF NOT EXISTS notifications_business_idx ON notifications (business_id, created_at DESC);
CREATE INDEX IF NOT EXISTS notifications_created_idx ON notifications (created_at DESC);

-- Seed initial welcome notifications for existing merchants
INSERT INTO notifications (user_id, business_id, title, body, event_type, payload)
SELECT 
    owner_user_id,
    id,
    'Storefront Online & Verified',
    'Your listing "' || name || '" is active and receiving discovery traffic across Odisha.',
    'system.welcome',
    jsonb_build_object('business_id', id, 'name', name)
FROM businesses
WHERE status = 'approved'
ON CONFLICT DO NOTHING;
