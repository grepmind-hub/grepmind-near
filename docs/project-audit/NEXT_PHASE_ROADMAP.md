# Grepmind Near — Updated Next Phase Roadmap

Audit date: 5 November 2026. Priorities account for work completed since the November 3 audit. Effort is a solo-developer estimate for code plus focused tests and excludes provider/legal lead times.

## Ranked next 10 items

| Rank | Feature | Current status | Value / why now | Dependencies and security | Effort |
|---:|---|---|---|---|---|
| 1 | Migration runner, backup and restore drill | NOT IMPLEMENTED operationally | Prevent schema drift and irreversible data loss before real customer/merchant records. | Preserve SQL history; validate upgrade from existing schema and fresh bootstrap; encrypt/offsite backups; restore into isolated DB. | M (1–2 weeks) |
| 2 | Production SMS OTP | PARTIALLY IMPLEMENTED | Needed for real customer, merchant and admin sign-in. | Choose India-supported provider; secrets outside repo; delivery observability, abuse controls and no production OTP echo. | M/L (2–3 weeks plus vendor setup) |
| 3 | Authenticated cross-platform acceptance harness | PARTIALLY IMPLEMENTED | Converts existing API/UI features into reliable release checks and prevents fake success. | Disposable PostgreSQL/MinIO/browser/emulator, generated identities/OTP, cleanup manifests, session revocation, no production target. | M (1–2 weeks) |
| 4 | Complete merchant order/reservation operations | PARTIALLY IMPLEMENTED | Food orders and hospitality bookings exist on customer side but lack complete merchant workflow and capacity policies. | Design order state machine; table/room inventory; server-side transition/tenant controls; cancellation and customer communication. | L (2–4 weeks) |
| 5 | Public launch security and Android release readiness | NOT READY | Debug signing, placeholder Maps key, account deletion and privacy evidence block Play release. | Protected signing secrets, Play policy review, data deletion/retention design, app/API domain and key restriction. | M/L (2–3 weeks plus review) |
| 6 | Merchant KYC/private media acceptance | PARTIALLY IMPLEMENTED | Builds trust and limits fraudulent business claims. | Verify authorization, private document access, retention/deletion, admin decision audit and full claim transfer E2E. | M (1–2 weeks) |
| 7 | 19-category capability matrix | PARTIALLY IMPLEMENTED | Current taxonomy is complete, but workflows and requirements are not data-driven per category. | Define product/service/booking/contact capabilities and required fields from validated launch categories; avoid premature generic engine. | M (1–2 weeks design + implementation slice) |
| 8 | Support and operational observability | PARTIALLY IMPLEMENTED | Needed to detect and resolve failed login, catalog, booking and moderation operations. | Request IDs, redacted logs, alert thresholds, crash reports, support intake/privacy policy. | M (1–2 weeks) |
| 9 | Native Android push notifications | NOT IMPLEMENTED | Reaches customers/merchants when app is backgrounded; SSE only serves live sessions. | FCM credentials, consent/preferences, device token lifecycle, notification privacy and deduplication. | M (1–2 weeks) |
| 10 | Verified reviews/ratings | NOT IMPLEMENTED | Adds trust after fulfilled transactions are real and verifiable. | Completed service/order model, eligibility, moderation/reporting and anti-abuse/rate limits. | M (2–3 weeks) |

Merchant registration fee and monthly/annual UPI subscriptions remain a high business priority, but should follow the account/onboarding and migration/backup foundations. Do not implement customer marketplace payments in that billing feature.

## Recommended phase sequence

### Phase A — Operational safety and release testability

1. Introduce a versioned migration runner/ledger for existing databases and make deployments fail on migration error.
2. Add scheduled PostgreSQL backups and a restore verification procedure; document RPO/RTO and credentials.
3. Repair CI so it runs all Go packages, applies migrations to a fresh database, runs web E2E with browsers, and does not silently skip authenticated tests.
4. Build generated local fixtures and browser/emulator test flows with reversible cleanup for OTP, merchant, admin, claims, catalog, orders, and slot workflows.

### Phase B — Production authentication and merchant trust

1. Select and implement a real SMS OTP provider for staging; verify rate controls under multi-instance assumptions and ensure OTP disclosure is local-only.
2. Run onboarding and claim review end to end, including KYC storage visibility and admin transfer audit.
3. Validate role/member scoping for every merchant endpoint and cross-business request/notification path.

### Phase C — Define supported commercial operations

1. Finish merchant food order workflow and table/room capacity before asserting confirmed fulfillment.
2. Define the 19-category capability matrix based on launch scope and actual service business rules.
3. Design merchant billing (registration fee + subscription through UPI) with professional tax/refund review and idempotent signed webhooks. Customer payments remain deferred.
4. Add support intake, monitoring, FCM and verified reviews in dependency order.

## Five small implementation tasks for the next phase

1. Add a migration ledger and `migrate up/status` command; test fresh schema and upgrade from the current local schema in disposable databases.
2. Add a local backup/restore script with integrity check and a documented restore drill; do not overwrite the working Compose volume.
3. Fix CI backend test command to run `go test ./...` and provision a migrated disposable DB for integration tests.
4. Provision deterministic E2E fixtures for admin and merchant; ensure OTP/session and generated business/catalog/request rows are always revoked/removed in cleanup.
5. Add merchant order pipeline requirements and state-transition matrix, including table/room inventory and cancellation; do not collect customer payments.

## Recommended next single development task

**Implement the migration ledger/runner and verify a safe upgrade of a disposable database.** It addresses a confirmed operational gap, is bounded, prevents new features from silently diverging between installations, and can be validated without production data. Backups should immediately follow; do not run migrations against production until there is a reviewed rollout/backup plan.
