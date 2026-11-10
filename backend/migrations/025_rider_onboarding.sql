-- Rider onboarding and approval are deliberately separate from delivery jobs.
-- No locality is granted until an administrator approves it.

CREATE TABLE rider_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Preserve the reviewed application identity/history. Account erasure must
    -- use an explicit retention/anonymization policy, never an implicit cascade.
    user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE RESTRICT,
    display_name TEXT NOT NULL CHECK (char_length(btrim(display_name)) BETWEEN 2 AND 120),
    vehicle_type TEXT NOT NULL CHECK (vehicle_type IN ('bicycle','two_wheeler','three_wheeler','other')),
    vehicle_details TEXT NOT NULL DEFAULT '' CHECK (char_length(vehicle_details) <= 500),
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','submitted','under_review','changes_requested','approved','rejected','suspended')),
    review_notes TEXT,
    reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    submitted_at TIMESTAMPTZ,
    approved_at TIMESTAMPTZ,
    suspended_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE rider_document_requirements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE CHECK (code ~ '^[a-z][a-z0-9_]{1,63}$'),
    label TEXT NOT NULL CHECK (char_length(btrim(label)) BETWEEN 2 AND 120),
    vehicle_type TEXT NOT NULL DEFAULT 'any' CHECK (vehicle_type IN ('any','bicycle','two_wheeler','three_wheeler','other')),
    is_required BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE rider_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rider_profile_id UUID NOT NULL REFERENCES rider_profiles(id) ON DELETE CASCADE,
    requirement_id UUID NOT NULL REFERENCES rider_document_requirements(id),
    bucket TEXT NOT NULL,
    object_key TEXT NOT NULL,
    content_type TEXT NOT NULL CHECK (content_type IN ('image/jpeg','image/png','image/webp')),
    size_bytes BIGINT NOT NULL CHECK (size_bytes BETWEEN 1 AND 8388608),
    sha256 BYTEA NOT NULL CHECK (octet_length(sha256)=32),
    review_status TEXT NOT NULL DEFAULT 'pending' CHECK (review_status IN ('pending','accepted','rejected','superseded')),
    rejection_reason TEXT CHECK (rejection_reason IS NULL OR char_length(rejection_reason) BETWEEN 10 AND 500),
    reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(bucket, object_key)
);
CREATE INDEX rider_documents_profile_idx ON rider_documents(rider_profile_id, uploaded_at DESC);

CREATE TABLE rider_profile_localities (
    rider_profile_id UUID NOT NULL REFERENCES rider_profiles(id) ON DELETE CASCADE,
    locality_id UUID NOT NULL REFERENCES platform_delivery_localities(id),
    status TEXT NOT NULL DEFAULT 'requested' CHECK (status IN ('requested','approved','rejected')),
    reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,
    PRIMARY KEY(rider_profile_id, locality_id)
);
CREATE INDEX rider_localities_approved_idx ON rider_profile_localities(locality_id) WHERE status='approved';

CREATE TABLE rider_application_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rider_profile_id UUID NOT NULL REFERENCES rider_profiles(id) ON DELETE CASCADE,
    actor_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    event_type TEXT NOT NULL CHECK (event_type IN ('created','submitted','review_started','changes_requested','approved','rejected','suspended','reactivated','document_reviewed','localities_reviewed')),
    reason TEXT CHECK (reason IS NULL OR char_length(reason)<=500),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX rider_application_events_profile_idx ON rider_application_events(rider_profile_id, created_at);

CREATE OR REPLACE FUNCTION prevent_rider_application_event_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'rider application history is append-only';
END;
$$;
CREATE TRIGGER rider_application_events_immutable
BEFORE UPDATE OR DELETE ON rider_application_events
FOR EACH ROW EXECUTE FUNCTION prevent_rider_application_event_mutation();
