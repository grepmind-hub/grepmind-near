# Phase 2B — Customer Cart & Product Ordering

**Evidence date:** 6 November 2026  
**Status:** Implemented; validation completed with the limitations below. Stop at this phase gate; Phase 2C requires explicit approval.

## Scope delivered

- Product ordering is enabled only when the backend confirms a published, approved, delivery-enabled restaurant/cafe. The existing category capability rules and all other 19-category discovery behavior remain in place; services, reservations and hotel bookings do not become cart products.
- Added a single-merchant customer cart with quantity adjustment, removal, clearing, badge/entry point, merchant-switch confirmation, per-user local persistence and restoration. Persisted state contains product IDs/quantities and display hints; opening and changing a cart triggers server validation.
- Server validation returns authoritative current unit prices, subtotal, currency, minimum-order amount and item availability. Monetary comparisons/calculations use integer minor units. Changed prices and unavailable products are surfaced; network failure is retryable.
- Inventory is explicit: legacy records default to `untracked`; finite inventory uses a nonnegative numeric quantity. Finite stock is rechecked and decremented under transaction/row lock in the existing food order creation path; cancellation restores the reserved quantity once.
- Existing `customer_orders` and `customer_order_items` remain the operational order model. No new parallel order table was created.
- Cart UI provides empty, loading/validating, unavailable/price-change, minimum-order and retry states. Full checkout is deferred to Phase 2C; this phase did not collect payment or place an emulator order.

## API, schema and changed files

### Database

- Added `backend/migrations/018_product_inventory.sql` (additive): `inventory_mode`, `available_quantity`, consistency constraints and an index. Existing catalog rows retain `untracked` mode and `NULL` quantity.
- Applied on the local development database and a disposable PostgreSQL test database. Production was not accessed. The historical full migration chain still has a pre-existing failure at migration 005 because it references the `fashion` category absent from migration 001; no historical migration was edited. The existing local development database had already advanced through that history before migration 018 was applied.

### API contract

- Added `POST /api/v1/businesses/{id}/cart/validate` (authenticated customer): validates a bounded list of unique product IDs and quantities; returns server price, subtotal, currency, merchant minimum and per-item availability/change details.
- Merchant catalog product create/update supports inventory mode and finite quantity. Existing `POST /api/v1/orders` food-delivery processing now checks and reserves finite inventory atomically using the existing order model.
- Relevant API and implementation files: `api/openapi.yaml`, `backend/cmd/api/main.go`, `backend/cmd/api/security_integration_test.go`, `backend/internal/discovery/service.go`, `backend/internal/operations/service.go`, `backend/internal/operations/cart_test.go`.

### Mobile

- `apps/mobile/lib/core/models/business.dart` — inventory/capability decoding and food-business route selection.
- `apps/mobile/lib/core/providers/app_provider.dart` — product inventory model/provider fields.
- `apps/mobile/lib/core/providers/cart_provider.dart` — persistent single-merchant cart and debounced server validation.
- `apps/mobile/lib/core/screens/customer_cart_screen.dart` — cart screen.
- `apps/mobile/lib/core/screens/business_detail_screen.dart` — eligible product controls and cart entry.
- `apps/mobile/lib/core/screens/merchant_catalog_screen.dart` — merchant finite/untracked stock editor.
- `apps/mobile/lib/core/screens/explore_screen.dart`, `apps/mobile/lib/core/screens/search_results_screen.dart` — capability-aware navigation.
- `apps/mobile/test/customer_cart_test.dart` — cart persistence, isolation, bounds, price/availability/error-state tests.

Project tracking was updated in `AGENTS.md`, `docs/phases/README.md`, and `codex-implementation.md`.

## Security and correctness checks

- Customer role is checked by the API. Cart validation scopes each product to the requested eligible merchant and avoids leaking cross-business product data.
- Server order creation does not trust client unit prices or totals. Quantity bounds, unique product IDs, orderability, publication, availability and finite stock are checked on the server.
- Merchant catalog writes remain protected by active membership/business scope. Stock decrement and cancellation restock run in the order transaction with row locks to prevent concurrent oversell.
- Unsupported categories fail closed for cart validation. The capability is not inferred from a client role or an `accepts_requests` flag.

## Validation evidence

- `cd backend && go test ./...` — **PASS**.
- PostgreSQL-backed `TestOwnershipAndTenantRoutes` against isolated `grepmind_phase2b` database — **PASS**. Covered customer authorization, business isolation, server price/minimum/stock validation, merchant inventory update isolation, simultaneous purchase of the final finite unit, and cancellation restock/idempotency.
- `cd apps/mobile && flutter test --no-pub` — **PASS, 64 tests**.
- `flutter analyze --no-pub` — FAIL under the repository analyzer exit policy: 120 diagnostics, including warnings and informational lints; the recorded Phase 1 baseline was 119. This is an increase of 1 overall, but no same-revision baseline run was available to attribute each new diagnostic precisely. Warnings remain in untouched admin portal, Home feed, order history/tracking and service profile files, plus informational lints in touched legacy screens and the new cart code.
- Existing Android `BuildRun` workflow with WSL Flutter SDK and ADB server port 5039 — **PASS** (latest debug APK installed/launched on `Medium_Phone_API_37.0`). Visual emulator check opened an eligible Jajpur restaurant, added one finite-stock product, opened the cart and displayed the server-verified ₹95 subtotal, then removed the item. No order was submitted. The emulator UI was inspected live; no screenshot artifact was saved to the repository.
- API container was rebuilt and restarted during the implementation. The updated discovery API returned `delivery_enabled=true` for an eligible restaurant, and the Android detail screen rendered the restaurant menu and Order Delivery action.
- `git diff --check` — Phase 2B file set passes. Repository-wide check reports a trailing blank line at EOF in the pre-existing user-modified `final-architecture.md`; it was left untouched.

## Performance and resource impact

- Cart data is local and scoped per authenticated user. Server validation is debounced after quantity edits; cart state adds no SSE subscription or polling loop.
- No benchmark/load test was run. The server performs bounded validation (at most 50 lines) with parameterized queries. Performance under large catalogs or concurrent high-volume ordering remains unmeasured.

## Known limitations / remaining risks

- Full checkout, customer address management, delivery-eligibility routing, taxes/fees quote review and payment-pending UX are Phase 2C.
- A server-side durable cart is not introduced; cart restoration is local to the app installation and authenticated user. The backend remains authoritative when validating and ordering.
- Existing catalog entries intentionally remain `untracked` until a merchant explicitly opts into finite quantity. This avoids inventing legacy stock levels.
- The full legacy migration chain is not reproducible from a clean database due to the earlier migration 005 category mismatch. This needs a separately approved migration-history repair plan; migration 018 itself was tested/applied additively.
- Performance/load baseline and Android screenshot capture are not part of executed evidence.

## Acceptance recommendation

**PASS for Phase 2B scope, with noted limits.** Cart and product ordering can proceed to review. Do not start Phase 2C until separately approved.

