-- Extend authenticated user profiles for mobile photo and preference settings.
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS avatar_url TEXT,
    ADD COLUMN IF NOT EXISTS notification_preferences JSONB NOT NULL DEFAULT '{"booking_updates":true,"offers":true,"service_updates":true}'::jsonb;

ALTER TABLE users
    ADD CONSTRAINT users_notification_preferences_object
    CHECK (jsonb_typeof(notification_preferences) = 'object');
