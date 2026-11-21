-- Staging invitations authorize a test installation, not phone ownership.
-- A random capability is stored only as a SHA-256 digest. Revocation and
-- expiry are checked for each staging authentication operation.
CREATE TABLE staging_enrollments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token_hash BYTEA NOT NULL UNIQUE CHECK (octet_length(token_hash) = 32),
    phone_e164 TEXT NOT NULL CHECK (phone_e164 ~ '^\+[1-9][0-9]{9,14}$'),
    installation_id TEXT UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    claimed_at TIMESTAMPTZ
);

-- NULL for the existing SMS/private QA authentication flows.
ALTER TABLE otp_codes ADD COLUMN staging_enrollment_id UUID
    REFERENCES staging_enrollments(id);
