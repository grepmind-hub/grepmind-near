-- Migration 048: Admin Password Authentication
-- Supports password-based login for platform administrators on the Admin Web Portal.

ALTER TABLE users ADD COLUMN IF NOT EXISTS email TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS users_email_unique_idx ON users (lower(email)) WHERE email IS NOT NULL AND email != '';

-- Provision or update Platform Superadmin credentials
-- Default Username/Email: admin@abashyaka.com or superadmin
-- Default Password: Admin@Abashyaka2027#
INSERT INTO users (id, phone_e164, display_name, email, password_hash, status, preferred_language)
VALUES (
  '00000000-0000-4000-8000-000000000001',
  '+910000000000',
  'superadmin',
  'admin@abashyaka.com',
  '$2a$10$3wXuwEt6a54aJfWgt4/US.G2R9MgTMCGX8Vvs6K0/5J6THUEY0XPS',
  'active',
  'en'
)
ON CONFLICT (phone_e164) DO UPDATE SET
  email = EXCLUDED.email,
  password_hash = EXCLUDED.password_hash,
  display_name = EXCLUDED.display_name,
  status = 'active';

INSERT INTO user_roles (user_id, role)
SELECT id, 'admin' FROM users WHERE phone_e164 = '+910000000000'
ON CONFLICT (user_id, role) DO NOTHING;
