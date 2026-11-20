# Phase 5D — Admin Payment Tracking

**Status — PASS for isolated Admin Web read-only acceptance (16 November 2026).**

The Admin portal's Payment tracking view looks up one exact order reference or UUID. It shows the stored order and payment states, payment intent state, provider attempts, and recorded reconciliation outcomes. It labels bounded histories when older records exist.

The read-only endpoint is `GET /api/v1/admin/payments/orders/{reference}`. It enforces `finance.read`, returns a consistent PostgreSQL snapshot, and limits results to the most recent 25 attempts and 50 reconciliation events. Provider references, idempotency keys, customer identifiers, and webhook payloads are omitted from the response. Lookup requires no schema migration.

## Acceptance

A separate tmpfs PostGIS stack applied migrations 001–041 and ran the new API image and Admin production build. A synthetic Customer created order `GN-1150C2AC` and completed a ₹280.00 sandbox payment. QA reconciliation recorded `matched` for its `succeeded` attempt. Two independent synthetic Admins granted `finance.read` through the request and approval APIs. The target Admin signed in through scoped OTP in the browser.

- Lookup by lower-case reference returned the same paid order, succeeded attempt, ₹280.00 amount, and matched reconciliation event as PostgreSQL. The sandbox capture journal had equal debits and credits.
- UUID lookup for COD order `GN-B2F97528` returned the order with a null intent and empty attempt and reconciliation histories.
- Unauthenticated lookup returned 401. Customer and ungranted Admin lookups returned 403. An ungranted Admin also received 403 for an unknown reference. With the read grant, an unknown reference returned 404 and invalid input returned 400.
- The Admin browser test passed against the live API. The production build, Go payment and API tests, and Go vet passed. OpenAPI parsed successfully.
- Live financial flags stayed disabled. This gate covers Admin Web. The Customer setup was exercised through isolated APIs.

[Admin payment tracking screenshot](evidence/phase5d/payment-tracking.png).
