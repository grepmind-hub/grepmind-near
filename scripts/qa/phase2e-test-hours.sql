-- Disposable Phase 2E fixture only: keep QA fulfillment partners open so the
-- checkout acceptance does not depend on the host's local time of day.
INSERT INTO business_hours(business_id,weekday,opens_at,closes_at,is_closed)
SELECT b.id, day::smallint, '00:00','23:59',false
FROM businesses b CROSS JOIN generate_series(0,6) day
WHERE b.id IN (
  '2e000000-0000-4000-8000-000000000101',
  '2e000000-0000-4000-8000-000000000102',
  '2e000000-0000-4000-8000-000000000103',
  '2e000000-0000-4000-8000-000000000104'
)
ON CONFLICT (business_id,weekday) DO UPDATE
SET opens_at=EXCLUDED.opens_at,closes_at=EXCLUDED.closes_at,is_closed=false;
