# Phase 5P.3 — Admin finance transaction transparency

## Implementation

- Finance Overview links refund and payable orders to the existing Admin Payment Tracking route. A valid order ID can stand in for a missing reference. Records without a usable identifier display a neutral fallback. Returning from tracking restores the refund status filter.
- Payment Tracking displays each attempt number and UUID, provider classification, recorded sandbox capture evidence, and recent refunds. Attempt-level navigation opens the existing paginated reconciliation history scoped by attempt ID.
- Classification comes from the stored provider, the payable payment source, the verified COD ledger journal, or the settlement funding mode and simulation timestamp. Records with insufficient evidence display “Classification unavailable.” Capture posting and settlement simulation are displayed separately.
- Finance Overview, Payment Tracking and reconciliation navigation are read-only. The existing transaction authorization, independent approvals, and posting paths still govern privileged operations. The older COD and merchant operations views continue to rely on their server checks for existing action controls.

## Files and API

- Admin Web: `FinanceOverview.tsx`, `FinanceOrderLink.tsx`, `AdminPaymentTracking.tsx`, `AdminPortalClient.tsx`, `AdminReconciliationQueue.tsx`, `CODFinanceView.tsx`, `MerchantSettlementFinanceView.tsx`, `lib/finance-display.ts`, and `app/dashboard/payment-tracking/[reference]/page.tsx`.
- Backend: `internal/payments/admin_tracking.go`, `internal/payments/refunds.go`, and `internal/codcash/service.go`.
- Tests: `e2e/finance-overview.spec.ts` and `e2e/reconciliation-pages.qa.spec.ts`.
- Additive Admin GET projections documented in `api/openapi.yaml`. Refund rows expose the order reference and stored provider. Tracking exposes `capture_posted` per attempt and the latest 25 refunds with a truncation flag. Admin remittance rows expose `sandbox_verified`. No migration or new endpoint.

## Environment

- The earlier Next.js portal at `127.0.0.1:18302` refused connections and had no listener. Its companion API on `18083` replied with HTTP 200. The historical portal process's exit cause could not be recovered.
- A separate local production build on `18305` used the disposable PostgreSQL/API on `18153` and private OTP helper on `18155`. Three consecutive readiness checks returned portal 200, API 200, and inbox 204. The shared and production environments were outside this validation.
- Windows-host ADB verified AVD names after Linux ADB timed out. Customer `Pixel_8` used `emulator-5554`, Merchant `Pixel_8_Merchant_QA` used `emulator-5556`, and Rider `Pixel_8_Rider_QA` used `emulator-5558`. The Admin-only change did not require a new APK. Mobile application authentication and build compatibility were not checked in this phase.
- Phase 5P.1 retains its independently unverified status.

## Validation decision

**PASS for isolated Admin Web scope.** The targeted suite passed across the final browser runs, including populated Finance Overview, Payment Tracking and reconciliation navigation, responsive desktop and 390 px layouts, missing references, retry distinction, and privileged-action denial. Go finance packages, the isolated production Next build, TypeScript, OpenAPI parsing, API/database fixture reconciliation, and repeated portal/API/OTP health checks passed. The disposable portal was reachable through the `18305` production build, and the `18302` listener was verified through the local forwarding path during acceptance. No production or shared database was changed, and no deployment was performed. Phase 5P.1 remains independently unverified.
