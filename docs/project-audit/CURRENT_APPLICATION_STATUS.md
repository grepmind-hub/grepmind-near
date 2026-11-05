# Grepmind Near — Current Application Status

Audit date: 5 November 2026
Git baseline: `409932a` (`feat(booking): add atomic appointment rescheduling`). The audit began with unrelated pre-existing changes in the Android debug manifest, local QA artifacts, and injection payload files; they were preserved. Only the requested audit documents were changed.
Scope: current repository plus read-only checks against the local Docker Compose development stack. This is an acceptance audit, not a penetration test, production database audit, legal opinion, or Play Store approval.

## Executive assessment

The November 3 audit is superseded where later implementation and evidence show progress. The current codebase has materially advanced: merchant onboarding and existing-business claim APIs persist records; merchant portal state is now loaded from authenticated business-scoped APIs; the active category API/database has 19 categories; date-specific availability is persisted; booking capacity is transactional; and merchant-proposed rescheduling has a dedicated atomic API with customer confirmation.

The local stack was running during this audit. Read-only queries found 50 businesses, 66 users, 19 category records, and the `merchant_view_events` table from migration 016. No appointment slots or date exceptions existed in that local database at audit time. The local API health endpoint reported `{"status":"ok"}`, and an unauthenticated merchant directory request returned HTTP 401. These are local-development observations, not production evidence.

**Readiness: not ready for public production launch.** The application is a substantial local-development product with persistent core discovery, catalog, request, and order flows, but production SMS delivery, an operational migration/backup/restore process, release signing and Maps configuration, account deletion, and full authenticated portal E2E remain unresolved or unverified. Food/table/hotel fulfillment also needs explicit lifecycle and capacity rules before its UI can promise confirmed service.

## Architecture and operations

| Area | Current implementation and evidence | Acceptance status |
|---|---|---|
| Mobile | Flutter app, Riverpod state, Dio API client; source under `apps/mobile/lib`. Android application ID is `local.grepmind.grepmind_mobile`. | Unit/widget suite passes; authenticated full-device acceptance was not rerun in this audit. |
| Backend | Go modular monolith using `net/http`, PostgreSQL/sqlx and domain packages under `backend/internal`; OpenAPI at `api/openapi.yaml`. | Full Go package suite and a fresh isolated PostgreSQL authorization/rescheduling integration test pass. |
| Database | PostgreSQL 16 + PostGIS, migrations `001`–`016`; current local tables include availability exceptions, claim requests and merchant view analytics. | Local schema is populated. No migration ledger/forward migration runner or verified backup/restore process was found. Compose mounts SQL into PostgreSQL's first-initialization directory only. |
| Merchant web | Next.js 14; authenticated snapshots and mutation calls in `apps/merchant-web/lib/api.ts` and `app/page.tsx`; uploads, requests, catalog, services, hours, offers, team and SSE clients are API-backed in source. | Build and browser E2E not verified in this environment. Current E2E source covers login screen and unauthenticated access, not authenticated CRUD. |
| Admin web | Next.js 14; API-backed dashboard, registry, KYC, claims, reports, offers, audit, activity and access views. Source catches load failures and exposes error states rather than treating failed requests as zero. | Build/browser E2E not verified in this environment; authenticated suite requires a fixture phone and Chromium. |
| Media | MinIO for local development, API-mediated uploads, Nginx media path. | No production cloud storage provider, private KYC object policy, or production media authorization review was performed. |
| Realtime | Authenticated SSE hub and notifications; web client reconnects. | API ownership tests exist; browser subscription and long-lived reconnect were not run here. Native FCM is not configured. |
| CI | GitHub Actions workflows exist. | Workflow runs were not executed. Current workflow's backend test step runs only `go test ./tests/...`; browser tests omit a local admin phone so authenticated admin acceptance is skipped. |

`opencode.md` is still a Phase 6 implementation brief with historical “complete” claims and migration range 001–008, not a current architecture status report. `DEVELOPMENT_PROCESS.md` references `PRTS.md`, but that file was not present in the repository inventory. `AGENTS.md`, the current OpenAPI contract, migrations, source and executed tests were used as the current evidence set.

## Current feature inventory

Statuses describe implementation maturity, not a percentage complete. “Verified” requires a relevant test actually run in this audit or an explicitly identified immediately preceding emulator run.

| Feature | Current status | Evidence and qualification |
|---|---|---|
| OTP customer/merchant/admin login | PARTIALLY IMPLEMENTED | Local OTP works and is rate-limited; local response may disclose the OTP. `backend/internal/auth/handlers.go`. No production SMS provider is selected/configured; non-local mode fails closed. |
| Session refresh, rotation, logout revocation | COMPLETE & VERIFIED | Opaque refresh token digest, row-locked rotation, session-bound access JWT validation and revocation; auth tests pass in fresh `go test -count=1 ./...`. |
| 19 active business categories | COMPLETE & VERIFIED | Local PostgreSQL category count is 19; `/api/v1/categories` is the runtime source. This is taxonomy coverage, not a configurable category capability engine. |
| Customer discovery, search, Nearby and saved | IMPLEMENTED, NOT VERIFIED | Live API clients and corresponding Flutter screens/tests exist. No complete customer discovery/favorites UI run was executed in this audit. Earlier city/category automation is documented in `scripts/CITY_VALIDATION.md` and `scripts/MERCHANT_UI_INJECTION.md`. |
| Business profile, contact, products and offers | IMPLEMENTED, NOT VERIFIED | Discovery API and Flutter UI exist; sample/media and city scenarios are automated in repository scripts. This audit did not repeat emulator acceptance. |
| Customer service request and booking slots | COMPLETE & VERIFIED (API/security scope) | Availability, overlap, timezone, closed-date, customer/business ownership and concurrent capacity-one tests pass in `TestOwnershipAndTenantRoutes` against an isolated temporary schema. Customer UI full flow not rerun in this audit. |
| Merchant-proposed appointment rescheduling | COMPLETE & VERIFIED (backend and recent UI E2E) | Dedicated PATCH proposal and customer confirmation endpoints move slot capacity transactionally. Fresh DB integration test passed here. Prior immediately preceding emulator run passed for Cuttack and Jajpur; emulator regression was not repeated in this audit because ADB could not start. |
| Merchant availability and date exceptions | IMPLEMENTED, NOT VERIFIED (current runtime) | Merchant create/edit/close slot APIs and mobile management UI exist. The local DB had zero slots/exceptions, so no retained fixture was available. Existing automation is documented, but was not rerun on device. |
| Merchant registration and claim | IMPLEMENTED, NOT VERIFIED | Mobile registration posts to merchant business API; claim search/submission/status and admin decision service persist ownership only after review. Evidence: `merchant_registration_screen.dart`, `backend/internal/businessclaims/service.go`, migration 014. Full UI claim/KYC transfer was not run. |
| Merchant catalog/product/service CRUD | IMPLEMENTED, NOT VERIFIED (current acceptance) | Authenticated mobile and web CRUD endpoints/UI exist; prior category automation exercises create/edit/delete. This audit ran Flutter widget tests, not live catalog CRUD on emulator/browser. |
| Merchant hours, coverage, offer and team management | IMPLEMENTED, NOT VERIFIED | Authenticated API calls and UI components are connected in source; no authenticated merchant browser session was run here. |
| Merchant portal source data | IMPLEMENTED, NOT VERIFIED | Main workspace now loads directory and snapshots from API; prior mock-backed finding is stale. `apps/merchant-web/app/page.tsx` contains no `INITIAL_*` fixture import. Runtime CRUD and isolation in portal remain unverified. |
| Admin dashboard and operations views | IMPLEMENTED, NOT VERIFIED | Dashboard and all principal tabs call APIs; visible load errors are implemented. No authenticated UI test ran in this audit. |
| Admin RBAC/root protection | IMPLEMENTED, NOT VERIFIED (API tests pass) | Protected routes and superadmin-only role changes are present; API integration tests cover role denial/root safeguards. Browser role-management flow not run. |
| Food order and customer order history | PARTIALLY IMPLEMENTED | Persisted orders, server-side price calculation, customer history/cancel and merchant status API exist. Merchant portal has no merchant order-management view, and this audit did not exercise a live order. |
| Table reservations and hotel stays | PARTIALLY IMPLEMENTED | Persisted order types and customer UI exist; table/room inventory, overlapping stay capacity, merchant confirmation and complete cancellation/refund policy are absent or unverified. |
| Reviews and ratings | NOT IMPLEMENTED | No review table/API/workflow found; UI avoids fabricating ratings when absent. |
| Delivery tracking / native notifications | PARTIALLY IMPLEMENTED | Order history/status exists; courier location and native FCM delivery are not implemented. SSE supports active clients only. |
| Merchant registration fee/subscription | NOT IMPLEMENTED | No subscription plans, payment records, verified UPI checkout/webhooks, invoices or entitlement lifecycle. Customer payments remain deliberately out of scope. |
| Account deletion and Play release readiness | NOT IMPLEMENTED / NOT READY | Profile says self-service account deletion is unavailable; release Gradle still uses debug signing and Maps key is a placeholder. |

## Fresh verification summary

- `go test -count=1 ./...` in WSL: passed all Go packages.
- `GREPMIND_TEST_DATABASE_URL=... go test ./cmd/api -run ^TestOwnershipAndTenantRoutes$ -count=1 -v`: passed against local PostgreSQL using a temporary isolated schema that the test removes.
- Flutter `test/`: all 53 tests passed.
- Flutter `analyze`: returned 119 lint findings, including warnings and informational findings; no clean analysis claim. Examples include unused declarations/imports and an unreachable switch default.
- Local Compose: all listed services were up; API reported healthy. Read-only API smoke returned health `ok` and unauthenticated merchant access 401. Database counts are local-only as stated above.
- Merchant Playwright E2E: 3 tests attempted; all failed before page assertions because the configured Chromium executable is absent. Admin Playwright E2E was not run; the admin dependency/browser setup is incomplete and the authenticated test needs `E2E_ADMIN_PHONE_E164`.
- Both Next.js production builds failed because the Windows SWC binary was missing and registry access failed (`ENOTFOUND registry.npmjs.org`). No web build pass is claimed.
- Android ADB daemon could not start in this session, so no current APK/device acceptance was run. The previous rescheduling task did pass emulator E2E in Cuttack and Jajpur and installed the rebuilt APK.

## Operational limitations

1. Migration SQL is mounted as PostgreSQL initialization scripts. There is no application migration ledger, safe existing-database migration command, rollback/forward-fix playbook, or migration deployment gate. Migration 010 has archival behavior and must not be blindly replayed.
2. Compose has a persistent PostgreSQL volume but no scheduled `pg_dump`, offsite backup configuration, restore automation, or recorded restore drill. External provider-level backup status was not observable in this repository audit.
3. The local database contains seeded/demo-style records; it must not be interpreted as genuine production customer or merchant activity.
4. Findings above concern source and the local development stack only; production configuration and live provider accounts were not accessed.
