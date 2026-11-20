# Phase 5P.4 — Admin security, browser PIN recovery, and Finance RBAC

## Baseline findings

- Phase 5P.1 remains independently unverified.
- Phase 5P.2 and Phase 5P.3 reports remain PASS for their isolated Admin Web scopes.
- Browser PIN enrollment already used an HttpOnly, Secure, SameSite cookie and bcrypt hash. Replacement was available only through a fresh OTP enrollment response. PIN lockout was enforced after five failures, and OTP could recover a locked or lost browser when the API offered enrollment.
- There was no explicit PIN removal endpoint or audit event, and finance write controls were not driven by a server capability response.

## Implemented changes

- Added OTP-gated `POST /api/v1/auth/admin-mpin/remove`. A PIN-authenticated session cannot remove its own recovery credential. The endpoint deletes the device record, clears the cookie, and writes an `audit_logs` entry.
- Admin OTP verification now returns the enrollment/replacement capability for Admins with or without an enrolled device. This supports browser-loss recovery and PIN replacement without weakening OTP verification, rate limits, or lockout behavior.
- PIN enrollment/replacement now writes an audit event.
- Added `GET /api/v1/admin/finance/capabilities`, derived from the authoritative read and `finance.post` checks. Finance writes continue to enforce permissions on the backend.
- Read-only COD finance views hide remittance review controls. Merchant settlement operations reject presentation-triggered writes before calling the API when `finance.post` is absent, while backend authorization remains authoritative.
- Added OpenAPI documentation and backend lifecycle coverage for PIN removal and finance capabilities.

## Verification

- `go test ./internal/auth ./internal/financialaccess ./internal/financialledger ./internal/payments` passed.
- The isolated Next production build passed.
- TypeScript validation passed.
- OpenAPI YAML parsed successfully.
- Backend Admin PIN lifecycle tests passed for enrollment, replacement, lockout, OTP recovery, removal, cookie invalidation, and audit records.
- Existing isolated QA services were healthy during implementation.

## Browser closure evidence

- The first failure was caused by Playwright reusing the Docker Admin portal on port `3000`, which served an older client bundle. The mocked OTP response contained `admin_mpin_enrollment_available: true`, while the stale bundle navigated directly to the dashboard.
- Running the modified lifecycle against the fresh isolated production build on `18306` passed enrollment, repeat PIN sign-in, OTP re-entry, PIN removal, and return to the phone screen.
- Phase 5P.4R.1 confirmed that dashboard error was an isolated image mismatch: the fresh Admin build called `/api/v1/admin/finance/capabilities`, while the disposable API still used `phase5p3-local` and returned 404. Rebuilding as `phase5p4-local` restored 200 responses and live dashboard rendering.
- The subsequent persistent-profile rerun was blocked before authentication by a disposable OTP inbox restart/readiness configuration (503/429). The close/reopen browser assertion remains unverified against live QA.
- Phase 5P.4R.2 repaired the QA-only helper by restoring its root-owned mode-0700 tmpfs mount and synchronizing the allowlist with the API container. OTP requests then returned 202 with the expected run/runner binding. The persistent test still stalled after the dashboard rendered, so the full close/reopen and finance-navigation acceptance remains unverified.

## Status

**PARTIAL.** The implementation, backend security checks, isolated mocked lifecycle, and finance RBAC checks are complete. The dashboard API mismatch and OTP helper readiness/allowlist defects are fixed in the disposable stack, but persistent Chrome close/reopen plus Finance Overview/Payment Tracking browser acceptance remains unverified because the Playwright flow still stalls after dashboard rendering. No production or shared database was changed, no migration was applied, and no deployment was performed. Phase 5P.1 remains independently unverified.
