# Phase 2D — Customer order history, tracking, and delivery verification

**Date:** 6 November 2026  
**Status:** Implemented; acceptance evidence and remaining limits below.  
**Scope:** Customer order history/details, truthful tracking, cancellation/reorder, order support. No payment, dispatch, rider GPS, FCM, or delivery OTP was activated.

## Implementation

- Extended the existing `customer_orders` workflow; did not create a competing order model.
- Added additive migration `backend/migrations/020_order_status_events.sql`. Existing orders receive a `history_snapshot` event only; no earlier status history is invented.
- Order list supports bounded cursor pagination (`limit`, `before`), status and order-type filters, and explicit API errors. Exact order detail remains customer-owned.
- Status transitions and new-order creation persist status events transactionally. Existing SSE is published as authenticated, customer-scoped `order.status` events; Flutter subscribes only while an order detail is open and disposes the stream/reconnect timer when leaving.
- Duplicate cancellation returns the already-cancelled order, so inventory is restored only for the first transition. Merchant status updates append status history and send the same existing SSE event.
- Added order-specific support submission using the existing reports table. An open report is reused on retry; order ownership is enforced.
- Flutter history includes loading, empty, error/retry, refresh, local status/type filters, and pagination. Detail fetches the exact order ID and shows not-found/access errors without falling back to another cached order.
- Tracking renders only server status events, labels the first observed state as a snapshot, and does not invent rider positions, GPS, ETA, or delivery OTP. It shows `not_collected` payment truthfully.
- Reorder validates current products/prices with the existing cart validation API and changes the cart only when every item remains eligible. Replacing a non-empty cart requires confirmation.

## API and data changes

- `GET /api/v1/customer/orders`: bounded `limit`, `before`, `status`, and `type` query parameters; response adds pagination metadata.
- `GET /api/v1/customer/orders/{id}`: adds ordered `status_events`.
- `POST /api/v1/customer/orders/{id}/support`: validates reason and customer ownership; reuses an existing open report on retry.
- Existing cancel/status APIs now persist state history and produce idempotent cancellation/SSE effects.
- `customer_order_status_events` is introduced by migration 020. No existing migration was edited.

## Validation evidence

- `go test -count=1 ./...` with `GREPMIND_TEST_DATABASE_URL` against an isolated PostgreSQL/PostGIS database — **PASS**. Covered customer order pagination and ownership, support report isolation/retry, cancellation retry and one-time stock restoration, and merchant status event publication.
- Isolated PostgreSQL migration execution for migration 020 — **PASS**. Development/production data was not used for that migration test.
- `flutter test --no-pub` — **PASS, 66 tests**, including exact order detail, truthful timeline/no-rider claims, and Phase 2B/2C regression tests.
- `flutter analyze --no-pub` — **118 diagnostics**, two fewer than the recorded 120 baseline. No errors; the command exits nonzero because the repository still has existing warnings/informational lints. `dart analyze lib/core/providers/customer_orders_provider.dart` — **PASS, no issues**.
- `flutter test --no-pub` final rerun — **PASS, all 66 tests**.
- Android emulator: final Phase 2D debug APK built, installed, and launched on Pixel_8/API 37. Home → Orders showed the real API-backed empty state for the signed-in QA customer; screenshot: `%TEMP%/grepmind-phase2d-final-orders.png`. A populated detail/cancellation/reorder/SSE flow was not run on-device because this local customer has no orders and there is no delivery-enabled QA business. No fake order data was inserted.
- No production systems or data were used. No order/payment/rider OTP was fabricated or submitted.

## Remaining limits

- The local authenticated customer currently has no safe disposable order fixture available. Full on-device order list/detail/SSE/cancel/reorder navigation still needs a disposable QA order run; widget and DB-backed API tests cover the respective logic.
- Legacy order rows receive one present-state snapshot, not a reconstructed historical timeline.
- The existing order schema currently has no `ready` or `picked_up` state. Merchant states are surfaced as they exist; rider pickup/delivery completion and secure delivery OTP belong to the later rider integration phase.
- Support reuses the existing reports workflow; no customer-facing ticket conversation/reply system exists.
- No performance/load benchmark was run. Pagination is bounded and one SSE stream is opened only for the selected order detail.

## Acceptance recommendation

**PARTIAL.** The build, local API health, automated suites, migration, and on-device empty-history state passed. On-device populated order details and transitions remain unverified because the local database has no eligible test order; database-backed tests cover these flows. Do not treat missing rider/GPS/OTP/payment functionality as operational; those capabilities remain explicitly deferred.
