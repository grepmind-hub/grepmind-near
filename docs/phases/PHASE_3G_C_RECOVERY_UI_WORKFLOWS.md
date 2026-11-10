# Phase 3G-C — Admin, Rider & Merchant Recovery Workflows

**Result: PASS for isolated QA acceptance (10 November 2026).**

Phase 3G-C adds recovery workflows over the Phase 3G-B APIs. It does not enable production recovery operations. Migration 029 remains unapplied to shared development and production databases.

## Scope delivered

- Admin Recovery Queue in the Dispatch Board: shows exact order/job/assignment identity, authoritative delivery and order states, custody and handover evidence, return disposition, and recovery event history. Eligible pre-pickup release/cancel and return finalization actions require explicit confirmation, audit reason, and idempotency key. API errors are surfaced rather than represented as an empty queue.
- Rider workspace: an assigned rider can report inability to continue with a bounded reason. The UI explains that reporting does not release the assignment or transfer physical custody. A retry reuses the same idempotency key for the same request.
- Merchant Platform Orders: supports assignment-scoped no-handover evidence and physical return receipt/inspection disposition through existing APIs. It states that Admin finalization applies the inventory outcome; it does not claim inventory is changed at receipt time.
- Admin access UI exposes the `delivery_operator` role option; the backend remains authoritative for granting and enforcing that role.
- Recovery queue read data includes execution/order state, assignment and custody indicators, partner proof/return disposition; a chronological case-event read API was added. Responses omit OTPs, customer contact/address, rider KYC, GPS, and settlement data.

The established invariants remain in force: lease expiry does not automatically release an assignment; post-pickup custody cannot be automatically reassigned; inventory changes only at the transactional finalization boundary; retries are idempotent; failed/returned work does not create completed-delivery earnings; payment remains `not_collected`.

## Implementation evidence

Relevant Phase 3G-C files:

- `backend/internal/deliverydispatch/recovery.go`
- `backend/internal/deliverydispatch/service.go`
- `backend/internal/deliverydispatch/integration_test.go`
- `backend/cmd/api/main.go`
- `api/openapi.yaml`
- `apps/admin-web/components/DispatchBoardView.tsx`
- `apps/admin-web/components/UserAccessView.tsx`
- `apps/mobile/lib/core/screens/rider_workspace_screen.dart`
- `apps/mobile/test/rider_dispatch_test.dart`
- `apps/merchant-web/lib/api.ts`
- `apps/merchant-web/components/PlatformOrdersManager.tsx`

No migration was added in Phase 3G-C. Existing migration 029 was exercised only in disposable QA by the Phase 3G-B recovery acceptance script. No shared or production database was migrated, and no commit or push was created.

## Validation performed

Commands were run through the approved Windows-host `wsl` path into `/mnt/d/grepmind-near`.

- `go test -count=1 ./...` — PASS.
- `bash scripts/qa/phase3g_recovery_acceptance.sh` — PASS against disposable tmpfs PostGIS with migrations 001–029; recovery queue and event-history assertions passed along with Chhatia isolation, dispatch and Admin role-boundary checks. The QA container was removed by the script.
- `flutter test --no-pub` — PASS, 92 tests.
- `flutter analyze --no-pub` — completed with 18 diagnostics (3 warnings, 15 infos, 0 errors); exit code 1 because diagnostics remain. This matches the recorded 18-diagnostic baseline.
- `flutter build apk --debug --no-pub` — PASS.
- `scripts/mobile_emulator.ps1 -Action BuildRun -AdbServerPort 5039` — PASS for build, install and launch on Pixel 8 `emulator-5554`. A screenshot of the launched app showed the OTP login screen, not an authenticated Rider recovery flow.
- Admin `npm run typecheck` — PASS. Admin `npm run build` — PASS.
- Merchant `npm run typecheck` — PASS. Merchant `npm run build` — PASS.
- OpenAPI YAML parsing and QA script syntax validation — PASS.
- `git -c core.whitespace=cr-at-eol diff --check` — PASS for targeted changes. `AGENTS.md` uses CRLF; a plain whitespace check can misinterpret carriage returns as trailing whitespace. Byte inspection found no literal trailing spaces/tabs, so the file was not line-ending-normalized.

## Final recovery and dual-emulator acceptance (10 November 2026)

**Result: PASS for the isolated QA scope.** Both recovery scenarios completed against one disposable PostgreSQL/PostGIS environment. The latest debug APK was installed on both Pixel 8 emulators, and each ran a separate approved rider session. Shared development and production were not changed.

### Recovery fix

The missing post-pickup transition was added to the Admin exception-resolution service and UI. `require_return` for `rider_unable_to_continue` now requires the reporting rider to match the active assignment, a recorded pickup verification, an execution state of `picked_up` or `en_route`, and the exact expected active-assignment ID. The action is transactional, idempotent, and audited. It moves the job to `return_required` while retaining the active rider assignment as custodian; it cannot release or reassign a rider after pickup. OpenAPI documents the assignment binding. A backend integration test covers wrong assignment rejection, concurrent idempotent retries, one return event/audit record, and retained custody.

### Build and device evidence

- Fresh debug APK built in the approved Ubuntu WSL environment using Flutter 3.47.8, Android SDK already installed in WSL, and `API_BASE_URL=http://10.0.2.2:8081` for the isolated API.
- APK: `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`; application ID `local.grepmind.grepmind_mobile`; SHA-256 `81028646C2D21CC21C9E8E0FCF6D05584FCE73C2DAE0873CB3F9479B04E5B4FC`.
- Windows ADB server port 5039 reported both devices online. `adb install -r` returned `Success` for `emulator-5554` (Rider A) and `emulator-5558` (Rider B). The installed `base.apk` digest matched the built APK on both devices. Each device showed the authenticated Rider workspace for its distinct QA account; both riders were online when dispatch/reassignment ran.
- Sanitized screenshots are under `docs/phases/evidence/phase3gc_final/accepted/`. They show Rider A's recovery report and final no-active-delivery state, Rider B's assigned delivery, and Admin/Merchant pre-pickup recovery screens. Customer address/contact details were redacted. A separate Merchant return-disposition screenshot was not retained; the return/disposition actions and their committed API/database state were verified during the live portal run.

### Scenario A — pre-pickup release and reassignment

QA order `GN-EE01AA8C` (`ee01aa8c-b32b-4a30-8c61-9e8361739b4f`, Kuanpal) was accepted by Rider A on `emulator-5554`. Rider A submitted unable-to-continue before pickup. The live Merchant Portal recorded no-handover evidence; the authenticated Admin Portal released the exact assignment with a typed order-reference confirmation and retried dispatch. Rider B received and accepted the reassigned offer on `emulator-5558`.

PostgreSQL showed Rider A's assignment `released`, Rider B's assignment `active`, and exactly one active assignment for the job. The order remained `ready_for_pickup`; inventory remained reserved because the order was still active. Payment remained `not_collected`. This scenario passed, including the required second-device acceptance.

### Scenario B — post-pickup return and disposition

A separate Kuanpal order `GN-740BFFFD` (`740bfffd-442a-416f-aa41-01d1216f2f2d`) was accepted and prepared in the live Merchant Portal. Rider A accepted the offer on `emulator-5554`, arrived at pickup, verified the merchant-issued short-lived pickup code in the app, and confirmed physical pickup. Rider A then submitted an unable-to-continue report from the Rider UI.

The Admin operator used the live Admin Portal to require return for the exact order and assignment. The app showed `return required`; Rider A started the return to the assigned partner. The Merchant Portal confirmed physical return receipt and submitted `not_restockable` after inspection. Admin finalized the return with an audited reason.

PostgreSQL showed order and delivery job `returned`, the rider assignment `released`, return disposition `not_restockable` and finalization timestamp present. The associated inventory reservation was `consumed` once (not restored because the product was marked not restockable), and no rider earning entry was created. The rider incident was resolved and immutable recovery/execution/admin audit records were present. Payment remained `not_collected`; no delivery completion, payment, earnings, or payout was fabricated.

### Automated and portal validation

- `go test -count=1 ./...` — PASS on a fresh run after the recovery fix.
- `flutter test --no-pub` — PASS, 92 tests.
- `flutter analyze --no-pub` — completed and reported 18 diagnostics (3 warnings, 15 infos, 0 errors), matching the recorded baseline. The command wrapper did not retain the final process exit code, so this is not reported as a clean analyzer exit.
- Admin `npm run typecheck` and `npm run build` — PASS.
- Merchant `npm run typecheck` and `npm run build` — PASS.
- The authenticated Admin finalization browser flow passed. Admin `Require return` and Merchant return receipt/disposition actions were also executed in their live portal UIs and confirmed by successful persisted state. Some temporary Playwright response waiters used stale route/assertion expectations: the disposition observer waited for `/return-disposition` while the app called `/return/disposition`, and a resolved Admin case correctly disappeared from the open-case list. Those observer assertions timed out after the UI action; the database and audit trail confirm the action committed. A final read-only Merchant smoke attempt after the production build did not find the login form while the existing dev server was still running against the same `.next` directory. No claim is made that this final smoke attempt passed.
- A targeted OpenAPI parse and `git diff --check` are recorded after this closeout edit.

### QA cleanup and boundaries

The isolated database used migrations 001–029 only. The final database reconciliation was captured before teardown. The QA DB/API/MinIO containers had no mounted persistent volumes and were attached only to `grepmind_3gc_final_net`; that stack and network were removed. Temporary Admin/Merchant portal processes were stopped. Both emulator app data stores were cleared after evidence capture. QA accounts, orders, test catalog/inventory, assignments, and media disappeared with the isolated database/containers. Shared development data and migration state are unchanged; migration 029 remains unapplied to shared development and production.

**Phase 3G-C acceptance: PASS for isolated QA.** This does not authorize production recovery, shared migration rollout, GPS/ETA, customer payment/COD, rider payouts, or real compensation posting. Phase 3G-D has not started and requires separate approval.
