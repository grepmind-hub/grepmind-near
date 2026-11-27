# Abashyaka Complete E2E UI & Platform Test Analysis

**Date:** 2026-11-27  
**Branch:** `abashyaka-dev-4-analysis-fix`  
**APK SHA-256:** `2AE75DC0AAD7EC642CC58202D6FB57586F56CBDE03ABE524CFA7463C2859FA3F`  
**QA Accounts Under Test:**
- **Customer:** `+919990000110` (`emulator-5554` / `Pixel_8`)
- **Merchant:** `+919990000111` (`emulator-5556` / `Pixel_8_Merchant_QA`)
- **Rider:** `+919990000112` (`emulator-5558` / `Pixel_8_Rider_QA`)
- **Admin:** Web Portal (`https://admin.abashyaka.com`)

---

## Environment Setup & Pre-Flight Observations

| # | Area | Finding / Observation | Type | Status |
|---|---|---|---|---|
| 0.1 | API QA Configuration | `QA_OTP_ALLOWLIST` only contained `+919990000171..173`; `SANDBOX_COD_ENABLED` and `PAYMENT_SANDBOX_ENABLED` defaulted to `false` on `abashyaka-api`. Updated for QA E2E run. | Config / Gate | Resolved for QA |

---

## Step-by-Step E2E Execution Log & Findings

### Step 1 — Pre-Flight & QA API Setup
- **API Health:** `abashyaka-api` (`abashyaka-api:rider-051`) initially lacked `abashyaka_edge` network access when recreated, causing `fcm.googleapis.com` DNS lookup to fail (`HTTP 503 OTP_UNAVAILABLE` on `/api/v1/auth/otp/request`). Connected `abashyaka-api` to `abashyaka_edge`, `abashyaka_app` (alias `api`), and `abashyaka_data`; `/healthz` returned `200 {"status":"ok"}`.
- **UI/Error Observation (Login Screen):** When `/api/v1/auth/otp/request` returns `503`, the login screen shows a generic snackbar (`"Could not send a code. Please try again."`), which is clean and user-friendly.

### Step 2 — Rider Registration & Camera Document Upload (`9990000112`, `emulator-5558` / `Pixel_8_Rider_QA`)
- **OTP & Auth:** FCM test OTP (`400540`) delivered via push banner cleanly; verified and landed on `Choose Your Role`.
- **UI Issue #1 (Choose Your Role):** On `Choose Your Role`, the Merchant card subtitle (`"List your business, manage orders, services and custom..."`) and Rider card subtitle (`"Pick orders, deliver to customers and earn with Ab..."`) truncate with ellipsis (`...`).
- **UI/Copy Issue #2 (Rider Application):** Both the draft banner and submitted banner (`ID: AR-1012`) still display stale copy: *"Rider approval provides workspace access only. Delivery assignments, GPS tracking and payments are not enabled in this phase."* even though delivery dispatch (`RIDER_DISPATCH_ENABLED=true`) and sandbox COD/UPI are active in QA.
- **Camera Upload & Submission:** Captured and uploaded **Aadhaar Card**, **Driving Licence**, and **Passport / Profile Photo** using the emulator virtual camera (`Take Photo with Camera`). All three rows updated cleanly to `Uploaded · pending` with `Replace` button, and `Submit for review` succeeded (`ID: AR-1012`, `Status: submitted`).

### Step 3 — Customer Login & Merchant Registration (`9990000110` & `9990000111`)
- **UI Issue #3 (Customer Home Category Grid):** On initial load of `Customer Home` (`9990000110` on `emulator-5554`), all 12 `"What do you need today?"` category tiles rendered as blank white boxes; on a second load (`emulator-5556`), 5 icons loaded (`Food`, `Grocery`, `Medicines`, `Doctors`, `Cab & Auto`) while 7 remained blank white boxes (`Services`, `Electronics`, `Shops`, `Fashion`, `Hotels & Stays`, `Fitness & Wellness`, `More`). Needs bundled local assets or reliable placeholder/icon fallback.
- **UI Issue #4 (Customer Home Default Location):** Default `DELIVERING TO` displays `"Chhatia, Cuttack"` (Chhatia is in Jajpur district, not Cuttack).
- **UI/Navigation Issue #5 (Choose Your Role — Merchant):** Tapping `Continue as Merchant ->` on `Choose Your Role` for a fresh user without an existing merchant role did not open Merchant Onboarding; had to enter Customer workspace first and navigate to `Profile -> Register / Claim Business`.
- **Functional Bug #6 (Merchant Onboarding Category Mismatch):** Step 1 of Merchant Onboarding lists 18 hardcoded categories including `"Food & Dining"`, which is **not** an active category in the backend `categories` table (`restaurant` = `"Restaurant & Food"`, `grocery` = `"Grocery"`). Selecting `"Food & Dining"` passes Steps 1–3 and only fails at Step 4 submission with *"Could not submit your business listing. Choose an active business category."* Switching to `"Grocery"` succeeded (`Application ID: GN-A75BCB81`).
- **Branding Issue #7 (Merchant Application ID Prefix):** The `Verification Under Review` confirmation screen displays a legacy `GN-A75BCB81` prefix instead of the `AM-` Abashyaka Merchant ID format.

### Step 4 — Admin Review & Approval
- **Auth/Env Finding #8 (Web Admin OTP):** With `FCM_TEST_OTP_ENABLED=true` and `QA_OTP_DELIVERY_ENABLED=false` (and no running `qa_otp` HTTP inbox helper), `fcm_otp_provider.go` rejects web OTP requests without an Android `installation_id` (`HTTP 503 OTP_UNAVAILABLE`). Operator approved **Rider `AR-1012` (`E2E Rider QA`, `+919990000112`)** and **Merchant `E2E Kuanpal Kitchen` (`+919990000111`)** in the Admin Web Portal.
- **UX Finding #9 (Stale Role Cache After Approval):** After Admin approval, Rider `9990000112` on `Choose Your Role` still showed `"Application required"` until the app was force-stopped and relaunched to refresh `/auth/me`.

### Step 5 — Merchant Catalog & Customer Discovery / Cart (`Basmati Rice 1kg E2E`)
- **Merchant Catalog (`emulator-5556`):** Created `Basmati Rice 1kg E2E` (`₹120`, MRP `₹150`, `In Stock`, `Published on Storefront`) cleanly.
- **Critical Functional Bug #10 (`delivery_enabled = false` on New Merchant):** Newly registered & approved merchants (`E2E Kuanpal Kitchen`) have `delivery_enabled = false` in `businesses` even when `Grocery` and `6 km radius` delivery coverage are selected during onboarding. As a result:
  1. `Groceries` and `Order on Abashyaka` show `"No products available here yet"`.
  2. Adding the product from `Explore -> E2E Kuanpal Kitchen` and opening `Your cart` fails quote with: *"This business no longer supports product ordering. Your cart is saved; remove these items or return later."*
  *(For E2E continuation, enabled `delivery_enabled = true` on `E2E Kuanpal Kitchen` in PostgreSQL.)*
- **UI Issue #11 (White Status Bar Text on Light AppBars):** On `Groceries`, `Food & Meals`, and `Your cart`, the Android status bar clock/icons are white on a white background (barely visible).
- **UI Issue #12 (Business Detail & Product Row Polish):**
  - `E2E Kuanpal Kitchen` displays `4.8 (0)` rating despite having `0` reviews.
  - `Grocery` appears twice (`• Grocery` and `Grocery` chip); the 2nd tab label `"Grocery &"` truncates.
  - Under `Grocery &`, the grocery product (`Basmati Rice 1kg E2E`) displays a red non-veg dot, `20m` prep badge, and red fork/knife icon, and the cart bar says `"1 items"` (singular/plural grammar).
- **UI Issue #13 (Add Address Form):**
  - Helper text `"Required to check Food and Grocery delivery."` under `Abashyaka delivery locality` overlaps with `"Landmark (optional)"` label below it.
  - `Save address` button sits behind the Android bottom gesture bar.
- **Critical Functional Bug #14 (`COVERAGE_NOT_CONFIGURED` on New Merchant):** Even though Merchant Onboarding Step 4 collects `"Service & Delivery Coverage: 6 km radius"`, no `professional_profiles` row with `service_radius_m` is created on registration/approval. Checkout quote (`backend/internal/operations/checkout.go:505`) rejects with `409 COVERAGE_NOT_CONFIGURED`: *"The merchant has not configured an order coverage radius."*
  *(For E2E continuation, inserted `service_radius_m = 6000` in `professional_profiles` for `E2E Kuanpal Kitchen`.)*
- **Config/DB Finding #15 (Empty `financial_feature_config` & Raw SQL Error in UI):**
  - `financial_feature_config` had `0 rows`, causing order submission to fail with a raw database error shown directly to the customer: *"ERROR: COD obligation is not eligible or synthetic COD is disabled (SQLSTATE P0001)"*. (Raw SQLSTATE should be mapped to a user-friendly message.)
  - Also `CheckoutReviewScreen` displays `"Payment is unavailable"` even when sandbox COD/UPI is enabled in QA.
  *(Seeded the `singleton = true` QA row in `financial_feature_config` with `sandbox_cod_enabled = true`, `sandbox_payment_enabled = true`, `financial_posting_enabled = true`, and all real-money flags `false`.)*

### Step 6 — COD Order Execution (`GN-58E95909`), Rider Handover & Synthetic COD Collection
- **Order Placement & Merchant Fulfillment:** Customer (`+919990000110`) placed COD order `GN-58E95909` (`58e95909-5737-43b4-a033-89555e9b939e`, `Total: ₹150.00` = `₹120` item + `₹30` delivery). Merchant (`E2E Kuanpal Kitchen`, `+919990000111`) accepted, prepared, marked ready, and issued pickup code `81261602`.
- **Rider Dispatch & Pickup:** Rider (`AR-1012`, `E2E Rider QA`, `+919990000112`, `emulator-5558`) accepted the offer (`Synthetic COD due · ₹150.00`), verified pickup code `81261602`, started delivery (`out_for_delivery` / `en_route`), and tapped `Arrived at customer` to open `Confirm customer handover`.
- **Critical Functional Bug #16 (Customer `Orders & bookings` Blank Screen & ANR):**
  - Opening `Orders & bookings` (`OrderHistoryScreen`, both from `Order on Abashyaka` receipt icon and from `Profile -> My Orders & Bookings`) while order `GN-58E95909` was `out_for_delivery` rendered a completely blank `#F8FAF9` body (even when `GET /api/v1/customer/orders?limit=20` returned `HTTP 200` with `1396` bytes) and triggered `Abashyaka isn't responding` ANR dialogs.
  - Impact: A Customer who navigates away from `OrderTrackingScreen` cannot reopen `OrderTrackingScreen` from the UI to track the order or view/request the 8-digit delivery verification code.
  - *(For E2E continuation, issued the 8-digit delivery code `39695448` via `POST /api/v1/orders/58e95909-5737-43b4-a033-89555e9b939e/delivery-code` as `+919990000110`.)*
- **Critical DB/Config & Error-Handling Bug #17 (Empty `financial_accounts` & Silent HTTP 500 on Rider Handover):**
  - After entering `39695448` and tapping `Confirm QA collection` on `Confirm synthetic COD collection` (`Amount due: ₹150.00`), `POST /api/v1/rider/delivery-jobs/c361b526-baae-45cf-8aaf-5a9f42bba313/delivery/confirm` returned **`HTTP 500`**.
  - Root cause: `financial_accounts` had **`0 rows`** in `abashyaka-postgres`. `codcash/service.go` (`RecordCollectionTx`) queries `rider_cash_receivable` and `cod_collection_clearing` via `QueryRowxContext(...).Scan(...)`, returning raw `sql.ErrNoRows` (`HTTP 500`).
  - **Rider UI Error-Handling Gap:** When `delivery/confirm` returned `HTTP 500`, the Rider app closed the dialog and silently remained on `Status · en route` with **no error banner or snackbar** shown to the rider. (When `401`/`409` occurred on a subsequent retry after the 5-minute code expired, the Rider UI did display `"Customer verification failed. The order was not marked delivered."`)
  - *(Seeded the 7 `financial_accounts` rows from migrations `034` and `035` into `abashyaka-postgres`.)*
- **Flow 1 (COD `GN-58E95909`) Status — PASS (Verified):** Completed end-to-end on `emulator-5558` (`Pixel_8_Rider_QA`) with 8-digit customer code `70544571` and `Confirm QA collection` (`₹150.00`). Verified `customer_orders.status = 'delivered'` and `cod_collections` row (`58e95909-5737-43b4-a033-89555e9b939e`, `amount_minor = 15000`, `currency = INR`).

---

## 4. Fixes Applied & Re-Verification (APK `6E8A814A1388ADA51CAC128B674E1B3EE6955E11D5CBFDB9D6C9BF76BBF821D3`)

- **Build & Devices:** Rebuilt `abashyaka-api:rider-051` and authoritative debug APK (`SHA-256: 6E8A814A1388ADA51CAC128B674E1B3EE6955E11D5CBFDB9D6C9BF76BBF821D3`), installed and verified on `emulator-5554` (`Pixel_8`, Customer `+919990000110`), `emulator-5556` (`Pixel_8_Merchant_QA`, Merchant `+919990000111`), and `emulator-5558` (`Pixel_8_Rider_QA`, Rider `+919990000112`).
- **Backend & DB Fixes Verified:**
  - `backend/cmd/api/merchant_onboarding.go`: `createMerchantBusiness` sets `delivery_enabled = true` for delivery-capable verticals and upserts `professional_profiles (business_id, service_radius_m)` (`go test ./cmd/api` passed).
  - `backend/internal/codcash/service.go`: Mapped missing `financial_accounts` `sql.ErrNoRows` to `503 COD_ACCOUNTS_NOT_CONFIGURED` (`go test ./internal/codcash` passed); seeded `financial_accounts` and `payment_ledger_account_mappings` (`provider_clearing`, `customer_receipts_unapplied`).
  - `backend/internal/operations/service.go`: Mapped `COD obligation` / `SQLSTATE P0001` to `409 COD_UNAVAILABLE` with sanitized user-facing error (`go test ./internal/operations` passed).
  - Configured `PAYMENT_SANDBOX_WEBHOOK_KEY_ID`, `PAYMENT_SANDBOX_WEBHOOK_SECRET`, and `PAYMENT_SANDBOX_QA_USER_IDS` on `abashyaka-api`.
- **Mobile UI/UX Fixes Applied:**
  - `checkout_review_screen.dart`: Replaced static unavailable copy with `SegmentedButton<String>` (`Cash on Delivery` vs `UPI (Sandbox)`), passing `payment_method`.
  - `rider_workspace_screen.dart`: Added `SnackBar` on `delivery/confirm` failure.
  - `role_selection_screen.dart`: Removed 2-line subtitle truncation, wired Merchant card tap to `MerchantRegistrationScreen`, added lifecycle resume refresh.
  - `customer_address_form_screen.dart`, `app_theme.dart`, `rider_application_screen.dart`, `merchant_registration_screen.dart`, `app_provider.dart`, `business_detail_screen.dart`, `home_screen.dart`, `explore_screen.dart`, and `order_history_screen.dart` fixes included in the `6E8A814A...` APK.

---

## 5. Flow 2 — Sandbox UPI E2E Verification (`GN-A1E4E11E`)

- **Order & Payment (`a1e4e11e-8c2c-4f18-8e4f-786564a14571`):**
  - Customer (`+919990000110`) placed `GN-A1E4E11E` (`payment_method = 'upi'`, `₹150.00`).
  - Sandbox UPI flow executed: `POST /orders/{id}/payment-intents` (`201`), `POST /orders/{id}/payment-sessions` (`201`), `POST /orders/{id}/sandbox-payment-outcomes` (`succeeded`, `200`). DB confirmed `payment_status = 'paid'`.
- **Merchant Fulfillment (`emulator-5556`):**
  - Merchant UI displayed `"Payment verified by Abashyaka backend."`, progressed through `Accepted` -> `Preparing` -> `Ready for pickup`, and issued 8-digit pickup code `79243795`.
- **Rider Delivery (`emulator-5558`):**
  - Rider UI displayed `"Payment · UPI verified by Abashyaka"`.
  - Verified pickup code `79243795` -> `Start delivery` (`Status · en route`) -> `Confirm customer handover` with 8-digit customer code `87777114`.
  - Confirmed **no synthetic COD collection prompt** appeared for the paid UPI order; UI showed `"Delivery completed with customer verification."`.
  - Rider `Earnings` tab updated to `"2 completed deliveries are awaiting an approved compensation policy."` with two `"Awaiting policy review"` ledger activity entries.
- **PostgreSQL Reconciliation:**
  - `customer_orders`: `GN-58E95909` (`delivered`, `cash_on_delivery`, `not_collected`) and `GN-A1E4E11E` (`delivered`, `upi`, `paid`).
  - `cod_collections`: 1 row (`58e95909-5737-43b4-a033-89555e9b939e`, `15000 INR`); zero COD rows created for `GN-A1E4E11E`.

---

## 6. Remaining Open Items Found During Re-Verification

| Priority | Area | Issue Observed | Status |
|---|---|---|---|
| **P1 (UI)** | Customer `OrderHistoryScreen` (`Orders & bookings`) | Renders a blank `#F8FAF9` screen on initial load and refresh whenever an active (`placed`) order (`GN-C9F246DA`) exists (`_ActiveOrderHeroCard` path). Worked when only `delivered` `GN-58E95909` existed. | Open |
| **P2 (API/UI)** | `GET /api/v1/orders/{id}/cod-status` | Returned `HTTP 404` on a `placed` COD order (`GN-C9F246DA`), causing `OrderTrackingScreen` to show `"Cash-on-delivery status is unavailable. Refresh to retry."`. | Open |

## 7. E2E Flow Summary

| Flow | Order Ref | Role Coverage | DB Reconciliation | Final Status |
|---|---|---|---|---|
| **Flow 1: COD** | `GN-58E95909` | Customer + Merchant + Rider (`emulator-5554/5556/5558`) | `delivered`, `cod_collections = 15000 INR` | **PASS** |
| **Flow 2: Sandbox UPI** | `GN-A1E4E11E` | Customer + Merchant + Rider (`emulator-5554/5556/5558`) | `delivered`, `upi / paid`, `0` COD rows | **PASS** |
