# ABASHYAKA — CUSTOMER DESIGN PHASE 01B ACCEPTANCE REPORT
## Explore, Search Results and Nearby Map Screens

**Date:** 19 November 2026  
**Branch:** `abashyaka-dev-01`  
**HEAD Commit:** `e9aa8750036950609fab0d2d007470511efd213d`  
**Repository:** `D:\grepmind-near` (`/mnt/d/grepmind-near`)  
**Target Surface:** Customer Android App (`Pixel_8` / `emulator-5554`)  
**Target APK Version:** Version Code 9101 (`local.grepmind.grepmind_mobile`)  
**Candidate APK SHA-256:** `942E8800C8CE9B87D68489B7BAAF9121457166D48D7457CC7DEC89353C208A01`  
**Status / Decision:** **PASS** (Isolated QA Acceptance)

---

## 1. Executive Summary

Phase 01B successfully advances the Abashyaka Customer UI modernization across the three immediate destinations from the new Customer Home screen:
1. **Explore Screen (`explore_screen.dart`)**: Task-focused search and category discovery surface with a compact Abashyaka header, official "A" shopping bag emblem, Odia badge (`ଆବଶ୍ୟକ`), canonical launch hub selector (**Chhatia, Jajpur** & **Kuanpal, Katak**), genuine GPS matching, category filters, and live backend business listings.
2. **Search Results Screen (`search_results_screen.dart`)**: Dynamic search querying, category filtering chips with `#E8F5E9` mint accents and `#0B6B4A` borders, distance radius filter modal (1 km to 20 km), sort sheet, and empty recovery state tailored to active hubs.
3. **Nearby Map Screen (`nearby_map_screen.dart`)**: Dual-mode interactive map featuring Google Map integration and dynamic Radar Map Canvas with Abashyaka emerald sweep animations, category pills, current-location centering, and floating business preview card.

All 142 automated Flutter tests pass (100%), Flutter code analysis reports 0 errors and 0 warnings, and runtime acceptance was fully executed on `Pixel_8` (`emulator-5554`).

---

## 2. Official Brand & Visual Assets Integration

The newly supplied official Abashyaka brand artwork was integrated into the mobile app asset bundle:
- **Brand Palette:**
  - Primary Forest Green: `#0B6B4A` (`AppTheme.emerald`)
  - Dark Accent Green: `#064D3A` (`AppTheme.emeraldDark`)
  - Accent Orange: `#FF8A00` (`AppTheme.accentOrange`)
  - Soft Mint: `#E8F5E9` (`AppTheme.brandMint`)
  - Warm White: `#FFF9F2` (`AbashyakaTheme.warmWhite`)
- **Official Assets Saved:**
  - `assets/images/abashyaka_official_logo.png`: Transparent full brand logo with English wordmark, Odia script `ଆବଶ୍ୟକ`, and tagline *"Everything You Need, Locally."*
  - `assets/images/abashyaka_emblem_official.png`: High-resolution isolated "A" emblem with internal shopping bag and location pin.
  - `assets/abashyaka/splash_emblem.png`: Overwritten with the official emblem for consistent splash and header display.

---

## 3. Screen Implementations & Behaviors

### 3.1 Explore Screen (`apps/mobile/lib/core/screens/explore_screen.dart`)
- **Compact Brand Header:**
  - 38dp circular/rounded container featuring `assets/abashyaka/emblem_official.png`.
  - Prominent "Explore" title in dark forest green with adjacent `ଆବଶ୍ୟକ` mint pill badge.
  - Interactive Location Selector pill displaying current hub name (e.g. `Chhatia, Jajpur` or `Kuanpal, Katak`).
  - Circular shortcut button navigating directly to `NearbyMapScreen`.
- **Canonical Launch Hub Selection:**
  - Modal bottom sheet displaying verified launch hubs:
    * **Chhatia Hub**: Jajpur District, coordinates `(20.6105, 86.0270)`, 15 active stores.
    * **Kuanpal Hub**: Katak District, coordinates `(20.5250, 86.0820)`, 12 active stores.
  - Genuine device GPS detection via `Geolocator.getCurrentPosition()`, calculating Euclidean geodesic distances to both hubs and snapping to the closest authorized coverage zone.
- **Search & Filter Entry:**
  - Search input box with prefix search icon and clear/submit actions routing to `SearchResultsScreen`.
  - Horizontal category scroll view with real category models.
  - Section headers: "Nearby Shops & Services", "Recently added in [City]", and curated seasonal collection banners.

### 3.2 Search Results Screen (`apps/mobile/lib/core/screens/search_results_screen.dart`)
- **Top Search Bar:** Retains user query with back navigation and clear action.
- **Abashyaka Filter Chips:**
  - Filter chips styled with `#E8F5E9` mint background and `#0B6B4A` borders when active.
  - Quick filters: Radius pill (`5 km`, `10 km`, `20 km`), Sort (`Nearest`, `Top Rated`, `Best Match`), `Verified`, and `Open Now`.
- **Results & Empty State:**
  - Results count indicator dynamically synced with backend responses.
  - Empty recovery state displaying `search_off_rounded` icon in mint container with copy referencing Chhatia and Kuanpal, plus a "Reset Filters & Show All" button.
- **Navigation:** Tapping any business navigates to `BusinessDetailScreen` or `ServiceProScreen`.

### 3.3 Nearby Map Screen (`apps/mobile/lib/core/screens/nearby_map_screen.dart`)
- **Dual Visual Presentation:**
  - Google Maps tile view for real geographic context.
  - Interactive Radar Canvas fallback with animated sweep beam in `AppTheme.emerald` (`#0B6B4A`) and concentric distance rings.
- **Controls & Filters:**
  - Header with back navigation, active hub name, radius indicator, "Show Radar View" / "Show Map Tiles" toggle, and "Center on Me" GPS button.
  - Top floating horizontal category pills (`All Places`, `🛍️ Shops`, `🛠️ Services`, `🕒 Open Now`, `Grocery`, `Hardware`, `Medical`).
  - Floating bottom preview card with business ratings, category badges, directions launcher, and profile routing.

---

## 4. Automated Verification Results

### 4.1 Static Analysis
Command executed:
```bash
flutter analyze lib/core/screens/search_results_screen.dart lib/core/screens/nearby_map_screen.dart lib/core/screens/explore_screen.dart
```
**Result:** `No issues found! (ran in 8.9s)` (0 errors, 0 warnings, 0 infos).

### 4.2 Unit & Widget Test Suite
Command executed:
```bash
flutter test
```
**Result:** `142/142 tests passed!` (100% pass rate in 01:03).

### 4.3 Build Verification
Command executed:
```bash
flutter build apk --debug
```
**Result:** `✓ Built build/app/outputs/flutter-apk/app-debug.apk in 163.9s`  
**Package ID:** `local.grepmind.grepmind_mobile`  
**Version Code:** `9101`  
**APK SHA-256:** `942E8800C8CE9B87D68489B7BAAF9121457166D48D7457CC7DEC89353C208A01`

---

## 5. Emulator Acceptance Evidence

Executed on dedicated Customer emulator:
- **AVD Name:** `Pixel_8`
- **Device Serial:** `emulator-5554`
- **Installed Build:** `app-debug.apk` (`942E8800C8CE9B87D68489B7BAAF9121457166D48D7457CC7DEC89353C208A01`)

| Step | Action / Screen | Evidence Path | Key Verification Points |
|---|---|---|---|
| 1 | Customer Home | `docs/phases/evidence/abashyaka-customer/phase01b_01_customer_home.png` | Bottom 5-tab bar with Explore & Nearby tabs |
| 2 | Explore Screen | `docs/phases/evidence/abashyaka-customer/phase01b_02_explore_screen.png` | Compact header, official emblem, Odia badge, Cuttack/Kuanpal hub |
| 3 | Delivery Hub Selector | `docs/phases/evidence/abashyaka-customer/phase01b_03_explore_location_sheet.png` | GPS detection option, Chhatia Hub (15 stores), Kuanpal Hub (12 stores) |
| 4 | Hub Switch to Chhatia | `docs/phases/evidence/abashyaka-customer/phase01b_04_chhatia_selected.png` | Location switches to `Chhatia, Jajpur`; business list updates |
| 5 | Search Results Screen | `docs/phases/evidence/abashyaka-customer/phase01b_05_search_results_screen.png` | Query input, mint filter chips, empty state with Chhatia/Kuanpal copy |
| 6 | Radius Filter Sheet | `docs/phases/evidence/abashyaka-customer/phase01b_06_search_radius_sheet.png` | Radio selections from 1 km to 20 km |
| 7 | Radius Selection 20km | `docs/phases/evidence/abashyaka-customer/phase01b_07_radius_20km.png` | Chip updates to `20 km` and re-executes search |
| 8 | Nearby Map Screen | `docs/phases/evidence/abashyaka-customer/phase01b_08_nearby_map.png` | Map header, search point `Chhatia, Jajpur`, category filter row |
| 9 | Nearby Radar View | `docs/phases/evidence/abashyaka-customer/phase01b_09_nearby_radar_view.png` | Animated emerald sweep beam, concentric range rings, center me |
| 10 | Business Detail Routing | `docs/phases/evidence/abashyaka-customer/phase01b_10_business_detail.png` | Tapping local tailor opens detail screen with About/Products/Offers |

---

## 6. Files Created or Modified

1. `apps/mobile/lib/core/theme/app_theme.dart`: Updated quick-commerce color tokens to official Abashyaka palette (`#0B6B4A`, `#064D3A`, `#E8F5E9`).
2. `apps/mobile/lib/core/screens/explore_screen.dart`: Integrated compact brand header, official emblem, canonical hub selector with GPS matching, and fixed string interpolation diagnostics.
3. `apps/mobile/lib/core/screens/search_results_screen.dart`: Updated filter pill decoration to `#E8F5E9` mint, enhanced empty state styling and hub-specific copy.
4. `apps/mobile/lib/core/screens/nearby_map_screen.dart`: Replaced legacy blue accents with `AppTheme.emerald`, updated radar beam sweep shaders and verification icons.
5. `apps/mobile/pubspec.yaml`: Registered official branding assets in the Flutter asset bundle.
6. `apps/mobile/assets/abashyaka/splash_emblem.png`: Updated with official brand emblem.
7. `apps/mobile/assets/images/abashyaka_official_logo.png`: Full transparent logo with English, Odia, and slogan.
8. `apps/mobile/assets/images/abashyaka_emblem_official.png`: High-resolution isolated "A" emblem.
9. `docs/phases/evidence/abashyaka-customer/*`: 10 captured acceptance screenshots.

---

## 7. Known Limitations & Scope Boundaries

1. **Google Maps Emulator Tiles:** Google Map rendering in Android emulator without Google Play Services accounts displays the fallback grid. The built-in Radar Map Canvas provides a full interactive visual fallback with animated radar sweep and pin placement.
2. **Merchant/Rider Workspaces:** Untouched during this customer phase in accordance with project constraints.
3. **Backend Schema & Contracts:** Zero modifications to Go REST APIs or PostgreSQL schema.

---

## 8. Conclusion & Recommendation

Phase 01B has achieved **PASS** status. The Abashyaka Customer UI now possesses a cohesive, responsive, and thoroughly tested foundation covering:
- **Splash Screen**
- **Onboarding Carousel**
- **Phone Login & OTP Authentication**
- **Role Selection**
- **Location Selector & Canonical Hubs**
- **Customer Home Screen**
- **Explore Screen**
- **Search Results Screen**
- **Nearby Map & Radar Screen**

**Recommended Next Step:**
Proceed to **Phase 01C: Customer Business Detail, Service Professional Profile, and Platform Catalog/Cart Views** to complete the customer commerce browsing journey.
