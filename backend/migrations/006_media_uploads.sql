-- 006_media_uploads.sql
-- Tracking uploaded media assets stored in MinIO S3 object storage.

CREATE TABLE IF NOT EXISTS media_uploads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    purpose VARCHAR(50) NOT NULL DEFAULT 'general',
    bucket VARCHAR(100) NOT NULL,
    object_key VARCHAR(500) NOT NULL UNIQUE,
    public_url VARCHAR(1000) NOT NULL,
    content_type VARCHAR(100) NOT NULL,
    size_bytes BIGINT NOT NULL,
    original_name VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_media_uploads_user ON media_uploads(user_id);
CREATE INDEX IF NOT EXISTS idx_media_uploads_purpose ON media_uploads(purpose);
CREATE INDEX IF NOT EXISTS idx_media_uploads_created ON media_uploads(created_at DESC);
