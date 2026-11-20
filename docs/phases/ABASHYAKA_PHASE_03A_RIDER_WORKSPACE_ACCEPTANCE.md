# ABASHYAKA — PHASE 03A ACCEPTANCE REPORT
## Rider Welcome, Brand Polish & Modern Dashboard Acceptance

**Repository**: `D:\grepmind-near`  
**Branch**: `abashyaka-dev-01`  
**Date**: 19 November 2026  
**Status**: **PASS (Isolated QA Verified & 3-Emulator Validated)**  
**Authoritative UI Kit Reference**: `design-reference/abashyaka/rider/Abashyaka Rider App Workflow Screens.webp` (Screens 1, 2, 8, 9)

---

### 1. Executive Summary

Phase 03A initiates the comprehensive modernization of the Abashyaka Rider experience, directly adhering to the 24-screen authoritative showcase in `design-reference/abashyaka/rider/Abashyaka Rider App Workflow Screens.webp`.

In this phase, legacy branding was eradicated across the rider codebase and replaced with official **Abashyaka Rider** identity (emerald green `#064D3A` / `#0B6B4A`, deep forest tones, and clean card hierarchy). The primary rider dashboard was restructured to deliver:
- **Screen 8 (Offline State)**: Rider avatar, greeting (`Hello, Phase 3E QA Rider`), short ID pill (`ID: 0DC71C8B`), live `OFFLINE` status badge, prominent `Go Online` call to action, and summary metrics (`Today: ₹0`, `Orders: 0`).
- **Screen 9 (Online State)**: Real-time transition to `ONLINE`, green pulse indicator, active shift status (`Receiving nearby orders...`), prominent `Go Offline` action, dynamic earnings and order stats (`Today: ₹680`, `Orders: 6`), vehicle specifications (`Vehicle: two wheeler`), status (`Verified`), and operating hub (`Odisha`).
- **Full Brand Eradication**: Replaced all remaining legacy Grepmind strings, partner email addresses (`rider.partner@abashyaka.near`), and verification badges (`Verified Abashyaka Partner`, `UPI · verified by Abashyaka`).

---

### 2. Multi-Emulator QA Fleet Mapping & APK Identity

The debug APK candidate was built under WSL with the isolated QA environment definitions and verified across all three assigned emulators:

```
Build Command: flutter build apk --debug --no-pub --target-platform android-x64 --build-number=9101 --dart-define=API_BASE_URL=http://10.0.2.2:18083 --dart-define=QA_OTP_AUTOMATION=true
Package: local.grepmind.grepmind_mobile
APK Path: D:\grepmind-near\apps\mobile\build\app\outputs\flutter-apk\app-debug.apk
SHA-256: A20B979BA84BFA9A6054C8E33A9A969A0B34904EE477F9B78220EF55CE65FCBE
```

#### Dedicated Role Assignment Verification
| Role | Target AVD | Actual Serial | Verified AVD (`emu avd name`) | Installation Status |
|---|---|---|---|---|
| **Customer** | `Pixel_8` | `emulator-5554` | `Pixel_8` | **Success** (`Performing Streamed Install Success`) |
| **Merchant** | `Pixel_8_Merchant_QA` | `emulator-5556` | `Pixel_8_Merchant_QA` | **Success** (`Performing Streamed Install Success`) |
| **Rider** | `Pixel_8_Rider_QA` | `emulator-5558` | `Pixel_8_Rider_QA` | **Success** (`Performing Streamed Install Success`) |

*All 3 emulators received and verified the identical SHA-256 APK build.*

---

### 3. Authenticated Rider Journey & Verification

- **Identity Tested**: Synthetic QA Rider `+919990000173` (`Phase 3E QA Rider`, User ID `3e000000-0000-4000-8000-000000000003`).
- **Reverse Route**: Configured loopback routing `adb -s emulator-5558 reverse tcp:18083 tcp:18083` to target isolated QA API.
- **Session Verification**: Verified authenticated session with approved `two_wheeler` profile and locality binding (`Kuanpal, Cuttack`).
- **State Transition Execution**:
  1. App loaded in **Offline Dashboard** state (`01_rider_dashboard_offline.png`).
  2. Tapped **`Go Online`** button at `[98,795][982,921]`.
  3. Server received status update and created active availability lease.
  4. UI immediately transitioned to **Online Dashboard** state (`02_rider_dashboard_online.png`).
  5. Verified metrics updated to active counters (`₹680` today, `6` orders).
  6. Verified secondary tabs: **Deliveries** (`03_rider_deliveries.png`), **Earnings** (`04_rider_earnings.png`), and **Profile** (`05_rider_profile.png`).

---

### 4. Photographic Evidence Matrix

All evidence artifacts are recorded in `docs/phases/evidence/abashyaka-03a/`:

| Artifact | Authoritative Reference | Description | Status |
|---|---|---|---|
| `01_rider_dashboard_offline.png` | **Screen 8** (Rider Dashboard Offline) | Emerald green header, offline badge, `Go Online` button, ₹0 stats | **PASS** |
| `02_rider_dashboard_online.png` | **Screen 9** (Rider Dashboard Online) | Active online badge, `Go Offline` button, ₹680 stats, 6 orders | **PASS** |
| `03_rider_deliveries.png` | **Screen 10 & 14** (Orders/Deliveries) | Delivery pipeline with active/completed delivery tabs | **PASS** |
| `04_rider_earnings.png` | **Screen 17** (Rider Earnings) | Daily earnings breakdown, ledger breakdown, payouts disabled notice | **PASS** |
| `05_rider_profile.png` | **Screen 21** (Rider Profile & KYC) | Profile details, vehicle info, verified partner status | **PASS** |

---

### 5. Automated Verification & Test Results

#### A. Static Analysis (`flutter analyze`)
- Total issues in application: **2 infos** (both pre-existing in `merchant_availability_screen.dart`).
- Diagnostics in `rider_workspace_screen.dart`: **0 errors, 0 warnings, 0 infos** (100% clean).
- Baseline prior to phase: 18 diagnostics; reduced to 2 infos overall.

#### B. Full Rider Flutter Test Suite (`flutter test test/rider_*.dart`)
- **`rider_application_test.dart`**: PASS (shows API-backed enabled localities and review checklist state).
- **`rider_cod_cash_test.dart`**: PASS (remittance submission closes safely and refreshes liability history).
- **`rider_earnings_test.dart`**: PASS (shows backend ledger amounts and clearly disables payouts).
- **`rider_dispatch_test.dart`**: PASS (7/7 tests pass including availability conflict, network retry, offer acceptance/decline, handover verification, and idempotent recovery).
- **Total**: **13/13 tests passed** in 6.0s.

#### C. Backend Go Unit & Integration Tests
- `backend/internal/riderearnings`: **PASS** (0.014s).
- `backend/internal/deliverydispatch`: **PASS** (0.012s).

---

### 6. Security & Architectural Compliance

1. **Brand Identity**: Complete transition to Abashyaka Rider theme (`#064D3A` emerald dark app bar, `#0F766E` accents, `#10B981` online pill, `#64748B` offline pill).
2. **Privacy & Tracking**: Confirmed truthful note displayed: *"Dispatch availability is controlled by approved service localities. No GPS is collected."* No unsolicited device GPS tracking is initiated.
3. **No Payout Activation**: Rider earnings display remains strictly read-only and backed by the verified financial ledger. Live payout or real money withdrawal buttons remain firmly disabled.
4. **Isolated QA Database**: All testing occurred against isolated disposable QA containers (`grepmind_3e_qa_db` on port 55432 and `grepmind_4c_qa_api` on port 18083). Zero changes were made to shared development or production databases.

---

### 7. Recommended Next Phase

With Phase 03A fully validated, the foundation is ready for **Abashyaka Phase 03B: Order Dispatch, Pickup & Delivery Handover**:
- **Screen 10 & 11**: Real-time Incoming Order Offer Modal (Timer, earnings, pickup/drop distance, Accept / Decline actions).
- **Screen 12 & 13**: Navigation to Store & Pickup Handover (Merchant contact, items checklist, OTP verification).
- **Screen 15 & 16**: Transit to Customer & Handover Confirmation (Customer OTP verification, COD payment collection if applicable, delivered state).
