# Phase 2R.4 — Partner Fulfillment & Order Preparation

**Date:** 6 November 2026
**Acceptance:** PASS for the scoped partner fulfillment milestone
**Branch:** `development-02` (worktree also contains prior uncommitted work; no commit was created)

## Outcome

Implemented partner-scoped operations for Grepmind platform catalog orders. An authorized member of the assigned business can inspect preparation details, accept or reject a placed order, start preparation, and mark an order ready for pickup. Customer tracking displays the persisted status history and receives the existing scoped SSE status event. Customer tracking shows no rider location or ETA, and payment remains `not_collected`.

## State and security rules

- Supported path: `placed → accepted → preparing → ready_for_pickup`; `placed → rejected` requires a 10–500 character reason.
- Partner list, detail, and mutations are scoped to the URL `business_id`, active membership, and the order's assigned `business_id`. Membership is rechecked inside the transaction.
- Status updates lock the order row. Same-state retries are idempotent; invalid or competing transitions return `409`.
- Partner responses include item snapshots and preparation instructions, but exclude customer address/contact data and customer selling/partner supply prices.
- Rejection, status event creation, and finite-stock reservation release occur in one transaction. Event rows are protected against update/delete; the rejection reason is persisted with the event.
- Existing generic merchant order status updates cannot bypass platform fulfillment rules.
- Customer status updates use `order.status`, matching the existing tracking SSE listener. Business notifications use a business-scoped platform order event. Partner assignment events publish only after successful order creation, not an idempotent replay.
- No payment collection, rider dispatch, GPS, partner reassignment, or delivery completion was added.

## Implementation

- Added migration `backend/migrations/024_platform_partner_fulfillment.sql` for partner status/event values, rejection-reason constraints, and append-only status-event protection. It is additive; prior migrations were not edited.
- Added `backend/internal/platformfulfillment/service.go` and merchant routes for list, exact order detail, accept, reject, prepare, and ready-for-pickup.
- Extended platform order creation to notify the assigned partner after commit. Updated the generic merchant status guard and documented routes in `api/openapi.yaml`.
- Added the Flutter merchant Platform Orders screen and wired the Merchant Orders tab to it. The UI exposes assigned orders and preparation information, with loading, empty, error/retry, rejection-reason, and transition feedback. Customer order history/tracking parses accepted, preparing, ready-for-pickup, and rejected states/reasons.
- Added a Merchant Portal Platform Orders view and refresh wiring. Its Playwright tests use a test-only mocked API; they validate UI presentation and required rejection reason, not a live authenticated browser session.

## Verification evidence

### Isolated runtime

- Created a disposable PostGIS database from schema only; no shared-database rows were copied. Applied migrations through 024 there and started a dedicated API container on port 8082. The shared development database was not migrated, reset, or otherwise changed.
- Created explicitly labeled QA-only Cuttack/Kuanpal partner, customer, product, finite-stock mapping, and address. No real merchant/customer data was used.
- Built and installed the latest debug APK through the approved `scripts/mobile_emulator.ps1 -Action BuildRun` workflow using the existing WSL Flutter 3.47.8 SDK and Pixel 8 emulator. The emulator used the temporary API at `http://10.0.2.2:8082`; production defaults and signing were unchanged.
- A disposable QA customer signed in through local development OTP, browsed the actual Food catalog, selected the QA product at backend price ₹149, selected the saved QA address, received the server quote naming the assigned Kuanpal partner, and submitted one order. The app confirmation explicitly said payment was not collected and displayed reference `GN-5E216CA6`.
- My Orders and exact order detail showed the placed order. An authenticated QA merchant session advanced that same record through the partner API: accept → prepare → ready. Refreshing the customer's tracking screen showed `Ready for pickup` and the persisted placed, accepted, preparing, and ready timeline events.
- PostgreSQL readback before teardown confirmed `GN-5E216CA6 | ready_for_pickup | not_collected | 4` (four events including initial placement).
- Removed the QA API and database containers and their private network after validation. Deleted the temporary fixture SQL. The QA order and identities were contained in the disposed database. Shared development containers, database, and volumes were preserved.

### Tests and checks

| Check | Result |
|---|---|
| `GREPMIND_TEST_DATABASE_URL=... go test -count=1 ./...` against disposable PostGIS DB | PASS, all packages |
| `flutter test --no-pub` | PASS, 73 tests |
| Focused `dart analyze` on `customer_order.dart`, `merchant_platform_orders_screen.dart`, `order_tracking_screen.dart`, and `order_history_screen.dart` | PASS, no issues |
| Full `flutter analyze --no-pub` | Did not finish within the 90-second retry; analyzer server was terminated by timeout. The prior recorded baseline is 18 diagnostics (3 warnings, 15 infos), but this run did not produce a current comparable total. |
| Debug APK build/install/launch on Pixel 8 | PASS; same build used for the live customer checkout and tracking validation |
| Merchant Portal typecheck and production build | PASS |
| `e2e/platform-orders.spec.ts` | PASS, 2 Playwright tests using mocked API responses |
| Live merchant partner action API | PASS, authorized merchant advanced the emulator-created QA order through all three actions |
| `TestPlatformFulfillmentIsolationTransitionsRejectionAndNotifications` | PASS within Go suite: ownership/tenant isolation, no pricing/customer PII leaks, transitions, concurrent accept/reject, reason validation, one-time stock release, immutable audit events, and scoped notifications |
| `TestPlatformCheckoutPartnerSelectionIdempotencyAndStockRestoration` | PASS within Go suite; assignment/customer placement notifications are not duplicated on idempotency replay |

### Emulator screenshots

- [Orders hub with QA catalog item](screenshots/phase2r4-mobile-orders-hub.png)
- [QA product details and platform price](screenshots/phase2r4-mobile-product.png)
- [Platform cart](screenshots/phase2r4-mobile-cart.png)
- [Server-quoted checkout review and assigned partner](screenshots/phase2r4-mobile-checkout-review.png)
- [Order confirmation with payment not collected](screenshots/phase2r4-mobile-order-placed.png)
- [Customer tracking before fulfillment](screenshots/phase2r4-mobile-tracking-placed.png)
- [Customer tracking after ready-for-pickup](screenshots/phase2r4-mobile-tracking-ready.png)

Screenshots containing local OTP codes were discarded. Remaining captures use disposable QA identity/address values.

## Changed files for Phase 2R.4

- `backend/migrations/024_platform_partner_fulfillment.sql`
- `backend/internal/platformfulfillment/service.go`
- `backend/internal/platformcommerce/service.go`
- `backend/internal/operations/service.go`
- `backend/cmd/api/main.go`
- `backend/cmd/api/security_integration_test.go`
- `api/openapi.yaml`
- `apps/mobile/lib/core/models/customer_order.dart`
- `apps/mobile/lib/core/screens/merchant_platform_orders_screen.dart`
- `apps/mobile/lib/core/screens/order_history_screen.dart`
- `apps/mobile/lib/core/screens/order_tracking_screen.dart`
- `apps/mobile/lib/main.dart`
- `apps/mobile/test/order_history_test.dart`
- `apps/mobile/test/workspace_navigation_test.dart`
- `apps/merchant-web/lib/api.ts`
- `apps/merchant-web/components/Sidebar.tsx`
- `apps/merchant-web/components/PlatformOrdersManager.tsx`
- `apps/merchant-web/app/page.tsx`
- `apps/merchant-web/e2e/platform-orders.spec.ts`
- `docs/phases/README.md`
- `docs/phases/PHASE_2R_4_PARTNER_FULFILLMENT_AND_ORDER_PREPARATION.md`
- `AGENTS.md`
- `codex-implementation.md`

The worktree contains substantial earlier Phase 2B–2R.3 changes. No unrelated worktree edits were reverted or included in a commit.

## Remaining limitations and next gate

- Migration 024 has **not** been applied to the shared development database; it also lacks migration 023. Deployment migration execution and backup/restore readiness remain separate work.
- Merchant Portal Playwright checks use mocked API responses; the live assigned-order transitions were verified through the authorized merchant API, while customer checkout/tracking was verified in the emulator. A live merchant-side browser/emulator E2E remains useful additional coverage.
- Full Flutter analysis did not finish; only targeted changed-file analysis is confirmed clean. Keep the known 18-diagnostic baseline on the quality backlog and rerun when the analyzer completes reliably.
- QA product images were empty intentionally; image upload/rendering is outside this fulfillment acceptance.
- No Phase 2E cross-platform acceptance, payment, dispatch, GPS, rider assignment, or delivery verification has started.

**Recommendation: PASS for Phase 2R.4 scope.** The emulator-created unpaid QA order was fulfilled by its authorized partner and customer tracking reflected the persisted timeline. Rejection authorization, audit, and inventory restoration passed isolated DB integration tests. Stop here and wait for explicit Phase 2E approval.
