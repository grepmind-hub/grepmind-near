# Phase 5B.4C — Controlled QA execution

**Status on 16 November 2026 — PARTIAL. Read-only preflight completed. Fixture execution could not start.**

## Verified at runtime

- Docker inspection showed `grepmind_4c_qa_api`, `grepmind_4c_qa_otp_inbox`, and `grepmind_3e_qa_db` on `grepmind_3e_qa_net`, with only those three endpoints attached. Their published ports were loopback-only (18083, 18085, and 55432).
- PostgreSQL reported database `grepmind_3e_qa` and data directory `/var/lib/postgresql/data`. Docker reported a tmpfs at that destination and no persistent database mounts. API and OTP inbox health returned HTTP 200 and 204, respectively.
- A read-only PostgreSQL transaction counted zero rows in `merchant_payable_snapshots`, `rider_earning_entries`, `cod_collections`, and `payout_transfers`. The preliminary connection using an assumed PostgreSQL role failed. The check succeeded using the container's configured role and database.
- The API container used `APP_ENV=qa` and `OTP_PROVIDER=qa_http`. The first comparison used the identity list in the 5B.4B report. The follow-up below uses the executable plan in source. `timeout 5s adb devices -l` exited 124 with no device list, so no AVD mapping was established in this session.

## Execution blockers

- `--execute` and `ScenarioRunner.ExecuteScenario` both terminate without invoking a workflow. The CLI inspection path also supplies a hardcoded tmpfs value and no database handle. Its schema list expects `rider_earnings_entries`, while the live schema has `rider_earning_entries`.
- The Go OTP adapter requests a challenge-only GET endpoint. The deployed protected reader uses a capability-authenticated POST to `/v1/read` bound to the runner, run, challenge, phone, purpose, and expiry. The existing `scripts/qa/qa-otp.mjs` implements that protocol. The fixture runner needs this protocol and matching allowlisted synthetic principals before login can be attempted.

Resume by wiring executable domain scenarios, binding verification to the live API configuration and database, and provisioning the synthetic principals through the isolated QA setup. Verify scoped authentication and feature/provider settings before the first fixture write.

No OTP requests, fixture mutations, flag changes, migrations, APK installations, or ledger acceptance checks were performed. Phase 5B remains PARTIAL. Phase 5B.5 has yet to start.

## Windows-host ADB follow-up

The Windows SDK executable at `D:\emulator\android-sdk\platform-tools\adb.exe` successfully ran `devices -l`. All three listed emulators were in the `device` state. Individual `emu avd name` queries confirmed the current assignments:

| Role | AVD | Actual serial |
| --- | --- | --- |
| Customer | `Pixel_8` | `emulator-5554` |
| Merchant | `Pixel_8_Merchant_QA` | `emulator-5556` |
| Rider | `Pixel_8_Rider_QA` | `emulator-5558` |

This resolves the earlier AVD identification gap. No installation or login was attempted. The fixture runner and QA OTP allowlist blockers remain open.

## Runner implementation follow-up

The CLI now performs a read-only preflight using the actual Docker metadata, QA API and OTP inbox settings, and a read-only connection to the PostgreSQL instance configured for the API. The check verifies the database path against the container tmpfs, requires live financial flags to be disabled in PostgreSQL, checks the required schema, and checks both service health endpoints. The inspector uses the live table name `rider_earning_entries`.

The Go login adapter now uses the protected reader's scoped `POST /v1/read` protocol before submitting normal OTP verification. A local HTTP test exercised the actual inbox handler and verified rejection of a replayed reader capability.

The previous allowlist finding used the numbers printed in the 5B.4B report. Comparing the running containers with `DefaultSyntheticIdentityPlan` in source found six of eight planned identities on both allowlists. No allowlists were edited and no live challenge was requested.

Targeted Go tests and vet passed, and the CLI preflight passed against the running isolated QA stack. Scenario workflow execution remains unwired, and the CLI still refuses `--execute`. No fixtures were created.
