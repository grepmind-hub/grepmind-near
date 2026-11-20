# ABASHYAKA — PHASE 01E PRODUCTION-TRUTH AUDIT
## Comprehensive Source, Backend, Database & Regulatory Verification Report

**Date:** 19 November 2026  
**Auditor:** Principal Flutter Architect, Go Backend Architect & Systems Auditor  
**Repository:** `D:\grepmind-near`  
**Branch:** `abashyaka-dev-01` (`e9aa8750036950609fab0d2d007470511efd213d`)  
**Audit Standard:** Strict Read-Only Verification against Production-Truth & Regulatory Compliance  

---

## 1. Executive Summary & Audit Classification Matrix

This audit examines the current implementation of Phase 01E (Customer Home, Food & Grocery Separation, Pharmacy Marketplace, Doctor Directory, and Local Transport). Every claim is validated directly against the Go backend REST API, PostgreSQL database schema, current table contents, and Flutter presentation layer.

### Classification Summary Table

| # | Audit Item | Classification | Severity | Current Status Summary |
|---|---|---|---|---|
| **1** | Food Delivery & Restaurant Menus | **VERIFIED** (Cart Isolation) / **REQUIRES APPROVAL** (Discovery Filter) | Medium | Single-merchant cart isolation is strictly enforced. However, `SearchResultsScreen` does not filter out non-delivery restaurants, and all 4 restaurants in the DB are synthetic fixtures. |
| **2** | Grocery Marketplace & Cart Separation | **VERIFIED** (No Silent Mixing) / **BLOCKED** (Merchant Grocery Ordering) | High | Platform cart and single-merchant carts are separated. However, merchant-owned grocery ordering is hard-blocked on the backend (`ValidateCart` restricts ordering to restaurants/cafes). |
| **3** | Pharmacy License & Prescription Workflow | **UI ONLY** / **MOCK / PLACEHOLDER** | High | `'Licensed'` badge is rendered from generic listing verification without drug license data (Form 20/21). Prescription CTA routes to generic trade service request with no image/document upload. |
| **4** | Doctor Profiles, Schedules & Appointments | **UI ONLY** / **MOCK / PLACEHOLDER** | High | No doctor records, qualifications, or schedules exist in the database. Specialty filter chips do not filter. "Book Visit" opens generic trade service request. |
| **5** | Cab & Auto Fare Amounts & Driver Verification | **MOCK / PLACEHOLDER** (**FLAGGED FOR REMOVAL**) | High | Route fares (₹25/₹180/₹40/₹350) are hardcoded in the Flutter widget with zero backend data source. Auto mechanic garage is displayed as "Verified Driver". Filter chips are inert. |
| **6** | Call and Book Action Handling | **VERIFIED** (Call) / **UI ONLY** (Book for Health/Transport) | Medium | Call initiates `tel:` intent. Book opens `ServiceRequestScreen`, which creates a `service_requests` row suitable for trades, but not for doctor tokens or transport booking. |
| **7** | Locality & Service Coverage Enforcement | **BLOCKED** / **REQUIRES APPROVAL** | High | App displays "near Kuanpal", but all database businesses are 25–50 km away in Badambadi or Jajpur Road. Checkout quotes later reject delivery due to distance. |
| **8** | QA PREVIEW & Synthetic Listings in Production | **BLOCKED** / **REQUIRES APPROVAL** | Critical | 46 out of 49 approved businesses in the database are synthetic `QA Fixture` or `QA PREVIEW` records. Backend `GET /businesses` lacks environment gating. |
| **9** | Elimination of Customer-Facing Grepmind Branding | **REQUIRES APPROVAL** | Medium | 14 customer-facing strings still display "Grepmind Near" across Explore, Hub, Cart, Product, Profile, and Support screens. |
| **10**| Core Commerce & Lifecycle Compatibility | **VERIFIED** | Low | Full Go test suite (`operations`, `discovery`, `cmd/api`) and mobile test suite (142/142) pass cleanly with zero breaking API contract changes. |

---

## 2. Detailed Findings & Technical Verification

### 1. Food Delivery: Eligible Restaurants, Menus & Cart Scoping
- **Classification:** **VERIFIED** (Cart Isolation & Pricing) / **REQUIRES APPROVAL** (Discovery Filtering)
- **Concrete Source Evidence:**
  - `apps/mobile/lib/core/providers/cart_provider.dart` (lines 160–210): Enforces single-merchant cart invariant. Adding an item from a new restaurant triggers a confirmation dialog preventing mixed-merchant carts.
  - `backend/internal/operations/service.go` (lines 43–110, `ValidateCart`):
    ```go
    if !enabled || (category != "restaurant" && category != "cafe") {
        writeError(w, http.StatusConflict, "ORDERING_UNAVAILABLE", "This business does not currently support product ordering.")
        return
    }
    ```
    Backend server-prices line items from PostgreSQL `products` and rejects unauthorized ordering.
  - `apps/mobile/lib/core/screens/search_results_screen.dart` (lines 80–92): Calls `GET /api/v1/businesses?category_slug=restaurant`.
- **Unresolved Issues:**
  - `GET /api/v1/businesses` selects `b.delivery_enabled`, but does NOT filter by `b.delivery_enabled = true` in the SQL `WHERE` clause (`backend/internal/discovery/service.go:290-330`). Consequently, restaurants that do not offer delivery (such as `QA PREVIEW · Neighborhood Kitchen`, where `delivery_enabled = f`) appear in search results; adding dishes from them fails downstream at cart validation.
  - In the database, only 4 restaurant records exist, and all 4 are synthetic QA records (`QA Fixture validation-0 - Restaurant & Food Cuttack`, `QA PREVIEW · Neighborhood Kitchen · Cuttack`, `QA PREVIEW · Neighborhood Kitchen · Jajpur`, `QA Fixture validation-0 - Restaurant & Food Jajpur`).
- **Proposed Fix:**
  1. Add optional query parameter `delivery_enabled=true` to `GET /api/v1/businesses` when invoked from Food Delivery routes.
  2. Display clear UI badges: "Delivery Available" vs. "Dine-in / Takeaway Only".

---

### 2. Grocery Marketplace: Storefronts vs. Platform Inventory
- **Classification:** **VERIFIED** (No Silent Mixing) / **BLOCKED** (Merchant Grocery Checkout)
- **Concrete Source Evidence:**
  - Platform Grocery uses `PlatformCatalogScreen` with `platformCartProvider` (`apps/mobile/lib/core/providers/platform_cart_provider.dart`), placing orders via `POST /api/v1/platform/orders`.
  - Store-specific ordering uses `BusinessDetailScreen` with `cartProvider` (`apps/mobile/lib/core/providers/cart_provider.dart`), placing orders via `POST /api/v1/businesses/{id}/orders`.
  - The two cart models are isolated in separate Riverpod state containers; they cannot silently combine items into a single order.
- **Unresolved Issues:**
  - In `backend/internal/operations/service.go` line 66, `ValidateCart` explicitly restricts product ordering:
    ```go
    if !enabled || (category != "restaurant" && category != "cafe") {
        writeError(w, http.StatusConflict, "ORDERING_UNAVAILABLE", "This business does not currently support product ordering.")
        return
    }
    ```
    Because `category != "restaurant" && category != "cafe"`, **any attempt to validate a cart from a local grocery store (`category_slug = 'grocery'`) is rejected with HTTP 409 `ORDERING_UNAVAILABLE`**.
  - Local grocery store checkout is therefore hard-blocked on the backend until an approved change expands `ValidateCart` to include eligible retail/grocery merchants.
- **Proposed Fix:**
  - Create a migration/application service update allowing approved grocery stores with `delivery_enabled = true` to pass cart validation.

---

### 3. Pharmacy Marketplace: License Verification & Prescription Workflow
- **Classification:** **UI ONLY** / **MOCK / PLACEHOLDER** (Severity: HIGH)
- **Concrete Source Evidence:**
  - `apps/mobile/lib/core/screens/pharmacy_marketplace_screen.dart` (lines 388–396):
    ```dart
    if (business.verificationStatus == 'verified')
      Text('Licensed')
    ```
  - `backend/migrations/001_core_schema.sql` (`businesses` table definition):
    ```sql
    verification_status text not null default 'unverified',
    CHECK (verification_status = ANY (ARRAY['unverified', 'pending', 'verified', 'rejected']))
    ```
- **Unresolved Issues:**
  - **Misleading Regulatory Claim:** The database `businesses` table has NO columns for drug license numbers (e.g. Form 20/21 issued by Odisha State Drugs Controller), NO license expiry dates, and NO registered pharmacist registration numbers. Labeling a business "Licensed" simply because an admin set generic listing verification to `'verified'` violates standard pharmaceutical regulatory truth.
  - **Prescription Workflow is Non-Functional:** Tapping "Send Prescription to Pharmacy" or "Order Medicines" navigates to `ServiceRequestScreen`. That screen was built for home trade bookings; it contains no camera capture, image upload, PDF upload, or prescription parsing capability. It creates an unattached text row in `service_requests`.
- **Proposed Fix:**
  1. Rename the badge from `'Licensed'` to `'Verified Listing'` until a dedicated `pharmacy_licenses` table is implemented.
  2. Replace the prescription CTA with an honest action: *"Call Pharmacist"* or add a camera prescription upload flow backed by object storage (`MinIO/S3`).

---

### 4. Doctor Availability: Profiles, Consultation Schedules & Appointment Engine
- **Classification:** **UI ONLY** / **MOCK / PLACEHOLDER** (Severity: HIGH)
- **Concrete Source Evidence:**
  - `apps/mobile/lib/core/screens/doctor_directory_screen.dart` (lines 20, 152, 168):
    ```dart
    String _selectedSpecialty = 'All';
    ...
    onSelected: (selected) {
      if (selected) setState(() => _selectedSpecialty = specialty);
    }
    ```
  - Database Inspection:
    - Tables `professional_profiles`, `services`, and `availability_slots` for the medical fixture `fcbf5946-778a-4e0c-9a09-f10820fb97ae` contain 0 services and 0 availability slots.
    - No doctor entities (Doctor Name, MBBS/MD, Medical Council Registration No.) exist anywhere in PostgreSQL.
- **Unresolved Issues:**
  - **Inert Specialty Filter:** `_selectedSpecialty` is never used to filter the facilities list or passed to the API. Tapping `Pediatrics` or `Dentistry` renders identical results without filtering.
  - **Fictitious Consultation Hours:** The UI displays `"Open now for consultations and walk-ins"` based purely on `business.isOpenNow` of the retail pharmacy shop, not actual doctor consultation timings.
  - **Booking CTA is a Trade Request:** Tapping "Book Visit" opens `ServiceRequestScreen` (`POST /businesses/{id}/requests`). There is no doctor selection, no appointment token generation, and no consultation fee handling.
- **Proposed Fix:**
  1. If doctor chamber scheduling cannot be backed by actual relational tables in this phase, label cards accurately as *"Clinics & Diagnostics"* rather than implying individual verified doctor schedules.
  2. Implement specialty filtering against actual business tags or service names.

---

### 5. Local Transport: Fare Amounts & Operator Claims
- **Classification:** **MOCK / PLACEHOLDER** (Severity: HIGH — **FLAGGED FOR REMOVAL**)
- **Concrete Source Evidence:**
  - `apps/mobile/lib/core/screens/local_transport_screen.dart` (lines 205–213):
    ```dart
    Text(
      '· $locality ➔ Salipur: ₹25 (Shared) / ₹180 (Reserve)\n'
      '· $locality ➔ Cuttack Badambadi: ₹40 (Shared) / ₹350 (Reserve)\n'
      '· Direct operator contact. Quotes agreed directly with driver.',
    )
    ```
  - Database Inspection:
    - Zero transport fare tables exist in the database.
    - Querying `category_slug = 'automotive'` returns `QA Fixture validation-0 - Automotive & Repairs Cuttack` (an auto repair garage).
  - `local_transport_screen.dart` (line 389): Displays `'Verified Driver'` for any automotive business with `verificationStatus == 'verified'`.
  - `local_transport_screen.dart` (lines 20, 151, 167): `_selectedVehicle` filter chips do not filter the list.
- **Unresolved Issues:**
  - **Fabricated Fare Amounts:** Fares (₹25, ₹180, ₹40, ₹350) are hardcoded strings without source attribution or tariff regulatory verification. They interpolate `$locality` indiscriminately (e.g., claiming ₹25 from Chhatia to Salipur across district borders).
  - **Misleading 'Verified Driver' Badge:** Automotive mechanic garages are displayed as "Verified Drivers".
  - **Inert Vehicle Filter:** Filter chips (`Auto-rickshaw`, `Local Taxi`, `Cab`) do not filter operators.
- **Proposed Fix:**
  1. **Flagged for Immediate Removal:** Remove hardcoded numeric fare claims (`₹25`, `₹180`, `₹40`, `₹350`).
  2. Replace the banner with an honest notice: *"Direct Operator Directory: Contact local drivers directly for availability and agreed fares."*
  3. Change the badge from `'Verified Driver'` to `'Verified Operator'`.

---

### 6. Call and Book Button Functional Verification
- **Classification:** **VERIFIED** (Call) / **UI ONLY** (Book for Health/Transport)
- **Concrete Source Evidence:**
  - `_makeCall(phoneE164)` in `DoctorDirectoryScreen`, `LocalTransportScreen`, and `PharmacyMarketplaceScreen`:
    ```dart
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
    ```
    Verified functional; triggers Android dialer intent with the stored E.164 phone number.
  - "Book" CTA navigates to `ServiceRequestScreen` (`POST /api/v1/businesses/{id}/requests`), which inserts a record into `service_requests`.
- **Unresolved Issues:**
  - For healthcare and transport, `ServiceRequestScreen` does not provide the advertised workflow (no doctor token, no patient details, no vehicle pickup/drop points).
- **Proposed Fix:**
  - For transport and medical stores without specific service slots, change the primary CTA to `"Contact / Inquire"` rather than `"Book"` to avoid misleading customers.

---

### 7. Locality and Merchant Service Coverage Enforcement
- **Classification:** **BLOCKED** / **REQUIRES APPROVAL** (Cross-Locality Distance Gap)
- **Concrete Source Evidence:**
  - Database Query:
    ```sql
    SELECT DISTINCT city, locality FROM businesses WHERE status = 'approved';
    -- Cuttack: Badambadi, Chandi Chhak
    -- Jajpur: Jajpur Road
    ```
  - `home_screen.dart` (line 40): `ref.watch(homeFeedProvider(location.cityName))` passes only `cityName` (`'Cuttack'`), not `localityId`.
- **Unresolved Issues:**
  - When a customer sets their location to `Kuanpal, Cuttack`, the app displays:
    - Header: `"Delivering to Kuanpal, Cuttack"`
    - Subheaders: `"Consultations near Kuanpal, Cuttack"`, `"Operators available in Kuanpal, Cuttack"`.
  - In reality, all approved Cuttack businesses are located in Badambadi (~28 km from Kuanpal). No approved businesses exist in Kuanpal.
  - When the customer proceeds to checkout, the quote engine flags or rejects delivery because distance exceeds allowable radius.
- **Proposed Fix:**
  - Display accurate locality distance badges on cards (e.g. *"Badambadi · 28 km away"*).
  - Explicitly mark listings outside delivery boundaries as *"Dine-in / Takeaway Only"* or *"Out of Delivery Range"*.

---

### 8. QA PREVIEW and Synthetic Listings in Production
- **Classification:** **BLOCKED** / **REQUIRES APPROVAL** (Severity: CRITICAL)
- **Concrete Source Evidence:**
  - PostgreSQL Database Audit:
    - Total approved businesses: **49**
    - Synthetic QA businesses (`QA Fixture validation-0 - ...` and `QA PREVIEW · ...`): **46**
    - Non-QA approved businesses: **3** (`Mahanadi Electrical & AC Care`, `Biraja Plumbing & Motor Services`, `Cuttack Chandi Paints & Hardware`).
  - `backend/internal/discovery/service.go` (line 291): `SELECT ... WHERE b.status = 'approved'`.
- **Unresolved Issues:**
  - The backend REST API does not distinguish between test fixtures and production merchants. Any business with `status = 'approved'` is returned in live customer searches.
  - If the database is not purged prior to production, real customers in Cuttack and Jajpur will see 46 mock businesses with placeholder phone numbers.
- **Proposed Fix:**
  1. Add a database migration/column `is_synthetic boolean not null default false`.
  2. Filter `b.is_synthetic = false` in `SearchBusinesses`, `Nearby`, and `HomeFeed` unless a `X-QA-Preview: true` header is provided.

---

### 9. Customer-Facing Grepmind Near Branding Regressions
- **Classification:** **REQUIRES APPROVAL** (14 Visible String Regressions)
- **Concrete Source Evidence:**
  A scan of `apps/mobile/lib/` identified 14 customer-visible strings referencing "Grepmind" rather than "Abashyaka":
  1. `explore_screen.dart:1732`: `'Grepmind Near will provide services in this location soon!'`
  2. `explore_screen.dart:1838`: `'...when Grepmind Near launches in ${appLocation.cityName}.'`
  3. `order_history_screen.dart:592`: `'Grepmind Food order'`
  4. `order_shopping_hub_screen.dart:156`: `'Order on Grepmind'`
  5. `order_shopping_hub_screen.dart:307`: `'Curated locally · Prices set by Grepmind'`
  6. `order_tracking_screen.dart:1172`: `'Grepmind is finding an approved rider for this locality.'`
  7. `order_tracking_screen.dart:1174`: `'A rider is not available yet. Grepmind will retry when possible.'`
  8. `platform_cart_screen.dart:380`: `'...Grepmind Near fulfills orders with double-entry accountability.'`
  9. `platform_product_detail_screen.dart:214`: `'Grepmind verifies availability and final pricing before checkout...'`
  10. `profile_screen.dart:907`: `'Apply to join the Grepmind rider network'`
  11. `profile_screen.dart:1022`: `'List your shop or professional trade on Grepmind'`
  12. `profile_screen.dart:1811`: `'Review Grepmind Near permissions in Android settings'`
  13. `role_selection_screen.dart:136`: `'Welcome to Grepmind Near'`
  14. `service_request_status_screen.dart:367`: `'Grepmind Help & Support'`
- **Proposed Fix:**
  - Update all 14 customer-facing user strings to "Abashyaka" while leaving internal IDs (`local.grepmind.grepmind_mobile`, package names, and backend endpoints) unchanged.

---

### 10. Existing Lifecycle & Architecture Compatibility
- **Classification:** **VERIFIED**
- **Concrete Source Evidence:**
  - Go Backend Test Suite:
    - `grepmind-near/backend/internal/operations`: **PASS**
    - `grepmind-near/backend/internal/discovery`: **PASS**
    - `grepmind-near/backend/cmd/api`: **PASS**
  - Flutter Mobile Test Suite: **142 / 142 tests passing (100%)** (`apps/mobile/test`).
  - Authoritative API contracts (`api/openapi.yaml`) and database migrations remain 100% backward-compatible.

---

## 3. Prioritized Remediation Roadmap (Awaiting Approval)

| Priority | Issue / Risk | Concrete Remediation | Approval Required |
|---|---|---|---|
| **P0 (Immediate)** | Hardcoded Cab/Auto Fares | Remove hardcoded fares (`₹25`, `₹180`, `₹40`, `₹350`) from `LocalTransportScreen`. Replace with honest driver contact disclaimer. | Yes |
| **P0 (Immediate)** | Misleading "Licensed" & "Verified Driver" Badges | Replace `'Licensed'` on medical stores with `'Verified Listing'`; replace `'Verified Driver'` on automotive shops with `'Verified Operator'`. | Yes |
| **P1** | Inert Filter Chips in UI | Wire or remove inert specialty chips (`DoctorDirectoryScreen`) and vehicle filter chips (`LocalTransportScreen`). | Yes |
| **P1** | Customer-Facing Grepmind Branding | Update the 14 identified UI strings from "Grepmind Near" to "Abashyaka". | Yes |
| **P2** | Backend Grocery Cart Gating | Expand `backend/internal/operations/service.go` (`ValidateCart`) to allow approved grocery merchants with `delivery_enabled = true`. | Yes |
| **P2** | Synthetic QA Listings in Production | Implement `is_synthetic` filter on `businesses` query to ensure test fixtures never appear in live production environments. | Yes |

---

## 4. Verification Conclusion

Phase 01E successfully established the modern visual hierarchy and core navigation paths for Abashyaka. However, this production-truth audit reveals that several domain surfaces (Doctor Chambers, Pharmacy Prescription Upload, and Transport Fares) are currently **UI prototypes / placeholders** rather than production-backed services. Furthermore, hardcoded fare amounts and unverified regulatory badges must be remediated prior to production release.

**Next Action:** Awaiting user review and approval of the prioritized remediation roadmap before modifying source code.
