# AUTH-OTP-01 — Secure OTP Autofill and QA Automation

**Updated:** 13 November 2026  
**Status:** PASS for isolated QA after AUTH-OTP-01-E2E-R2. Production SMS delivery remains unconfigured; this is not production authentication readiness.  
**Scope:** OTP delivery/entry hardening, Android autofill, browser OTP semantics, and isolated QA OTP retrieval. Phase 4D settlement execution was attempted only as an authorization check and remains PARTIAL.

## Repository audit

- The Go API owns OTP generation, persistence, expiry, attempt counting, verification, role lookup, and session creation. Codes are generated with the cryptographic random source and stored as bcrypt hashes.
- Login OTPs are rate-limited by phone and peer IP, expire, count failed attempts, and are atomically consumed once. A newer request invalidates prior unverified login challenges. New clients bind verification to a returned `challenge_id`; the no-ID lookup remains temporarily for older clients.
- Existing JWT/session and role authorization are retained. An OTP authenticates an identity; it does not grant Admin finance permissions or bypass merchant membership/rider approval.
- Source inspection found no configured production SMS gateway adapter or credentials in this repository. The default `stub` therefore cannot send a message. With no delivery provider, requests now fail closed with `503 OTP_UNAVAILABLE`; no development code is returned.
- Admin Web and Merchant Web already use the Go OTP endpoints. Both now retain the challenge ID, use a six-digit one-time-code input, and keep manual entry/resend behavior. This offers browser/OS autofill where supported; it does not make desktop browsers read Android SMS.
- Android now starts the SMS Retriever listener before requesting the code, uses the platform one-time-code hint, preserves manual entry, and binds verification to the challenge. An early-arriving SMS is buffered until the request response establishes the current challenge. No broad SMS permission or unrelated inbox scanning is used.
- The QA file transport is opt-in only for `APP_ENV=qa`, `OTP_PROVIDER=qa_file`, explicit delivery enablement, a synthetic E.164 allowlist, a private inbox, and a per-run ID. It writes challenge-scoped JSON files mode 0600 under a mode-0700 directory. There is no OTP retrieval HTTP route and OTPs are not placed in normal auth responses or application logs. The current local reader uses `docker exec` against an allowlisted QA API container; Docker daemon access is broad host authority, so this is suitable only for a trusted, isolated local QA runner, not a shared CI credential model.
- Additive migration 036 adds login-purpose and invalidation fields/indexing. It has not been applied to shared development or production databases.

## Implemented behavior

1. OTP request responses contain only the normalized phone, request state, and opaque challenge ID.
2. The latest challenge is invalidated transactionally before a new one is issued. Verification checks exact challenge, phone, login purpose, validity window, attempt budget, and single-use state under a row lock.
3. No configured transport means request failure and no OTP disclosure. The QA file adapter is not selected from `APP_ENV=local` or production.
4. Flutter listener lifecycle is disposed with the screen; manual typing, paste, six-digit validation, resend countdown, loading feedback, and existing server verification remain.
5. Admin and Merchant web forms use `autocomplete="one-time-code"`, numeric input semantics, bounded resend UI, and normal backend verification.
6. The updated Admin and Merchant workspace E2E specs read one challenge by challenge ID, phone hash, purpose, and run ID from a private QA container and consume it once. Several older/historical QA scripts and Flutter integration tests still expect the former local OTP response or visible local-code UI; those scripts now fail closed and must be migrated to the private reader before they are used for authenticated QA.

## Security and operational limits

- **Production SMS: NOT READY.** Select/configure the SMS vendor, credentials, sender identity, and compliant Indian DLT message template before deployment. The SMS Retriever message also needs the correct app hash for each package/signing certificate; no release signing hash is assumed or hardcoded here.
- **QA login:** R1 did not exercise login because its reader/configuration failed the security boundary. R2 below supersedes that result for isolated QA: the protected reader was configured and Customer, Merchant, Rider, and Admin authenticated through normal UI verification. Never allowlist a real root superadmin or expose its OTP through QA tooling.
- **Browser autofill: capability only.** Standards-compatible browser/OS one-time-code autofill is advertised by the input. Actual SMS autofill depends on supported browser/OS, origin security, SMS formatting, and a real configured SMS delivery route. Manual input remains the fallback.
- **OTP integration tests requiring PostgreSQL:** require `GREPMIND_TEST_DATABASE_URL` or `TEST_DATABASE_URL` and an isolated disposable database. The full Go suite below ran without those variables; those DB-backed cases are conditional and must not be described as having run against Postgres.
- **QA reader privilege:** `docker exec` is not a least-privilege runner token. Keep it on a trusted host and disposable network; a future shared CI setup should use a dedicated short-lived runner capability rather than Docker administrator access.
- **No financial side effects:** no UPI/COD, settlement, funding allocation, payout, or existing Phase 4D batch was changed in this task.

## Emulator evidence

The same final x86_64 debug APK was built from WSL and installed/launched through Windows ADB:

| Role | AVD | ADB serial | Result |
|---|---|---|---|
| Customer | `Pixel_8` | `emulator-5560` | Install and launch PASS; login screen visible |
| Merchant | `Pixel_8_Merchant_QA` | `emulator-5558` | Install and launch PASS; login screen visible |
| Rider | `Pixel_8_Rider_QA` | `emulator-5556` | Install and launch PASS; login screen visible |

APK: `apps/mobile/build/app/outputs/flutter-apk/app-x86_64-debug.apk`  
SHA-256: `3789BE6CDEB67496D1111C2A4387DCC4420708FF6CC17A4F52D0AC64611A79C2`  
Application ID: `local.grepmind.grepmind_mobile`; version code 4001, version name 1.0.0, target SDK 36.  
Screenshots: `docs/phases/evidence/auth-otp-01/customer-login.png`, `merchant-login.png`, and `rider-login.png`.

The Customer AVD initially hit an Android package-manager `PackageManagerInternal.freeStorage` null-reference during APK installation. Its `/data` partition had 4.3 GB free. A clean AVD shutdown/relaunch (no wipe) restored installation. A smaller x86_64 APK then installed successfully on all three AVDs. No emulator data was wiped.

## Commands and results

Commands were executed from Windows PowerShell through the authorized Windows-host WSL route (`wsl.exe --exec bash -lc ...`) using the installed Flutter SDK at `/home/grepmind/projects/flutter-setup/develop/flutter/bin/flutter`.

| Check | Result |
|---|---|
| `go test -count=1 ./...` in `backend` | PASS — all packages reported passing/no test files |
| AUTH-OTP-01-E2E-R1 focused `go test -count=1 ./internal/auth ./pkg/config ./cmd/api` | PASS — rerun during runtime recovery; no shared database was used |
| `flutter test --no-pub` in `apps/mobile` | PASS — 106 tests |
| Focused `dart analyze lib/core/providers/app_provider.dart lib/core/screens/onboarding_screen.dart test/auth_onboarding_test.dart` | Completed with one pre-existing informational redundant-argument diagnostic in `app_provider.dart`; no errors in the changed OTP screen/provider/test |
| `npm run typecheck` in `apps/admin-web` | PASS |
| `npm run typecheck` in `apps/merchant-web` | BLOCKED — local `tsc` dependency is absent; no successful Merchant typecheck/build claimed |
| Full `flutter analyze --no-pub` | PASS with respect to introduced diagnostics; completed in 134.9 seconds with 18 existing diagnostics (3 warnings, 15 infos), no errors. The one newly exposed integration-test override error was corrected before this rerun. |
| Focused Dart analysis after override correction | PASS for errors; one existing informational redundant-argument diagnostic remains in `app_provider.dart`; no diagnostics in the changed OTP screen, test, or integration-test override |
| Android split-ABI debug build | PASS — x86_64 APK SHA-256 recorded above |
| AVD mapping, install, launch | PASS on all three listed serials |
| Authenticated customer/merchant/rider/admin flow | NOT VERIFIED — no delivery provider/QA OTP run was active; Admin login displayed “Phone verification is currently unavailable” |
| Phase 4D approved-batch simulation/reconciliation | NOT EXECUTED — no authenticated, distinct simulator session; existing UPI/COD batches and allocations were preserved |

The admin and merchant browser pages were not changed to weaken their authentication. The previously open Admin login page in the Codex right-side browser was already closed at the start of this task.

## Changed-file groups

- Go OTP challenge/delivery/configuration, migration 036, and auth tests.
- Flutter login listener, challenge-aware API calls, package lock, and OTP widget tests.
- Admin/Merchant OTP forms and authenticated E2E helpers/specs.
- OpenAPI OTP response/verification contract and QA OTP reader/start scripts.
- `AGENTS.md`, phase index, Phase 4D report, and implementation log.

The repository contains substantial unrelated/uncommitted Phase 4D and earlier QA work. No changes were reverted, and no commit or push was made.

## Acceptance decision

**Historical R1 status (12 November): PARTIAL; superseded by R2 below.** At that point OTP response secrecy, challenge binding, server verification, Android OTP UI, browser autofill semantics, automated checks, APK build, and login-screen launches were verified, but the isolated reader and authenticated role acceptance were not. Phase 4D remained PARTIAL, and Phase 4E/3H were not authorized.

## Next steps

1. Choose and configure an SMS gateway adapter and approved DLT template; calculate the app hash from the actual release signing certificate without exposing a private key.
2. Start a disposable QA API with the private OTP inbox and synthetic-only allowlist, then validate actual OTP entry/login on all three emulators and Admin Web.
3. Provide the isolated Merchant Web dependency installation needed for typecheck/build and run its tests.
4. Authenticate a distinct authorized finance simulator through the legitimate flow; then continue the two existing approved Phase 4D batches without recreating them.

## AUTH-OTP-01-E2E-R1 — Runtime QA Gate 1 inspection (12 November 2026)

**Result: BLOCKED before Gate 2.** This run performed only configuration, schema, network, storage, synthetic-role, and emulator-availability inspection. No OTP request was sent; no new challenge or session was created; no OTP value was read or emitted; existing Phase 4D payment and settlement records were not queried or changed.

### QA isolation and migration evidence

- Existing QA resources: API `grepmind_4c_qa_api` (`127.0.0.1:18083`), Admin `grepmind_4c_qa_admin` (`127.0.0.1:3302`), Merchant `grepmind_4c_qa_merchant` (`127.0.0.1:3301`), MinIO `grepmind_4c_qa_minio`, database `grepmind_3e_qa_db` / database `grepmind_3e_qa` (`127.0.0.1:55432`), network `grepmind_3e_qa_net`. API `/healthz` returned `{"status":"ok"}`.
- Database container has no mounts and uses tmpfs for `/var/lib/postgresql/data`. All five QA containers are attached to the dedicated QA network. Shared `grepmind_postgres` and `aayara-postgres` use different Docker networks; the QA API's `DB_HOST` points only to `grepmind_3e_qa_db`. Thus the active database is disposable and isolated from shared Postgres by container network and storage configuration.
- The API environment reports `APP_ENV=qa`, `OTP_PROVIDER=qa_file`, delivery enabled, and inbox `/run/qa-otp`, but **`QA_OTP_RUN_ID` is absent**. The API inbox tmpfs is `mode=0700,uid=100,gid=100`, not the requested root-owned directory. The existing reader uses Docker `exec`, which grants broader daemon authority rather than a scoped runner capability. These fail the current runner-credential and inbox-owner acceptance checks. I did not use that reader.
- Before applying migration 036, the QA `otp_codes` schema lacked both `purpose` and `invalidated_at`, and the active-challenge index was absent. Per the explicit authorization, `backend/migrations/036_auth_otp_challenge_scope.sql` was applied only to this tmpfs-backed QA database with `psql -v ON_ERROR_STOP=1`; verification showed both columns and `otp_codes_active_challenge_idx`. This database has no `schema_migrations` relation, so migration history is evidenced by the inspected schema rather than a version ledger. Shared databases were not migrated.
- The already allowlisted synthetic QA identities are present and active: suffix `0171` Customer; `0172` Merchant owner (also Customer); `0173` approved Rider (also Customer); `0174`, `0175`, and `0176` Admin (also Customer). Only last-four identifiers are recorded here. No root superadmin was allowlisted or used.
- Source/config inspection confirms the QA file provider is selected only for explicit QA + `qa_file` + delivery-enable configuration, validates a synthetic allowlist and run ID, and has no HTTP retrieval route. OTP verification remains in Go. Normal OTP responses omit the code. The current container's missing run ID means this instance does not demonstrate the current-source QA config; do not request codes through it.

### Runtime gates not executed

- Gate 2 OTP delivery/retrieval and positive/negative verification cases were not run because the current QA inbox fails the requested ownership/runner-capability requirements and the active API lacks a run ID.
- Gates 3–5 (Customer, Merchant, Rider and Admin UI login/role checks) were not run. Windows ADB status failed on both ports 5037 and 5039 with an ADB daemon startup/version handshake error; no process was killed and no emulator data was wiped. The QA Android APK/API target also remains the previously installed build, not a newly validated connection to this QA API.
- No production provider credentials/template are configured, so real SMS Retriever autofill could not be exercised. No attempt was made to use real customer numbers.
- No phase code changed in this closeout pass; the only database change was additive migration 036 on the isolated QA database. QA containers and historical test/finance data were preserved. No settlement action, payment, COD, payout, role grant, or shared/production database change occurred.

### Required recovery before retry

1. Recreate/restart only the named QA API after confirming its isolated network and tmpfs DB, supplying a fresh run ID and test synthetic allowlist; do not touch the DB or shared services.
2. Replace the Docker-daemon OTP reader with the requested scoped, single-use capability and reconcile the root-owned 0700 inbox requirement with access for an unprivileged QA runner. Until that boundary is implemented and reviewed, do not read OTP files.
3. Restore Windows ADB observability using the approved host workflow, then verify actual AVD names before UI login.
4. Rebuild portals from lockfiles if needed; do not upgrade dependencies. Then repeat each role's normal UI challenge flow and negative authorization/replay tests.

R1 ended **PARTIAL**. Migration 036 was applied only to the disposable QA database. Phase 4D remained **PARTIAL**, with its approved settlement batches unchanged; Phase 4E remained unauthorized. R2 results follow.

## AUTH-OTP-01-E2E-R2 — Secure reader and authenticated role acceptance (13 November 2026)

**Result: PASS for isolated QA.** This run replaces the R1 runtime status. Production SMS, live financial operations, and shared/production migration remain outside scope.

### Protected QA reader and isolation

- The existing isolated stack was preserved: API `grepmind_4c_qa_api`, private reader `grepmind_4c_qa_otp_inbox`, Admin/Merchant QA portals, and tmpfs-backed PostGIS `grepmind_3e_qa_db` on `grepmind_3e_qa_net`. Migration 036 is present only in that disposable QA database; shared development and production databases were not changed.
- A fresh unpredictable run ID was generated outside the application and injected into both API and reader. The values matched; only the SHA-256 fingerprint `723a6512169095459f4806f2713755c1754a3b4faa0cf555e7da3b23883b764f` is recorded. No default run ID is used.
- Runtime configuration was `APP_ENV=qa`, `OTP_PROVIDER=qa_http`, and explicit QA delivery enablement. The API runs as UID/GID 100:101; the dedicated inbox helper runs as 0:0 with `/run/qa-otp` owned by 0:0, mode 0700. Challenge records are mode 0600. API, reader, and database have no host mounts and share only the isolated QA network. The database data directory is tmpfs-backed.
- The reader is bound to `127.0.0.1:18085`, is not routed through public Nginx, and an unauthenticated read returned HTTP 401. The API can write only through its authenticated delivery endpoint; the QA runner uses a separate HMAC capability scoped to run, challenge, synthetic phone, purpose, expiry, and runner ID. Reads are atomic and single-use. The API remains unprivileged; no broad Docker-exec OTP reader was used for acceptance.
- The run-scoped tests exercised matching scope, wrong run/challenge/phone/purpose/runner/capability, expiry, missing record, path traversal, symlink, production-mode rejection, non-allowlisted delivery, replay, and concurrent reads. The inbox reader package tests passed in the full Go run. OTP values and credentials were not printed in command output or this report. A post-run check found three expired, mode-0600 records; after verifying all had expired and the root-owned mode-0700 inbox, those records were removed. Final inbox record count was zero and an unauthenticated read still returned 401.

### Authenticated UI acceptance

- Customer Android authenticated through the normal OTP request and verify UI and opened Customer Home.
- Merchant Android authenticated through the normal OTP request and verify UI and opened Merchant Workspace.
- Rider Android authenticated through the normal OTP request and verify UI and opened Rider Dashboard. Backend-approved Rider access and Kuanpal locality were shown; delivery availability remained offline and no GPS state was fabricated.
- Admin Web authenticated as an ordinary synthetic Admin through Windows Chrome at the isolated QA origin. The OTP response contained no `otp_code`; the scoped reader supplied the matching challenge once; a replayed verify request returned HTTP 401. Protected dashboard data and sections loaded, ordinary Admin role-grant control remained disabled, and logout revoked the session.
- No root superadmin was used or added to the allowlist. The flows did not modify finance permissions, settlements, payment records, rider earnings, or COD records.

### Device and browser evidence

The same x86_64 APK was installed on all three dedicated Windows-host emulators and reported versionCode 5000, package `local.grepmind.grepmind_mobile`:

| Role | AVD | ADB serial | Result |
|---|---|---|---|
| Customer | `Pixel_8` | `emulator-5560` | Authenticated Customer Home |
| Merchant | `Pixel_8_Merchant_QA` | `emulator-5558` | Authenticated Merchant Workspace |
| Rider | `Pixel_8_Rider_QA` | `emulator-5556` | Authenticated Rider Dashboard |

APK: `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`  
SHA-256: `19B1C710EBDBDC45C08BAE7142053329AD11A1FBFB1C46EF6F2AC6C42BCE2385`  
Sanitized screenshots: `docs/phases/evidence/auth-otp-01-e2e-r2/customer-workspace.png`, `merchant-workspace.png`, `rider-workspace.png`, and `admin-dashboard.png`.

Windows ADB's non-elevated invocation still failed to start its server handshake on port 5037. The approved elevated Windows-host ADB executable at `D:\emulator\android-sdk\platform-tools\adb.exe` worked; `adb emu avd name` verified all three AVD-to-serial mappings and `dumpsys package` showed versionCode 5000. No emulator processes were killed and no AVD data was wiped. The earlier handshake failure's underlying port/process cause was not conclusively identified.

### Fresh validation

| Check | Result |
|---|---|
| Windows-host `wsl --exec bash -lc 'cd /mnt/d/grepmind-near/backend && go test -count=1 ./...'` | PASS; all reported Go packages passed. No custom integration-test DSN was supplied, so conditional database tests are not claimed as a separate PostGIS suite. The live authenticated flow used the isolated PostGIS API/database. |
| Windows-host WSL `flutter test --no-pub` in `apps/mobile` | PASS — 106 tests. |
| `npm run typecheck` in `apps/admin-web` | PASS. |
| Admin Web authenticated Playwright workflow in Windows Chrome | PASS — 1 test; scoped OTP retrieval, challenge replay denial, protected dashboard/data, role-boundary UI, navigation, logout. |
| `npm run build -- --webpack` in `apps/admin-web` | PASS. Default Turbopack had a local worker-spawn issue in an earlier attempt; Webpack build completed successfully. |
| Merchant Web typecheck/build | Not run: local `tsc.cmd` and `next.cmd` dependencies are absent. No dependency installation was made. |
| Full Flutter analyzer | Not rerun during R2. The prior documented result is 18 existing diagnostics (3 warnings, 15 infos), zero errors; it is historical, not a fresh R2 result. |
| `git diff --check` | Code, test, and phase-document diffs pass. The broader existing `AGENTS.md` worktree diff reports CRLF/trailing-whitespace warnings across its pre-existing uncommitted content; no file-wide reformat was performed. |

### Changed files for R2

- `backend/internal/auth/handlers.go`: normalize challenge expiry to UTC and PostgreSQL microsecond precision, keeping API, persisted challenge, and private inbox expiry equal.
- `backend/internal/auth/security_test.go`: response secrecy, private QA writer behavior, and timestamp precision coverage; `backend/internal/auth/service.go`, `backend/pkg/config/`, `backend/internal/auth/qa_otp_http.go`, `backend/Dockerfile`, `backend/cmd/api/main.go`, and migration 036 provide challenge-scoped delivery/configuration.
- `backend/internal/qaotpinbox/` and `backend/cmd/qa-otp-inbox/`: dedicated root-owned inbox helper, scoped atomic read capability, runtime checks, and security tests.
- Flutter OTP UI/state and tests: `apps/mobile/lib/core/providers/app_provider.dart`, `apps/mobile/lib/core/screens/onboarding_screen.dart`, `apps/mobile/test/auth_onboarding_test.dart`, and the integration-test override. These preserve normal challenge verification, SMS Retriever/manual entry, and no-code response behavior.
- Admin/Merchant OTP forms and E2E: `apps/admin-web/app/login/page.tsx`, `apps/merchant-web/components/AuthLoginView.tsx`, `apps/admin-web/e2e/qa-otp.ts`, `apps/merchant-web/e2e/qa-otp.ts`, and the browser QA configs/specs. Admin E2E verifies the ordinary Admin role boundary and challenge replay denial; its guard checks the scoped HTTP reader rather than the retired container-reader variable.
- `api/openapi.yaml` documents the non-secret challenge response and challenge-aware verification contract.
- `scripts/qa/auth-otp-01-e2e-r2-attach-reader.sh` and `scripts/qa/qa-otp.mjs`: guarded isolated-stack setup, fresh run ID, private runner env, and scoped reader usage.
- Sanitized UI evidence under `docs/phases/evidence/auth-otp-01-e2e-r2/`.

No shared/production migration, real SMS, financial operation, role grant, commit, or push occurred. Phase 4D remains PARTIAL with its existing approved batches untouched; Phase 4E remains unauthorized. Production SMS delivery and Merchant Web build dependencies remain open release items.
