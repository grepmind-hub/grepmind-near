-- Store only pseudonymous, daily-deduplicated customer view events.
-- Merchant dashboards aggregate the most recent 30 UTC dates.
CREATE TABLE merchant_view_events (
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    view_type TEXT NOT NULL CHECK (view_type IN ('profile', 'catalog')),
    view_date DATE NOT NULL,
    viewer_fingerprint BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (business_id, view_type, view_date, viewer_fingerprint)
);

CREATE INDEX merchant_view_events_summary_idx
    ON merchant_view_events (business_id, view_date, view_type);
