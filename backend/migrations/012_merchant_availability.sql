-- Merchant-managed local-time appointment inventory and one-day exceptions.
ALTER TABLE businesses
    ADD COLUMN IF NOT EXISTS time_zone TEXT NOT NULL DEFAULT 'Asia/Kolkata';

ALTER TABLE availability_slots
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE TABLE IF NOT EXISTS business_availability_exceptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    local_date DATE NOT NULL,
    is_closed BOOLEAN NOT NULL DEFAULT false,
    opens_at TIME,
    closes_at TIME,
    note TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (business_id, local_date),
    CHECK (
        (is_closed AND opens_at IS NULL AND closes_at IS NULL)
        OR (NOT is_closed AND ((opens_at IS NULL AND closes_at IS NULL) OR
            (opens_at IS NOT NULL AND closes_at IS NOT NULL AND opens_at < closes_at)))
    ),
    CHECK (char_length(note) <= 240)
);

CREATE INDEX IF NOT EXISTS availability_exceptions_business_date_idx
    ON business_availability_exceptions (business_id, local_date);
