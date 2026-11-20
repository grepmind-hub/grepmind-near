# ABASHYAKA — PHASE 03C ACCEPTANCE REPORT
## Rider Live Delivery Map, Route Guidance & Multi-Locality Hubs Acceptance

**Repository**: `D:\grepmind-near`  
**Branch**: `abashyaka-dev-01`  
**Date**: 19 November 2026  
**Status**: **PASS (Isolated QA Verified & 3-Emulator Validated)**  
**Authoritative UI Kit Reference**: `design-reference/abashyaka/rider/Abashyaka Rider App Workflow Screens.webp` (Screens 14, 18, 19, 20)

---

### 1. Executive Summary & Deliverables

Phase 03C implements and validates the **Rider Live Delivery Map, Turn-by-Turn Route Guidance, and Service Locality Hubs** for the **Abashyaka Rider** mobile application, fulfilling Screens 14, 18, 19, and 20 of `Abashyaka Rider App Workflow Screens.webp`:

1. **Screens 14 & 18 (In-Transit Route Guidance & Interactive Delivery Map)**:
   - Created `apps/mobile/lib/core/screens/rider_map_screen.dart` (`RiderDeliveryRouteMapScreen`).
   - **Screen 18 (Turn-by-Turn Header Guidance)**:
     - Prominent dark emerald (`#064D3A`) instruction card with maneuver icon (`Icons.straight_rounded` / `Icons.turn_right_rounded`).
     - Real-time instructional text (e.g. *"Head North towards Phase 3E QA Food Partner"*, or *"In 250m, continue onto Cuttack-Kuanpal Road"*).
     - Remaining distance and ETA badge (*"Pickup: Phase 3E QA Food Partner · 850m (~4 mins)"*, *"Destination: Kuanpal · 2.4 km (~12 mins)"*).
   - **Interactive Route Canvas (`_RiderRouteMapPainter`)**:
     - Custom high-performance canvas rendering stylized road network grid, arterial avenues, partner store origin pin, customer destination pin, and pulsing animated rider position indicator.
     - Floating map navigation controls: Zoom in, Zoom out, Recenter.
   - **Screen 14 (Destination Action Sheet)**:
     - Floating destination card displaying order reference, partner/customer name, locality, address, and single-use security code alert.
     - Direct contact action (`Call`), external navigation intent launcher (`Directions`), and primary stage transition action (`Verify partner handover` / `Confirm customer handover`).
2. **Screens 19 & 20 (Service Locality Hubs & Coverage Settings)**:
   - Created `apps/mobile/lib/core/screens/rider_locality_hubs_screen.dart` (`RiderLocalityHubsScreen`).
   - Replaced legacy placeholder in `apps/mobile/lib/main.dart` with dedicated Tab 3 (`Hubs`, `Icons.hub_rounded`).
   - **Screen 19 (Primary Hub & Distribution Radar)**:
     - Header banner for *"Cuttack & Jajpur Central Hubs · Active Regional Dispatch Center"*.
     - Interactive concentric radar canvas (`_HubCoverageRadarPainter`) showing distance rings (5 km, 10 km, 15 km), central hub node, and surrounding localities with approval status markers.
   - **Screen 20 (Shift Coverage Radius Slider)**:
     - Operational delivery radius slider (3.0 km to 15.0 km) with live badge and quick presets (`[3 km]`, `[5 km]`, `[8 km]`, `[10 km]`, `[15 km]`).
     - *"Apply Shift Radius"* action updating operational coverage with confirmation toast feedback.
   - **Operational Locality Directory**:
     - Live directory fetched from `/rider/localities` and `/rider/profile` displaying locality status pills (`Approved & Active`, `Available`, `Queue`).
   - **Strict Privacy Compliance**:
     - Clear notice: *"Dispatch availability is strictly controlled by backend-approved service localities. No background GPS tracking or unsolicited device geolocation is active."*

---

### 2. Multi-Emulator QA Fleet Mapping & APK Identity

The debug candidate APK was built with isolated QA flags and installed and verified across all three assigned emulators:

```
Build Command: flutter build apk --debug --no-pub --target-platform android-x64 --build-number=9104 --dart-define=API_BASE_URL=http://10.0.2.2:18083 --dart-define=QA_OTP_AUTOMATION=true
Package: local.grepmind.grepmind_mobile
APK Path: D:\grepmind-near\apps\mobile\build\app\outputs\flutter-apk\app-debug.apk
SHA-256: F62F40901F1AB7EAF6FAD5AA31AFE553D1C00934675FA2B4582B4D5A02665BBD
```

#### Dedicated Role Assignment Verification
| Role | Target AVD | Actual Serial | Verified AVD (`emu avd name`) | Installation Status |
|---|---|---|---|---|
| **Customer** | `Pixel_8` | `emulator-5554` | `Pixel_8` | **Success** (`Performing Streamed Install Success`) |
| **Merchant** | `Pixel_8_Merchant_QA` | `emulator-5556` | `Pixel_8_Merchant_QA` | **Success** (`Performing Streamed Install Success`) |
| **Rider** | `Pixel_8_Rider_QA` | `emulator-5558` | `Pixel_8_Rider_QA` | **Success** (`Performing Streamed Install Success`) |

*All 3 emulators received and verified the identical SHA-256 APK build.*

---

### 3. Photographic Evidence Matrix

All photographic artifacts are recorded in `docs/phases/evidence/abashyaka-03c/` and copied to conversation artifacts:

| Artifact | Reference Screen | Description | Status |
|---|---|---|---|
| `01_rider_dashboard_with_hubs_tab.png` | **Screen 8 & 19** | Rider Dashboard with clickable Hub quick metric and Bottom Bar Tab 3 (`Hubs`) | **PASS** |
| `02_rider_hubs_coverage_screen.png` | **Screen 19** | Service Locality Hubs screen with Central Hub card, active badge, and concentric distribution radar canvas | **PASS** |
| `03_rider_hubs_radius_toast.png` | **Screen 20** | Shift Delivery Radius adjusted to 8 km with floating confirmation toast | **PASS** |
| `04_rider_localities_directory.png` | **Screen 19** | Operational Locality Directory listing Kuanpal with `YOUR HUB` and `Approved` status | **PASS** |
| `05_rider_assignment_with_route_map_button.png` | **Screen 12 & 14** | Active delivery card (`GN-E57D8ECE`) displaying `Route Map` navigation button | **PASS** |
| `06_rider_delivery_route_map_screen.png` | **Screen 14 & 18** | Full-screen Route Map navigation with turn-by-turn guidance, route canvas, and destination sheet | **PASS** |

---

### 4. Automated Verification & Test Results

#### A. Static Analysis (`flutter analyze`)
- Analyzed:
  - `apps/mobile/lib/main.dart`
  - `apps/mobile/lib/core/screens/rider_workspace_screen.dart`
  - `apps/mobile/lib/core/screens/rider_map_screen.dart`
  - `apps/mobile/lib/core/screens/rider_locality_hubs_screen.dart`
- Result: **0 errors, 0 warnings, 0 infos** (`No issues found! ran in 6.1s`).

#### B. Full Rider Flutter Test Suite (`flutter test test/rider_*.dart`)
- **`rider_map_hubs_test.dart`**: PASS (2/2 tests: turn-by-turn guidance verification, destination sheet action, distribution radar, and shift radius presets).
- **`rider_dispatch_test.dart`**: PASS (7/7 tests: availability conflict, network retry, offer acceptance/decline, handover verification, and idempotent recovery).
- **`rider_application_test.dart`**: PASS (shows API-backed enabled localities and review checklist state).
- **`rider_cod_cash_test.dart`**: PASS (remittance submission closes safely and refreshes liability history).
- **`rider_earnings_test.dart`**: PASS (shows backend ledger amounts and clearly disables payouts).
- **Total**: **15/15 tests passed** in 8.0s.

#### C. Backend Go Unit & Integration Tests
- `backend/internal/riderearnings`: **PASS** (0.010s).
- `backend/internal/deliverydispatch`: **PASS** (0.010s).

---

### 5. Architectural & Privacy Compliance

1. **Locality-Bounded Dispatch**: All routing, offers, and hub visibility are bound strictly to administrative PostgreSQL delivery localities (`platform_delivery_localities`).
2. **Zero Unsolicited Geolocation**: No background GPS tracking or external telematics collection is activated. The visual route guidance is rendered in safe preview mode within approved administrative boundaries.
3. **Preserved Modular Monolith**: Maintained the Go modular monolith backend, PostgreSQL PostGIS database integrity, and standard Riverpod/Flutter navigation architecture.
