# Phase 2C — Delivery Addresses & Checkout

**Evidence date:** 6 November 2026  
**Status:** Implemented; backend and Flutter automated suites passed. Emulator flow was exercised on the APK before the final detail-label cleanup; the final rebuild was blocked by local WSL/ADB startup failures. Stop here; Phase 2D needs explicit approval.

## Scope delivered

- Added customer-owned addresses with create, list, edit, delete, default selection, Cuttack/Jajpur city selection, optional PostGIS map pin, landmark, and contact details. Manual address entry does not request location permission. The API enforces customer role and owner scoping; the database enforces one default address per customer.
- Added a five-minute server-priced checkout quote for supported restaurant/cafe food orders. It checks the approved merchant's current opening schedule, delivery capability, configured coverage radius, address ownership/serviceability, item publication, current price, inventory, minimum order, and configured delivery fee.
- Quotes are read-only and do not reserve stock. Order submission revalidates the quote/address and locks the relevant product rows. Finite inventory is reserved only during order submission.
- Food-order creation reuses `customer_orders`/`customer_order_items`. An authenticated customer's UUID `Idempotency-Key` prevents duplicate orders on retries; replay with the same key and request returns the existing order. A conflicting payload for that key is rejected.
- Orders preserve an address snapshot so deleting a saved address does not erase order history. Address/quote foreign keys are cleared or cascaded according to lifecycle; the immutable JSON snapshot remains.
- Payment gateway behavior remains disabled. Quote/order responses use `payment_status: not_collected`; the mobile UI explicitly states that no payment is collected. No payment success, gateway reference, dispatch or rider location is fabricated.
- Tax configuration is not present. The quote marks tax as `not_configured` and warns that listed total excludes tax not already included in menu prices. No GST rate was inferred.
- During emulator validation, a real form bug was found and corrected: the optional landmark field had inherited the required-field validator.

## API and database

### API

- `GET /api/v1/customer/addresses`
- `POST /api/v1/customer/addresses`
- `PUT /api/v1/customer/addresses/{id}`
- `DELETE /api/v1/customer/addresses/{id}`
- `POST /api/v1/businesses/{id}/orders/quote`
- Food delivery order submission reuses `POST /api/v1/orders`, requires a checkout quote and `Idempotency-Key` for the Phase 2C food flow, and retains existing order routes for reservations, stays and other supported operations.
- Quote failures use explicit documented error codes, including `INVALID_ADDRESS`, `DELIVERY_OUT_OF_COVERAGE`, `MERCHANT_CLOSED`, `ORDERING_UNAVAILABLE`, `COVERAGE_NOT_CONFIGURED`, `QUOTE_EXPIRED`, `QUOTE_STALE`, `ITEM_UNAVAILABLE`, `INSUFFICIENT_STOCK`, `MINIMUM_ORDER_NOT_MET`, and idempotency conflicts.
- OpenAPI was updated in `api/openapi.yaml`.

### Migration

- Added sequential additive migration `backend/migrations/019_customer_addresses_checkout.sql` for `customer_addresses`, `checkout_quotes`, order address snapshots, quote linkage, idempotency and payment-status fields/indexes.
- The migration was applied to the local development database after creating `/tmp/grepmind-pre-phase2c.dump` inside the local PostgreSQL container. No existing migration was edited and no production database was accessed.
- Migration 019 and the Phase 2C integration fixture were exercised on disposable PostgreSQL/PostGIS. A clean replay of the full historical chain still needs pre-seeding for known unrelated historical prerequisites: migration 005 references absent `fashion`, and migration 008 assumes a Spice Garden business. Those historical migrations were not changed.

## Flutter implementation

- `customer_addresses_screen.dart`: saved-address list, select mode, edit/delete, default indicator and retry/empty states.
- `customer_address_form_screen.dart`: add/edit, manual address fields, optional Google map pin, Cuttack/Jajpur selection, default toggle, validation and error feedback.
- `checkout_review_screen.dart`: delivery/takeaway choice, saved address, server quote, line items and minor-unit totals, expiry/refresh, order-submit progress, errors and retry-safe idempotency behavior, and explicit no-payment messaging.
- `profile_screen.dart`: Saved addresses entry.
- `business_detail_screen.dart`: eligible cart flow enters checkout review instead of using the previous client-priced success sheet.
- `customer_orders_provider.dart`: passes the checkout idempotency key to the existing order API.
- Added `customer_address.dart` and address model tests.

## Validation evidence

- `go test -count=1 ./...` in WSL with `GREPMIND_TEST_DATABASE_URL` targeting the disposable PostGIS database — **PASS** (API, auth, discovery, operations, and remaining packages).
- PostgreSQL-backed API authorization/checkout integration cases in `TestOwnershipAndTenantRoutes` — **PASS** in the full Go run. They cover address ownership, invalid/cross-customer address use, serviceability, stale/expired quote, price and availability changes, idempotency replay/conflict, payment remaining uncollected, saved-address deletion preserving order snapshot, and finite-stock contention/restock. No stock is changed by quote creation.
- `flutter test --no-pub` in WSL — **PASS, 66 tests** after fixing the optional landmark validator. The final APK was rebuilt, installed, and launched after the display-only cleanup; Home and Profile → Saved addresses were checked on the emulator.
- Final full `flutter analyze --no-pub` — **120 diagnostics**, equal to the Phase 2B reported baseline of 120; analyzer exits nonzero due to existing diagnostics. No new diagnostic was attributed to the Phase 2C edits in the output review.
- Docker Compose API image rebuilt after the final Go stock-error change. The Compose file emits its existing obsolete `version` warning; no service architecture was changed.
- Emulator UI validated saved address creation, default selection, edit, explicit default-delete confirmation, deletion, cart navigation, server quote totals, quote expiry messaging, and the explicit no-payment state on the prior APK; no order was submitted. The final post-cleanup APK was then built, installed, and launched successfully; Home and Profile → Saved addresses were verified. The available local QA menu/address fixtures had been cleaned, so the final APK run did not revisit a populated checkout review.
- Emulator checkout used a temporary QA menu item and delivery toggle on an existing QA restaurant. Both were cleaned/restored after the test; verification showed zero remaining QA product, address, quote or order rows and the merchant delivery flag restored.
- `git diff --check` reports an existing trailing blank line at EOF in the pre-existing user-modified `final-architecture.md`; that unrelated file was not edited for Phase 2C.

## Security, concurrency and reliability

- Every saved-address operation scopes the address to the authenticated customer ID; quote resolution repeats that ownership check.
- The quote accepts only orderable restaurant/cafe capability and an approved merchant. Delivery requires the merchant's explicit delivery flag, business hours, service radius and customer address serviceability. Without coordinates it allows only a same-city address match; it does not assert GPS precision.
- Quote items are bounded and unique, quantities are bounded, and all price math uses integer minor units after server-side decimal conversion. Client totals are ignored.
- Quote state is time-limited (five minutes), bound to the customer, business, fulfillment mode, items, prices, and address update timestamp. Submission revalidates and locks rows in a transaction.
- No new SSE connection, polling loop, or customer-location permission request was added.
- No load/performance benchmark was run. Queries and item counts are bounded, but production scale behavior has not been measured.

## Known limitations and remaining risks

- Merchant tax/GST configuration and legal/accounting review are pending; quotes explicitly state that tax is not configured.
- There is no payment gateway in Phase 2C. Orders use the existing supported unpaid/no-payment path; do not interpret `not_collected` as paid.
- Delivery coverage is based on configured service radius for pinned addresses and same-city matching for manual addresses. It does not geocode text or certify municipal boundaries.
- End-to-end emulator order review depends on local eligible QA restaurant data. If such data is unavailable, report that UI step as blocked rather than claiming it passed.
- Historical migration chain prerequisites and backup/restore automation remain separate production-hardening work.
- No production data/services were used. No Phase 2D work was started.

## Acceptance recommendation

**PASS for backend/API and automated Phase 2C scope; PARTIAL for final emulator flow coverage.** Customer address CRUD, server-authoritative quote/review, no-payment presentation and cleanup were visually exercised on the prior APK; the final APK build/install/launch and Home/address entry were verified after the label cleanup. The final populated checkout review was not repeated because temporary QA fixtures had been cleaned. No checkout order was submitted.
