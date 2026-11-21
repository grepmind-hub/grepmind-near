-- Migration 045: Google Sign-In identity linking
-- Maps Google subject identifiers to local user accounts.
-- Automatic merging by email or phone is prohibited; linking requires
-- explicit authenticated authorization.

CREATE TABLE IF NOT EXISTS google_identities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    google_subject TEXT NOT NULL UNIQUE,
    email TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX google_identities_user_idx ON google_identities (user_id);
CREATE INDEX google_identities_subject_idx ON google_identities (google_subject);

COMMENT ON COLUMN google_identities.google_subject IS
    'Stable Google subject identifier; never changes for a given Google account.';
COMMENT ON COLUMN google_identities.email IS
    'Google account email; informational only, never used for automatic account linking.';

-- Grant permissions to the application database user.
GRANT SELECT, INSERT, UPDATE, DELETE ON google_identities TO abashyaka_api;
