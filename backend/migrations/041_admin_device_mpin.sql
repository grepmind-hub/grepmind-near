ALTER TABLE sessions ADD COLUMN admin_otp_authenticated_at timestamptz;

CREATE TABLE admin_mpin_devices (
    device_digest text PRIMARY KEY,
    user_id uuid NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    pin_hash text NOT NULL,
    failed_attempts smallint NOT NULL DEFAULT 0 CHECK (failed_attempts BETWEEN 0 AND 5),
    expires_at timestamptz NOT NULL
);
