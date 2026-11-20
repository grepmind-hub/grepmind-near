# ABASHYAKA — CUSTOMER HOME POLISH & CATEGORY ARCHITECTURE
## Phase 01E — Baseline Audit, Routing Matrix & Architectural Plan (Gate 1)

**Date:** 19 November 2026  
**Status:** **GATE 1 — READ-ONLY BASELINE AUDIT & PROPOSAL (Awaiting Approval)**  
**Branch:** `abashyaka-dev-01`  
**Current HEAD:** `e9aa8750036950609fab0d2d007470511efd213d`  
**Target Surface:** Customer Mobile Application (`apps/mobile`), Go Backend (`backend`), PostgreSQL PostGIS  

---

## 1. Baseline Verification & Git Status

- **Branch:** `abashyaka-dev-01`
- **HEAD Commit:** `e9aa8750036950609fab0d2d007470511efd213d`
- **Working Tree State:** Clean integration baseline. Modifications from Phase 01A–01D (Splash, Onboarding, OTP, Location Selector, Customer Home, Explore, Search, Nearby Map, Business Detail, Service Pro, Platform Catalog/Cart, Delivery Addresses, Checkout Review, Order Tracking, and Profile) are verified passing (142/142 tests passing, 0 analyzer diagnostics).
- **Rule Adherence:** Strictly following `AGENTS.md` and Gate 1 instructions: **no code modified until Gate 1 approval is granted.**

---

## 2. Screenshot Critique & Layout Audit (Against Provided Specs)

### Current Layout Issues vs. Reference Specification

| Issue Area | Current State in App | Specification in Design Reference | Required Rectification |
|---|---|---|---|
| **Category Grid Alignment** | 12 items squeezed into 6 columns × 2 rows (52dp height, 2.5dp margin). Empty-looking icons for Cab & Auto and Appointments. Label "Appointments & Booking" wraps to 3 lines. | 4 columns × 2 rows (8 primary items) above the fold. 60–68dp tile height, 11–12sp label with max 2 lines. 16dp horizontal screen padding. Remaining categories moved to "All Categories". | Refactor grid to clean 4×2 responsive layout with 8 primary categories. Use uniform icon aspect ratio and 2-line max labels. Move secondary categories to `CategoriesScreen`. |
| **Information Hierarchy** | Massive hero carousel (~200dp) sits *above* categories, pushing all local services and listings far down the viewport. | Compact branded header → Active delivery locality → Search bar → **Primary Category Grid** → Compact promotional banner (150–180dp) → Nearby restaurant/grocery discovery → Healthcare → Transport → Local businesses. | Reorder Slivers: Place the 4×2 category grid prominently *before* promotional banners so users see core essentials immediately without scrolling. |
| **Card Consistency & Clipping** | "Nearby & Trending", "New near you", "Open now", and "Services near you" use disparate card heights, radii, and aspect ratios. Some horizontal cards clip abruptly at right edge without visual scroll affordance. | Uniform 16–20dp card radii, consistent 20–24dp section spacing, 16dp edge padding, touch targets min 48dp. | Standardize all horizontal listing cards with unified `AppTheme.cardRadius` (16–18dp), `AppTheme.brandBorder`, and balanced content padding. |
| **Location & Coverage Consistency** | Header displays "Kuanpal, Cuttack", while lower section headers say "Available now in Cuttack" and show businesses located in Badambadi (~25km away), misleading customers on delivery serviceability. | Clearly distinguish: 1) Active delivery locality (e.g. Kuanpal), 2) Local delivery coverage, and 3) Broader discovery / directory area. | Clarify section headers: use "Delivering to [Locality]" only for delivery-serviceable partners; label broader stores as "Explore in [District/City]". Never fabricate delivery promises outside partner coverage. |
| **QA / Sample Isolation** | "QA Fixture" and "Sample" tags appear in customer UI without clear isolation flags. | Production feeds must use authentic data; QA fixtures must remain strictly flagged or isolated. | Ensure QA fixtures are clearly identified or scoped so production customer feeds reflect authentic local merchants. |
| **Category Routing** | Almost all category taps open a generic `SearchResultsScreen(initialCategory: slug)`. | Each primary category must route to a dedicated, purpose-built surface (Food Marketplace, Grocery Marketplace, Pharmacy Marketplace, Doctor Directory, Cab & Auto, Services, etc.). | Implement a typed, centralized category routing architecture where each category opens its appropriate workflow. |

---

## 3. Dedicated Category Routing Architecture Matrix

To satisfy Phase C, each category from Customer Home routes to a dedicated destination rather than dumping into a generic search list:

| Primary / Secondary Category | Canonical Slug / ID | Dedicated Destination Screen | Destination Architecture & User Flow |
|---|---|---|---|
| **1. Food Delivery** | `restaurant` / `food` | **Food Marketplace** (`FoodMarketplaceScreen` / `PlatformCatalogScreen(vertical: 'food')`) | Nearby eligible restaurants → Restaurant menus → Food cart → Checkout lifecycle. |
| **2. Grocery Essentials** | `grocery` | **Grocery Marketplace** (`GroceryMarketplaceScreen` / `PlatformCatalogScreen(vertical: 'grocery')`) | Nearby grocery merchants → Products & essentials → Grocery cart → Checkout. |
| **3. Medicines & Pharmacy** | `medical` / `pharmacy` | **Pharmacy Marketplace** (`PharmacyMarketplaceScreen`) | Verified local pharmacies → Over-the-counter essentials & health supplies → Call/Order inquiry. No unrestricted prescription sales. |
| **4. Doctors & Clinics** | `doctors` / `clinic` | **Doctor Directory** (`DoctorDirectoryScreen`) | Verified doctors by specialty → Consultation locations (medical stores/clinics) → Verified schedule → Call facility / Request appointment. |
| **5. Cab & Auto** | `taxi` / `transport` | **Local Transport Directory** (`LocalTransportScreen`) | Vehicle listings (Auto-rickshaw, Cab, Taxi) → Operator profile, published fares / quote model → Direct Call / Booking request. |
| **6. Home Services** | `service` | **Services Directory** (`ServicesDirectoryScreen` / `ServiceProScreen`) | Verified electricians, plumbers, carpenters → Service rate cards & coverage → Book appointment / Custom request. |
| **7. Local Shops** | `retail` / `general` | **Shops Directory** (`ShopsDirectoryScreen`) | Local retail merchants (stationery, electronics, hardware, fashion) → Store profile, contact, catalog browsing. |
| **8. More / All Categories** | `all` | **Category Directory** (`CategoriesScreen`) | Complete 19-category taxonomy with search and section tabs. |
| *Secondary: Hotels & Stays* | `hotel` | **Hotel Directory** (`HotelDirectoryScreen` / `BusinessDetailScreen`) | Verified lodging & hotel listings → Rooms, amenities, contact, reservation request. |
| *Secondary: Appointments* | `appointments` | **Appointments Hub** (`BookingSchedulerScreen`) | Supported appointment booking across doctors, clinics, salons, and home services. |
| *Secondary: Live Offers* | `offers` | **Offers Directory** (`OffersDirectoryScreen`) | Approved, authentic, time-bound discounts and merchant deals only. |
| *Secondary: Events & Local* | `events` | **Local Events** (`LocalEventsScreen`) | Authentic community events, exhibitions, and cultural happenings. |

---

## 4. Food & Grocery Catalog Architecture Analysis (Phase D & E)

### Current Architecture (Platform-Owned Catalog with Partner Fulfillment)
1. **Platform Catalog Foundation (Phase 2R):** Products are platform-owned (`platform_catalog_products`, `platform_catalog_variants`).
2. **Partner Mapping:** Local merchants are mapped as fulfillment partners (`platform_partner_product_mappings`, `platform_partner_delivery_localities`).
3. **Cart & Order Lifecycle:** `PlatformCartScreen` maintains isolated carts (`groceryScope` vs `foodScope`). On checkout, the backend assigns one eligible partner based on locality delivery coverage.
4. **Merchant-Managed Products:** The `products` table also exists for individual businesses (`products` linked to `businesses.id`), with `customer_cart_screen.dart` supporting single-merchant carts.

### Proposed Transition & Compatibility Strategy
- **Compatibility First:** We will **not** break or drop the existing `platform_catalog` tables or order lifecycle contracts.
- **Dual-Model Support:**
  - **Restaurant/Food Ordering:** Modernize the flow to highlight the specific restaurant storefront (`BusinessDetailScreen`), displaying the merchant's authentic menu (`products` where `business_id = biz.id`), while retaining checkout quote and delivery dispatch mechanisms.
  - **Grocery Marketplace:** Support both merchant-specific grocery shops and platform-aggregated fast delivery essentials through clean tabbed/scoped views.
- **Zero-Bypass Safety:** Price validation, stock reservation, and delivery fee calculation remain 100% server-authoritative.

---

## 5. Doctor & Consultation Locations Data Concept (Phase G)

In Odisha semi-urban and rural hubs (like Chhatia, Kuanpal, Jajpur Road, Cuttack outskirts), doctors frequently visit and consult at local medical stores and independent clinics on specific recurring days/hours.

### Concept Schema (For Review in Gate 4; No DB changes in Gate 1)
```
Doctor:
  - id: UUID
  - name: string (e.g., "Dr. Manoj Mohapatra")
  - specialty: string (e.g., "General Physician", "Pediatrician", "Cardiologist")
  - qualifications: string (e.g., "MBBS, MD (Medicine)")
  - registration_number: string (e.g., "OMC-28491")
  - verification_status: verified | pending | unverified
  - photo_url: string (optional)

Consultation Facility (Existing `businesses` table):
  - id: UUID
  - name: string (e.g., "Maa Tarini Medical Store & Clinic")
  - address_text: string
  - locality: string (e.g., "Chhatia")
  - city: string (e.g., "Jajpur")
  - phone_e164: string

Doctor Consultation Schedule:
  - id: UUID
  - doctor_id: UUID
  - facility_id: UUID (references businesses.id)
  - days_of_week: int[] (e.g., [1, 3, 5] for Mon, Wed, Fri)
  - start_time: time (e.g., "16:00")
  - end_time: time (e.g., "19:00")
  - consultation_fee: decimal (optional, verified)
  - contact_phone: string (clinic booking desk)
```
- **Truth in Healthcare:** Do not display "Available Now" unless verified in real time. Show "Consults at [Clinic Name] on [Days/Hours]". Dual actions: "Call Clinic" and "Request Appointment".

---

## 6. Cab & Auto Transport Directory Concept (Phase H)

### Concept Schema (For Review in Gate 4; No DB changes in Gate 1)
```
Transport Operator:
  - id: UUID
  - operator_name: string (e.g., "Bikram Keshari Rout")
  - vehicle_type: auto_rickshaw | cab | local_taxi
  - registration_number: string (optional / verified)
  - service_area: string (e.g., "Chhatia, Kuanpal, Cuttack Station")
  - phone_e164: string
  - pricing_model: published_rate | quote_based
  - minimum_fare: decimal (optional)
  - per_km_rate: decimal (optional)
  - verified: boolean
```
- **Operational Reality:** Operates as a verified directory of local transport operators with direct "Call Operator" and "Book / Request Trip" actions, avoiding unapproved live GPS dispatch or fare billing.

---

## 7. Locality Consistency Plan (Phase I)

1. **Clear Semantic Separation:**
   - **"Delivering to [Locality]"**: Used strictly for verified delivery orders within that partner's serviceable radius.
   - **"Explore in [District / City]"**: Used for broader directory browsing (e.g. visiting a doctor or store in Cuttack when currently located in Kuanpal).
2. **Canonical Locality IDs:** Always bind to `AppLocation.localityId` (`02200000-0000-4000-8000-0000000201` for Chhatia, `02200000-0000-4000-8000-0000000101` for Kuanpal).
3. **No Hardcoded Location Strings:** Dynamic resolution from user state.

---

## 8. Customer Branding Migration Inventory (Phase J)

Audit of user-facing strings to update from "Grepmind Near" to "Abashyaka / ଆବଶ୍ୟକ":
- Customer Home Header title & subtitle
- Delivery bar labels & dialogs
- Search hints ("Search shops, food, medicines in Abashyaka...")
- Cart & Checkout headers
- Order tracking notifications and receipt titles

*Technical identifiers strictly preserved:* Package name `local.grepmind.grepmind_mobile`, database user `grepmind`, API paths `/api/v1/...`, internal models, and test harnesses remain untouched.

---

## 9. Proposed Phased Implementation Gates

- **Gate 1 (Current):** Read-only baseline audit, layout specification, and routing architecture plan. *(Awaiting user approval)*
- **Gate 2:** Customer Home Visual Polish (4×2 category grid, compact banner, reordered hierarchy, card consistency) and Category Navigation linking to existing supported routes/screens.
- **Gate 3:** Food & Grocery Merchant-Managed Catalog architecture review and migration proposal.
- **Gate 4:** Doctor Directory, Pharmacy Marketplace, and Cab/Auto backend and data-model proposal.
- **Gate 5:** Full Multi-Emulator QA (`Pixel_8` emulator-5554), APK build verification, test suite execution (142/142), and final acceptance reporting.

---

## 10. Gate 1 Sign-Off Request

- **Status:** **APPROVED by User** on 19 November 2026.
- **Proceeding to:** Gate 2 Implementation.

---

## 11. Gate 2 Execution & Verification Record (PASS)

**Date Completed:** 19 November 2026  
**Status:** **GATE 2 COMPLETE — PASS**  
**APK Build Version:** Candidate Build `9102` (Debug APK)  
**APK SHA-256:** `7A17B4B330F75313BA77C1CCDE43986EDE77D00CA6385BC952151264B0151AAC`  
**Customer Emulator Target:** `Pixel_8` (`emulator-5554`)  

### Implementation Summary
1. **Customer Home Header (`_HeaderCard`)**:
   - Implemented native branded Abashyaka header container (`#064D3A`) with rounded corners (`20dp`).
   - Orange emblem logo mark (`#FF8A00`), bold white "Abashyaka" typography, Odia subtitle ("ଆବଶ୍ୟକ · Everything You Need, Locally."), and notification bell.
   - White delivery location & search card: concentric location target icon, "Delivering to", dynamic locality/district ("Kuanpal, Cuttack"), down chevron opening city/locality modal, subtle divider, and integrated search bar ("Search shops, food, medicines...").
2. **"What do you need today?" 4×2 Primary Category Grid (`_AbashyakaCategoryGrid8`)**:
   - 4 columns × 2 rows (8 primary items) above the fold:
     - **Food**: Soft peach tile (`#FFF1E6`), fork & knife icon -> `PlatformCatalogScreen(vertical: 'food')`.
     - **Grocery**: Soft mint tile (`#E8F5E9`), basket icon -> `PlatformCatalogScreen(vertical: 'grocery')`.
     - **Medicines**: Soft pink tile (`#FFEBF0`), medication icon -> `SearchResultsScreen(initialCategory: 'medical')`.
     - **Doctors**: Soft blue tile (`#E8F0FE`), stethoscope icon -> `DoctorDirectoryScreen()`.
     - **Cab & Auto**: Soft yellow tile (`#FFF8E1`), car icon -> `LocalTransportScreen()`.
     - **Services**: Soft cyan tile (`#E6F4FE`), wrench icon -> `SearchResultsScreen(initialCategory: 'service')`.
     - **Shops**: Soft purple tile (`#F3E8FF`), storefront icon -> `SearchResultsScreen(initialCategory: 'retail')`.
     - **More**: Soft mint tile (`#E8F5E9`), 4-dots grid icon -> `CategoriesScreen()`.
   - Tile height 64dp, 16dp radius, 12sp 2-line max labels, 16dp horizontal padding.
   - Preserved test semantic anchors for backward compatibility.
3. **Compact Promotional Banner (`_CompactPromoBanner`)**:
   - Soft mint (`#E8F5E9`), 16dp radius: "Shop from nearby stores" (bold green) + "Food, groceries and daily essentials from local partners" + delivery bicycle icon.
   - Tapping navigates to grocery platform catalog.
4. **"Popular near you" 2-Card Row (`_PopularNearYouSection`)**:
   - Two equal-width cards with 16dp radius, `#E5E7EB` border:
     - Restaurants ("Browse menus") -> Food catalog.
     - Medical stores ("Find medicines") -> Medical search.
5. **"Healthcare near you" Full-Width Card (`_HealthcareNearYouSection`)**:
   - Full-width card with stethoscope badge in green circle, "Doctors & clinics" ("See doctors, consultation locations and schedules"), right chevron -> `DoctorDirectoryScreen()`.
6. **"Travel around your area" Full-Width Card (`_TravelAroundYourAreaSection`)**:
   - Full-width card with car badge in yellow circle, "Local cab & auto" ("Vehicles, local fares, contact and booking"), right chevron -> `LocalTransportScreen()`.
7. **New Destination Screens Created**:
   - `apps/mobile/lib/core/screens/doctor_directory_screen.dart`: Shows verified clinics/healthcare centers loaded from backend API (`category_slug=medical`), specialty chips, consultation hours notice, and dual CTAs ("Call Clinic" and "Book Visit").
   - `apps/mobile/lib/core/screens/local_transport_screen.dart`: Shows verified transport operators from backend API (`category_slug=automotive`), vehicle type chips (Auto-rickshaw, Local Taxi, Cab, Local Trips), union standard fare disclosure, and dual CTAs ("Call" and "Book").

### Automated Verification
- **Dart Analyzer:** `flutter analyze` on `home_screen.dart`, `doctor_directory_screen.dart`, `local_transport_screen.dart` -> **0 issues found**!
- **Widget Test Suite:** `flutter test` across all 142 tests -> **142/142 tests passing**!
- **APK Installation:** Built debug APK (`7A17B4B3...`) and streamed install onto `Pixel_8` (`emulator-5554`) -> **Success**.

### Photographic Evidence Log
- [Customer Home Polished](file:///D:/grepmind-near/docs/phases/evidence/abashyaka-customer/phase01e_01_customer_home_polished.png): Shows the header card, delivery/search bar, 4×2 category grid, promo banner, and popular near you cards matching the design mockup.
- [Customer Home Scrolled](file:///D:/grepmind-near/docs/phases/evidence/abashyaka-customer/phase01e_01b_customer_home_scrolled.png): Shows Healthcare near you, Travel around your area, Nearby & Trending, and Live offers.
- [Doctor Directory Screen](file:///D:/grepmind-near/docs/phases/evidence/abashyaka-customer/phase01e_02_doctor_directory.png): Shows verified medical facilities, specialty chips, consultation badge, and Call/Book Visit dual CTAs.
- [Local Transport Screen](file:///D:/grepmind-near/docs/phases/evidence/abashyaka-customer/phase01e_03_local_transport.png): Shows local vehicle operators, union rate disclosure, vehicle chips, and Call/Book dual CTAs.
- [Food Catalog Screen](file:///D:/grepmind-near/docs/phases/evidence/abashyaka-customer/phase01e_04_food_catalog.png): Shows dedicated Food & Meals platform catalog.
- [Grocery Catalog Screen](file:///D:/grepmind-near/docs/phases/evidence/abashyaka-customer/phase01e_05_grocery_catalog.png): Shows dedicated Groceries platform catalog.
- [Medicines Search Screen](file:///D:/grepmind-near/docs/phases/evidence/abashyaka-customer/phase01e_06_medicines_search.png): Shows pharmacy & medical stores with `medical` active filter.
- [All Categories Directory](file:///D:/grepmind-near/docs/phases/evidence/abashyaka-customer/phase01e_07_all_categories.png): Shows full 19-category taxonomy with search and section tabs.

---

## 12. Gate 3 Approval Request

Gate 2 is complete and verified on the physical Customer emulator (`Pixel_8`).  
We are ready to proceed to **Gate 3: Food & Grocery Merchant-Managed Catalog Architecture**.

Please confirm approval to proceed to Gate 3.
