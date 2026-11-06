# Phase 2A — Existing commerce audit and contract design

**Date:** 6 November 2026
**Status:** Audit/design only. No application source, OpenAPI contract, or database migration was changed for Phase 2A.
**Approval gate:** Stop here. Phase 2B requires explicit user approval.

## Executive recommendation

Build customer commerce by extending the existing `customer_orders` / `customer_order_items` model and the existing Go `operations.Service`, not by introducing a second orders system. The restaurant checkout currently creates persisted food orders, and table/hotel flows use the same table. Phase 2 should retain those behaviors while replacing the in-memory one-screen cart, free-text/no-op address editor, client-estimated total, silent order-load failure, and cached-first order detail fallback.

Do not make a checkout look paid. Phase 2 can persist an order and display an explicit payment state such as **Not collected / Pending setup**. `confirmed` payment status must only be reachable from a later verified payment-provider event in Phase 6. No customer money collection is authorized in Phase 2.

## Evidence examined

- `backend/migrations/001_core_schema.sql`: `categories` is a controlled taxonomy; `products` has price, publication and coarse `stock_status` (`unknown`, `in_stock`, `out_of_stock`, `limited`), but no available quantity or reservation counter.
- `backend/migrations/008_hospitality_and_food_delivery.sql`: business-level `delivery_enabled`, `delivery_time_mins`, `delivery_fee`, `min_order_amount`, `table_booking_enabled`, and `room_booking_enabled`; food tags on products. No category capability relation was found in the inspected schema.
- `backend/migrations/011_operational_bookings.sql`: existing `customer_orders` and `customer_order_items` store food delivery, table reservation, and hotel booking data, item snapshots, totals, status, and timestamps. There is no customer-address table, payment state, checkout idempotency key, or order-status event ledger in this migration.
- `backend/internal/operations/service.go`: `CreateOrder`, customer list/get/cancel, merchant status transition, and public availability are implemented. Totals and prices are read server-side, and product ownership is constrained to the requested business. Delivery fee and minimum order are read from the business. `tax_amount` is written as zero. A product is accepted when published and not marked `out_of_stock`; quantity is not decremented because stock is not modeled numerically.
- `backend/cmd/api/main.go`: authenticated routes exist for `POST /businesses/{id}/orders`, `GET /customer/orders`, `GET /orders/{id}`, `POST /orders/{id}/cancel`, and `PATCH /merchant/orders/{id}/status`.
- `api/openapi.yaml`: documents those routes and `CreateCustomerOrderRequest`; the request schema allows quantity up to 99 while the service accepts at most 50. The create endpoint documents 409 for business/inventory/minimum conflicts, while the current handler returns 400 `ORDER_REJECTED` for those errors.
- `apps/mobile/lib/core/screens/business_detail_screen.dart`: product quantity state is an in-memory `Map<String,int>` on the business detail screen. The delivery checkout sheet estimates a flat ₹30 fee and zero tax on the client, irrespective of the business values read by the API. Its address `Change` button has no action and the initial delivery address is empty. The create API still calculates persisted totals on the server.
- `apps/mobile/lib/core/providers/customer_orders_provider.dart`: loads `/customer/orders`, but catches all failures and replaces the list with an empty list. There is no loading/error/retry state. Create and cancel use existing API routes.
- `apps/mobile/lib/core/screens/order_tracking_screen.dart`: displays an explicit “Live courier location is not available” message; keep that truthful behavior. It obtains the order from the in-memory list and falls back to the first order if the requested ID is absent, despite the existing exact-order API route.
- `apps/mobile/lib/core/screens/order_history_screen.dart` and `customer_order.dart`: the Orders screen displays food/reservation/stay records and current statuses but does not have a dedicated retry state, robust exact-detail fetch, or a reorder workflow.
- `apps/mobile/lib/core/providers/app_provider.dart` and catalog providers: catalog and product APIs already support published products/services, stock status, price and business scoping; use these existing records rather than adding a duplicate catalog.

## Reuse / extend / new screen matrix

| Area | Existing implementation | Phase 2 direction |
|---|---|---|
| Restaurant menu and product catalog | Business profile product tab, merchant product CRUD, `products` table | Reuse. Add cart interactions for eligible products and consistently show server catalog price/stock state. |
| Customer cart | Business detail `_cart` map; lost when screen is disposed | Replace with a cart state/provider scoped to authenticated user and one `business_id`. Persist locally for restoration; do not add a server cart table unless multi-device cart sync becomes a confirmed requirement. |
| Delivery / takeaway checkout | Bottom sheet calls existing order API; client estimates totals | Reuse the entry point and refine the review UI. Obtain a server quote and show authoritative item, delivery, tax, and grand-total fields. The create request sends product IDs/quantities and fulfillment details only; never trust client totals. |
| Delivery address | Single free-text string; no saved-address API/table; Change action is a no-op | Add address management and map pin/landmark capture. Store address under the authenticated customer and minimize location precision/retention. |
| Order persistence | `customer_orders` + `customer_order_items` | Extend compatibly with additive migration(s) only after the contract/data design is approved and tested on an isolated DB. Keep one customer order aggregate for food orders and hospitality bookings. |
| Payment | No `payment_status` field or gateway; create returns order status | Add a non-collecting Phase 2 state and clear UI copy. Keep successful/confirmed payment unreachable until a provider is selected and server webhook verification exists in Phase 6. |
| Order list | Existing Orders tab and `GET /customer/orders` | Reuse. Add explicit loading, empty, error, retry and pull-to-refresh states; retain cancellation only when server says eligible. |
| Order detail/tracking | Existing tracking screen; exact GET API exists; courier message is honest | Reuse and load by exact `order_id`. Show persisted status/timestamps and delivery timeline. Remove/use no static route or fake rider/ETA data. |
| Reservations and hotel stays | Existing profile sheets and same order endpoints/table | Preserve unchanged. Add regression coverage before and after shared order changes; do not turn them into food cart items or migrate them to another model. |
| Category capability | 19 taxonomy records are present in the local DB audit; category schema contains taxonomy fields only | Do not infer orderability from category name or icon. Define explicit, server-backed ordering capability metadata with category and merchant override semantics before enabling shop ordering beyond existing food delivery. |

## Customer ordering architecture

1. **Discovery/catalog:** existing discovery APIs return only published business/catalog records and category data. Product detail and cart eligibility are evaluated from server fields, not client category labels.
2. **Capability gate:** the API determines whether an approved business supports product ordering, food delivery, takeaway, or another fulfillment option. Capability defaults must come from explicit data; merchant configuration may narrow but must not bypass category/business policy.
3. **Single-merchant cart:** a cart contains items from one business. Switching businesses starts or restores that business's separately keyed cart; never silently merge sellers. Persist only product IDs, quantities, and enough display metadata for restoration; refresh price, publication and stock from the API at checkout.
4. **Quote:** server receives item IDs/quantities, fulfillment type, and a customer-owned address identifier. It re-reads current product prices and availability, capability, minimum order, delivery coverage, delivery fee and applicable tax configuration, then returns an expiring quote with a breakdown and a quote/version identifier. No payment is taken.
5. **Create:** authenticated customer posts the quote reference plus order intent with an idempotency key. The server recomputes or atomically validates the quote under transaction/row locks, enforces ownership and current inventory/coverage, snapshots line items and totals, and creates exactly one order for the key.
6. **Lifecycle:** merchant/customer status updates follow a server-enforced state machine and persist status events. Existing bookings remain records in `customer_orders` with their current reservation-specific fields.
7. **Display:** Orders list and details load from API. Payment state is separate from fulfillment state. No GPS marker, rider assignment, or precise ETA is shown unless backed by persisted authorized live data.

## Category-specific ordering eligibility rules

The existing taxonomy does not define ordering capabilities. Proposed safe rules for contract/design:

- **Current food delivery:** continue to require the business's server-side `delivery_enabled` flag, approved business status, a published product tied to the same business, supported fulfillment type, minimum order, and covered delivery address. Takeaway remains a separate explicit fulfillment choice.
- **Other shop products (for example grocery, pharmacy, fashion, hardware):** remain browse-only until the capability matrix explicitly marks the category/business as orderable and the merchant has configured fulfillment and stock policy. Do not treat presence of a product or `in_stock` label as sufficient proof.
- **Services/trades:** remain service-request/appointment flows, not product cart checkout. Reuse the existing service request and availability state machine.
- **Restaurants/cafes:** food items use the existing order types. Table reservations remain `table_reservation` records and are not checkout payments.
- **Hotels/stays:** room booking remains `hotel_booking`; availability/capacity and date-overlap semantics must be verified separately before presenting a reservation as confirmed.
- **Other category records:** no orderability is assumed. A default-deny capability registry should make unsupported behavior explicit and testable across the 19 taxonomy entries.

Before a later implementation changes the taxonomy, publish a 19-row capability matrix with category slug, browse-only/product-order/service-request/appointment/table/room flags, required merchant setup, and customer CTA. The exact matrix is a Phase 2B design dependency if shop categories are included in the first cart release.

## Proposed API contracts (design only; no contract changed)

### Reuse existing routes

- `GET /api/v1/customer/orders` — customer-owned, newest first; add bounded cursor pagination when the list needs more than the current first 100.
- `GET /api/v1/orders/{id}` — exact customer-owned order lookup; preserve 404 for missing or not-owned records.
- `POST /api/v1/orders/{id}/cancel` — existing eligibility/state rules remain authoritative.
- `PATCH /api/v1/merchant/orders/{id}/status` — existing `business_id` membership check and state transitions remain authoritative; add race/tenant regression tests.
- `POST /api/v1/businesses/{id}/orders` — preserve as the one order-creation route for food delivery/takeaway and existing hospitality flows. Do not create `/customer/orders` as a parallel POST model.

### Proposed additions for later approval

- `POST /api/v1/businesses/{id}/orders/quote`: request includes `items[{product_id, quantity}]`, `fulfillment_type`, and optional `address_id`; response includes server-priced lines, item subtotal, delivery fee, tax breakdown, total, currency, eligibility errors, and quote expiry/version. No request field accepts a trusted total or a client-selected price.
- `GET /api/v1/customer/addresses`, `POST /api/v1/customer/addresses`, `PATCH /api/v1/customer/addresses/{id}`, `DELETE /api/v1/customer/addresses/{id}`: authenticated owner-scoped CRUD, bounded fields, validated coordinates, and no cross-user access.
- Existing `POST /businesses/{id}/orders`: add an `Idempotency-Key` header (or equivalent documented request key) for duplicate-submit protection; accept quote reference/address ID. Preserve its current route and response envelope.
- Order responses: add explicit `payment_status` only with a separately defined transition authority. Before Phase 6, no API/client action may set it to `confirmed`; no gateway call or real-money collection is allowed.

### Contract defects to resolve before implementation

- Align order item quantity maximum across OpenAPI, Go validation, DB constraints, and Flutter. Current OpenAPI permits 99 while service and DB permit 50.
- Document current `400 ORDER_REJECTED` behavior or deliberately normalize it to the contract's `409` in a reviewed contract change; do not silently diverge.
- Specify unauthenticated/unauthorized responses and request IDs consistently.
- Specify quote expiration, stale-price/stock errors, address-coverage errors, idempotency replay semantics, and cancellation conflicts.

## Order state machine proposal

Keep fulfillment lifecycle and payment lifecycle separate.

```text
Fulfillment: placed -> confirmed -> preparing -> out_for_delivery -> delivered -> completed
                    \-> cancelled (only in permitted pre-fulfillment states)

Payment before Phase 6: not_collected / setup_pending; no transition to confirmed from the app
Payment after Phase 6 only: pending -> confirmed | failed -> retry_pending (gateway-verified rules)
```

Current implementation already has fulfillment states `placed`, `confirmed`, `preparing`, `out_for_delivery`, `delivered`, `completed`, and `cancelled`. Merchant transition validation exists. Food orders start `placed`; table and hotel requests are currently inserted as `confirmed` at customer submission. Phase 2 must preserve existing reservation behavior unless the audit/acceptance matrix establishes a safer compatible correction; do not conflate merchant confirmation with payment confirmation. Add append-only order status events for auditability if the chosen migration plan requires them.

## Payment-pending design (Phase 2 only)

- No checkout SDK, UPI intent, card collection, provider credentials, payment webhook, or real customer collection in Phase 2.
- Customer sees a clear non-payment state: order submitted; payment collection is not enabled in this build. The UI must not use “Paid”, “Payment successful”, a green payment confirmation, or success receipt language.
- Keep payment independent from fulfillment. If Phase 2 adds the status field, initialize only to an explicit non-collected/pending-setup state and reject any client transition to confirmed/paid. The exact enum and public contract are a Phase 2B approval item.
- Reserve `confirmed` as a future server-only result of verifying an authentic provider event and matching order, amount, currency, and provider IDs. This remains scheduled for Phase 6.
- Customer payments remain deferred; merchant registration/subscription billing is a separate business model and not part of this commerce slice.

## Database change plan (proposal; no migration created)

1. Preserve `customer_orders` and `customer_order_items`; add only backwards-compatible fields/tables needed by approved scope.
2. Add a customer-owned address table with `user_id` FK, label/contact, structured locality/address/landmark, and nullable validated point for map-pin placement. Store minimum precision needed for coverage and fulfillment; use parameterized SQL and enforce ownership in every query.
3. Model inventory quantity separately from the current coarse stock label if exact stock validation is required. Select a transaction/locking approach that prevents concurrent orders from overselling. Do not pretend `stock_status` is a numeric count.
4. Add order idempotency key storage with a unique customer/business scope, request fingerprint, response/order reference, and expiry/retention policy. A repeated identical key returns the original result; a different payload under the same key conflicts.
5. Add payment and order-event columns/tables only after their enum, transition authority, retention, and compatibility rules are approved. No real payment records or gateway secrets in Phase 2.
6. Keep tax configuration server-side and auditable; do not calculate tax as a hardcoded zero or accept a tax rate from the app. Exact Indian tax treatment needs qualified accounting/legal review.
7. Test migration upgrade and fresh install in isolated disposable PostgreSQL databases before applying to a developer Compose DB. Do not modify migrations 001–017.

## UI and navigation specification

- Customer bottom navigation remains Home, Explore, Nearby, Orders, Profile. Product cards open existing business/product detail; Cart appears only after adding an eligible item and stays scoped to its business.
- Add a polished Cart screen/route with merchant identity, item photo/name/price, quantity controls, remove action, current availability, subtotal, and an empty-cart state. Show a merchant-switch confirmation if the user adds from a different seller while a cart exists.
- Add a saved-address selector and address editor with map pin, landmark, label, contact phone, validation, and loading/error/saved states. Request location only when the customer chooses the map-pin action; manual entry remains possible.
- Add Checkout review with delivery/takeaway selector only when supported, address selection only for delivery, server quote breakdown, stale quote retry, and explicit non-payment disclosure. Disable submit for empty/unavailable cart, missing address, unsupported coverage, or quote failure.
- Customer Orders gets loading, empty, retryable error, pull-to-refresh, status/date/type and concise totals. Details load by exact order ID and show persisted fulfillment milestones, item/price snapshots, address, cancel eligibility, and payment-not-collected status.
- A reorder action is offered only when the original seller remains approved/orderable and every item is currently published, available, and priced; otherwise present item-level reasons and let the customer rebuild the cart.
- Keep Saved businesses in Profile and do not change the Phase 1 workspace navigation.
- Use existing Grepmind Near tokens/components: light-first, blue `#2457D6`, teal `#0F766E`, Inter, 16px cards, accessible contrast, >=48dp targets, responsive text, and explicit loading/empty/error states.

## Security and performance acceptance criteria

- Every customer address, cart restoration record, order, cancellation, quote, and status event is authenticated and scoped to `customer_user_id`; return 404 for another customer's resource.
- Every merchant order query and status update is scoped to `business_id` membership. Use tenant-scoped reads/updates to avoid record-existence leaks. Preserve owner/manager/staff authorization policy and root protections.
- Recompute item prices, stock, category/business capability, minimum, delivery coverage/fee, taxes, and grand total on the server. Client values are display hints only.
- Use a transaction with explicit concurrency control for inventory reservation, quote finalization, idempotency, and order creation. Test simultaneous last-item purchase and duplicate submission.
- Validate payload sizes, array limits, quantities, coordinates, address lengths, quote expiry, and rate limits. Avoid putting full address/coordinates in logs, analytics, SSE payloads, or crash reports.
- SSE, if used for order status, must authenticate and scope subscriptions to the owning customer or authorized business. Do not add a client polling loop or a new SSE stream for a screen that is not active; close subscriptions on dispose.
- Use cursor pagination and DB indexes matching customer/business/status/time filters. Avoid N+1 order-item loads; aggregate or batch item fetches for a list.
- Validate with Go unit + PostgreSQL integration tests, Flutter state/widget tests, OpenAPI validation, and emulator ordering UI. Confirm no additional analyzer diagnostics, no fake payment/GPS success, and no regression to table reservations/hotel bookings.

## Phase 2 implementation gates

1. **2A — Audit/design (this document):** complete. Stop for explicit approval before 2B.
2. **2B — Cart and product ordering:** only after approval; persist/restoration, quantity changes, price/stock/capability validation, minimum order, single-merchant rules, error states.
3. **2C — Addresses and checkout:** only after approval; address CRUD/map pin, coverage, authoritative quote and non-collecting pending state.
4. **2D — Orders and tracking:** only after approval; loading/error/detail-by-ID, state timelines, cancellation/reorder eligibility, verification-ready interface without live rider tracking.
5. **2E — Integration/acceptance:** only after preceding subphases are approved and implemented; full tests, emulator flow, concurrency/idempotency/security/performance evidence.

## Phase 2A test record

No application test or build was run specifically for this documentation-only audit. Evidence was gathered by inspecting the source files and existing audit records listed above. Existing test results must not be represented as Phase 2A test passes. No Phase 2 source, OpenAPI, or database changes were made.
