# Phase 3D — Pickup, Delivery Execution & Exceptions

**Validation date:** 7 November 2026  
**Status:** **PASS — isolated QA acceptance completed across Pixel 8 customer/rider apps, live Merchant/Admin portals, API, and PostgreSQL**  
**Scope:** Pickup verification, rider execution, customer delivery confirmation and exception handling. No real deliveries, production deployment, payments, GPS, earnings or Phase 3E work.

## Summary

### Final device acceptance closeout — 7 November 2026

The mandatory same-order acceptance flow passed in an isolated disposable QA stack. The Pixel 8 customer emulator (`emulator-5554`) created QA order `19911400-d0cf-45e5-a324-a2b6d9199a69` (`GN-19911400`) for Cuttack → Kuanpal. The assigned QA merchant used the live Merchant Portal to accept the order, begin preparation, mark it ready, and issue the short-lived pickup verification code. The approved QA rider used the second Pixel 8 emulator (`emulator-5556`) to accept the dispatch offer, advance through arrival and pickup verification, collect the order, and mark it en route. The customer supplied the in-app delivery code on the rider app; the rider completed handover on that same order.

The customer reopened/refreshed the exact order and saw the server-backed timeline through **Delivered with your confirmation**. The live Merchant Portal and Admin Portal showed the same delivered order and assigned rider; the Admin delivery history showed customer OTP verification. The API and PostgreSQL records agreed: order status `delivered`, execution state `delivered`, payment status `not_collected`, and no active rider assignment after completion. The immutable execution events recorded pickup verification, en-route transition, and customer-code verification. No GPS location, ETA, payment success, or SSE refresh is claimed; the customer screen was refreshed from the API.

Final UI review found two presentation/read-model defects and they were corrected within scope. The Admin dispatch query now retains the most recent rider on completed jobs after the active assignment is released, and the completed-job label reads “Delivered by rider”. The customer milestone query now omits pickup-code issuance audit events, which had appeared as duplicate “Rider arrived at partner” milestones; the integration test asserts that verification issuance is excluded while verified transitions remain visible.

Evidence screenshots (all use synthetic QA data; no OTP or verification code is shown):

- Customer final timeline: [phase3d-customer-delivered.png](evidence/phase3d-customer-delivered.png)
- Rider offer and execution: [offer](evidence/phase3d-rider-offer.png), [assigned](evidence/phase3d-rider-assigned.png), [at pickup](evidence/phase3d-rider-at-pickup.png), [picked up](evidence/phase3d-rider-picked-up.png), [delivered](evidence/phase3d-rider-delivered.png)
- Merchant final order: [phase3d-merchant-delivered.png](evidence/phase3d-merchant-delivered.png)
- Admin final dispatch record: [phase3d-admin-delivered.png](evidence/phase3d-admin-delivered.png)

The acceptance stack used a separate QA database/API and temporary portal/proxy containers. It was removed after evidence capture. The shared development database and its containers were not changed; migration 027 remains unapplied there. Temporary Phase 3D fixture files and test servers were removed. No commit was created.

Phase 3D adds an API-authoritative delivery execution lifecycle over the Phase 3C delivery job and assignment model. Pickup and delivery confirmation use short-lived, per-job codes stored as keyed HMAC values. State changes, exceptions and administrative resolutions are persisted in execution history. The implementation keeps order, delivery and payment states separate; successful test completion leaves payment as `not_collected`.

The lifecycle supports assigned → arriving at pickup → at pickup → picked up → en route → delivered, with failure and return paths. Cancellation is permitted only before physical pickup. The database also prevents cancellation after pickup. No rider GPS, ETA, COD, payment, earnings or automatic refund behavior was added.

## Implementation

- Added migration `027_delivery_execution.sql` for execution state, verification-code metadata, execution events and delivery exceptions. Historical migrations were not edited.
- Added authenticated rider, assigned merchant, customer and Admin endpoints for delivery progression, pickup code issuance/verification, customer delivery-code retrieval/submission, exception reporting/resolution, return handover and Admin execution history.
- Pickup verification is available only after the partner marks the order ready and the assigned approved rider is at pickup. Codes expire, have a cooldown and bounded attempts, are replay-protected, and are never included in broad SSE payloads.
- Customer delivery codes are available only to the owning customer while the assigned delivery is en route. Delivery completion is idempotent, requires the assigned rider's valid code, and transitions the order to `delivered` without changing `payment_status`.
- Return-required and pre-pickup cancellation resolutions are audited. Pre-pickup cancellation releases reserved inventory transactionally; physical return confirmation releases the active rider assignment. Inventory is not restored after pickup.
- Scoped SSE events include only minimal event identifiers; authenticated API reads are the recovery source. Customer tracking refreshes delivery history from the server.
- Rider workspace exposes assigned job details and execution controls. Merchant order detail can issue pickup codes and confirm returned handover. Admin dispatch shows execution state/history and open exceptions with audited resolution controls.

## API surface

- `POST /api/v1/rider/delivery-jobs/{jobId}/state`
- `POST /api/v1/rider/delivery-jobs/{jobId}/pickup/verify`
- `POST /api/v1/rider/delivery-jobs/{jobId}/delivery/verify`
- `POST /api/v1/rider/delivery-jobs/{jobId}/exceptions`
- `GET /api/v1/customer/orders/{orderId}/delivery`
- `GET /api/v1/customer/orders/{orderId}/delivery-code`
- `POST /api/v1/merchant/businesses/{businessId}/delivery-jobs/{jobId}/pickup-code`
- `POST /api/v1/merchant/businesses/{businessId}/delivery-jobs/{jobId}/return-confirmation`
- `GET /api/v1/admin/delivery-exceptions`
- `POST /api/v1/admin/delivery-jobs/{jobId}/exceptions/{exceptionId}/resolve`
- `GET /api/v1/admin/delivery-jobs/{jobId}/execution-history`

The OpenAPI YAML parsed successfully. Authenticated browser/API acceptance passed against the isolated QA API and the same order; the screenshot evidence above records the final portal and mobile states.

## Main files changed for Phase 3D

- `backend/migrations/027_delivery_execution.sql`
- `backend/internal/deliverydispatch/execution.go`, `service.go`, and `integration_test.go`
- `backend/internal/platformfulfillment/service.go`
- `backend/cmd/api/main.go`
- `api/openapi.yaml`
- `apps/mobile/lib/core/screens/rider_workspace_screen.dart`
- `apps/mobile/lib/core/screens/order_tracking_screen.dart`
- `apps/mobile/test/rider_dispatch_test.dart`
- `apps/merchant-web/lib/api.ts` and `components/PlatformOrdersManager.tsx`
- `apps/admin-web/components/DispatchBoardView.tsx`
- `docs/phases/README.md`, this report, and `codex-implementation.md`

## Validation actually executed

| Check | Result |
|---|---|
| `go test -count=1 ./...` | PASS; integration test skips without the opt-in DSN |
| `TEST_DATABASE_DSN=... go test -count=1 ./internal/deliverydispatch -run TestDispatchPrepareOfferAcceptAndIsolation` against disposable PostGIS | PASS; rerun after the final Admin read-model and customer milestone fixes. Covers dispatch/execution ownership, code expiry and attempt controls, replay/idempotency, concurrency, cancellation boundaries, exceptions/return handling, inventory restoration, completed-rider visibility and customer timeline event filtering |
| `flutter test --no-pub` | PASS, 78 tests in the Phase 3D validation run; not rerun during this final device closeout because no Flutter source changed |
| `flutter analyze --no-pub` | Phase 3D validation reported 18 diagnostics (3 warnings, 15 infos), no errors; exit code 1 due to diagnostics. Not rerun during this final device closeout; no Flutter source changed |
| `flutter build apk --debug --no-pub --dart-define=API_BASE_URL=http://10.0.2.2:18081` | PASS; this QA APK was installed on both emulators |
| Android build/install/launch and device flow | PASS; customer and rider APK sessions on Pixel 8 emulators `emulator-5554` and `emulator-5556` used the isolated API at port 18081; the exact order completed customer checkout through customer-code-verified delivery |
| Live Merchant Portal browser flow | PASS; authenticated merchant viewed the same order, issued pickup code, and its final delivered state was reconciled in the portal |
| Live Admin Portal browser flow | PASS; authenticated Admin dispatch board/history showed the same delivered order, retained rider identity, and customer OTP verification |
| Admin portal typecheck and production build | PASS; final source build and browser reconciliation passed |
| Merchant portal browser acceptance | PASS for the same QA order. A separate new Merchant source production build was not required for this closeout |
| OpenAPI YAML parse | PASS |
| `gofmt -d` on the three changed Go files | PASS; no formatting diff |
| `git diff --check` | `docs/phases/README.md` passed. Checking the already-dirty `codex-implementation.md` reports pre-existing trailing-whitespace diagnostics on unrelated historical entries; the new Phase 3D lines have no trailing whitespace. Repository-wide check is not clean because the worktree contains unrelated existing changes |

The retained screenshots show only synthetic QA order and workflow states. OTPs and short-lived pickup/delivery codes were not captured or retained.

## Isolated QA and cleanup

The disposable PostGIS database `grepmind_3d_acceptance_qa` and isolated API/Admin/Merchant/Nginx containers were used for the populated Kuanpal flow; migration 027 was applied only there. QA order `19911400-d0cf-45e5-a324-a2b6d9199a69` and job `d20528dd-44cc-45a5-86c3-95453af1a1b8` were verified across customer/rider Android UI, Merchant/Admin browser UI, authenticated API, and PostgreSQL before teardown. The QA containers, images, and network were removed, and temporary test scripts/fixture files were deleted. Shared development PostgreSQL/API/MinIO/portal services were not changed. Chhatia was not exercised in this acceptance run.

No commit or push was created.

## Security and operational limitations

- Verification-code HMAC derivation currently uses the application's existing secret configuration; production should use a dedicated, independently rotated delivery-verification secret.
- Customer code delivery is authenticated in-app retrieval only. A production notification/SMS channel and support policy require separate design and authorization.
- Legal/privacy review and production key/storage policy remain pre-production requirements.
- No SSE behavior was exercised; reopening/refreshing the customer order performed a fresh API read.
- Migration 027 remains unapplied to the shared development database. Prior reports record migrations 023–026 as also unapplied there; this final acceptance did not recheck that shared migration state.

## Acceptance recommendation

**PASS for Phase 3D isolated QA acceptance.** The same populated QA order completed partner handover and customer-code-verified delivery through the two Pixel 8 emulator roles; Merchant Portal, Admin Portal, authenticated API, and PostgreSQL matched. The QA environment was removed, and the shared development database was left unchanged. This is not production-readiness approval: do not begin Phase 3E without separate approval, and keep legal/privacy, operational, migration rollout, and production-secret/storage work as launch gates.
