# ABASHYAKA — PHASE 02I ACCEPTANCE REPORT
## Merchant-Owned Grocery UI, Clean Food Dispatch Regression & Integrity Verification

**Date:** 20 November 2026  
**Repository:** `D:\grepmind-near`  
**Branch:** `abashyaka-dev-01`  
**Execution Surface:** 3 Dedicated Android Emulators (`emulator-5554`, `emulator-5556`, `emulator-5558`) + Isolated QA Stack  
**Status:** **QA PASS** (Phase 02E Food COD & Sandbox UPI Workflows Accepted; Merchant-Owned Grocery UI Verified; Clean Dispatch Autonomy Confirmed; Production Readiness Pending Separation of Production Migrations)

---

### 1. Executive Summary

Phase 02I is a targeted acceptance pass executed directly on three Android emulators (`Pixel_8`, `Pixel_8_Merchant_QA`, and `Pixel_8_Rider_QA`) without relying on synthetic mocks or bypassing the client UI. It formalizes the acceptance of Phase 02E's Food workflows, validates a genuine merchant-owned Grocery storefront and cart, proves full dispatch runner autonomy during a fresh food delivery without manual database resets or backend restarts, and confirms that the Phase 01F.1 doctor and transport integrity fixes remain intact.

#### Key Milestones Validated:
1. **Phase 02E Formal Acceptance:** Accepted Phase 02E's Cash on Delivery (COD) and Sandbox UPI Food UI lifecycles as QA PASS.
2. **Genuine Merchant-Owned Grocery Storefront & Cart:** Customer discovered FMCG groceries (Amul Taaza Milk, Aashirvaad MP Atta) under "Daily Groceries & Essentials", verified MRP, discount, units, barcodes, and single-merchant server quoting (Subtotal ₹269.00 + Delivery fee ₹30.00 = Total ₹299.00).
3. **End-to-End Grocery COD Lifecycle:** Completed full order `GN-BA2EE85A` (`ba2ee85a-20de-4a2e-88a9-16eaef3080a6`) across Customer, Merchant, and Rider Android UIs with mutual 8-digit verification codes and synthetic COD collection recorded in PostgreSQL.
4. **Clean Food Dispatch Regression (Zero DB Resets / Zero Backend Patching):** Executed a fresh food order `GN-42904B10` (`42904b10-4079-4eac-bcc2-bc3fbed3a9fd`) for *Hyderabadi Dum Biryani Pot* (₹350.00 COD). When Merchant tapped "Start preparation", the Go backend autonomous dispatch runner (`deliverydispatch/service.go`) created `delivery_jobs` and dispatched `delivery_offers` in real time with zero manual intervention. Rider accepted from Dashboard, verified partner pickup with merchant-issued code `03101019`, verified customer delivery with code `37694722`, and collected ₹350.00 synthetic COD.
5. **Phase 01F.1 Doctor/Transport Integrity Intact:** Executed `test/doctor_transport_integrity_test.dart` (4/4 tests passed) and 35+ core Flutter test cases with 100% pass rate.

---

### 2. Multi-Emulator Setup & Authenticated Identities

All UI validation was strictly performed against the assigned AVD emulators verified via `adb -s <serial> emu avd name`:

| Role | AVD Name | Assigned Serial | Authenticated Phone | User ID | Current UI State |
|---|---|---|---|---|---|
| **Customer** | `Pixel_8` | `emulator-5554` | `+919990000171` | `3e000000-0000-4000-8000-000000000001` | Active Session (`OrderShoppingHubScreen` / Home) |
| **Merchant** | `Pixel_8_Merchant_QA` | `emulator-5556` | `+919990000172` | `3e000000-0000-4000-8000-000000000002` | Partner Fulfillment Pipeline (`History` tab) |
| **Rider** | `Pixel_8_Rider_QA` | `emulator-5558` | `+919990000173` | `3e000000-0000-4000-8000-000000000003` | Deliveries (`Delivery completed with customer verification`) |

#### Isolated QA Stack:
- **PostgreSQL Database:** `grepmind_3e_qa_db` on `127.0.0.1:55432` (database `grepmind_3e_qa`, user `qa3e`)
- **API Server:** `grepmind_4c_qa_api` on `http://127.0.0.1:18083`
- **OTP Inbox:** `grepmind_4c_qa_otp_inbox` on `http://127.0.0.1:18085`

---

### 3. Verification 1: Genuine Merchant-Owned Grocery Storefront & Cart

#### Storefront Configuration:
- **Business:** `3e000000-0000-4000-8000-000000000101` (*Kuanpal Daily Fresh Supermarket & Meals*)
- **Category:** `grocery` (`delivery_enabled = true`, location `POINT(85.883 20.4625)`)
- **FMCG Catalog Items:**
  - *Amul Taaza Homogenised Milk*: ₹34.00 (MRP ₹36.00, 500 ml Pouch, barcode `8901262010054`, stock 60)
  - *Aashirvaad Superior MP Atta*: ₹235.00 (MRP ₹265.00, 5 kg Bag, barcode `8901030383749`, stock 40)

#### Customer UI Flow on `emulator-5554`:
1. Navigated from Home Screen via "Daily Groceries & Essentials" card.
2. Filtered storefront by Grocery categories (Dairy & Eggs, Staples & Flours).
3. Added 1x Amul Taaza Milk and 1x Aashirvaad MP Atta.
4. Floating basket pill reflected `2 items | ₹269.00`.
5. Tapped "View Cart & Order" -> Opened `CustomerCartScreen`.
6. Verified single-merchant guard (`Single-merchant cart`), server price validation (Subtotal ₹269.00 + Delivery ₹30.00 = Total ₹299.00 COD).

---

### 4. Verification 2: End-to-End Grocery COD Lifecycle

#### Lifecycle Progression:
1. **Order Placement (Customer UI):** Submitted order `ba2ee85a-20de-4a2e-88a9-16eaef3080a6` (`GN-BA2EE85A`) for ₹299.00 COD.
2. **Merchant Order Acceptance (Merchant UI):** Order appeared in "New Orders" tab on `emulator-5556`. Merchant tapped "Accept" -> moved to "Preparing" tab.
3. **Triggered Preparation (Merchant UI):** Merchant tapped "Start preparation". The PostgreSQL trigger `create_delivery_job_for_platform_preparation()` generated `delivery_jobs` `85bf4813-b76b-4bde-bff8-a3851d6c9fca`.
4. **Autonomous Dispatch:** Background dispatch runner created `delivery_offers` for Rider `+919990000173`.
5. **Rider Offer Acceptance (Rider UI):** Incoming offer appeared on Dashboard (Tab 1). Rider tapped "Accept" -> transitioned to Deliveries (Tab 2) in status `assigned`.
6. **Merchant Handover Verification:**
   - Rider tapped "Arrived at pickup" -> "I am at the partner" (status `at_pickup`).
   - Merchant UI unlocked "Issue pickup code" -> issued 8-digit code `01029071`.
   - Rider tapped "Verify partner handover" -> entered `01029071` -> status progressed to `picked up`.
7. **Customer Delivery & COD Collection:**
   - Rider tapped "Start delivery" -> status `en_route` (order `out_for_delivery`).
   - Customer provided delivery code `75461517` (verified via HMAC challenge).
   - Rider entered `75461517` on UI -> modal prompted "Confirm synthetic COD collection: ₹299.00".
   - Rider tapped "Confirm QA collection".
   - Rider UI transitioned to "Delivery completed with customer verification. No active delivery."

---

### 5. Verification 3: Clean Food Dispatch Regression (Zero DB Resets / Zero Patching)

To verify the dispatch runner’s autonomy without manual resets, a fresh food order was placed and fulfilled immediately after the grocery delivery.

#### Lifecycle Progression:
1. **Customer Order Placement (`emulator-5554`):**
   - Navigated to storefront -> Selected *Hyderabadi Dum Biryani Pot* (₹320.00).
   - Cart subtotal: ₹320.00 + Delivery fee: ₹30.00 = Grand Total: ₹350.00 (COD).
   - Placed order -> Reference: `GN-42904B10` (ID: `42904b10-4079-4eac-bcc2-bc3fbed3a9fd`).
2. **Merchant Acceptance (`emulator-5556`):**
   - Tapped refresh on `Orders & Fulfillment` -> `New Orders` count updated to 5.
   - Expanded `GN-42904B10` card -> Tapped `Accept` -> moved to `Preparing` tab (count 13).
   - Switched to `Preparing` tab -> Tapped `Start preparation`.
3. **Autonomous Dispatch Autonomous Verification:**
   - Querying PostgreSQL immediately confirmed:
     - `delivery_jobs`: ID `7f2da425-9c8e-4851-966c-728d1bfc09be`, state `offered`, execution_state `assigned`.
     - `delivery_offers`: ID `f663a32b-6580-4246-bfea-8c6a8088a3d8`, offered to Rider `3e000000-0000-4000-8000-000000000003`.
     - Zero manual SQL inserts, zero backend restarts, zero script patches.
4. **Merchant Ready for Pickup (`emulator-5556`):**
   - Tapped `Mark ready for pickup` -> moved to `Ready for Pickup` tab (count 6).
5. **Rider Offer Acceptance (`emulator-5558`):**
   - Switched to Dashboard (Tab 1) -> Received "NEW DELIVERY OFFER" for *Hyderabadi Dum Biryani Pot* (Synthetic COD due: ₹350.00).
   - Tapped `Accept` -> switched to Deliveries (Tab 2).
   - Tapped `Arrived at pickup` -> Tapped `I am at the partner` (execution state `at_pickup`).
6. **Partner Handover Verification:**
   - Merchant UI unlocked `Issue pickup code`.
   - Merchant tapped `Issue pickup code` -> Confirmed dialog -> Received code `03101019` (expires in 300s).
   - Rider tapped `Verify partner handover` on UI -> Entered `03101019` -> Verified!
   - Rider status updated to `picked up`.
7. **Customer Handover & COD Collection:**
   - Rider tapped `Start delivery` -> execution state `en_route`.
   - Rider tapped `Confirm customer handover` -> Modal opened requesting 8-digit customer delivery code.
   - Customer delivery code retrieved via challenge-bound service: `37694722`.
   - Rider entered `37694722` on UI -> Tapped `Verify`.
   - Modal transitioned to "Confirm synthetic COD collection: Amount due ₹350.00".
   - Rider tapped `Confirm QA collection`.
   - Screen updated: "Delivery completed with customer verification. No active delivery."

---

### 6. Verification 4: Database & Ledger Reconciliation

| Metric | Grocery Order (`GN-BA2EE85A`) | Food Order (`GN-42904B10`) |
|---|---|---|
| **Order ID** | `ba2ee85a-20de-4a2e-88a9-16eaef3080a6` | `42904b10-4079-4eac-bcc2-bc3fbed3a9fd` |
| **Order Source** | `merchant_catalog` | `merchant_catalog` |
| **Item Total** | ₹269.00 (Milk + Atta) | ₹320.00 (Biryani Pot) |
| **Delivery Fee** | ₹30.00 | ₹30.00 |
| **Grand Total** | ₹299.00 | ₹350.00 |
| **Order Status** | `delivered` | `delivered` |
| **Payment Status** | `not_collected` (COD flow) | `not_collected` (COD flow) |
| **Job ID** | `85bf4813-b76b-4bde-bff8-a3851d6c9fca` | `7f2da425-9c8e-4851-966c-728d1bfc09be` |
| **Execution State** | `delivered` | `delivered` |
| **COD Collection ID** | `9ab33865-0762-40b4-87f5-5f3430a0c0ad` | `a1b4916a-8d76-4d2b-bf23-41bb2de451e0` |
| **Amount Minor** | `29900` (₹299.00) | `35000` (₹350.00) |
| **Environment** | `synthetic_qa` | `synthetic_qa` |
| **Reconciled At** | `2026-11-19 21:49:01 UTC` | `2026-11-19 22:38:01 UTC` |

---

### 7. Verification 5: Full Flutter Suite & Integrity Verification

#### Suite 1: Phase 01F.1 Doctor & Transport Integrity (`test/doctor_transport_integrity_test.dart`)
- `DoctorDirectoryScreen renders truthful empty state when no facilities exist`: **PASS**
- `DoctorDirectoryScreen displays genuine facility data and separates facility verification from doctor claims`: **PASS**
- `LocalTransportScreen excludes repair garages and renders honest empty state`: **PASS**
- `HomeScreen displays truthful category label and truthful subtitles`: **PASS**
- **Outcome:** **4/4 passed (100%)**

#### Suite 2: Core Feature & Pipeline Suite
- `test/customer_cart_test.dart` (6 tests): **PASS**
- `test/merchant_catalog_inventory_phase02d_test.dart` (4 tests): **PASS**
- `test/merchant_orders_pipeline_phase02c_test.dart` (4 tests): **PASS**
- `test/rider_cod_cash_test.dart` (2 tests): **PASS**
- `test/rider_dispatch_test.dart` (3 tests): **PASS**
- `test/workspace_navigation_test.dart` (3 tests): **PASS**
- **Outcome:** **22/22 passed (100%)**

#### Suite 3: Commerce & Payment Integration Suite
- `test/payment_workflow_test.dart` (6 tests): **PASS**
- `test/platform_catalog_test.dart` (5 tests): **PASS**
- `test/order_history_test.dart` (2 tests): **PASS**
- **Outcome:** **13/13 passed (100%)**

**Total Automated Flutter Tests Executed in Acceptance Pass:** **39 tests, 0 failures, 0 regressions.**

---

### 8. Architectural Conclusions & Production Readiness Gates

1. **Phase 02E Acceptance:** Accepted as QA PASS. The COD and sandbox UPI Food workflows function properly across mobile emulators and backend services.
2. **Phase 02I Acceptance:** **QA PASS**. Genuine Grocery discovery, cart validation, single-merchant constraints, mutual handover verification, and autonomous dispatch regression are verified.
3. **Production Approval Gate:**
   - Migrations `041`, `042`, and `043` remain applied only to `grepmind_3e_qa_db`. They must not be applied to shared development or production until formally approved.
   - Real-money payment gateways and physical cash collection remain strictly disabled. All operations run under `synthetic_qa` environment guards.
