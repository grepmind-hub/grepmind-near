# Antigravity Work & Fix Reference Guide — Grepmind Near

**Repository**: `D:\grepmind-near`  
**Active Branch**: `dev-antigravity`  
**Current Milestone**: Phase 4E.2 (PASS), Phase 4E.3 (PASS — Gate G3 CLOSED), Phase 4E.4 Gate G4-B (PASS — Gate G4-B CLOSED)  
**Acceptance Date**: 14 November 2026  

---

## 1. Role Identities & Assigned Surfaces

All test identities are synthetic, allowlisted QA numbers. No real SMS or production customer data is used.

| Role | Synthetic Name | Mobile Number (E.164) | Assigned Surface / Device | Database ID / Entity |
|---|---|---|---|---|
| **Customer** | Priyanka Mishra | `+919990000181` | `emulator-5554` (`Pixel_8`) | User: `4e300000-0000-4000-8000-000000000001`<br>Address: `4e300000-0000-4000-8000-000000000301` (Kuanpal, Cuttack) |
| **Merchant** | Deepak Patra | `+919990000182` | `emulator-5556` (`Pixel_8_Merchant_QA`) | User: `4e300000-0000-4000-8000-000000000002`<br>Store: *Kalinga Fresh Grocery* (`4e300000-0000-4000-8000-000000000101`) |
| **Rider** | Ashok Samal | `+919990000183` | `emulator-5558` (`Pixel_8_Rider_QA`) | User: `4e300000-0000-4000-8000-000000000003`<br>Vehicle: `two_wheeler`, Approved: Kuanpal, Cuttack |
| **Admin** | Platform Superadmin | `+919990000174` | Web Browser (`http://localhost:3302/admin`) | User: `3e000000-0000-4000-8000-000000000004`<br>Role: `admin` (`finance.post` duty) |
| *Cust (Hist)* | QA Customer | `+919990000171` | `emulator-5554` (Backup) | User: `3e000000-0000-4000-8000-000000000001` |
| *Merch (Hist)*| QA Merchant | `+919990000172` | `emulator-5556` (Backup) | Store: *Phase 3E QA Food Partner* |
| *Rider (Hist)*| QA Rider | `+919990000173` | `emulator-5558` (Backup) | User: `3e000000-0000-4000-8000-000000000003` |
| *Admin (Hist)*| QA Admins | `+919990000175`, `176`, `177` | Web Browser (Backup) | Administrative review identities |

---

## 2. Platform Catalog Grocery Product Details

- **Catalog Category**: Grocery (`bb3fe995-94a8-4b73-8b63-cad321dd107b`)
- **Product Name**: Kalinga Premium Basmati Rice (`4e300000-0000-4000-8000-000000000201`)
- **SKU**: `P4E-GROC-RICE-KUANPAL`
- **Variant**: `5 kg Pack` (`4e300000-0000-4000-8000-000000000202`), Unit: `1 bag (5 kg)`
- **Customer Price**: ₹280.00 (`28000` minor units)
- **Partner Supply Price**: ₹210.00 (`21000` minor units)
- **Partner Business**: Kalinga Fresh Grocery (`4e300000-0000-4000-8000-000000000101`)
- **Stock Quantity**: 50 bags (finite inventory mode, status: `approved`)
- **Fulfillment Locality**: Kuanpal, Cuttack (`02200000-0000-4000-8000-000000000101`)

---

## 3. Root Causes Identified & Fixes Implemented

### Fix 1: Subshell Freezes in Windows Host PowerShell (`wsl.exe --exec`)
- **Root Cause**: Running `wsl.exe --exec bash -lc <command>` from Windows PowerShell 5.1/7 would hang indefinitely due to stdin pipe inheritance issues when executing nested subshells.
- **Fix**: Standardized all invocation to `wsl.exe -d Ubuntu -- bash -lc "<command>"` across [`scripts/qa/auth-otp-02-windows-ui.ps1`](file:///d:/grepmind-near/scripts/qa/auth-otp-02-windows-ui.ps1) and [`scripts/qa/auth-otp-02-admin-playwright.ps1`](file:///d:/grepmind-near/scripts/qa/auth-otp-02-admin-playwright.ps1).

### Fix 2: Stale Delivery Offers Blocking Dispatch
- **Root Cause**: The Rider dispatch service allows only one active pending offer per rider at a time. Leftover fixture jobs from earlier test runs held stale offers in state `offered`, causing new orders to trigger `no_rider_available`.
- **Fix**: Purged stale unassigned offers in `delivery_offers`. New orders now match the active rider in Kuanpal within 2 seconds.

### Fix 3: QA OTP Allowlist Expansion
- **Root Cause**: The QA API and OTP Inbox rejected OTP requests for new phone numbers outside the predefined fixture set.
- **Fix**: Updated [`scripts/qa/auth-otp-01-e2e-r2-attach-reader.sh`](file:///d:/grepmind-near/scripts/qa/auth-otp-01-e2e-r2-attach-reader.sh) allowlist to include:
  `+919990000171,+919990000172,+919990000173,+919990000174,+919990000175,+919990000176,+919990000177,+919990000181,+919990000182,+919990000183`.

### Fix 4: Sandbox Payment Simulation Security Boundary (`PAYMENT_SANDBOX_QA_USER_IDS`)
- **Root Cause**: In [`backend/internal/payments/refunds.go:636`](file:///d:/grepmind-near/backend/internal/payments/refunds.go#L636), `SimulatePaymentOutcome` strictly verifies `sandboxSimulationAllowed(userID)` against the `PAYMENT_SANDBOX_QA_USER_IDS` environment variable. Customer Priyanka Mishra's user ID was rejected with `404 NOT_FOUND` during sandbox payment simulation.
- **Fix**: Updated [`scripts/qa/auth-otp-01-e2e-r2-attach-reader.sh`](file:///d:/grepmind-near/scripts/qa/auth-otp-01-e2e-r2-attach-reader.sh) to inject:
  `PAYMENT_SANDBOX_QA_USER_IDS=3e000000-0000-4000-8000-000000000001,4e300000-0000-4000-8000-000000000001`. Re-attached API container.

### Fix 5: Merchant Direct Store Catalog Mapping
- **Root Cause**: While platform products existed in `platform_catalog_products`, direct store queries in mobile explore mode check the `products` table.
- **Fix**: Added corresponding entry in `products` table for `Kalinga Fresh Grocery`, keeping platform catalog and merchant inventory in sync.

### Fix 6: Android Emulator Network Bridging
- **Root Cause**: Emulators communicate with host loopback through `10.0.2.2` or port-reversed local sockets. Mobile apps targeting `127.0.0.1:18083` failed to reach the QA API if reverse bindings were lost.
- **Fix**: Automated reverse port mapping across all emulators:
  `adb -s <serial> reverse tcp:18083 tcp:18083`.

---

## 4. Operational Commands Reference

### A. Network & Port Forwarding
Run from Windows PowerShell to ensure emulators connect to the isolated QA API:
```powershell
adb -s emulator-5554 reverse tcp:18083 tcp:18083
adb -s emulator-5556 reverse tcp:18083 tcp:18083
adb -s emulator-5558 reverse tcp:18083 tcp:18083
```

### B. Automated OTP UI Authentication
Authenticate any assigned role on its designated surface with a single command:

```powershell
# Authenticate Customer (Priyanka Mishra) on Pixel_8
pwsh -File scripts/qa/auth-otp-02-windows-ui.ps1 -Role customer -Serial emulator-5554 -Phone '+919990000181'

# Authenticate Merchant (Deepak Patra) on Pixel_8_Merchant_QA
pwsh -File scripts/qa/auth-otp-02-windows-ui.ps1 -Role merchant -Serial emulator-5556 -Phone '+919990000182'

# Authenticate Rider (Ashok Samal) on Pixel_8_Rider_QA
pwsh -File scripts/qa/auth-otp-02-windows-ui.ps1 -Role rider -Serial emulator-5558 -Phone '+919990000183'

# Authenticate Admin Web Portal via Playwright
pwsh -File scripts/qa/auth-otp-02-admin-playwright.ps1 -AdminPhone '+919990000174'
```

### C. Create Grocery Test Orders
Execute inside WSL or via PowerShell wrapper:

```bash
# Place Cash on Delivery (COD) Grocery Order
wsl -d Ubuntu -- bash /mnt/d/grepmind-near/scripts/qa/run-grocery-order.sh cash_on_delivery

# Place Sandbox UPI Prepaid Grocery Order
wsl -d Ubuntu -- bash /mnt/d/grepmind-near/scripts/qa/run-grocery-order.sh upi
```

### D. Verify Orders & Financial Ledgers in PostgreSQL
```bash
# Check Order Status & Payment Status
wsl -d Ubuntu -- docker exec -i grepmind_3e_qa_db psql -U qa3e -d grepmind_3e_qa -c \
  "SELECT reference_code, status, payment_method, payment_status, grand_total, created_at FROM customer_orders ORDER BY created_at DESC LIMIT 5;"

# Check Balanced Double-Entry Financial Journals
wsl -d Ubuntu -- docker exec -i grepmind_3e_qa_db psql -U qa3e -d grepmind_3e_qa -c \
  "SELECT j.id, j.source_type, j.source_event, a.account_code, p.side, p.amount_minor FROM financial_journals j JOIN financial_postings p ON p.journal_id = j.id JOIN financial_accounts a ON a.id = p.account_id ORDER BY j.created_at DESC LIMIT 6;"

# Verify Zero Automatic Merchant Payable Posting Invariant
wsl -d Ubuntu -- docker exec -i grepmind_3e_qa_db psql -U qa3e -d grepmind_3e_qa -c \
  "SELECT count(*) FROM merchant_payable_snapshots WHERE business_id = '4e300000-0000-4000-8000-000000000101';"
```

### E. Re-attach QA OTP Reader & API Container
If containers are restarted or allowlists change:
```bash
wsl -d Ubuntu -- bash /mnt/d/grepmind-near/scripts/qa/auth-otp-01-e2e-r2-attach-reader.sh
```

---

## 5. Live Acceptance Evidence Summary

### Order 1: Cash on Delivery (COD) — `GN-1E923DBB`
- **Total**: ₹280.00
- **Merchant Workflow**: Accepted -> Prepared -> Ready for pickup. Merchant generated pickup code `07699848`.
- **Rider Workflow**: Received incoming offer, arrived at store, entered pickup code `07699848`, started delivery.
- **Customer Handover**: Customer displayed verification code `52917879`. Rider entered code in handover modal.
- **Cash Liability Collection**: Rider confirmed synthetic COD collection of ₹280.00.
- **Reconciliation**:
  - `status`: `delivered`, `payment_status`: `not_collected`.
  - Rider cash liability updated to **₹280.00**.
  - `merchant_payable_snapshots`: **0 rows** (strictly preserved for Admin `finance.post`).

### Order 2: Sandbox UPI — `GN-053335A3`
- **Total**: ₹280.00
- **Prepayment Workflow**: Customer initiated sandbox session in mobile UI; submitted `Success` under QA controls.
- **Capture Journal**: Journal `f33b1b4f-e093-4c87-8567-66d6e424d432` posted with:
  - Debit `qa_provider_clearing`: 28000 INR
  - Credit `qa_customer_receipts_unapplied`: 28000 INR
- **Merchant Workflow**: Displayed `Sandbox UPI: Payment verified by Grepmind backend`. Advanced to ready; issued pickup code `03446961`.
- **Rider Workflow**: Offer explicitly marked `UPI · verified by Grepmind`. Pickup verified with code `03446961`.
- **Customer Handover**: Customer displayed delivery code `76390647`. Rider entered code; order completed immediately without cash collection prompt.
- **Reconciliation**:
  - `status`: `delivered`, `payment_status`: `paid`.
  - Rider cash liability **remained ₹280.00** (unaffected by prepaid UPI).
  - `merchant_payable_snapshots`: **0 rows**.

### Admin Web Portal Authentication
- **URL**: `http://localhost:3302/admin`
- **Spec**: `apps/admin-web/e2e/auth-otp-02.admin.spec.ts`
- **Result**: **1 passed (3.2s)**.

---

## 6. Final Financial Reconciliation & Gate Acceptance Evidence

| Acceptance Requirement | Query / Test Command | Evidence & Verified Values | Status |
|---|---|---|---|
| **COD Collection & Liability** | `SELECT * FROM cod_collections WHERE order_id = '1e923dbb-ec68-47ec-bb5e-be9792fbfd3d'` | Exactly 1 collection row (`f5aa62cc-89b1-4b77-94c5-4340d3e9560e`), `amount_minor = 28000`, `currency = 'INR'`. Obligation `f0c84c12-3d1a-422a-81c8-a1a3e927228d` updated to `state = 'collected'`. Order `GN-1E923DBB` status = `delivered`, payment_status = `not_collected`. | **PASS** |
| **COD Balanced Journal** | `SELECT * FROM financial_postings WHERE journal_id = 'e276bc95-c232-48a0-8b2c-3f7dbda99408'` | Journal `e276bc95-c232-48a0-8b2c-3f7dbda99408` (`sandbox_cod_collection`):<br>• Debit `rider_cash_receivable`: 28000 INR (₹280.00)<br>• Credit `cod_collection_clearing`: 28000 INR (₹280.00)<br>Net imbalance: 0. Rider UI liability = ₹280.00. | **PASS** |
| **UPI Verified Capture & Journal** | `SELECT * FROM financial_postings WHERE journal_id = 'f33b1b4f-e093-4c87-8567-66d6e424d432'` | Exactly 1 intent (`86ae056c-4211-42a6-8c81-60bb8074789c`), 1 attempt (`253409ab-2575-4ae3-8041-e8f383488248`, `status = succeeded`). Order `GN-053335A3` status = `delivered`, payment_status = `paid`.<br>Journal `f33b1b4f-e093-4c87-8567-66d6e424d432` (`sandbox_payment_capture`):<br>• Debit `qa_provider_clearing`: 28000 INR (₹280.00)<br>• Credit `qa_customer_receipts_unapplied`: 28000 INR (₹280.00)<br>Net imbalance: 0. Outstanding rider cash liability unaffected (remained ₹280.00). | **PASS** |
| **Zero Automatic Payable Posting** | `SELECT count(*) FROM merchant_payable_snapshots WHERE business_id = '4e300000-0000-4000-8000-000000000101'` | Exactly **0 rows**. Fulfilling and delivering orders does not automatically post merchant payables. Requires explicit Admin review with `finance.post` permission. | **PASS** |
| **Security Negative Tests** | `node scripts/qa/negative-security-tests.mjs` | 5/5 negative cross-role access tests blocked:<br>• Customer -> Admin audit logs: 403 Forbidden<br>• Customer -> Merchant mark ready: 404/403 Blocked<br>• Rider -> Merchant capabilities: 403 Forbidden<br>• Rider -> Complete delivery without code: 404 Blocked<br>• Unauthenticated -> Financial journals: 404 Blocked | **PASS** |
| **Safety & Production Guardrails** | Source inspection (`refunds.go:638`, `config.go`) | `sandboxSimulationAllowed` returns `false` unconditionally unless `APP_ENV=qa` or `APP_ENV=test`. Cannot execute in production. Stale-offer purge isolated to `QA-PAYMENT-GATE-` and `QA-DISPATCH-PAYMENT-` prefixes. | **PASS** |
| **Regression: Go Backend** | `go test -p 1 -count=1 ./...` | All packages passed (auth, codcash, deliverydispatch, discovery, financialledger, merchantfinance, payments, platformcatalog, platformcommerce, platformfulfillment, riderearnings, etc.). | **PASS** |
| **Regression: PostGIS Integration** | `go test ./internal/platformfulfillment ./internal/deliverydispatch` | `TestUnverifiedUPIIsBlockedFromMerchantFulfillmentPostGIS`: PASS (0.11s)<br>`TestUPIDispatchWaitsForVerifiedPaymentPostGIS`: PASS (0.13s) | **PASS** |
| **Regression: Mobile Flutter** | `flutter test` | **All 111 tests passed**. | **PASS** |
| **Regression: Flutter Analyzer** | `flutter analyze` | **18 diagnostics** (3 warnings, 15 infos, 0 errors; exactly matches baseline). | **PASS** |
| **Regression: Admin Web** | `auth-otp-02-admin-playwright.ps1` | **1 passed (3.2s)**. | **PASS** |

---

## 7. Admin Posting Authorization & Payable Accrual Closure

Tested via automated script `scripts/qa/run-finance-post-tests.sh` (`test-finance-post-authorization.mjs`):

### 1. Negative Access Tests (Denied `finance.post`)
Attempting `POST /api/v1/admin/finance/orders/{orderId}/accrue-payable` across non-permitted identities:
- **Customer** (`+919990000181`): HTTP 403 Forbidden (`FORBIDDEN: The required finance permission is not granted.`)
- **Merchant** (`+919990000182`): HTTP 403 Forbidden (`FORBIDDEN: The required finance permission is not granted.`)
- **Rider** (`+919990000183`): HTTP 403 Forbidden (`FORBIDDEN: The required finance permission is not granted.`)
- **Admin without `finance.post` grant** (`+919990000177`): HTTP 403 Forbidden (`FORBIDDEN: The required finance permission is not granted.`)

### 2. Two-Person Commission Policy Governance
- **Policy Creation**: Admin 1 (`+919990000174`) drafted grocery commission policy (`percentage_bps: 500` / 5%).
- **Self-Approval Blocked**: Admin 1 attempting self-approval returned HTTP 403 `SELF_APPROVAL_FORBIDDEN`.
- **Independent Approval**: Admin 2 (`+919990000175`, distinct approver) approved standard policy (`a3551c58-b91b-4f40-bde0-26deb62ab983`).
- **Database Trigger Guard**: `merchant_commission_policy_guard` verified preventing overlapping active policies for the same business/vertical.

### 3. Permitted Posting & Balanced Accrual Journals
- **COD Order `GN-1E923DBB` Accrual**: Admin with `finance.post` (`+919990000174`) called accrue: HTTP 201 Created. Snapshot `a4d2c637-92f1-4138-8251-2b3dbdec223f` posted with Journal `b4756684-3455-4d83-85a6-71f20ee1ccdf`:
  - Debit `merchant_fulfillment_cost`: 21000 minor (₹210.00)
  - Credit `merchant_payable_liability`: 19950 minor (₹199.50)
  - Credit `platform_commission_clearing`: 1050 minor (₹10.50)
  - Balanced: Total Debit 21000 = Total Credit 21000.
- **Idempotent Replay**: Re-calling accrue on `GN-1E923DBB` returned HTTP 201 with `idempotent_replay: true`.
- **Selective Posting (Zero Auto-Posting)**: While COD order was accrued, UPI order `GN-053335A3` remained unposted and present in `GET /api/v1/admin/finance/eligible-orders`.
- **UPI Order `GN-053335A3` Accrual**: Admin with `finance.post` (`+919990000174`) called accrue: HTTP 201 Created. Snapshot `6f024059-f0d6-424f-bd9b-c308e32399e0` posted with Journal `f05050ce-e810-4066-8441-bfe4a94e592d`:
  - Debit `merchant_fulfillment_cost`: 21000 minor (₹210.00)
  - Credit `merchant_payable_liability`: 19950 minor (₹199.50)
  - Credit `platform_commission_clearing`: 1050 minor (₹10.50)
  - Balanced: Total Debit 21000 = Total Credit 21000.
- **Audit Trail**: Recorded in `merchant_finance_audit_events` with actor `3e000000-0000-4000-8000-000000000004` and event type `payable_accrued`.

---

## 8. Runtime Environment, Container Inventory & Untested Criteria

### Active Container & Service Inventory
1. **Retained Isolated QA Containers**:
   - `grepmind_3e_qa_db` (`127.0.0.1:55432->5432/tcp`): Tmpfs PostGIS isolated database with Phase 4E.2 test data.
   - `grepmind_4c_qa_api` (`127.0.0.1:18083->8080/tcp`): QA API service.
   - `grepmind_4c_qa_otp_inbox` (`127.0.0.1:18085->8090/tcp`): Challenge-bound QA OTP reader.
   - `grepmind_4c_qa_admin` (`127.0.0.1:3302->3000/tcp`): Admin Web QA portal.
   - `grepmind_4c_qa_merchant` (`127.0.0.1:3301->3001/tcp`): Merchant Web QA portal.
   - `grepmind_4c_qa_minio` (`9000/tcp`): QA object storage.
2. **Stopped Disposable Containers**:
   - `grepmind_4e2_runtime_api` (Exited 0): Preserved batch artifact.
   - `grepmind_4c_qa_otp_inbox_stale_20261113` (Exited 2): Stale OTP runner.
   - `grepmind_4c_qa_api_previous` (Exited 0): Stale QA API container.
3. **Preserved Standard Dev Services (Shared Environment Protected)**:
   - `grepmind_api` (`8080`), `grepmind_postgres` (`5432`), `grepmind_admin_web` (`3000`), `grepmind_merchant_web` (`3001`), `grepmind_nginx` (`80`), `grepmind_minio` (`9000-9001`), `grepmind_worker`: All running untouched; zero migrations applied to shared development database.

### Device & APK Verification Identity
- **Package**: `local.grepmind.grepmind_mobile`
- **versionCode**: `8008`
- **versionName**: `1.0.0`
- **SHA-256**: `46E2D48982F743170D41A05025A1F6A00FBC2445C9B415F50801FBD17FE20074`
- **Target Emulators**:
  - Customer: `emulator-5554` (`Pixel_8`)
  - Merchant: `emulator-5556` (`Pixel_8_Merchant_QA`)
  - Rider: `emulator-5558` (`Pixel_8_Rider_QA`)

### Untested Criteria (Explicitly Out of Scope for Phase 4E.2 & 4E.3)
1. **Real Money / External Payouts**: Real payment gateway API calls, live UPI collections, and real bank payouts remain disabled (`real_money_enabled = false`, `upi_enabled = false`).
2. **Physical Cash Handling**: Courier physical cash collection and branch cash deposit remain disabled (`cod_enabled = false`).
3. **Live GPS / Telemetry**: Device real-time GPS coordinate streaming and real-world traffic ETA calculations remain disabled (simulated status progression used).
4. **Phase 4E.4 Scope**: Final commerce settlement and payout execution remain unstarted pending Phase 4E.4 authorization.

---

## 9. Phase 4E.3 — Cancellation, Returns, Refunds & Financial Adjustments (Gate G3 Acceptance)

### A. Additive Migration 038
- **File**: `backend/migrations/038_cancellation_return_refund_safeguards.sql`
- **Applied to**: `grepmind_3e_qa_db` isolated PostGIS container.
- **Trigger Replacement**: Replaces trigger function `prevent_paid_platform_order_cancellation()` on `customer_orders` without modifying historic Migration 032.
- **Enforced Invariants**:
  1. **Pre-pickup cancellation only**: Blocks `NEW.status = 'cancelled'` if delivery job has `execution_state IN ('picked_up', 'en_route', 'delivered', 'returned')`.
  2. **Authoritative cancellation refund**: Requires `payment_refunds` row with `order_id = NEW.id`, `reason_code = 'order_cancelled'`, active/succeeded status (`requested`, `approved`, `processing`, `succeeded`), and sum of refunds covering order grand total. Partial refunds (`items_damaged`, `items_missing`) or rejected/failed refunds do NOT authorize order cancellation.
  3. **Authoritative return prerequisites**: Requires `delivery_jobs.execution_state = 'returned'`, `delivery_return_receipts.inventory_disposition IN ('restockable', 'not_restockable')`, `received_by` and `disposition_by` recorded, and `delivery_recovery_cases` with `incident_type = 'return_disposition_pending'`.

### B. `CancelOrder` Service Implementation
- **File**: `backend/internal/operations/service.go`
- **Container Build & Deploy**: Compiled with `CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /tmp/api ./cmd/api`, deployed to `grepmind_4c_qa_api:/bin/api`.
- **Workflow**:
  1. Atomically locks order (`SELECT ... FOR UPDATE`).
  2. Restricts cancellation to pre-pickup statuses: `placed`, `accepted`, `confirmed`, `preparing`, `ready_for_pickup`.
  3. Blocks post-pickup cancellation with HTTP 409 Conflict (`INVALID_STATE: Order has already been picked up for delivery and cannot be cancelled.`).
  4. Authoritative check on captured amount and remaining refundable balance.
  5. Idempotent creation of cancellation-linked refund in `payment_refunds` with `reason_code = 'order_cancelled'`, `status = 'requested'`.
  6. Atomic transition of order to `cancelled`, delivery job to `cancelled`, unassigned delivery offers to `cancelled`.
  7. Idempotent release of reserved inventory via `restoreOrderInventory`.
  8. Emits SSE event for real-time mobile updates.

### C. Validation Suite Execution
Automated suite: `scripts/qa/run-phase4e3-validation.sh` (`scripts/qa/phase4e3-validation.mjs`).

```bash
# Executed via WSL in repository root:
wsl bash -lc "cd /mnt/d/grepmind-near && ./scripts/qa/run-phase4e3-validation.sh"
```

**Results (Exit Code 0 — ALL PASS)**:
1. **Raw SQL Bypass 1**: Direct SQL `UPDATE customer_orders SET status='cancelled'` without refund rejected with `verified paid platform order requires an approved refund workflow before cancellation or return`. **PASS**
2. **Raw SQL Bypass 2**: Partial refund (`items_damaged`, ₹50 < ₹280) does not permit cancellation. **PASS**
3. **Raw SQL Bypass 3**: Rejected cancellation refund (`status='rejected'`) does not permit cancellation. **PASS**
4. **Raw SQL Bypass 4**: Direct SQL return without custody-aware return workflow rejected with `verified paid platform order requires an authorized custody-aware delivery return workflow before return`. **PASS**
5. **Race 12 (Cancel vs Merchant Accept)**: Customer cancellation races Merchant acceptance. Order cancelled, merchant accept returns HTTP 409 Conflict (`INVALID_STATE`), inventory reservations released exactly once (`status='released'`). **PASS**
6. **Race 10 (Payment Success vs Cancel)**: Payment success races Order cancellation. Order cancelled before capture; simulation webhook succeeds; capture journal posted (`sandbox_payment_capture`), attempt is `succeeded`, order remains `cancelled` (lifecycle not reopened), intent status is `reconciliation_required`, reconciliation event recorded (`late_success`). **PASS**
7. **Paid Order Cancellation & Independent Refund Review**: Paid order cancelled; refund automatically created in `requested` status; Admin 1 approved refund (HTTP 200); sandbox provider outcome simulated; refund transitioned to `succeeded` with balanced refund journal. **PASS**
8. **Race 23 (Concurrent Refunds Exceeding Captured Balance)**: 2x ₹200 refunds against ₹280 captured. Refund 1 returns HTTP 201 Created; Refund 2 returns HTTP 409 Conflict (`REFUND_AMOUNT_EXCEEDED`). **PASS**
9. **Race 26 (Return Ineligibility)**: Order in `returned` state submitted to `POST /api/v1/admin/finance/orders/{id}/accrue-payable`; rejected with HTTP 409 `ORDER_NOT_ELIGIBLE`. **PASS**
10. **Race 27 (Disputed Financial Adjustments)**: Debit adjustment of ₹50.00 requested on accrued order `GN-053335A3`; Admin 1 self-approval blocked with HTTP 403 `SELF_APPROVAL_FORBIDDEN`; Admin 2 (`+919990000175`, `4c000000-0000-4000-8000-000000000005`) independent approval succeeds (HTTP 200); balanced compensating journal posted (`financial_postings`: Debit `merchant_payable_liability` ₹50, Credit `merchant_fulfillment_cost` ₹50); historical capture, accrual, and refund journals preserved immutably. **PASS**

### D. Regression Suite Evidence
| Test Suite | Command | Result |
|---|---|---|
| **Go Backend Unit/Integration** | `go test -p 1 -count=1 ./internal/operations/... ./internal/payments/... ./internal/merchantfinance/...` | **PASS** (0.015s, 0.014s, 0.017s) |
| **PostGIS Fulfillment & Dispatch** | `go test -p 1 -count=1 ./internal/platformfulfillment ./internal/deliverydispatch` | **PASS** (0.012s, 0.011s) |
| **Flutter Mobile Tests** | `flutter test --no-pub` | **PASS (All 111 tests passed)** |
| **Flutter Analyzer** | `flutter analyze --no-pub` | **18 issues found** (3 warnings, 15 infos, 0 errors; exactly matches baseline) |

---

## 10. Phase 4E.3 Targeted Gate G3 Closure Verification Evidence (Executed 14 November 2026)

Automated script: `scripts/qa/run-phase4e3-closure-checks.sh` (`scripts/qa/phase4e3-closure-checks.mjs`).

```bash
# Executed via WSL in repository root:
wsl --exec bash -c "cd /mnt/d/grepmind-near && ./scripts/qa/run-phase4e3-closure-checks.sh"
```

### Check 1: Migration 038 Authorization Boundary & Anti-Forgery
- **PostgreSQL Privilege Hardening**: Privileges on `payment_refunds` verified granted strictly to `qa3e` (`INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER`). Anonymous and public access revoked.
- **Direct SQL Bypass Attempts on Verified Paid Order (`GN-6B5E2ED4`, `6b5e2ed4-fc7b-464d-b51f-5bce1e31528c`)**:
  - *Attempt 1 (Direct cancel without refund)*: Blocked by `prevent_paid_platform_order_cancellation()` trigger with `verified paid platform order requires an approved refund workflow before cancellation or return`.
  - *Attempt 2 (Manufactured refund with invalid SHA-256 fingerprint)*: Blocked by trigger fingerprint check `digest(order_id || '|' || amount_minor || '|order_cancelled', 'sha256')`.
  - *Attempt 3 (Manufactured refund requested by unauthorized actor)*: Blocked by trigger check `pr.customer_user_id = NEW.customer_user_id AND pr.requested_by = NEW.customer_user_id`.
  - *Attempt 4 (Manufactured refund lacking immutable audit trail)*: Blocked by trigger audit check requiring `payment_refund_audit_events` with `event_type = 'requested'` and `reason_code = 'order_cancelled'`.
- **Authoritative API Execution**: Order cancelled via `CancelOrder` endpoint; status transitioned to `cancelled`; refund automatically created with valid SHA-256 fingerprint and audit event logged (`actor_user_id: 4e300000-0000-4000-8000-000000000001`). **CHECK 1 PASS**

### Check 2: Successful Paid-UPI Custody-Aware Return
- **Order Lifecycle (`GN-7D92B2D0`, `7d92b2d0-7278-47a3-9714-04d009f0df17`)**:
  - Grand total: ₹280.00 sandbox UPI capture verified.
  - Merchant accepted, prepared, marked ready (`/platform-orders/{id}/ready`).
  - Rider accepted dispatch offer (`/rider/offers/{id}/accept`).
  - Partner issued 8-digit pickup verification code (`93736674`) via `POST /merchant/businesses/{id}/delivery-jobs/{jobId}/pickup-code`.
  - Rider verified pickup code -> custody transferred to Rider (`execution_state = 'picked_up'`).
  - Post-pickup cancellation guard verified: customer cancellation rejected with HTTP 409 Conflict (`INVALID_STATE`).
  - Rider reported transit exception (`unable_to_continue`) -> recovery case created.
  - Admin operator resolved exception with `action: 'require_return'` -> `execution_state = 'return_required'`.
  - Rider initiated return handover -> `execution_state = 'return_in_progress'`.
  - Merchant confirmed physical receipt (`POST /return/confirm`) -> job state transitioned to `returned`, rider assignment `released`.
  - Merchant recorded physical disposition: `restockable` (`POST /return/disposition`).
  - Admin finalized return (`POST /return/finalize`) -> order status transitioned to `returned`, inventory reservation `released`.
  - Return receipt immutable evidence verified:
    `{"inventory_disposition":"restockable","received_by":"4e300000-0000-4000-8000-000000000002","disposition_by":"4e300000-0000-4000-8000-000000000002","finalized_by":"3e000000-0000-4000-8000-000000000004"}`.
  - Customer refund requested (`e4aee938-3a1c-481f-b3ec-63969ef1bded`), Admin approved, simulated succeeded.
  - Balanced refund journal verified (`ce128a17-4a7b-48e8-b835-9212f6bd0381`):
    - Debit `qa_customer_receipts_unapplied` ₹280.00
    - Credit `qa_provider_clearing` ₹280.00
  - Returned order payable accrual guard verified: `POST /admin/finance/orders/{id}/accrue-payable` rejected with HTTP 409 `ORDER_NOT_ELIGIBLE`. **CHECK 2 PASS**

### Check 3: Refund-to-Payable Adjustment Double-Entry Linkage
- **Order Delivery & Payable Accrual (`GN-05611B6B`, `05611b6b-cbc3-462a-a4a5-b8b94c82a7c2`)**:
  - Capture journal posted: `befde472-c73e-48c6-8753-56c8919d9a7c` (Debit `qa_provider_clearing` ₹280.00, Credit `qa_customer_receipts_unapplied` ₹280.00).
  - Fulfilled and delivered with 8-digit customer delivery code.
  - Accrued merchant payable snapshot: Partner Gross ₹210.00, Commission (5%) ₹10.50, Net Merchant Payable ₹199.50.
  - Accrual journal posted: `2d85c139-7d90-46c2-bbc9-c20e0d59b738`:
    - Debit `merchant_fulfillment_cost` ₹210.00
    - Credit `merchant_payable_liability` ₹199.50
    - Credit `platform_commission_clearing` ₹10.50
- **Customer Partial Refund**:
  - Customer requested ₹50.00 refund for transit damage (`items_damaged`).
  - Admin approved refund; sandbox outcome simulated to `succeeded`.
  - Refund journal posted: `64041dfa-10b6-4b0b-a9c0-016d60976ce2`:
    - Debit `qa_customer_receipts_unapplied` ₹50.00
    - Credit `qa_provider_clearing` ₹50.00
- **Merchant Payable Adjustment & Two-Person Review**:
  - Debit payable adjustment requested: `417ba436-bff9-46da-ba4f-82d18b8a6b3b` (₹50.00).
  - Two-person control: Admin 1 (`3e000000-0000-4000-8000-000000000004`) self-approval blocked with HTTP 403 `SELF_APPROVAL_FORBIDDEN`. **PASS**
  - Independent Admin 2 (`4c000000-0000-4000-8000-000000000005`) approved adjustment.
  - Compensating journal posted: `b786598b-f6ff-4644-9c14-7a06e3425418`:
    - Debit `merchant_payable_liability` ₹50.00
    - Credit `merchant_fulfillment_cost` ₹50.00
- **Ledger Immutability Verified**:
  - Original capture journal preserved intact.
  - Original accrual journal preserved intact.
  - Customer refund journal preserved intact.
  - Compensating adjustment journal posted and balanced (Net merchant payable reduced from ₹199.50 to ₹149.50). **CHECK 3 PASS**

---

## 11. Final Gate G3 Closure Status

**Gate G3 Status**: **FULL PASS — CLOSED** (14 November 2026).  

---

## 12. Phase 4E.4 Gate G4-B Payout & Settlement Integration (Executed 14 November 2026)

Automated script: `scripts/qa/run-phase4e4-g4b-validation.sh` (`scripts/qa/phase4e4-g4b-validation.mjs`).

```bash
# Executed via WSL in repository root:
wsl --exec bash -c "cd /mnt/d/grepmind-near && ./scripts/qa/run-phase4e4-g4b-validation.sh"
```

### A. Architectural & Financial Deliverables
- **Additive Migrations Applied to QA DB (`grepmind_3e_qa_db`)**:
  - `backend/migrations/039_payout_beneficiaries_and_transfers.sql`:
    - `bank_beneficiaries`: AES-GCM envelope encryption (`account_number_encrypted`), keyed HMAC-SHA256 (`account_number_hmac`), masked read API (`XXXXXXXX1098`), auto-invalidation on detail modification, penny-drop verification status.
    - `bank_beneficiary_audit_events`: Immutable audit trail for beneficiary registration and verification.
    - `payout_transfers`: Multi-step payout transfer record with two-person approval columns and journal links.
    - `payout_transfer_attempts`: Durable attempt history tracking attempt number, idempotency key, provider transfer ID, and status (`initiated`, `timeout`, `succeeded`, `failed`, `reversed`).
    - `payout_provider_events`: Webhook ledger with payload SHA-256 and processing state (`received`, `processed`, `duplicate`).
    - Added `status` column and `merchant_payable_active_allocation_idx` to `merchant_settlement_batch_items`.
  - `backend/migrations/040_rider_settlement_and_ledger.sql`:
    - `rider_settlement_batches`: Lifecycle table for rider payouts (`draft`, `reviewed`, `approved`, `succeeded`, `failed`).
    - `rider_settlement_batch_items`: Earning entry allocation with `rider_earning_active_allocation_idx`.
    - `rider_earning_financial_mappings`: Exactly-once mapping from `rider_earning_entries` to general ledger journals.
    - Provisioned financial accounts: `rider_fulfillment_cost`, `rider_payable_liability`, `payout_clearing_liability`, `simulated_payout_disbursement_clearing`, `bank_disbursement_clearing`, `payout_return_clearing`.
    - Fail-closed gates: `sandbox_rider_settlement_enabled = true`, `payout_enabled = false`, `real_money_enabled = false`.

### B. Gate G4-B Acceptance Suite Results (8/8 Scenarios Passed)
1. **Scenario 1 (Beneficiary Security & Penny-Drop Verification)**:
   - Rejected invalid IFSC penny drop with HTTP 400 (`IFSC_INVALID`).
   - Updating bank details automatically deactivated previous active beneficiary.
   - Valid merchant and rider beneficiaries registered and verified.
   - Stored securely: Masked `XXXXXXXX1098`, 40 bytes encrypted, 32 bytes keyed HMAC.
2. **Scenario 2 (Merchant Settlement & Double-Entry Journals)**:
   - Created UPI order (`GN-F5199C3B`), fulfilled, delivered, accrued payable (Net ₹199.50).
   - Created settlement batch; two-person control verified: Admin 1 self-review blocked (403), Admin 2 self-approval blocked (403), Admin 3 approved.
   - Payout transfer created; Allocation journal posted:
     - Debit `merchant_payable_liability` ₹199.50
     - Credit `payout_clearing_liability` ₹199.50
   - Admin 2 approved transfer; execution confirmed by provider with UTR `QA_UTR_6d356bf7_66931908`.
   - Disbursement journal posted:
     - Debit `payout_clearing_liability` ₹199.50
     - Credit `simulated_payout_disbursement_clearing` ₹199.50
   - Batch items marked `status = 'settled'`.
3. **Scenario 3 (Concurrent Allocation & Duplicate Transfer Protection)**:
   - Re-allocating settled payable into new batch rejected by database unique index `merchant_payable_active_allocation_idx`.
   - Duplicate payout transfer on same batch rejected by unique constraint.
4. **Scenario 4 (Rider Settlement & Exactly-Once Earning Accrual)**:
   - 17 eligible earning entries mapped to GL without duplication (`rider_earning_financial_mappings`).
   - Batch created (Net ₹580.00), approved by independent Admin 2, transfer executed with UTR `QA_UTR_e1c14471_83760459`.
5. **Scenario 5 (COD Cash Liability Isolation)**:
   - Delivered COD order; rider collected ₹280.00 cash.
   - Outstanding liability ₹280.00 immediately blocked payout creation: `COD_REMITTANCE_REQUIRED`.
   - Rider remitted cash; Admin verified remittance; liability cleared.
6. **Scenario 6 (Provider Timeout & Late Reconciliation)**:
   - Special timeout beneficiary (account ending in `9999`) triggered simulated timeout; API returned HTTP 504 `PROVIDER_TIMEOUT`.
   - Transfer locked in `status = 'reconciliation_required'` without reversing ledger.
   - Retry while in-flight blocked.
   - Reconciliation query fetched authoritative provider status (`succeeded`) with UTR `QA_RECON_qa_tx_757e993f_1` and finalized disbursement.
7. **Scenario 7 (Post-Success Reversal via Webhook & Compensating Journal)**:
   - HMAC-SHA256 signed webhook processed for `payout.reversed`.
   - Compensating reversal journal posted:
     - Debit `simulated_payout_disbursement_clearing` ₹199.50
     - Credit `merchant_payable_liability` ₹199.50
   - Partner balance cleanly restored; historical disbursement journals untouched.
   - Duplicate webhook safely acknowledged with HTTP 200 and zero duplicate ledger actions.
8. **Scenario 8 (Real-Money Execution Disabled Guard)**:
   - `real_money_enabled = false` and `payout_enabled = false` verified in `financial_feature_config`.
   - `DisabledProductionProvider` fails closed on all operations with `ErrRealMoneyPayoutDisabled`.

---

## 13. Test Suite & Static Analysis Summary

| Test Suite | Command | Result |
|---|---|---|
| **Go Backend Unit/Integration** | `go test -p 1 -count=1 ./internal/operations/... ./internal/payments/... ./internal/merchantfinance/... ./internal/platformfulfillment ./internal/deliverydispatch ./internal/payouts/...` | **PASS (All 6 packages ok)** |
| **Flutter Mobile Tests** | `flutter test --no-pub` | **PASS (All 111 tests passed)** |
| **Flutter Analyzer** | `flutter analyze --no-pub` | **18 issues found** (3 warnings, 15 infos, 0 errors; exactly matches baseline) |
| **Phase 4E.4 Gate G4-B Suite** | `./scripts/qa/run-phase4e4-g4b-validation.sh` | **PASS (8/8 Scenarios Passed)** |

---

## 14. Phase 4E.4 Gate G4-B Closure Status

**Gate G4-B Status**: **FULL PASS — CLOSED for Isolated QA** (14 November 2026).  
**Phase 4E.4 Gate G4-C Status**: **STRICTLY DISABLED / UNAUTHORIZED** (stopped at Gate G4-B; real-money bank transfers remain disabled pending explicit user authorization).

---

## 15. Phase 4E.4 Gate G4-B Final Hardening Suite Verification

Automated Hardening Script: `scripts/qa/phase4e4-g4b-hardening.mjs`  
Runner: `scripts/qa/run-phase4e4-g4b-hardening.sh`  
Execution Date: 14 November 2026

### 5 Mandatory Hardening Checks

| Check # | Description | Execution Result | Integrity Verification |
|---|---|---|---|
| **Check 1** | **True Concurrent Allocation** | **PASS** | 10 concurrent requests to allocate single merchant payable: exactly 1 succeeded (HTTP 201), 9 failed safely with `merchant_payable_active_allocation_idx` unique index conflict. Zero duplicate journals; 100% GL balanced (0 unbalanced). Winning batch executed to payout (`status = succeeded`, UTR `QA_UTR_f030220f_2578059`). |
| **Check 2** | **Contradictory Provider Events** | **PASS** | **2.1 Stale Failure after Success**: Quarantined (`processing_state = 'quarantined'`), transfer preserved as `succeeded`.<br>**2.2 Late Success after Failure**: Quarantined (`processing_state = 'quarantined'`), transfer preserved as `failed`.<br>**2.3 Duplicate Reversal**: Marked duplicate (`processing_state = 'duplicate'`), zero duplicate journals posted.<br>**2.4 Unknown Provider Event**: Quarantined (`processing_state = 'quarantined'`).<br>**2.5 Timeout followed by Late Success**: Processed (`processing_state = 'processed'`), transfer transitioned `reconciliation_required` -> `succeeded`, disbursement journal posted. |
| **Check 3** | **Production & Staging Fail-Closed** | **PASS** | Database schema constraint `financial_feature_config_check` strictly rejects `real_money_enabled = true` at DB engine level. `DisabledProductionProvider` unit tests passed in both `production` and `staging` environments. Config flags restored safely (`real_money_enabled = false`, `payout_enabled = false`). |
| **Check 4** | **Beneficiary Security & Key Rotation** | **PASS** | Merchant, Rider, and Admin read endpoints return masked account (`XXXXXXXX4567`) and zero plaintext. Audit trail metadata logs only masked accounts and IFSC. Modifying bank details automatically deactivated previous beneficiary (`status = 'deactivated'`). AES-GCM key rotation (`v1:`, `v2:`) and historical ciphertext decryption verified (`TestKeyRotationAndHistoricalDecryption` PASS). |
| **Check 5** | **Fresh Migration Reproducibility** | **PASS** | Applied migrations 001 to 040 sequentially on disposable database `grepmind_fresh_mig_test`. Exactly 108 tables matched `grepmind_3e_qa`. All indexes (`merchant_payable_active_allocation_idx`, `rider_earning_active_allocation_idx`) and triggers (`payout_provider_events_immutable`, `bank_beneficiary_audit_immutable`) verified. Database dropped cleanly. |

### Hardening Verification Summary Table

| Hardening Scope | Command | Exit Code | Result |
|---|---|---|---|
| **Gate G4-B Hardening Suite** | `./scripts/qa/run-phase4e4-g4b-hardening.sh` | `0` | **PASS (5/5 Checks Passed)** |
| **Original 8-Scenario Acceptance** | `./scripts/qa/run-phase4e4-g4b-validation.sh` | `0` | **PASS (8/8 Scenarios Passed)** |
| **Backend Unit/Integration Tests** | `go test -p 1 -count=1 ./internal/payouts/... ./internal/operations/... ./internal/payments/... ./internal/merchantfinance/...` | `0` | **PASS** |
| **Flutter Mobile Tests** | `flutter test --no-pub` | `0` | **PASS (111/111 Tests Passed)** |
| **Flutter Static Analysis** | `flutter analyze --no-pub` | `1` (baseline) | **18 issues found** (0 errors, 3 warnings, 15 infos; exactly matches baseline) |





