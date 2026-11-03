# Audit Test Results

Execution date: 3 November 2026 (Asia/Kolkata). Tests were run against the current local checkout. No production deployment, production DB command, real payment, or irreversible migration was run. The audit created documentation only; prior operational implementation changes were already present in the checkout.

## Commands actually executed

| Command | Result | Notes |
|---|---|---|
| `wsl bash -lc "cd /mnt/d/grepmind-near/backend && go test ./..."` | PASS | All Go packages passed. Includes JWT/auth boundary tests, discovery tests, moderation tests and API anonymous-route rejection. Does not exercise a live DB transaction for every route. |
| `wsl bash -lc "cd /mnt/d/grepmind-near/apps/mobile && .../flutter/bin/flutter test"` | PASS | 25 widget tests passed, including merchant category, booking empty-slot behavior, hours draft behavior, service status and order history widget navigation. This is not full authenticated emulator/API E2E. |
| `.../flutter/bin/flutter analyze` | FAIL (findings) | Completed analysis: 99 warning/info issues, no Dart errors were printed. Nonzero exit due to warnings/info. Findings include deprecated APIs, unused code/imports, async BuildContext lint and style findings. |
| `wsl bash -lc "cd /mnt/d/grepmind-near && docker compose -f docker-compose.yml config -q && docker compose -f docker-compose.test.yml config -q && docker compose -f docker-compose.staging.yml config -q"` | PASS with warnings | All three parse. Obsolete `version` warnings. Staging emits unset environment-variable warnings for passwords, JWT, FCM and Twilio credentials. Parsing does not establish the stacks can safely run. |
| `wsl python3 -c "import yaml; yaml.safe_load(open('/mnt/d/grepmind-near/api/openapi.yaml')); print('OpenAPI YAML parsed')"` | PASS | YAML syntax only; does not validate OpenAPI schema correctness or routes against Go. |
| `cd apps/merchant-web && npm run typecheck` | FAIL | `@playwright/test` missing in installed dependencies; E2E files/config are included in TS compilation, causing missing module and implicit-any errors. |
| `cd apps/admin-web && npm run typecheck` | FAIL | Same missing `@playwright/test` dependency and E2E fixture implicit-any errors. |
| `cd apps/merchant-web && npm run build` | INCOMPLETE | Started Next 14 production build; attempted downloading Linux SWC binaries, then stalled in this environment. Interrupted; no build result claimed. |
| `cd apps/admin-web && npm run build` | INCOMPLETE | Started Next 14 production build; remained at optimized build stage in available environment and was interrupted. No build result claimed. |

## Not executed

- Flutter integration test directory (`flutter test integration_test/ -d ...`): not run. Existing CI references an emulator/service arrangement that requires workflow repair and a live seeded test stack.
- Playwright E2E (`npm test`): not run. `@playwright/test` is missing; portal tests also contain fixed phone/OTP placeholders, and no API-backed fixture/login setup was verified.
- Docker Compose startup/test stack: not started for this audit. Compose configuration validation is read-only and safer; no fresh test database bootstrap was performed.
- Security workflows (`Trivy`, OWASP ZAP): not run. They require action runner/network and a correctly started test stack; the workflow itself has dependencies/gaps described in `FEATURE_GAP_ANALYSIS.md`.
- Load test (`k6`): not run. It needs a defined safe test target and baseline.
- Android release build: not run during this audit. Prior implementation notes record a debug APK build/install/launch, but release signing is currently debug-key based, so a public release artifact is not appropriate yet.
- Live OTP/SMS, FCM, gateway payment, backup/restore, live media authorization, customer reservation or merchant subscription transactions: not run.

## Prior execution evidence inspected (not rerun here)

- `codex-implementation.md` records that local API image rebuilt, migration 011 applied and `/api/v1/categories` returned HTTP 200 in the previous implementation turn. This was not revalidated against a new database in this audit.
- `scripts/CITY_VALIDATION.md` and `scripts/MERCHANT_UI_INJECTION.md` document successful local runs across 19 categories × Cuttack/Jajpur (38 cases) with generated fixture cleanup. These are repository records; this audit did not rerun the scripts or inspect an execution artifact from those runs.
- Prior turn recorded an APK install and launch to OTP screen. This audit did not repeat emulator validation.

## Environmental limitations and interpretation

- WSL Go/Flutter SDKs and Docker Compose are available. Host Flutter analyze is relatively slow and emits pre-existing lint findings.
- Web package environment lacks Playwright installation. The production builds attempted SWC download and did not finish in the bounded run window; no network workaround or package installation was performed.
- Compose config parsing with staging environment unset is only syntactic validation; blank secrets would be unsafe to run.
- A passing unit/widget suite does not prove database schema bootstrapping, authorization for all tenant objects, real OTP delivery, release signing, Play compliance or production operations.

## Verification tasks before launch

1. Fresh disposable PostgreSQL/PostGIS DB: apply migrations 001–011 through the actual deployment migration mechanism and verify repeatability without reapplying archive migration incorrectly.
2. API integration tests with real local DB: create food/table/hotel order, calculate amount, list/get, cancel state, merchant transition, unauthorized customer and cross-business owner/member denial.
3. Appointment race test: concurrent requests against one slot never exceed capacity; cancellation releases capacity once.
4. Run full Flutter analyzer after sorting warnings; run Flutter widget suite and integration tests with dynamic disposable identities.
5. Install Playwright dependencies in clean CI using lockfile (`npm ci`), configure browser install and run portal tests against disposable API/database fixtures.
6. Run merchant/admin typecheck/build and repair current failures. Check relative browser `/api/v1` request routing through Nginx.
7. Validate OpenAPI structurally and compare registered method/path routes in an automated CI check.
8. Run Trivy/config/dependency scanning and a scoped ZAP baseline against isolated test environment; triage findings.
9. Exercise private media upload/list/access and unauthorized/cross-user access; verify production cloud provider, not MinIO public-read defaults.
10. Run signed Android release/AAB through internal Play testing only after signing, privacy, Data safety, account deletion and Maps key are ready.
