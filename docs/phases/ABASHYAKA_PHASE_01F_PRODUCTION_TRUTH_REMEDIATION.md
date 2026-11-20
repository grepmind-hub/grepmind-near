# ABASHYAKA — PHASE 01F PRODUCTION-TRUTH REMEDIATION REPORT

**Phase**: 01F — Production-Truth Remediation & Customer Release-Safety  
**Repository**: `D:\grepmind-near`  
**Branch**: `abashyaka-dev-01`  
**Date**: 19 November 2026  
**Status**: ✅ PASS (Verified on Customer Emulator Pixel_8, Automated Suites 142/142 Flutter & Go Discovery Tests)

---

## 1. Executive Summary

Phase 01F resolves all critical data integrity gaps, unsupported claims, and branding inconsistencies discovered during the Phase 01E Production-Truth Audit. 

Synthetic QA businesses are now strictly isolated at the PostgreSQL database and Go backend discovery layers. In production, public clients can no longer see synthetic test fixtures, and client-supplied headers cannot bypass isolation. Customer app workflows in Pharmacy, Healthcare Facilities, and Local Transport have been stripped of fabricated badges, false prescription workflows, fake doctor hours, and hardcoded fares. All 14 legacy customer-facing Grepmind Near branding strings have been replaced with the approved Abashyaka identity while maintaining zero test regressions across the entire mobile test suite (142/142 passing).

---

## 2. Key Remediation Deliverables

### Step 1 (P0): Critical Synthetic QA Data Isolation
1. **Database Schema & Backfill Migration (`042_synthetic_business_isolation.sql`)**:
   - Added `is_synthetic BOOLEAN NOT NULL DEFAULT false` column to `businesses` table.
   - Created partial index `businesses_is_synthetic_idx ON businesses (is_synthetic) WHERE is_synthetic = true`.
   - Backfilled `is_synthetic = true` on all 46 synthetic records (0 genuine businesses touched).
   - Verified row counts: 4 genuine records (`is_synthetic = false`), 46 synthetic records (`is_synthetic = true`).
2. **Backend Discovery Enforcement (`backend/internal/discovery/service.go`, `locations.go`)**:
   - Implemented `allowSynthetic(r *http.Request) bool` helper strictly bound to server configuration (`cfg.Env == "qa" || cfg.Env == "test"`).
   - In production (`cfg.Env != "qa" && cfg.Env != "test"`), `b.is_synthetic = false` is enforced unconditionally in `SearchBusinesses`, `Nearby`, `Locations`, `ListCityOffers`, and `ListNewCatalogItems`.
   - Client headers (`X-QA-Preview`) cannot bypass server environment gates.
   - Tested live API: `curl /api/v1/businesses?city=Cuttack` returns strictly the 2 approved genuine merchants (`Cuttack Chandi Paints & Hardware` and `Mahanadi Electrical & AC Care`). Zero synthetic records leak.

### Step 2 & 4 (P0/P1): Truthful Category Workflows & Inert Filter Cleanup
1. **Pharmacy Marketplace (`pharmacy_marketplace_screen.dart`)**:
   - **Badge**: Removed false `'Licensed'` drug authority badge; replaced with `'Verified Listing'` strictly conditioned on `verification_status == 'verified'`.
   - **Prescription Workflow**: Replaced false prescription order CTA and service ticket button with an honest consultation card: *"Prescription Medicines & Inquiries: For scheduled prescription medicines, please call or visit your local chemist directly with a valid prescription."*
   - **Store Card CTAs**: Replaced generic home service booking (`ServiceRequestScreen`) with `'View Store'` (`BusinessDetailScreen`) and `'Call Store'` (`tel: phone_e164`).
   - **Empty State**: Truthful messaging indicating medical stores and pharmacies will appear as they register.
2. **Clinics & Medical Facilities (`doctor_directory_screen.dart`)**:
   - **Title**: Renamed from generic "Doctors & Clinics" to "Clinics & Medical Facilities".
   - **Inert Filters**: Removed static `_specialties` choice chips that lacked backend filtering support.
   - **Truthful Notice**: Added transparent info banner: *"Doctor consultation schedules at local clinics and medical stores will be listed here once verified by healthcare providers."*
   - **Facility Cards**: Display authentic facility status (*"Open now · Walk-in visits available"* vs *"Closed currently"*).
   - **CTAs**: Removed fake `'Book Visit'` trade booking action; retained `'Call Clinic'` and `'View Facility'`.
3. **Local Cab & Auto (`local_transport_screen.dart`)**:
   - **Hardcoded Fares**: Removed hardcoded numeric fares (₹25, ₹180, ₹40, ₹350).
   - **Automotive Repair Separation**: Filtered out automotive repair shops, garages, motor mechanics, and service centers from the passenger transport directory.
   - **Driver Badging**: Removed unverified `'Verified Driver'` badge; replaced with `'Verified Listing'`.
   - **Inert Filters**: Removed non-functional vehicle type chips (`Auto`, `Cab`, `Taxi`, `Local Trips`).
   - **CTAs**: Removed fake `'Book'` action; retained `'Call Operator'` and `'Operator Details'`.
   - **Empty State**: Truthful notice informing customers that registered drivers in their locality will appear as they join.

### Step 3 (P0): Locality & Delivery Badging
- Updated `BusinessCard` (`apps/mobile/lib/core/widgets/business_card.dart`):
  - Displays merchant locality and distance prominently (e.g. `Hardware • Chandi Chhak • 551 m`).
  - Badges restaurants with `'Delivery'` when `delivery_enabled == true`, or `'Dine-in Only'` when `delivery_enabled == false`.

### Step 5 (P1): Complete Visible Abashyaka Branding
Replaced all 14 customer-facing legacy Grepmind Near branding strings:
1. `apps/mobile/lib/core/screens/explore_screen.dart` (lines 1732 & 1838) -> Replaced with Abashyaka.
2. `apps/mobile/lib/core/screens/order_history_screen.dart` (line 592) -> `'Abashyaka Food order'`.
3. `apps/mobile/lib/core/screens/order_shopping_hub_screen.dart` (lines 156 & 307) -> `'Order on Abashyaka'`, `'Prices set by Abashyaka'`.
4. `apps/mobile/lib/core/screens/order_tracking_screen.dart` (lines 1172 & 1174) -> `'Abashyaka is finding an approved rider...'`, `'Abashyaka will retry...'`.
5. `apps/mobile/lib/core/screens/platform_cart_screen.dart` (line 380) -> `'Orders fulfilled with verified local partners under Abashyaka verified accountability.'`.
6. `apps/mobile/lib/core/screens/platform_product_detail_screen.dart` (line 214) -> `'Abashyaka verifies availability...'`.
7. `apps/mobile/lib/core/screens/profile_screen.dart` (lines 907, 1022, 1811) -> `'Abashyaka rider network'`, `'List your shop or professional trade on Abashyaka'`, `'Review Abashyaka permissions...'`.
8. `apps/mobile/lib/core/screens/service_request_status_screen.dart` (line 367) -> `'Abashyaka Help & Support'`.

---

## 3. Verification & Validation Evidence

### 1. Automated Test Suites
- **Go Discovery & Backend Tests**: `go test -v ./internal/discovery/...` and `go test ./internal/...` passed with 0 errors.
- **Flutter Mobile Suite**: `flutter test` executed 142 tests.
  - Result: **142 passed, 0 failed**.

### 2. Live Mobile Build Identity
- **APK Target**: `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`
- **APK SHA-256**: `AC6BBD848AC1784D549F35D71AA00A97E7D0747C7532A2419F3F5E2A2F050477`
- **Installation Surface**: Customer Emulator (`Pixel_8` / `emulator-5554`)
- **Package Installed**: `local.grepmind.grepmind_mobile` (`Streamed Install: Success`)

### 3. Screen Captures (Pixel_8)
- `phase01f_01_home_screen.png`: Validated 4x2 Category Grid, Abashyaka top branding, "Popular near you", "Shop from nearby stores" banner.
- `phase01f_03_pharmacy.png`: Honest prescription banner, no fake prescription uploads, truthful empty state.
- `phase01f_04_doctors.png`: "Clinics & Medical Facilities" header, honest doctor schedule notice, zero inert chips, truthful empty state.
- `phase01f_05_transport.png`: "Local Cab & Auto", zero hardcoded fares, automotive mechanics excluded, truthful empty state.
- `phase01f_07_all_search.png`: Shows exactly 2 genuine businesses with verified badges, locality tags (`Chandi Chhak`, `Badambadi`), and zero synthetic records.

---

## 4. Acceptance Status
Phase 01F Production-Truth Remediation is **PASS**. All audit-identified issues regarding synthetic exposure, fake badges, misleading booking workflows, and legacy customer branding have been resolved and verified on Android Customer emulator `emulator-5554`.
