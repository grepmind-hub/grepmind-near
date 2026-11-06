# Phase 0B — Runtime validation and CI baseline

**Evidence date:** 5 November 2026 cross-platform audit
**Purpose:** Capture executable local checks and environmental blockers after the repository audit.
**No production operations, real payments, production SMS, destructive database commands, or production migrations were performed.**

## Results recorded at the baseline

| Check | Recorded result |
|---|---|
| `go test -count=1 ./...` in WSL/backend | PASS — all Go packages |
| PostgreSQL-backed `TestOwnershipAndTenantRoutes` | PASS — disposable schema; ownership, availability/capacity, rescheduling, cancellation, and tenant checks |
| Flutter test suite | PASS — 53 tests at that date; superseded by Phase 1's later 58-test run |
| Flutter analyzer | NOT CLEAN — 119 diagnostics at that date, including warnings and informational lints |
| Docker Compose services and health checks | PASS for local availability check; the audit captured PostgreSQL, API, MinIO, Nginx, worker, and both portals running |
| Read-only database inspection | PASS — local development counts/schema inspected; not production data |
| API health and unauthenticated merchant access | PASS — `/healthz` healthy and protected merchant endpoint returned 401 |
| Merchant/admin Playwright E2E | BLOCKED before useful application assertions by missing browser/runtime and, for admin, missing fixture-phone configuration |
| Next.js portal builds | FAIL due to unavailable/missing platform build dependency and DNS/network resolution; no successful build was claimed |
| Android emulator in that audit | BLOCKED — Windows ADB startup handshake failure; no emulator pass was claimed there |
| Migration strategy | GAP — no migration ledger/runner was found; no migration was executed by this audit |
| Database backup/restore | GAP — no scheduled repository backup/restore flow or restore drill was found |

Full commands and caveats are preserved in [AUDIT_TEST_RESULTS.md](../project-audit/AUDIT_TEST_RESULTS.md).

## Later evidence and supersession

On 6 November, Playwright Chromium was installed into the Windows user browser cache. Merchant portal E2E then passed 3/3; Admin portal E2E passed 2 tests and skipped its credential-dependent authenticated-admin case because `E2E_ADMIN_PHONE_E164` was not configured. This resolves the earlier missing-browser startup blocker for those runs, but does not prove the skipped authenticated Admin flow. Admin dependency installation also reported 8 moderate audit findings. No later successful Next.js production build is recorded here.

Phase 1 validation on 6 November superseded the old mobile test/build/emulator status: 58 Flutter tests passed and the latest debug APK built, installed, and was exercised on `emulator-5554` using the existing WSL Flutter SDK and Windows emulator helper. The analyzer still reported 119 diagnostics. The migration-runner and backup/restore gaps remain.

The previously observed `Wsl/Service/E_ACCESSDENIED` and ADB startup errors were environment/process-bound in the validated runs: the existing helper succeeded from an authorized Windows process. The earlier SDK-path investigation also confirmed the intended WSL Flutter/Linux Android SDK setup and corrected login-shell PATH handling; Windows Flutter was not installed and Android signing configuration was preserved. No firewall or signing-key changes were made.

## Baseline limitations

- Browser E2E coverage was not proven by the blocked runs.
- No production provider credentials or service delivery were tested.
- Local DB table counts are point-in-time development evidence and should not be reused as current counts.
- Phase 1 only proved merchant workspace entry for a test account with no assigned business; it did not prove merchant catalog persistence for that account.
