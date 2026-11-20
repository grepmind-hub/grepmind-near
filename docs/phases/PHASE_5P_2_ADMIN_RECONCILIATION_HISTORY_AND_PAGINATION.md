# Phase 5P.2 — Admin reconciliation queue, history, and pagination

## Starting point

The checkout was on `dev-antigravity` with existing uncommitted work. The phase index, implementation log, Phase 5E report, and browser PIN report were reviewed. No Phase 5P.1 acceptance report or register entry was found. Browser PIN persistence has independent QA evidence. Permission-aware finance controls are unverified as a complete Phase 5P.1 gate. Phase 5P.2 proceeds independently using the existing Admin read policy and existing protected operations.

Phase 5E returned a mixed, capped list with a 50-row limit and no next cursor. Historical events already reference the exact payment attempt and can store the acting user and an immutable timestamp.

## Implementation

- **Needs action** lists one row per attempt whose current status is `reconciliation_required`. The outcome column shows the latest non-matched event when available. **View history** scopes the history by that attempt UUID.
- **Recorded history** shows stored outcomes, including matched events, with their timestamps and actor names or identifiers where recorded. Current attempt status is labeled separately from the event outcome. Distinct attempts on the same order remain distinct.
- The existing queue GET endpoint preserves its previous mixed response when called without `view`. Explicit views return 20 rows by default, with a maximum of 50 and `meta.next_cursor`. The keyset sorts by recorded timestamp and UUID. Newly updated active rows can move to the front and are visible on refresh.
- Exact order reference or UUID, outcome, and inclusive UTC dates work in both views. The history view also filters by current attempt status. Next and Previous preserve the applied filters.
- Each order link uses the existing Payment Tracking route. The queue exposes inspection links and uses the existing Admin read authorization. Finance actions remain under their existing authorization and separation-of-duties checks.

## Acceptance — PASS for isolated Admin Web scope (16 November 2026)

- A dedicated tmpfs PostGIS database ran existing migrations 001–041 and a new API image. A separate production Admin build served only the disposable test portal on port 18305. Protected OTP authenticated separate synthetic read-only and privileged Admins.
- Normal sandbox endpoints and signed provider events produced 56 immutable reconciliation events. `GN-27D327A5` remained in Needs action with one linked amount mismatch. For `GN-579F3E92`, the failed and succeeded attempts had different UUIDs. The succeeded attempt had 53 recorded amount mismatch events and a matched reconciliation with a recorded Admin actor.
- Filtered history returned 20, 20, and 13 matching rows with 53 unique event IDs. Browser pagination kept status, outcome, dates, and exact order reference, and Previous returned 20 rows. The related history query used the outstanding attempt UUID. The linked Payment Tracking view showed the separate failed and succeeded attempts.
- The browser tested loading, empty, HTTP 500, and permission-denied states. Live endpoints returned 401 for anonymous access and 403 for a Customer. The read-only Admin could view the queue and received 403 for the existing protected reconciliation action. A privileged Admin passed the permission gate and received 404 for a deliberately absent attempt, creating no event. Both queue views expose read-only controls.
- The desktop and 390 px layouts were checked with Playwright and screenshots. The narrow layout uses a compact header and a keyboard-focusable horizontally scrollable table.
- `go test -count=1 ./...`, targeted Go vet, the isolated Next.js production build, TypeScript, targeted ESLint, OpenAPI parsing, and three Playwright tests passed. An early browser run exposed an incorrect test actor label and a retry hit the OTP rate limit. The final rerun passed with the correct label and normal rate protections.
- The sandbox capture journal balanced. Payout transfers counted zero and live financial flags remained disabled. This was Admin Web acceptance. The existing shared services, historical migrations, and Android app were outside this change. Disposable services and protected runner configuration were removed.

[Desktop Needs action](evidence/phase5p2/needs-action-desktop.png) · [Mobile Recorded history](evidence/phase5p2/history-mobile.png)

The post-cleanup check found no listener on the existing Admin Web port 18302. Its existing QA API container was still running the prior image. No restart or deployment of the existing portal was performed in Phase 5P.2.
