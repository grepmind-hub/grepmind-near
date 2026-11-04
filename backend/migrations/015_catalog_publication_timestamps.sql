-- Track when a catalog item first becomes visible to customers.
-- Existing catalog rows intentionally remain without publication timestamps;
-- they must be republished/reactivated by the merchant before being featured
-- as new, rather than being presented as recently added during migration.
ALTER TABLE products
    ADD COLUMN IF NOT EXISTS published_at TIMESTAMPTZ;

ALTER TABLE services
    ADD COLUMN IF NOT EXISTS activated_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS products_publication_feed_idx
    ON products (published_at DESC, business_id)
    WHERE is_published = true AND published_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS services_activation_feed_idx
    ON services (activated_at DESC, business_id)
    WHERE is_active = true AND activated_at IS NOT NULL;
