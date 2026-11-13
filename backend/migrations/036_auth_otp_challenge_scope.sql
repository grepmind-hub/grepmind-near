-- Phase AUTH-OTP-01: explicitly scope login challenges and invalidate older
-- unconsumed codes after a newer OTP request is accepted.
-- Existing rows represent historical login challenges; no OTP is backfilled.

ALTER TABLE otp_codes
    ADD COLUMN purpose TEXT NOT NULL DEFAULT 'login',
    ADD COLUMN invalidated_at TIMESTAMPTZ;

ALTER TABLE otp_codes
    ADD CONSTRAINT otp_codes_purpose_check CHECK (purpose = 'login');

CREATE INDEX otp_codes_active_challenge_idx
    ON otp_codes (phone_e164, created_at DESC)
    WHERE verified_at IS NULL AND invalidated_at IS NULL;

COMMENT ON COLUMN otp_codes.purpose IS
    'Authentication purpose bound to this challenge; currently login only.';
COMMENT ON COLUMN otp_codes.invalidated_at IS
    'Set when a newer challenge supersedes this code before it is consumed.';
