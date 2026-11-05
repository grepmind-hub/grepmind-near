# Grepmind Near — Cross-Platform Audit Test Results

Audit date: 5 November 2026. Only checks listed as passed below were executed successfully. No production endpoint, payment, SMS, migration, or deployment was used.

## Commands executed

| Command / procedure | Result |
|---|---|
| `wsl.exe --exec bash -lc 'cd /mnt/d/grepmind-near/backend && go test -count=1 ./...'` | PASS. All Go packages completed successfully without Go test cache. |
| `GREPMIND_TEST_DATABASE_URL=postgres://grepmind:grepmind_dev@127.0.0.1:5432/grepmind_near?sslmode=disable go test ./cmd/api -run ^TestOwnershipAndTenantRoutes$ -count=1 -v` (from WSL/backend) | PASS. Uses a temporary, isolated test schema and removes it. Covers tenant ownership, roles, SSE authorization, concurrent slot capacity, availability exceptions and rescheduling transitions. |
| `wsl.exe --exec bash -lc 'cd /mnt/d/grepmind-near/apps/mobile && /home/grepmind/projects/flutter-setup/develop/flutter/bin/flutter test'` | PASS. All 53 Flutter tests passed. |
| Flutter `analyze` using `/home/grepmind/projects/flutter-setup/develop/flutter/bin/flutter analyze` | NOT CLEAN. 119 lint findings were reported, including analyzer warnings and informational findings. Examples include unused declarations/imports and an unreachable switch default. This is not a zero-warning result. |
| `docker compose ps` (WSL, local Compose) | PASS for availability check. PostgreSQL, API, MinIO, Nginx, worker, merchant-web and admin-web were running; API/PostgreSQL/MinIO reported healthy where health checks are configured. |
| Read-only local psql counts | PASS. `businesses=50`, `users=66`, `categories=19`, `availability_slots=0`, `business_availability_exceptions=0`, `merchant_view_events=1`; user role totals were admin 1, customer 50, merchant 61. These are development records and do not imply production activity. Migration-016 analytics table exists. |
| Local `GET /healthz` and unauthenticated `GET /api/v1/merchant/businesses` through WSL curl | PASS: health returned `{"status":"ok"}`; merchant directory returned HTTP 401. |
| `node ./node_modules/playwright/cli.js test --reporter=line` in `apps/merchant-web` | BLOCKED before page assertions: 3 tests were attempted but Playwright Chromium executable is missing. All 3 failed at browser launch, not because of an application assertion. Generated `test-results` was removed after review. |
| `npm test -- --reporter=line` in `apps/admin-web` | BLOCKED before test execution: Windows could not resolve the Playwright executable. Additionally, authenticated admin E2E requires `E2E_ADMIN_PHONE_E164`; no fixture phone was configured. |
| `node ./node_modules/next/dist/bin/next build` in both web apps | FAIL due to environment/dependency availability: Next attempted to download missing Windows SWC from `registry.npmjs.org`, but DNS/network access failed (`ENOTFOUND`). No successful web build is claimed. |
| `adb devices -l` | BLOCKED: Windows ADB daemon failed startup handshake (`could not read ok from ADB Server`). No emulator/device test was run in this audit. |
| YAML/OpenAPI validation | OpenAPI file was not modified in this audit. A prior project validation parsed it; no fresh OpenAPI parser run was necessary for this documentation-only audit. |

## Regression: appointment rescheduling

- Fresh backend tenant/ownership integration test passed with a disposable PostgreSQL schema. It exercises request capacity-one concurrency, cross-business access denial, full/closed replacement rejection, preservation of the old reservation on failure, atomic slot move, customer-only confirmation, cancellation and capacity release.
- Full Go package suite passed; full Flutter widget suite (53 tests) passed, including service request confirmation coverage.
- The immediately preceding implementation task ran the mobile Workspace automation on emulator for Cuttack and Jajpur, passed, cleaned generated QA data, and reinstalled the standard APK. That is prior-turn evidence, not a rerun in this audit.
- Current emulator regression was blocked because ADB could not start. Therefore the rescheduling backend regression is freshly verified; current visual/emulator regression remains unverified.

## Database migration and backup status

- Migrations `001`–`016` are present; the local database contains tables introduced through 016 (including merchant view analytics) and availability/claim tables.
- No migration ledger/runner was found. Compose's SQL mount is PostgreSQL first-initialization behavior, not an upgrade mechanism for an existing volume.
- No scheduled backup, `pg_dump`/`pg_restore` workflow, restore automation, or restore drill was found in the repo. A persistent Docker volume is not a backup. External provider snapshots were not accessible from this audit.
- No migration or destructive database operation was run.

## Checks not completed

1. Authenticated admin portal login and tab actions through a browser.
2. Authenticated merchant portal login, business switch, product/service CRUD, image upload, hours, requests, offer/team actions and business isolation through browser E2E.
3. Customer OTP/discovery/favorites/order/request journey on the live app and emulator in this audit.
4. Production SMS delivery, production secret handling, session revocation against deployed config, cloud storage permissions, FCM, online payments, release signing and Play review.
5. Backup integrity or restore from an actual backup.

The code/API evidence and specific reasons for each uncompleted workflow are recorded in `CROSS_PLATFORM_ACCEPTANCE_MATRIX.md`.
