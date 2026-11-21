-- Migration 044: device registrations for FCM push delivery
-- Tracks installations, FCM tokens, and notification permission per user.
-- FCM tokens are delivery addresses only, never authentication credentials.
-- user_id is nullable to support pre-login test installation registration.

CREATE TABLE IF NOT EXISTS device_registrations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    installation_id TEXT NOT NULL,
    fcm_token TEXT NOT NULL,
    platform TEXT NOT NULL CHECK (platform IN ('android', 'ios', 'web')),
    environment TEXT NOT NULL CHECK (environment IN ('qa', 'production')),
    notification_permission BOOLEAN NOT NULL DEFAULT false,
    last_seen TIMESTAMPTZ NOT NULL DEFAULT now(),
    active BOOLEAN NOT NULL DEFAULT true,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX device_registrations_installation_idx
    ON device_registrations (installation_id)
    WHERE active = true AND revoked_at IS NULL;

CREATE INDEX device_registrations_user_idx
    ON device_registrations (user_id)
    WHERE user_id IS NOT NULL;

CREATE INDEX device_registrations_token_idx
    ON device_registrations (fcm_token)
    WHERE active = true AND revoked_at IS NULL;

COMMENT ON COLUMN device_registrations.user_id IS
    'Authenticated user; nullable for pre-login test installation registration.';
COMMENT ON COLUMN device_registrations.installation_id IS
    'Client-generated installation identifier; bound to one app install.';
COMMENT ON COLUMN device_registrations.fcm_token IS
    'FCM registration token; delivery address only, never an auth credential.';
COMMENT ON COLUMN device_registrations.notification_permission IS
    'Whether the user granted notification permission on this device.';
COMMENT ON COLUMN device_registrations.active IS
    'Set false on logout or explicit revocation; tokens are never reused across accounts.';

-- Grant permissions to the application database user.
GRANT SELECT, INSERT, UPDATE, DELETE ON device_registrations TO abashyaka_api;
