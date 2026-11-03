CREATE TABLE business_claim_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    claimant_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    claimant_message TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'approved', 'rejected')),
    reviewer_user_id UUID REFERENCES users(id) ON DELETE RESTRICT,
    review_note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    reviewed_at TIMESTAMPTZ,
    CHECK (length(btrim(claimant_message)) BETWEEN 10 AND 2000),
    CHECK ((status = 'pending' AND reviewer_user_id IS NULL AND reviewed_at IS NULL)
        OR (status <> 'pending' AND reviewer_user_id IS NOT NULL AND reviewed_at IS NOT NULL))
);

-- A listing may have only one active review at a time. Historical decisions remain.
CREATE UNIQUE INDEX business_claim_requests_one_pending_per_business
    ON business_claim_requests (business_id) WHERE status = 'pending';
CREATE INDEX business_claim_requests_status_created_idx
    ON business_claim_requests (status, created_at DESC);
CREATE INDEX business_claim_requests_claimant_created_idx
    ON business_claim_requests (claimant_user_id, created_at DESC);
