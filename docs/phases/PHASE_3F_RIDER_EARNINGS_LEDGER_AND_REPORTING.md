# Phase 3F — Rider Earnings Ledger & Reporting

**Date:** 9 November 2026
**State:** PASS for isolated QA acceptance — Rider Pixel 8 and authenticated Admin browser reconciled to the same PostgreSQL ledger.
**Scope:** implementation and disposable QA only. No commit, push, shared database migration, production rollout, payout, COD, customer payment, or Phase 3G work.

## Summary

Phase 3F adds an append-only rider compensation ledger tied to the existing customer-verified delivery completion transaction. It separates compensation accrual from customer payment status and money transfer. No production compensation policy or rate was found in Phase 3A or the current source, and none was invented or seeded.

When posting is disabled or no eligible policy exists, a verified completed delivery creates an explicit `unpriced` record and an audit event. It does not create a zero-value earning. Synthetic rates can be used only when the runtime is explicitly `APP_ENV=qa|test`, synthetic use is enabled, and posting is explicitly enabled. All flags default off; production rejects the synthetic switch. There is no payout, withdrawal, bank account, COD, customer-payment, settlement, GPS, or distance-based earning implementation.

## Architecture and storage

Additive migration [`028_rider_earnings_ledger.sql`](../../backend/migrations/028_rider_earnings_ledger.sql) defines:

- `rider_compensation_policies`: versioned rate snapshots, locality/currency/effective period, status and synthetic marker. Policy rows are immutable; the migration seeds no rate.
- `rider_earning_entries`: immutable delivery earnings, unpriced completions, adjustments, and reversals, linked to rider/job/order/assignment/policy/version. Values use `BIGINT` integer minor units; unpriced amounts are SQL `NULL`.
- `rider_earning_audit_events`: immutable actor/reason/event history.

The unique delivery-effect index permits at most one priced or unpriced posting for a delivery job. Unique idempotency keys protect manual entries, and a unique reversal reference prevents multiple reversals of one delivery earning. Database triggers reject updates/deletes to policy versions, ledger entries, and ledger audit events.

The delivery completion service invokes `RecordCompletionTx` in the same transaction as the customer-code-confirmed Delivered transition. It verifies both order/job terminal states, a `customer_otp_verified` event, and that the supplied rider is the latest assigned rider. Locality policy takes precedence over global policy; synthetic rows are ignored unless the explicit QA gate is enabled. Historical rate/version are snapshotted on the entry. Retries and concurrent callbacks are safe under database uniqueness constraints.

No aggregate table was introduced: reports are computed from ledger rows, so there is no stale materialized balance to reconcile. Summary and overview totals are grouped by currency, so different currencies are never added together. Reconciliation reports missing postings, incorrect rider linkage, invalid rate snapshots, and excessive reversals; it does not mutate financial history. Duplicate delivery postings are prevented by a database unique index.

## API and authorization

OpenAPI now documents the following `/api/v1` routes:

- Rider-owned: `GET /rider/earnings/summary`, `GET /rider/earnings`, `GET /rider/earnings/{entryId}`.
- Primary-superadmin-only: overview, locality list, ledger entries, audit, policy inspection, reconciliation, adjustment, and reversal under `/admin/rider-earnings/...`.

Rider endpoints derive the rider identity from authenticated backend authorization and scope every query to that ID. `requireRider` enforces approved active rider access. Admin financial routes use the existing primary-superadmin guard; merchant routes are not provided. Anonymous requests are covered by API security route tests. No policy create/activation endpoint is exposed because the commercial policy is not approved.

**Money response contract:** all output `*_minor` amounts and totals are JSON decimal strings to preserve exact 64-bit integer values in JavaScript clients. Unpriced `amount_minor` is `null`. The adjustment request accepts a bounded JSON integer amount in minor units (`±100,000,000`), ISO three-letter currency, reason, actor-derived identity, and idempotency key. Reversals copy the original entry currency. The Flutter rider screen parses exact integer strings; the Admin portal uses `BigInt` for aggregation and string-based Indian currency formatting. Mixed-currency dashboard totals are not summed together.

## Client experience

The Rider Earnings placeholder now uses authenticated API summary/history data with date-range selection, loading/error/retry/empty states, an explicit unpriced-policy notice, and a clear statement that payouts are unavailable. No paid status or withdrawal control is shown.

The Admin portal adds a Rider Earnings dashboard with date/locality filters, rider totals, policy inspection, reconciliation exceptions, immutable ledger/audit history, and audited adjustment/reversal actions. It surfaces API failures as unavailable data rather than silently showing zero totals. Access remains restricted to the primary superadmin at the backend.

## Tests and validation performed

| Check | Result |
|---|---|
| `go test -count=1 ./...` from `backend` in WSL | PASS on final acceptance rerun, including currency validation and API route security tests. |
| `bash scripts/qa/phase3f_earnings_acceptance.sh` from WSL | PASS against a disposable tmpfs PostgreSQL/PostGIS database migrated through 028. The latest run covered a Chhatia delivery, synthetic INR 475 earning, duplicate completion, eight concurrent posting callbacks, adjustment/retry/payload mismatch, reversal/retry, production-disabled unpriced behavior, exact Rider/Admin JSON minor-unit strings, currency-grouped totals, event timeline, and unpaid status. Script removed its uniquely named container. |
| `flutter test --no-pub` from WSL | PASS on final acceptance rerun, 91 tests, including Rider Earnings API states, exact 64-bit amount formatting, and separate currency totals. |
| `flutter analyze --no-pub` | Completed in 83 seconds with exit 1 because of 18 diagnostics (3 warnings, 15 infos, 0 errors), matching the documented baseline. No diagnostic was reported in the Rider Earnings screen. |
| Admin `npm run typecheck` | PASS after the earnings view and exact integer formatting changes. |
| Admin `npm run build -- --webpack` | PASS after the currency-grouping changes, including TypeScript, static generation, and page build. The default Turbopack attempt failed to create a child process in this host. |
| Emulator status | PASS: rebuilt debug APK was installed/launched on Pixel 8 (`emulator-5554`); Rider Earnings loaded from the isolated API. The APK SHA-256 was `19F0FD9C514DA971618763B9886BA29AB83B8790B479B5243FD2374585E1C075`. |
| Rider Earnings visual acceptance | PASS: authenticated synthetic QA rider saw INR 5.00 (475-paise delivery earning plus 25-paise Admin adjustment), one completed delivery, and explicit payout-unavailable messaging. Evidence: [`phase3f-rider-earnings-updated.png`](screenshots/phase3f-rider-earnings-updated.png). |
| Authenticated Admin browser acceptance | PASS: the authorized primary-superadmin opened Rider Earnings, loaded all earnings endpoints, recorded a reasoned 25-paise adjustment through the live UI (HTTP 201), and saw the same INR 5.00 locality/rider amount. Evidence: [`phase3f-admin-earnings.png`](screenshots/phase3f-admin-earnings.png). |
| PostgreSQL/API/UI reconciliation | PASS: the selected rider/delivery has exactly two ledger rows totaling 500 minor units (475 earning + 25 adjustment), two audit events, and its customer order remains `not_collected`; Rider and Admin API/UI values match. |
| Admin locality endpoint defect | Fixed: the query referenced nonexistent `platform_delivery_localities.district`; it now joins `platform_districts` by `district_id`. Added a PostgreSQL-backed Chhatia/Jajpur locality assertion. `go test ./internal/riderearnings` and the focused `TestChhatiaDeliveryTimelineAndLocalityIsolation` integration passed. |
| OpenAPI parsing | PASS with Python PyYAML. |
| Targeted `git diff --check` | PASS for the Phase 3F tracked files; new Phase 3F files also passed a trailing-whitespace scan. Whole-worktree check still reports trailing whitespace in pre-existing appended `AGENTS.md` content, which was not edited for this phase. |

### Disposable QA and shared environment

The QA script starts only a unique PostgreSQL/PostGIS container with a tmpfs data directory, applies migrations 001–028 there, runs one opt-in integration test, and removes that exact container through its exit trap. The two historical migration prerequisites (`fashion` taxonomy and the legacy Spice Garden business) are created only in this disposable database; historical migrations were not edited. No QA policy/product/customer/order/media fixture was created in the shared development DB. Migrations 028 was **not** applied to shared development or production. No shared Docker volume/service was recreated or removed.

## Open issues and release boundaries

- No commercial rider compensation rate, eligibility rule, bonus schedule, or reversal policy is approved. Production posting must remain disabled until a policy and rollout are explicitly approved.
- Full Go and Flutter suites, focused disposable-database integration, OpenAPI parse, Admin typecheck/build, live Admin browser acceptance, Pixel 8 Rider acceptance, and targeted whitespace checks pass.
- The isolated QA host required a temporary IPv4 loopback relay because the WSL API was reachable through `localhost` but not Windows `127.0.0.1`, which is the address used by emulator reverse forwarding. No permanent network or SDK configuration was changed.
- A synthetic QA rider phone fixture had an invalid Indian-number prefix; it was corrected only inside the disposable QA database. No OTP was exposed in logs or documentation.
- The Admin locality API initially returned HTTP 500 due to the invalid locality column reference. The query fix and regression assertion passed before the live UI run.
- Migration 028 has only been applied to the disposable QA database. It requires an approved, backed-up migration rollout before any shared or production service can use earnings routes.
- Reconciliation is a bounded operational report, not an automatic repair or accounting close process. No export feature was added.
- Historical Phase 3E Merchant Portal 500 remains an operational watch item; its trigger is unknown and it did not reproduce in the final isolated browser acceptance. Chhatia Android UI was not tested during Phase 3E.
- Legal/tax/accounting review of rider compensation, worker classification, records retention, and rider privacy is still required before real rider operations.

## Acceptance recommendation

**PASS for isolated QA acceptance.** The Pixel 8 Rider screen, authenticated Admin browser, API, and disposable PostgreSQL ledger show the same synthetic INR 5.00 balance for the selected QA rider. The order remains unpaid, payout controls remain unavailable, and migration 028 remains unapplied to shared development and production. Full analyzer diagnostics match the recorded baseline. No Phase 3G work is authorized.

### Final acceptance evidence — 9 November 2026

- Same synthetic QA rider and delivery were verified across Pixel 8 (`emulator-5554`), authenticated Admin browser, API, and PostgreSQL. Admin added a 25-paise QA adjustment through the live interface; the ledger retains the original 475-paise earning and the append-only adjustment separately.
- PostgreSQL reconciliation returned `2|500` (two entries, 500 minor units), two audit events, and payment state `not_collected`. The Admin adjustment request returned HTTP 201. Rider refresh displayed INR 5.00 and continued to state that payouts are unavailable.
- Final full Go suite passed; final Flutter suite passed (91); analyzer completed with 18 diagnostics (3 warnings, 15 infos, 0 errors; exit 1 due to diagnostics). The focused PostgreSQL-backed Chhatia test passed after the Admin locality query fix.
- APK was built, installed, and launched. Evidence: [`phase3f-rider-earnings.png`](screenshots/phase3f-rider-earnings.png), [`phase3f-rider-earnings-updated.png`](screenshots/phase3f-rider-earnings-updated.png), and [`phase3f-admin-earnings.png`](screenshots/phase3f-admin-earnings.png).
- The disposable QA database/container, API, MinIO, Admin dev process, temporary relay listener, ADB reverse mapping, QA browser session, QA temp directory, relay source/PID, and diagnostic screenshots were removed after verification. Two zero-byte Windows relay stdout/stderr log files remain because the host reports them locked; the relay has no listener and its PID/process is absent. These contain no QA data or credentials. Shared development and production services/data were not migrated or altered. No commit or push was created.
