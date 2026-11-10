# Phase 2R.3 — Platform Cart & Checkout Adaptation

**Status: PASS — isolated populated checkout completed on the Pixel 8 emulator, created one unpaid platform order, displayed it in My Orders, and matched it to PostgreSQL. Migration 023 remains unapplied to the shared development database.**

## Scope and decisions

Customers shop from Grepmind's Food or Grocery catalog. The backend chooses exactly one approved fulfillment partner for the complete basket using explicit approved variant mappings and locality coverage. The customer never selects the partner. Food and Grocery carts are isolated. Existing merchant-owned carts, restaurant bookings, hotel bookings, service requests, and earlier order paths remain available.

This phase adds migration `023_platform_cart_checkout.sql`; it has **not** been applied to the shared development database. No development database data or schema was changed during this implementation. The migration is additive and leaves historical migrations unchanged.

## Implementation

- Added customer-scoped platform checkout quote and submit endpoints: `POST /api/v1/platform/orders/quote` and `POST /api/v1/platform/orders`.
- Quotes use saved addresses with stable delivery-locality IDs, active catalog variants, district visibility, explicit locality delivery scope, approved product mappings, business verification/delivery state, opening hours, and partner inventory/capacity. A partner is returned only if it can fulfill every item. Candidate tie-breaking is deterministic. Quotes expire after five minutes and do not reserve stock.
- Prices and item names are loaded from Grepmind catalog records and stored as immutable order-line snapshots. Public quote responses omit partner supply costs. Delivery fee and tax are explicitly marked `not_configured` and zero; no ETA or payment success is invented.
- Submission revalidates the quote, address version, prices, stock, capacity, mappings, and partner eligibility inside a transaction. Finite inventory is reserved atomically. The `Idempotency-Key` header prevents duplicate submissions; reusing a key with changed notes/request content returns a conflict. Payment remains `not_collected`.
- Platform orders reuse `customer_orders` with `order_type=platform_order`, assigned partner business identity, and `order_source=platform_catalog`; separate immutable platform order-item and inventory-reservation tables preserve catalog snapshots and restock behavior. Cancellation restores finite partner inventory once.
- Saved addresses optionally carry a stable `delivery_locality_id`; legacy free-text addresses remain compatible with existing checkout. Stable locality selection is available in the address editor.
- Flutter platform carts persist in secure storage, keyed by authenticated user, vertical, and stable locality. Cart payloads contain variant IDs and quantities; local prices are display hints only. The platform cart is separate from the legacy merchant cart. Cart edits invalidate the displayed quote; address changes require a matching locality. Food/Grocery hub and catalog expose their separate cart entry points.
- Existing customer Orders history and tracking recognize platform order type/source and display its item snapshots and fulfillment partner.

## Changed and added files

The Phase 2R.3 changes are among the current uncommitted worktree edits. The targeted source files include:

- `backend/migrations/023_platform_cart_checkout.sql`
- `backend/internal/platformcommerce/service.go`
- `backend/cmd/api/main.go`
- `backend/cmd/api/security_test.go`
- `backend/cmd/api/security_integration_test.go`
- `backend/internal/operations/checkout.go`
- `backend/internal/operations/service.go`
- `api/openapi.yaml`
- `apps/mobile/lib/core/models/customer_address.dart`
- `apps/mobile/lib/core/models/customer_order.dart`
- `apps/mobile/lib/core/models/platform_catalog.dart`
- `apps/mobile/lib/core/providers/platform_cart_provider.dart`
- `apps/mobile/lib/core/screens/customer_address_form_screen.dart`
- `apps/mobile/lib/core/screens/order_shopping_hub_screen.dart`
- `apps/mobile/lib/core/screens/platform_cart_screen.dart`
- `apps/mobile/lib/core/screens/platform_catalog_screen.dart`
- `apps/mobile/lib/core/screens/platform_product_detail_screen.dart`
- `apps/mobile/lib/core/screens/order_history_screen.dart`
- `apps/mobile/lib/core/screens/order_tracking_screen.dart`
- `apps/mobile/test/platform_cart_test.dart`
- `docs/phases/README.md`, `AGENTS.md`, and `codex-implementation.md`

The worktree also contains extensive pre-existing/unrelated edits from earlier approved phases; those were preserved and are not attributed to this phase.

## Verification evidence

Executed in the project's WSL Ubuntu environment:

- `cd backend && GREPMIND_TEST_DATABASE_URL=postgres://grepmind:grepmind_dev@localhost:5432/grepmind_near?sslmode=disable go test -count=1 ./...` — PASS. Tests apply required migrations inside isolated schemas and clean them up.
- `GREPMIND_TEST_DATABASE_URL=postgres://grepmind:grepmind_dev@localhost:5432/grepmind_near?sslmode=disable go test ./cmd/api -run TestPlatformCheckoutPartnerSelectionIdempotencyAndStockRestoration -count=1 -v` — PASS after adding a mixed basket test. The test fixture applies migrations to a disposable schema and drops it afterward.
- The integration test verifies Cuttack/Kuanpal and Jajpur/Chhatia, no partner can fulfill a split-only basket, no stock reservation at quote, customer ownership, idempotent replay, order snapshots, cancellation restoration, concurrent last-unit contention (one success, one conflict), and no supply-price leakage.
- `flutter test --no-pub test/platform_cart_test.dart` — PASS, 2 tests. Covers persistence, account/vertical/locality scoping, add/quantity/remove, inactive variant, vertical mismatch, and quantity bounds.
- `flutter test --no-pub test/platform_catalog_test.dart test/platform_cart_test.dart` — PASS, 6 tests.
- `flutter test --no-pub` — PASS, 72 tests. The initial run found a missing Dio `Options` import and an obsolete catalog widget assertion; both were corrected before the passing rerun.
- `flutter build apk --debug --no-pub` — PASS using the existing WSL Flutter 3.47.8 SDK; generated `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`.
- `flutter analyze --no-pub` — completed with 18 diagnostics (3 warnings, 15 infos, 0 errors), equal to the Phase 2R.2 baseline. Exit code was 1 due to existing warnings/infos; focused `dart analyze` of the new/changed cart, product, hub, address, and tests returned `No issues found!` after fixing seven curly-brace infos in newly changed files.
- `python -c "import yaml; yaml.safe_load(open('api/openapi.yaml', encoding='utf-8'))"` — PASS. Targeted `git diff --check` on Phase 2R.3 files — PASS (Git emitted line-ending normalization notices only).
- Initial standard Windows-host ADB attempts failed. The server diagnostic was `fdevent_poll.cpp:62 failed to create fdevent interrupt socketpair: Invalid argument` inside the restricted runner. Running the existing helper through the approved elevated Windows-host execution path succeeded: `scripts/mobile_emulator.ps1 -Action Start` — PASS, Pixel_8 / `emulator-5554` ready.
- `scripts/mobile_emulator.ps1 -Action BuildRun` — PASS. Rebuilt with WSL Flutter 3.47.8 and `API_BASE_URL=http://10.0.2.2:80`, streamed install succeeded, and `local.grepmind.grepmind_mobile/.MainActivity` launched.
- Visual emulator checks: Orders hub rendered; Cuttack → Kuanpal and Jajpur → Chhatia were selectable and marked delivery enabled; Jagatpur/Chandikhol/Tangi remained labeled planned/unavailable. Food at Kuanpal and Grocery at Chhatia displayed the honest empty catalog state. Food cart opened and displayed its empty state. Screenshots: `apps/mobile/build/phase2r3-orders.png`, `phase2r3-location.png`, `phase2r3-kuanpal.png`, `phase2r3-food.png`, `phase2r3-cart.png`, `phase2r3-jajpur-picker.png`, and `phase2r3-grocery.png`.

## Final integration acceptance — 6 November 2026

- Created isolated database `grepmind_phase2r3_qa` from schema-only structure, applied migrations through 023 there, and launched a separate API container on port 8081. No shared development data was copied into QA; no shared API, Nginx configuration, PostgreSQL volume, or shared schema was modified.
- Seeded QA-only products, variants, approved partner mappings, locality coverage, finite inventory, and disposable customer addresses for Cuttack/Kuanpal and Jajpur/Chhatia. Catalog image arrays were empty, so the app correctly rendered image fallbacks; image upload/rendering was not exercised.
- Public API smoke checks returned HTTP 200 with one Food and one Grocery product for each enabled locality. Planned Cuttack/Jagatpur returned an empty catalog. Public responses did not include partner settlement prices.
- On Pixel 8, signed into a disposable OTP customer and completed Orders hub → Jajpur/Chhatia → Food catalog → QA Veg Thali details → Food cart → Chhatia address selection → server quote → order submission → My Orders → order details. The UI showed ₹99 server pricing, `QA Chhatia Fulfillment Partner`, quote expiry/revalidation, payment not collected, and no fabricated ETA or rider location.
- PostgreSQL verified exactly one QA `platform_order` with `status=placed`, `payment_status=not_collected`, partner `QA Chhatia Fulfillment Partner`, Chhatia locality, ₹99 total, one immutable order item, and finite mapped stock reduced once from 5 to 4. No real payment, dispatch, or rider workflow was invoked.
- `TestPlatformCheckoutPartnerSelectionIdempotencyAndStockRestoration` passed. It covers both enabled localities, complete-basket single-partner selection, quote non-reservation, ownership, idempotent replay, order snapshots, cancellation/restoration, last-unit contention, and settlement-price privacy. Full Go suite passed. Full Flutter suite passed 72 tests. Flutter analyzer reported 18 diagnostics (3 warnings, 15 infos, 0 errors), equal to the Phase 2R.2 baseline; process exit code was 1 due to existing warnings/infos. APK build, install, and launch passed.
- Cleanup removed the disposable QA customer session and temporary emulator user, dedicated QA API container/image, `grepmind_phase2r3_qa` database, schema dump, and temporary fixture seed script. PostgreSQL confirmed `grepmind_near` remains and `public.platform_checkout_quotes` is absent there (migration 023 remains unapplied). No QA order/product rows remain because the isolated database was dropped.
- Screenshots: `apps/mobile/build/phase2r3-qa-catalog.png`, `phase2r3-qa-product.png`, `phase2r3-qa-cart.png`, `phase2r3-qa-checkout.png`, `phase2r3-qa-order-success.png`, `phase2r3-qa-my-orders.png`, and `phase2r3-qa-order-detail.png`. OTP and address-entry captures are excluded because they contain QA credentials/contact details.

## Risks and limitations

- The shared development DB has migrations 021/022 but not 023. Migration 023 and QA records existed only in the disposable database and were removed after validation.
- No real fees, tax rules, payment collection, merchant acceptance/fulfillment workflow, dispatch, or rider GPS are implemented here. Payment is explicitly `not_collected`; the new assigned-partner order lifecycle needs Phase 2R.4 fulfillment work.
- No performance benchmark was run; production fee/tax configuration and fulfillment latency remain unmeasured.
- User-facing address locality scoping depends on the stable locality ID. Legacy addresses remain accepted by legacy ordering APIs, while platform checkout requires an enabled mapped locality.
- Quote-expiry and unavailable-partner error UI were not forced during the successful purchase flow; no product images were uploaded for the QA catalog.

## Acceptance recommendation

**PASS for Phase 2R.3.** The required acceptance condition was met: one actual QA order was submitted through platform checkout on the emulator, appeared in My Orders, and matched isolated PostgreSQL records. It remained unpaid, used one eligible QA partner, and did not alter real customer or merchant records or the shared development database. Do not begin Phase 2R.4 without separate explicit approval.
