# ABASHYAKA — PHASE 02G & 02H ACCEPTANCE REPORT
## Merchant-Owned Food & Grocery Commerce Lifecycle & Discovery Ordering

**Repository:** `D:\grepmind-near`  
**Branch:** `abashyaka-dev-01`  
**Date:** 20 November 2026  
**Status:** ✅ **PASS (Isolated QA & Multi-Emulator Verified)**  

---

## 1. Executive Summary

Following the accepted **Phase 02F Architecture & Compatibility Audit**, this phase unifies the platform commerce engine with local merchant-owned Food (Restaurants/Cafes) and Grocery (Kiranas/Supermarkets) commerce. It satisfies the user directive:
> *"Order on Abashyaka screen can you list the food and meals first and bellow Fresh grocery list"*

All 16 gates of the merchant-owned commerce lifecycle were implemented, verified, and proven through end-to-end automated testing (`scripts/qa/validate_merchant_owned_e2e.mjs`) against the isolated QA environment (`grepmind_3e_qa_db` on port 55432, `grepmind_4c_qa_api` on port 18083, and `grepmind_4c_qa_otp_inbox` on port 18085).

---

## 2. Multi-Emulator & Environment Mapping

As mandated by `AGENTS.md`, validation was executed against the assigned multi-emulator topology:

| Role | Emulator Serial | AVD Name | Synthetic Phone | Status |
|---|---|---|---|---|
| **Customer** | `emulator-5554` | `Pixel_8` | `+919990000171` | ✅ Verified Active |
| **Merchant** | `emulator-5556` | `Pixel_8_Merchant_QA` | `+919990000172` | ✅ Verified Active |
| **Rider** | `emulator-5558` | `Pixel_8_Rider_QA` | `+919990000173` | ✅ Verified Active |

---

## 3. Architectural Implementations

### A. Database Migration 043 (`backend/migrations/043_merchant_owned_commerce_unification.sql`)
1. **Product Schema Extension**: Added `unit_label`, `mrp`, `barcode`, and `grocery_category` to `products` with B-tree indexes.
2. **Automated Delivery Job Creation Trigger**: Broadened `create_delivery_job_for_platform_preparation()` to fire for `order_source IN ('platform_catalog', 'merchant_catalog')`. Automatically resolves `target_locality_id` from `customer_orders.delivery_locality_id`, fallback to `customer_addresses`, and fallback to default locality.
3. **Delivery Job Cancellation Trigger**: Broadened `cancel_delivery_job_with_order()` to cancel delivery jobs when merchant orders transition to `cancelled` or `rejected`.
4. **Physical Pickup Custody Safeguards**: Broadened `prevent_cancel_after_delivery_pickup()` and `mark_delivery_cancelled_before_pickup()`.
5. **Cash on Delivery (COD) Accountability**: Broadened `protect_cod_obligation()` to accept merchant-owned orders and enforce synthetic COD checks.
6. **Payment Method Immutability**: Broadened `prevent_platform_order_payment_method_change()`.
7. **Payment Intent Validation**: Broadened `validate_payment_intent_snapshot()` to allow online payments (UPI) for merchant-catalog orders.
8. **Paid Cancellation Safeguards**: Broadened `prevent_paid_platform_order_cancellation()`.

### B. Go Backend Monolith Unification
1. **`backend/internal/operations/`**:
   - `ValidateCart` & `CreateCheckoutQuote`: Allowed categories broadened to `restaurant`, `cafe`, `grocery`, `supermarket`, `bakery`.
   - `CreateOrder`: Fixed foreign-key sequence by inserting `customer_orders` before `customer_order_items`, populated `delivery_locality_id`, and created synthetic `cod_obligations` with audit records.
2. **`backend/internal/platformfulfillment/`**:
   - Unified incoming order pipeline: Broadened queries to `WHERE o.order_source IN ('platform_catalog', 'merchant_catalog')`.
   - Populated `platform_vertical` dynamically via `COALESCE(o.platform_vertical, CASE WHEN o.order_type='food_delivery' THEN 'food' ELSE 'grocery' END)`.
   - Added item load fallback to `customer_order_items` for merchant orders.
   - Added finite stock restoration in `releaseInventory` when merchant orders are rejected.
3. **`backend/internal/deliverydispatch/`**:
   - Fixed `offerSelect` and `assignmentSelect` to safely coalesce `platform_vertical`.
   - Updated `loadOfferItems` and `ActiveJob` to load items from both `customer_order_items` and `platform_customer_order_items`.
4. **`backend/internal/payments/`**:
   - Broadened `CreateIntent` and `Refunds` to support `merchant_catalog` orders.
5. **`backend/cmd/api/main.go`**:
   - Supported `unit_label`, `mrp`, `barcode`, and `grocery_category` in merchant product creation and update endpoints.

### C. Flutter Mobile Presentation (`OrderShoppingHubScreen` & `ExploreScreen`)
1. **"Order on Abashyaka" Screen** (`apps/mobile/lib/core/screens/order_shopping_hub_screen.dart`):
   - Structured `_FeaturedCatalogSection` to present **🍲 Food & Meals** first with its own items list and "See all" action.
   - Rendered **🛒 Fresh Grocery** directly below Food & Meals with its own dedicated items list and "See all" action.
   - Filter pills maintain single-vertical toggles (`All`, `Food & Meals`, `Fresh Groceries`).
2. **Explore Screen** (`apps/mobile/lib/core/screens/explore_screen.dart`):
   - Reordered category filter chips: `('food', '🍲 Food & Meals', null)` placed before `('grocery', '🛒 Fresh Grocery', null)`.
3. **Product Model** (`apps/mobile/lib/core/models/business.dart`):
   - Added `unitLabel`, `mrp`, `barcode`, `groceryCategory`, and `discountPercent`.

---

## 4. 16-Gate Automated E2E Validation Results

Executed via `scripts/qa/validate_merchant_owned_e2e.mjs`:

```
========================================================================
  ABASHYAKA: MERCHANT-OWNED FOOD & GROCERY COMMERCE LIFECYCLE (02G/02H)
========================================================================

✓ Initial state ready (Rider online, Financial features enabled).
[AUTH] Authenticating actors: Customer (+919990000171), Merchant (+919990000172), Rider (+919990000173)...
✓ All 3 actors authenticated.

[Step 1] Merchant creating new Food and Grocery catalog items with 02G attributes...
  ✓ Created Food Product: 0c3f6c4d-4a53-452a-8ea1-50e3a0372b06 (Hyderabadi Dum Biryani Pot, MRP: ₹360, Price: ₹320, Unit: 1 Handi)
  ✓ Created Grocery Product: 1c874f63-3015-4f2b-bf88-524ab8ba1589 (Fortune Sunlite Oil, MRP: ₹170, Price: ₹145, Barcode: 8901234567890, Cat: Edible Oils)
  ✓ DB Food Record: Hyderabadi Dum Biryani Pot|320.00|360.00|1 Handi (750g)|35
  ✓ DB Grocery Record: Fortune Sunlite Refined Sunflower Oil|145.00|170.00|1 Litre Pouch|8901234567890|Edible Oils & Ghee

[Step 2] Customer fetching merchant products via Discovery API...
  ✓ Customer discovered Food: Hyderabadi Dum Biryani Pot (Unit: 1 Handi (750g), Price: ₹320, MRP: ₹360)
  ✓ Customer discovered Grocery: Fortune Sunlite Refined Sunflower Oil (Unit: 1 Litre Pouch, Category: Edible Oils & Ghee)

[Step 3] Customer generating checkout quote for Merchant Food order...
  ✓ Quote created: 033d8b11-837b-46bd-a233-4dca0a335db6 | Subtotal: ₹640 | Delivery: ₹30 | Total: ₹670

[Step 4] Customer placing Merchant-Owned order (payment_method='cash_on_delivery')...
  ✓ Merchant Order Placed: Reference=GN-C63FB408 (ID: c63fb408-f60f-4c7e-a962-fefa7d04c808)
    Status: placed | Source: merchant_catalog | Payment: cash_on_delivery/not_collected
  ✓ Finite inventory safely deducted: 35 -> 33 (expected 33)

[Step 5] Merchant retrieving incoming orders via Unified Platform Orders API...
  ✓ Merchant sees order in incoming queue: ID=c63fb408-f60f-4c7e-a962-fefa7d04c808, Status=placed

[Step 6] Merchant accepting order...
  ✓ Merchant accepted order (status='accepted').

[Step 7] Merchant marks preparing -> Verifying delivery_job trigger for merchant_catalog order...
  ✓ Merchant started preparing order.
  ✓ Delivery Job successfully created by DB trigger: 5fd174b3-44d1-4537-a0e7-ff90772da176 | State: pending_dispatch|assigned|02200000-0000-4000-8000-000000000101

[Step 8] Triggering delivery dispatch runner to offer job to Rider...
  ✓ System dispatched delivery offer to Rider (+919990000173): OfferID=4a2c1845-5f12-4897-bb47-9aaf4777a1bd

[Step 9] Rider accepting delivery offer...
  ✓ Rider accepted offer (job state='assigned').

[Step 10] Merchant marking order ready & Rider arriving at store...
  ✓ Merchant marked order ready.
  ✓ Rider arrived at store (state='at_pickup').

[Step 11] Merchant issuing pickup code & Rider verifying custody transfer...
  ✓ Merchant issued single-use pickup code: 27225749
  ✓ Rider verified pickup code! Custody transferred (Order status='out_for_delivery').

[Step 12] Rider en route and Customer generating delivery confirmation code...
  ✓ Customer generated delivery confirmation code: 79757590

[Step 13] Rider confirming delivery and collecting COD...
  ✓ Rider confirmed delivery and collected COD!

[Step 14] Verifying final PostgreSQL state...
  ✓ Order State: delivered|cash_on_delivery (expected: delivered|cash_on_delivery)
  ✓ Job Execution State: delivered (expected: delivered)
  ✓ COD Obligation State: collected|67000 (expected: collected|67000)

[Step 15] Testing Rejection & Finite Inventory Restoration path...
  ✓ Order 2 created (d91d9dc7-51eb-4ed5-9c5e-ebd80cf7d666). Stock decremented: 33 -> 30 (expected 30)
  ✓ Merchant rejected order 2. Finite inventory safely restored: 30 -> 33 (expected 33)

[Step 16] Testing Merchant-Owned UPI Payment & Sandbox Capture Lifecycle...
  ✓ Merchant-Owned Grocery UPI Order Placed: ID=ccfca26b-a97a-4ec3-9602-1884bad9c97a, Total=₹320, Payment=upi/not_collected
  ✓ Payment intent created for merchant-owned order
  ✓ Payment session initialized
  ✓ Sandbox UPI capture successful! Payment status in DB: paid (expected: paid)

========================================================================
🎉 ALL 16 GATES OF MERCHANT-OWNED FOOD & GROCERY COMMERCE PASSED!
========================================================================
```

---

## 5. Verification & Test Suite Execution

### A. Go Backend Tests
```bash
go test -v -count=1 ./internal/operations ./internal/platformfulfillment ./internal/platformcommerce ./internal/discovery ./internal/deliverydispatch ./internal/payments
```
- `internal/operations`: **PASS (0.020s)**
- `internal/platformfulfillment`: **PASS (0.019s)**
- `internal/platformcommerce`: **PASS (0.013s)**
- `internal/discovery`: **PASS (0.018s)**
- `internal/deliverydispatch`: **PASS (0.011s)**
- `internal/payments`: **PASS (0.011s)**
- **Result:** **100% PASS**

### B. Flutter Tests
```bash
flutter test test/workspace_navigation_test.dart test/platform_catalog_test.dart
```
- `workspace_navigation_test.dart`: **3/3 PASS**
- `platform_catalog_test.dart`: **7/7 PASS**
- **Result:** **100% PASS**

---

## 6. Security & Invariant Verification

1. **Isolation Invariant**: Merchant-owned orders remain strictly bounded by `business_id`. Unaffiliated merchants cannot read or update products or orders of another business.
2. **Single-Merchant Cart Invariant**: A merchant checkout quote strictly validates items against a single `business_id`. Mixing items across multiple merchants in a single checkout quote is strictly rejected.
3. **Database Guard Invariant**: All delivery jobs for merchant-owned orders require an approved business with `delivery_enabled = true`.
4. **Custody & Pickup Code Invariant**: Pickup codes are single-use, cryptographically verified, and valid only after merchant marks order ready and rider arrives at pickup.
5. **Inventory Consistency Invariant**: Finite inventory deductions occur under transactional row locks and are automatically restored upon merchant rejection or customer cancellation before pickup.

---

## 7. Deliverables Summary

- **Migration**: [043_merchant_owned_commerce_unification.sql](file:///d:/grepmind-near/backend/migrations/043_merchant_owned_commerce_unification.sql)
- **Validation Script**: [validate_merchant_owned_e2e.mjs](file:///d:/grepmind-near/scripts/qa/validate_merchant_owned_e2e.mjs)
- **Mobile Client**: [order_shopping_hub_screen.dart](file:///d:/grepmind-near/apps/mobile/lib/core/screens/order_shopping_hub_screen.dart), [explore_screen.dart](file:///d:/grepmind-near/apps/mobile/lib/core/screens/explore_screen.dart), [business.dart](file:///d:/grepmind-near/apps/mobile/lib/core/models/business.dart)
- **Backend**: [operations/service.go](file:///d:/grepmind-near/backend/internal/operations/service.go), [platformfulfillment/service.go](file:///d:/grepmind-near/backend/internal/platformfulfillment/service.go), [deliverydispatch/service.go](file:///d:/grepmind-near/backend/internal/deliverydispatch/service.go), [payments/service.go](file:///d:/grepmind-near/backend/internal/payments/service.go)
- **Contract**: [api/openapi.yaml](file:///d:/grepmind-near/api/openapi.yaml)
- **Acceptance Report**: [docs/phases/ABASHYAKA_PHASE_02G_02H_MERCHANT_OWNED_COMMERCE_ACCEPTANCE.md](file:///d:/grepmind-near/docs/phases/ABASHYAKA_PHASE_02G_02H_MERCHANT_OWNED_COMMERCE_ACCEPTANCE.md)
