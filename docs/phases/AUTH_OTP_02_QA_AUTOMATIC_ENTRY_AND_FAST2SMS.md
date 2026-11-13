# AUTH-OTP-02 — QA Automatic OTP Entry and Fast2SMS Status

**Date:** 13 November 2026
**Result:** **PASS for isolated QA automatic entry**
**Native Android SMS Retriever:** Not tested with a real SMS
**Fast2SMS production delivery:** Adapter implemented and mock-tested; not configured or live-tested

## Scope and safety

This acceptance verifies that a trusted QA runner retrieves the one fresh code for each challenge from the existing private QA inbox and enters it in the normal Customer, Merchant, Rider, or Admin login UI. The app and browser still submit the code and challenge ID to the Go verification endpoint. No OTP bypass, fixed code, token injection, production identity, settlement, or financial operation was used.

The isolated QA API and inbox were already configured with `APP_ENV=qa`, `OTP_PROVIDER=qa_http`, explicit delivery enablement, a matching per-run ID, synthetic allowlisting, and the protected root-owned inbox. Migration 036 was already applied only to the disposable QA database by the prior AUTH-OTP-01 runtime acceptance; it was not applied again here. Shared development and production databases were not changed. Phase 4D remains PARTIAL, and Phase 4E remains unstarted.

## Implementation

- `apps/mobile/lib/core/providers/app_provider.dart` exposes only `challenge_id` and `expires_at` to a debug-only test runner when the explicit `QA_OTP_AUTOMATION` Dart define is enabled. It never logs or returns the OTP.
- `scripts/qa/auth-otp-02-windows-ui.ps1` drives the actual app through Windows-host ADB, gets challenge metadata from logcat, invokes the existing private scoped reader through WSL, enters the one-time code into the real Flutter OTP field, and presses the ordinary Verify control. It validates the resulting role workspace and captures only the post-login screen. Its explicit `-ManualEntry` mode instead displays the newly retrieved code once in the trusted local PowerShell console for a human to type into the already-open OTP screen; it does not expose the code in app UI, API responses, files, or application logs.
- `scripts/qa/qa-otp-read-scope.mjs` reads one exact challenge scope using the existing QA reader helper. The code is held only in the runner process/input path and is not printed to logs or saved to a file.
- `apps/admin-web/e2e/auth-otp-02.admin.spec.ts` uses Windows Chrome and Playwright to request a normal OTP, verifies the ordinary response contains no `otp_code`, retrieves only the scoped challenge, fills the actual one-time-code field, verifies through the normal API, checks replay rejection, confirms the protected dashboard, and logs out.
- Rider Profile previously had no logout action. `apps/mobile/lib/core/screens/rider_workspace_screen.dart` now offers a confirmed normal logout, and `apps/mobile/test/workspace_navigation_test.dart` verifies that logout clears the authenticated state. This enabled the required fresh Rider challenge without clearing app data.

The QA instrumentation is debug-only, requires an explicit build define, and logs challenge metadata only. Do not ship an APK built with `QA_OTP_AUTOMATION=true` as a release artifact. Manual console mode is restricted to this trusted Windows QA runner, the protected one-time reader, and synthetic allowlisted identities; it does not change backend verification or production SMS behavior. Example customer invocation (run locally from the project root, not through Codex output): `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\qa\auth-otp-02-windows-ui.ps1 -Role customer -Serial emulator-5560 -ManualEntry`.

## Windows ADB and emulator identity

All ADB operations used the installed Windows SDK executable `D:\emulator\android-sdk\platform-tools\adb.exe`. The AVD-to-serial mapping was verified with `adb devices -l` and `adb -s <serial> emu avd name`:

| Role | AVD | Serial | APK install |
|---|---|---|---|
| Customer | `Pixel_8` | `emulator-5560` | PASS |
| Merchant | `Pixel_8_Merchant_QA` | `emulator-5558` | PASS |
| Rider | `Pixel_8_Rider_QA` | `emulator-5556` | PASS |

Read-only diagnostics found Windows ADB 1.0.41 / platform-tools 37.0.1, with separate server processes present on ports 5037, 5038, and 5039. The default Windows ADB server successfully enumerated all three devices and completed installs and UI automation. No ADB process was killed and no emulator data was wiped. The cause of the earlier handshake failures was not conclusively isolated; the issue did not block this acceptance using the elevated Windows-host ADB path.

## APK identity

Built from WSL using the existing Flutter 3.47.8 SDK and isolated QA API base `http://10.0.2.2:18083`:

```text
wsl.exe --exec bash -lc 'cd /mnt/d/grepmind-near/apps/mobile && /home/grepmind/projects/flutter-setup/develop/flutter/bin/flutter build apk --debug --split-per-abi --no-pub --build-number=7 --dart-define=API_BASE_URL=http://10.0.2.2:18083 --dart-define=QA_OTP_AUTOMATION=true'
```

- APK: `apps/mobile/build/app/outputs/flutter-apk/app-x86_64-debug.apk`
- SHA-256: `4D492CABC6FC244A85E2D54C7859CEB2B76751A45F61A917A1EB7DCCCE24200C`
- Installed package: `local.grepmind.grepmind_mobile`
- Installed `versionCode`: `4007`; `versionName`: `1.0.0`
- The same APK hash and version were installed successfully on all three assigned emulators with `adb install -r`.

## Authenticated UI acceptance

The final sequence completed four fresh-challenge logins: Customer, Merchant, Rider, then Admin. In every case the runner—not a person—retrieved the scoped OTP and entered it into the actual UI; the backend verified it normally.

| Role | Surface | Fresh challenge and automated entry | Result |
|---|---|---:|---|
| Customer | Pixel 8 / `emulator-5560` | Yes | PASS — Customer Home shown |
| Merchant | Pixel 8 Merchant QA / `emulator-5558` | Yes | PASS — Merchant Workspace shown |
| Rider | Pixel 8 Rider QA / `emulator-5556` | Yes | PASS — approved Rider Dashboard shown |
| Admin | Windows Chrome, `http://localhost:3302` isolated Admin portal | Yes | PASS — protected Admin Dashboard shown; normal logout completed |

Admin Playwright result: `1 passed`. The test asserts HTTP 202 for OTP request, absence of `otp_code` in the response, HTTP 200 for normal verification, authenticated dashboard content, HTTP 401 for replay, and logout to the login page. It does not print the challenge OTP or session token.

Screenshots, captured only after authentication:

- [Customer Home](evidence/auth-otp-02/customer-workspace.png)
- [Merchant Workspace](evidence/auth-otp-02/merchant-workspace.png)
- [Rider Dashboard](evidence/auth-otp-02/rider-workspace.png)
- [Admin Dashboard](evidence/auth-otp-02/admin-dashboard.png)

No OTP values appear in the screenshots. Intermediate diagnostic captures containing synthetic account details were removed.

## Security and negative-test evidence

Fresh Go test runs passed for `./internal/auth`, `./internal/qaotpinbox`, and `./pkg/config`; the full Go suite also passed during this task. The QA inbox tests exercised unauthorized/wrong runner and capability, wrong challenge scope, non-allowlisted delivery, expired/missing/symlink records, concurrent one-time consumption, owner-only directory enforcement, and rejection outside QA or with an unprivileged inbox owner. Auth tests cover fail-closed production requests, OTP expiry/replay, challenge mismatch and resend invalidation where the PostgreSQL integration test DSN is available. PostgreSQL session lifecycle tests that require `GREPMIND_TEST_DATABASE_URL` were not claimed as run by the package-only test invocation. The live Admin UI test additionally observed replay rejection and the normal response's lack of an OTP field.

No fixed OTP, SMS inbox permission, QA-reader HTTP exposure through Nginx, root-superadmin allowlist, fabricated session, or OTP bypass was introduced. The runner credentials remained in the protected QA environment and process memory; no secret values are recorded in this report. The optional manual mode intentionally reveals one short-lived synthetic QA code only to the local trusted operator console after a normal request and scoped read; never capture that console in a transcript or screenshot.

## Automated checks

| Command/check | Result |
|---|---|
| `go test -count=1 ./...` (backend) | PASS |
| `go test -count=1 ./internal/auth ./internal/qaotpinbox ./pkg/config` (backend) | PASS |
| `flutter test --no-pub` | PASS — 106 tests |
| `flutter analyze --no-pub` | 18 diagnostics (3 warnings, 15 infos), exit 1; matches documented baseline, no new diagnostic from this change |
| APK debug split-ABI build | PASS — x86_64 APK recorded above |
| Admin `npm run typecheck` (WSL) | PASS |
| Admin `npm run build -- --webpack` (WSL) | PASS — Next.js 16.4.5 production build |
| Admin Playwright OTP E2E (Windows Chrome) | PASS — 1 test |
| Merchant TypeScript (`node node_modules/typescript/bin/tsc --noEmit`, WSL) | PASS |
| Merchant production build | BLOCKED by environment dependencies: WSL `node_modules` contains Windows SWC binaries and no Linux SWC; Windows build attempted to fetch `@next/swc-win32-x64-msvc` but DNS to `registry.npmjs.org` failed. No dependency install or source/config change was made. |
| PowerShell runner parse, Node helper syntax, targeted `git diff --check` | PASS |

The Rider widget test is included in the passing full Flutter suite. No backend or database schema code changed during this task.

## SMS Retriever and Fast2SMS (separate from QA autofill)

- **QA automatic OTP entry:** PASS for four role surfaces as documented above.
- **Android SMS Retriever:** NOT TESTED with a real SMS. The app contains `CodeAutoFill`/`listenForCode()`, the one-time-code autofill hint, and manual entry fallback, but the QA HTTP inbox does not deliver an SMS and cannot prove the native SMS Retriever callback.
- **Fast2SMS:** The Go provider adapter exists at `backend/internal/auth/fast2sms.go`; automated tests use a mock HTTP server and verify the provider request, error handling, timeout/no-retry behavior, malformed payload handling, and no secret forwarding on redirect. Production API credentials/template are not configured here, and no real Fast2SMS request or SMS delivery was performed.

## Changes and remaining limits

Changes for this acceptance are limited to debug challenge metadata instrumentation, the Windows QA UI runner and scoped reader CLI, the Admin Playwright flow, the Rider Profile logout action/widget assertion, and this documentation/evidence. Existing unrelated dirty files and previously approved Phase 4D settlement records were preserved. No migration, production/shared database, order, payment, refund, COD, payable, settlement, rider earning, or payout was changed. No commit or push was made.

**Final status: AUTH-OTP-02 PASS for isolated QA automatic entry.** Native SMS Retriever and real Fast2SMS delivery remain unverified. Merchant production build is environment-blocked, although Merchant typecheck passed. Phase 4D remains PARTIAL; Phase 4E remains unstarted.

## AUTH-OTP-02-E2E-R3 final automatic-entry retest (13 November 2026)

This is a fresh, narrowly scoped retest after the runner's fresh-challenge guard was added. It does not reuse the historical four-role PASS above. Automatic mode was used throughout; `-ManualEntry` was not selected and no OTP was printed, copied into a report, or entered by a person.

| Role | Result | Evidence |
|---|---|---|
| Customer | **PASS** | `auth-otp-02-windows-ui.ps1 -Role customer -Serial emulator-5560` completed with a fresh challenge, automatic entry, normal backend verification, and Customer Home visible on AVD `Pixel_8`. |
| Merchant | **BLOCKED** | The runner stopped during Windows ADB initialization before app interaction or OTP request. Direct `D:\emulator\android-sdk\platform-tools\adb.exe start-server` also failed its server handshake on port 5037. No retry of the Merchant login was made. |
| Rider | **NOT RUN** | Stopped after the shared Windows ADB daemon failure; no OTP request was made. |
| Admin Web | **NOT RUN** | The Windows-host `wsl.exe --exec bash -lc ...` invocation used to access the protected run-scoped QA reader configuration returned `Wsl/Service/E_ACCESSDENIED`. No Admin OTP request was made in this retest. The prior Admin 429/503 outcomes remain historical diagnostics and were not retried. |

The ADB checks used the installed Windows SDK executable at `D:\emulator\android-sdk\platform-tools\adb.exe`. Read-only process and TCP-listener inspection found no visible `adb`, emulator, or QEMU process and no listener on ports 5037/5039 at inspection time. `Get-CimInstance Win32_Process` was denied by the host execution policy, so process ownership beyond accessible PowerShell process/network views could not be established. No process was terminated and no emulator data was wiped. The successful Customer run proves ADB was available for that invocation; its later daemon failure is an intermittent host/runtime condition, not evidence of an application authentication defect.

The OTP request limiter remains unchanged: source inspection shows IP-keyed `request-ip` (20 requests per minute), phone-keyed `request-phone` (5 per hour), plus a database per-phone limit of 5 per hour and a default 60-second resend cooldown. A generic 429 response does not expose a limiter key or `Retry-After`; therefore the cause of the earlier Admin 429 cannot be attributed to a specific bucket from available evidence. The current QA API/inbox health and matching run configuration were previously observed healthy, but the R3 Windows host could not enter WSL to recheck them or perform the Admin reader flow. No counters, accounts, or protections were changed.

Current validation:

- Focused Go auth/QA-reader/config tests: `go test -count=1 ./internal/auth ./internal/qaotpinbox ./pkg/config` — **PASS** (run through the approved WSL route earlier in this validation session, before the subsequent Windows-host WSL denial).
- Windows ADB customer auto-entry: **PASS** for `Pixel_8` / `emulator-5560`.
- Windows ADB Merchant auto-entry: **BLOCKED** before app interaction.
- Windows ADB Rider auto-entry: **NOT RUN** after the shared ADB failure.
- Admin Playwright auto-entry: **NOT RUN** because the protected QA reader run environment could not be reached; no login/OTP request was attempted.
- PowerShell runner syntax validation: **PASS**.
- Targeted whitespace check with CRLF-aware Git settings: **PASS**.

**R3 recommendation: PARTIAL.** The Customer fresh-login flow passed on the current automatic runner. Merchant, Rider, and Admin have not all passed after the latest runner change, so AUTH-OTP-02 does not meet the four-role acceptance gate. Native SMS Retriever and live Fast2SMS remain separate and untested. No authentication, finance, payment, settlement, shared-database, or production state was changed; no commit or push was made.

## User-requested sequential retest

A later sequential rerun was performed from Windows PowerShell using the assigned emulators and the same isolated QA API. The first Customer attempt exposed a PowerShell 5.1 runner issue: successful ADB `monkey` output on stderr was treated as terminating. `Invoke-Adb` now tolerates native stderr text while still checking the actual ADB exit code. Customer then passed; Merchant and Rider also passed in sequence, each using a new challenge and reaching the expected authenticated workspace. The three role screenshots above were refreshed after login.

Admin did not pass this rerun. The first Playwright invocation was incorrectly scoped and enumerated the full Admin E2E suite; it encountered OTP throttling/transport failures in unrelated live tests. A corrected discovery check confirmed the targeted command selects exactly one AUTH-OTP-02 test. That targeted test reached the real Admin login page, but the normal OTP request returned HTTP 429 (`RATE_LIMITED`) before a challenge was created or read. No retry, cooldown reset, alternate identity, or rate-limit bypass was attempted. The Admin dashboard screenshot above is from the earlier accepted run, not this rerun.

**Sequential retest result:** The earlier post-runner-fix sequence had Customer, Merchant, and Rider PASS. Admin was not reverified: the first synthetic Admin identity returned HTTP 429 (`RATE_LIMITED`) before challenge creation, and a single later attempt with an authorized synthetic Finance reviewer returned HTTP 503 from the QA OTP request, also before challenge creation. A subsequent Customer attempt stopped before reader access because the runner could not confirm both a newly generated challenge and the actual OTP screen. The runner was then hardened to ignore challenge IDs already present in logcat and to require a fresh, unexpired challenge plus the OTP UI before reading. That final guard change received PowerShell syntax and whitespace checks only; it has not yet received another live emulator run. No further OTP attempts or limit changes were made. The earlier four-role pass remains the original acceptance evidence; it must not be confused with a complete four-role pass after the latest runner change. Investigate the isolated QA delivery path and retry only the dedicated role checks when normal request conditions permit.

## AUTH-OTP-02-E2E-R4 host recovery and final acceptance (13 November 2026)

### Host recovery

Read-only diagnostics through the low-integrity command bridge showed PowerShell 7.6.9 at Low Mandatory Level, with Administrators marked deny-only. The same bridge returned `Wsl/Service/E_ACCESSDENIED` for `wsl.exe --status` and `--list --verbose`. The host-approved execution path then succeeded without changing Windows policy, WSL configuration, or distribution state: Ubuntu was Running on WSL 2, `wsl.exe --exec bash -lc ...` reached `/mnt/d/grepmind-near` as user `grepmind` (UID 1000), and the QA container checks completed. This establishes that the earlier WSL error was specific to the restricted command-bridge execution context; it was not a failed Ubuntu distribution.

Windows ADB was `D:\emulator\android-sdk\platform-tools\adb.exe`, version 1.0.41 / platform-tools 37.0.1. In the host-approved context, ADB listed all three devices as `device` and `emu avd name` confirmed:

| Role | AVD | Serial | Installed package |
|---|---|---|---|
| Customer | `Pixel_8` | `emulator-5560` | `local.grepmind.grepmind_mobile`, versionCode 4007 / versionName 1.0.0 |
| Merchant | `Pixel_8_Merchant_QA` | `emulator-5558` | Same package/build |
| Rider | `Pixel_8_Rider_QA` | `emulator-5556` | Same package/build |

Three ADB server processes owned by the current Windows user were observed using that same executable, on server ports 5037, 5038 and 5039. ADB operations failed in the low-integrity bridge but succeeded in the host-approved context, including emulator enumeration and the UI runner. No process was stopped, no ADB key was changed, and no emulator was wiped. The observed execution-context difference explains why host-approved calls worked; the presence of multiple server instances is recorded as an operational complication, not asserted as the sole cause of the initial handshake failure.

### QA reader and rate-limit checks

Before attempting new Admin authentication, the protected runner environment file was confirmed mode 0600; its run ID matched both isolated QA API and inbox configuration; the API was in QA `qa_http` mode with delivery enabled; the OTP inbox was owned by root with mode 0700; and the loopback reader health check returned HTTP 204. No OTP was read during these checks. The QA synthetic Admin account had zero OTP rows created in the preceding hour and its last recorded request was 7,607 seconds old, so the configured database cooldown had expired before the single Admin test.

Source inspection confirms the configured request gates: process-local IP limit 20/minute, process-local phone limit 5/hour, database per-phone limit 5/hour, and default resend cooldown 60 seconds. The generic 429 response does not expose which limiter fired or a `Retry-After` value, so the historical Admin 429 cannot be attributed to one specific bucket. The earlier 503 was not reproduced in R4; the synthetic Admin's fresh request returned success. No counters were reset, no alternate Finance identity was used, and no rate-limit configuration was changed.

### Fresh automatic login results

The existing runner was used in default automatic mode; `-ManualEntry` was not selected. OTP values remained in the protected runner flow and were not printed, manually typed, or included in screenshots.

| Role | R4 result | Evidence |
|---|---|---|
| Customer | **PASS** | A fresh challenge was entered by the runner and normally verified; Customer Home opened on `Pixel_8` / `emulator-5560`. |
| Merchant | **PASS** | After signing out through the app's ordinary top-level Profile → Log out confirmation, a fresh challenge was automatically entered and normally verified; Merchant Workspace opened on `Pixel_8_Merchant_QA` / `emulator-5558`. No APK or app source change was needed. |
| Rider | **PASS** | Android displayed the ordinary system “isn't responding” dialog. Choosing “Wait” restored the normal login UI. The automatic runner was then run with `-KeepAppRunning`, which first verifies that the standard login screen is visible and skips app relaunch only in that case. It requested a fresh challenge, retrieved the matching OTP through the scoped reader, entered it in the real UI, submitted normal verification, and opened Rider Workspace on `Pixel_8_Rider_QA` / `emulator-5556`. No OTP was retrieved before the login UI check. |
| Admin | **PASS** | Dedicated Windows Chrome Playwright test: `1 passed`. The synthetic Admin requested one fresh challenge, the runner filled the actual OTP field, normal verification succeeded, replay returned 401, the protected dashboard opened, and normal logout completed. The test asserted that the ordinary OTP response contained no `otp_code`. No Finance reviewer or superadmin was used. |

Authenticated screenshots from this retest: [Customer](evidence/auth-otp-02/customer-workspace.png), [Merchant](evidence/auth-otp-02/merchant-workspace.png), [Rider](evidence/auth-otp-02/rider-workspace.png), and [Admin](evidence/auth-otp-02/admin-dashboard.png).

The initial host-approved Merchant and Rider runner attempts began with earlier authenticated sessions and did not reach fresh login. Inspection showed that Merchant has separate nested business-profile and workspace-profile destinations; normal logout is under the workspace's top-level **My Profile** screen. The runner now resolves matched labels to their nearest clickable ancestor and explicitly targets `Profile Tab 5 of 5` to avoid the nested Merchant Profile tab. PowerShell syntax validation passed after this runner adjustment. Merchant was then signed out through its normal UI and its fresh automatic login passed. The updated runner branch that automatically navigates an already-authenticated session to the top-level Profile and logs out has not yet been rerun end-to-end; this is an automation convenience gap, not a failed authentication gate.

Rider initially encountered Android's system not-responding dialog during app relaunch. Choosing the ordinary **Wait** action restored the standard login screen. The fail-closed `-KeepAppRunning` option confirmed that screen before requesting a new challenge, then completed the fresh automatic login. This recovered the UI test path without changing app authentication, weakening security, or retrieving an OTP before the login screen was verified.

### Commands and checks

- Host WSL diagnostics: `wsl.exe --status`, `wsl.exe --list --verbose`; then `wsl.exe --exec bash -lc 'cd /mnt/d/grepmind-near ...'` — **PASS in host-approved context; E_ACCESSDENIED in low-integrity bridge**.
- ADB identity: `adb devices -l` and `adb -s <serial> emu avd name` for each required serial — **PASS** in host-approved context; all three required AVD mappings confirmed online.
- Existing package version inspection on all three emulators — **PASS**, all versionCode 4007 / versionName 1.0.0. No APK was rebuilt or reinstalled because mobile application source was not changed.
- Focused Go tests: `go test -count=1 ./internal/auth ./internal/qaotpinbox ./pkg/config` — **PASS** through the recovered WSL host path.
- Admin Playwright: `npm.cmd exec -- playwright test -c playwright.codex.local.config.ts e2e/auth-otp-02.admin.spec.ts` — **PASS, 1 test**.
- PowerShell parser for `scripts/qa/auth-otp-02-windows-ui.ps1` — **PASS**.
- Scoped README diff check and updated-report trailing-whitespace check — **PASS**.

No mobile source change remains from this R4 run, no APK was produced, and no Flutter suite was rerun. The transient Merchant logout UI patch attempted during diagnosis was reverted; there is no retained mobile app modification from that attempt. The runner's target-selection adjustment and fail-closed `-KeepAppRunning` option remain and received PowerShell syntax validation. No OTP bypass, reader credential change, rate-limit bypass, migration, finance operation, settlement simulation, shared/production change, commit, or push occurred.

**R4 recommendation: PASS for isolated QA automatic entry.** Fresh unattended automatic login passed for Customer, Merchant, Rider, and Admin through each real UI and normal backend verification. Rider's recovered login screen was confirmed before the runner requested an OTP. Native Android SMS Retriever and real Fast2SMS delivery remain untested and are not established by QA runner entry. AUTH-OTP-01 isolated QA remains accepted; Phase 4D remains PARTIAL; Phase 4E remains unauthorized.

### Admin Playwright invocation follow-up (13 November 2026)

The direct Playwright command can report a skipped test when its process lacks `E2E_ADMIN_PHONE_E164`, `QA_OTP_READER_URL`, or `QA_OTP_RUN_ID`; the Playwright config has no global setup to load the protected WSL runner environment. Added `scripts/qa/auth-otp-02-admin-playwright.ps1` to load the existing scoped reader settings into the Playwright child process without printing them, and to use the loopback isolated Admin origin. The wrapper preserves the spec's skip guard and clears/restores environment variables after execution. PowerShell parsing passed and the wrapper ran the Admin E2E in both modes: **1 test passed headless and 1 test passed with `-Headed`**, each with a fresh challenge, scoped automatic OTP entry, normal backend verification, replay rejection, dashboard assertion, and logout. Use `scripts/qa/auth-otp-02-admin-playwright.ps1` from Windows PowerShell for repeatable Admin validation; add `-Headed` to watch the configured Chrome window, while the default remains headless. Native SMS Retriever and Fast2SMS remain untested.

### Headed Admin rerun rate-limited (13 November 2026)

The user ran `scripts/qa/auth-otp-02-admin-playwright.ps1 -Headed` again from Windows PowerShell. Visible Chrome launched, but the Admin login OTP request returned HTTP 429 (the test expected 202). The run stopped before a new challenge was created; it did not retrieve or enter an OTP and did not authenticate. This is a rate-limit response, not evidence that headed browser launch or OTP autofill failed.

Source inspection shows request limits of 20 per source IP per minute and 5 per phone per hour in the API process, plus a database per-phone maximum of 5 requests per hour and a default 60-second resend cooldown. The API uses the same generic 429 response and does not identify the bucket or provide `Retry-After`, so the exact 429 source cannot be determined from the response. A read-only query of `otp_codes` for the synthetic Admin showed 5 challenge rows in the previous hour; the latest was 3 minutes 38 seconds old. This establishes that the database hourly limit is currently exhausted. No retries, counter resets, configuration changes, OTP reads, or financial actions were performed. Wait for the natural rate-limit window to expire before the next attempt; do not rotate accounts or bypass the limit.

The user retried and received the same HTTP 429 before challenge creation. A later read-only calculation found the same five rows still inside the one-hour database window. The oldest expires from that rolling window at `2026-11-13 08:11:28 UTC` (about 40 minutes after the query); that is the earliest estimated database-quota release, not a guarantee that the separate API IP/phone buckets or edge limiter have also cleared. Do not retry until that time has passed; then make only one request and stop if it is still limited.

### Explicit Admin manual-entry fallback

Added optional `-ManualEntry` to `scripts/qa/auth-otp-02-admin-playwright.ps1`. It must be combined with `-Headed`; after a successful fresh OTP request, the Playwright runner obtains the challenge-bound code through the existing scoped single-use reader and displays it in the invoking PowerShell output. The operator types it into the visible real Admin OTP field, and the test continues through normal Go verification, replay rejection, dashboard assertion and logout. The default remains fully automatic and never prints the code. Manual mode cannot create an OTP while the server returns 429 and does not bypass or reset any rate limiter. PowerShell parsing and Admin TypeScript typecheck passed; live manual-mode acceptance is pending natural cooldown expiry.

The user's first `-Headed -ManualEntry` invocation returned HTTP 429 at the same OTP request assertion, before the manual-mode code-display branch. A read-only timestamp query still shows 5 challenges in the rolling hour, with estimated database quota release at `2026-11-13 08:11:28 UTC` (about 32 minutes after this query). No OTP was generated/read for this invocation and no limiter state was changed. This confirms manual entry cannot help until the server accepts a new challenge.

At the Phase 4D recovery checkpoint, the same five challenge rows remained in the rolling hour; the database quota release estimate remained `2026-11-13 08:11:28 UTC` (about 24 minutes after that query). No OTP request or value read was made during this check.
