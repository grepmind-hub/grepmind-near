# ABASHYAKA — CUSTOMER HOME POLISH & CATEGORY ARCHITECTURE
## Phase 01E Final Acceptance & Verification Report

**Date:** 19 November 2026  
**Status:** **PASS — ACCEPTED**  
**Branch:** `abashyaka-dev-01`  
**Target Surface:** Customer Mobile Application (`apps/mobile`)  
**Assigned Emulator:** `Pixel_8` (`emulator-5554`)  
**Verified Debug APK SHA-256:** `24b4ca518449abffa472ce99f9d8ee9be18c97ddcb00a913e8800862a921e889`  
**Test Suite Execution:** **142 / 142 tests passing (100%)**  

---

## 1. Executive Summary

Phase 01E modernizes the Abashyaka Customer Home visual hierarchy, category navigation architecture, and marketplace separations according to the approved 2026 Abashyaka Brand System:
- **Brand Palette:** Primary `#0B6B4A`, Accent Orange `#FF8A00`, Soft Mint `#E8F5E9`, Dark Green `#064D3A`, Neutral `#FFF9F2`.
- **Layout & Hierarchy:** Compact 160dp header card with embedded location and search bar, 4×2 category grid (8 primary categories above the fold), compact promotional banner, popular near you section, healthcare section, and local travel section.
- **Architectural Market Separation:** Dedicated routing for Food Delivery (merchant-owned restaurant menus with single-merchant cart), Grocery Marketplace (neighborhood kiranas + platform essentials), Pharmacy Marketplace (prescription inquiry + OTC wellness), Doctor Directory (chamber schedules + dual CTAs), and Local Transport Directory (fare guides + operator cards).
- **Zero Fabrication:** 100% of listings, dishes, medicines, fares, and doctors are backed by PostgreSQL PostGIS data and server-authoritative contracts.

---

## 2. Gate Execution & Audit Summary

| Approval Gate | Scope | Status | Evidence Document |
|---|---|---|---|
| **Gate 1** | Baseline Audit, Category Routing Matrix, Layout Specification | **PASS** | `docs/phases/ABASHYAKA_CUSTOMER_CATEGORY_ARCHITECTURE.md` |
| **Gate 2** | Customer Home Visual Polish, 4×2 Grid, Header Card, Dedicated Screens | **PASS** | `apps/mobile/lib/core/screens/home_screen.dart` |
| **Gate 3** | Food & Grocery Catalog Separation, Restaurant Menus, Single-Merchant Cart | **PASS** | `docs/phases/ABASHYAKA_FOOD_GROCERY_CATALOG_ARCHITECTURE.md` |
| **Gate 4** | Healthcare (Doctor Chambers & Pharmacy) & Local Transport Architecture | **PASS** | `docs/phases/ABASHYAKA_HEALTHCARE_TRANSPORT_ARCHITECTURE.md` |
| **Gate 5** | Multi-Emulator QA, APK Hash Recording, Automated Tests, Acceptance Report | **PASS** | `docs/phases/ABASHYAKA_CUSTOMER_HOME_CATEGORY_PHASE_01E_ACCEPTANCE.md` |

---

## 3. Dedicated Category Routing Matrix (Final)

| # | Home Category | Destination Screen | Architecture & Primary Functionality |
|---|---|---|---|
| 1 | **Food** | `SearchResultsScreen(initialCategory: 'restaurant')` | Merchant-owned restaurant discovery $\rightarrow$ Menu $\rightarrow$ Single-merchant cart (`cartProvider`) $\rightarrow$ Checkout review. |
| 2 | **Grocery** | `SearchResultsScreen(initialCategory: 'grocery')` | Local kiranas and supermarket storefronts $\rightarrow$ Store inventory $\rightarrow$ Checkout. (Banner preserves platform essentials catalog). |
| 3 | **Medicines** | `PharmacyMarketplaceScreen` | Dual healthcare flow: Prescription order inquiry to local chemist + OTC wellness store with direct checkout. |
| 4 | **Doctors** | `DoctorDirectoryScreen` | Doctor consultation chambers hosted at local clinics/medical stores, specialty filters, solid black `Book Visit` + outlined `Call Clinic`. |
| 5 | **Cab & Auto** | `LocalTransportScreen` | Local auto-rickshaws, cabs, and taxis, Union Standard Fare Guide, verified driver cards, solid black `Book` + outlined `Call`. |
| 6 | **Services** | `SearchResultsScreen(initialCategory: 'service')` | Professional services (Electrician, Plumber, Carpenter) $\rightarrow$ Service pro profile $\rightarrow$ Service request. |
| 7 | **Shops** | `SearchResultsScreen(initialCategory: 'retail')` | General neighborhood retail and artisans $\rightarrow$ Business details $\rightarrow$ Inquiries and orders. |
| 8 | **More / View all** | `CategoriesScreen` | Full 19-category taxonomy directory with search and section filter tabs. |

---

## 4. Photographic Evidence Table (Pixel 8 / emulator-5554)

| Artifact Reference | Screen Verified | Observations |
|---|---|---|
| `phase01e_01_customer_home_polished.png` | Polished Customer Home | Deep green header card (`#064D3A`, 20dp radius), nested delivering to & search, 4×2 category grid, compact banner, popular near you. |
| `phase01e_01b_customer_home_scrolled.png` | Customer Home (Scrolled) | Healthcare near you full-width card, Travel around your area full-width card, active bottom navigation bar. |
| `phase01e_08_restaurants_list.png` | Restaurant Directory | `Food & Restaurants` filter chip, real nearby restaurant listings, open/closed status. |
| `phase01e_09_restaurant_menu.png` | Restaurant Profile | Cover image, business details, Badambadi location, Products/Offers/Reviews tabs, Call/View actions. |
| `phase01e_09b_restaurant_products.png` | Restaurant Menu & Dishes | Dishes listing with Odia Chhena Poda Slice (₹95), 20m prep time, veg indicator, `+ ADD` CTA. |
| `phase01e_09d_added.png` | Cart Invariant Protection | Modal dialog enforcing single-merchant cart boundary and offering replace/keep options. |
| `phase01e_09e_cart_replaced.png` | Stepper & Floating Bar | `- 1 +` counter and brand green floating bar `1 items | ₹95` with `View Cart & Order ->`. |
| `phase01e_10_restaurant_cart.png` | Customer Cart Screen | Single-merchant cart badge, server-verified subtotal ₹95.00, Continue to order CTA. |
| `phase01e_11_restaurant_checkout.png` | Checkout Review Screen | Delivery address, items breakdown, Delivery/Takeaway selector, distance coverage rules. |
| `phase01e_12_grocery_stores.png` | Grocery Search Results | `Groceries & Kirana` filter chip with local grocery stores and kirana storefronts. |
| `phase01e_13_home_gate4.png` | Customer Home (Gate 4 Build) | Verified loaded home with active cart badge (`1`) on Orders tab. |
| `phase01e_14_pharmacy_marketplace.png` | Pharmacy Marketplace | Prescription upload banner card, filter chips, licensed pharmacy cards with dual CTAs. |
| `phase01e_15_doctor_directory.png` | Doctor & Clinic Directory | Doctor consultation cards, specialty chips, solid black `Book Visit` and outlined `Call Clinic`. |
| `phase01e_16_local_transport.png` | Local Cab & Auto Directory | Union Standard Fare Guide card, vehicle operator cards with solid black `Book` and outlined `Call`. |

---

## 5. Automated Regression Test Verification

The complete mobile test suite was executed against the modernized codebase:
- **Command:** `cd apps/mobile && flutter test`
- **Result:** **142 / 142 tests passing (100%)**
- **Execution Duration:** 36s
- **Regressions:** 0 detected.

Key test areas verified:
- `auth_onboarding_test.dart`: Splash, OTP entry, Indian phone validation.
- `abashyaka_entry_test.dart`: Onboarding persistence, session restore, 200% font scaling.
- `customer_cart_test.dart`: Single-merchant cart isolation, server-price verification, minimum order validation.
- `screens/explore_screen_test.dart`: Explore screen discovery cards and filter chips.
- `booking_scheduler_test.dart`: Appointment scheduling and time slot validation.
- `workspace_navigation_test.dart`: Customer navigation exposing Orders and Saved under Profile.

---

## 6. Build Artifact Verification

- **Package:** `local.grepmind.grepmind_mobile`
- **Build Mode:** Debug APK
- **APK Path:** `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`
- **SHA-256 Checksum:** `24b4ca518449abffa472ce99f9d8ee9be18c97ddcb00a913e8800862a921e889`
- **Installation Status:** Verified on `emulator-5554` (`Pixel_8`).

---

## 7. Conclusion & Next Recommendation

Phase 01E successfully addresses all UI alignment, category architecture, and marketplace separation requirements. The Customer experience now provides:
1. Fast, balanced 4×2 category discovery without awkward label wrapping or empty containers.
2. Distinct, functional destinations for Food Delivery, Groceries, Medicines, Doctors, and Cab & Auto.
3. Strict regulatory and architectural invariants (single-merchant cart protection, prescription inquiry compliance, real backend data only).

**Recommended Next Step:**
Proceed to customer order tracking and service fulfillment lifecycle enhancements or merchant order acceptance and dispatch workflows.
