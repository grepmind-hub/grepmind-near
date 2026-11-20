# ABASHYAKA PHASE 01F.1 — DOCTOR, TRANSPORT AND DATA-INTEGRITY REGRESSION CORRECTIONS

**Phase:** Abashyaka Phase 01F.1  
**Date:** 19 November 2026  
**Repository:** `D:\grepmind-near`  
**Branch:** `abashyaka-dev-01`  
**Status:** PASS (Isolated QA / Emulator Verification)  
**APK Build Target:** `build/app/outputs/flutter-apk/app-debug.apk`  
**APK SHA-256:** `708fd9205537e4da1fce5430200a9f19bab8f6b3f49c8c14cbb9e12e90b3279b`  
**Validated Device:** `emulator-5554` (AVD: `Pixel_8`, Customer QA)  
**Evidence Directory:** `docs/phases/evidence/abashyaka-01f1/`  

---

## 1. Executive Summary

Phase 01F.1 successfully remediates the critical data integrity regressions, fictional doctor profile claims, misleading transport bookings, and unauthorized database mutation identified in the post-01F review. All corrections strictly comply with the **three mandatory safeguards** approved for this phase.

Every finding was addressed across the backend database, Flutter client screens, automated test suites, and emulator runtime acceptance:
1. **Fictional Doctor Claims Removed**: `Dr. Visiting Consultant`, fake qualifications (`Qualification · Specialty · Registration details`), unsupported `Verified` doctor badge, and fake `Booking` buttons were completely excised from `DoctorDirectoryScreen`.
2. **Transport Integrity Enforced**: The `Concept` pill badge, vehicle filter chips (`Auto`, `Cab`, `Taxi`, `Local Trips`), fabricated fare claims, and `Book` CTA were removed from `LocalTransportScreen`. Keyword-based string filtering (`garage`, `repair`) was eliminated in favor of an explicit passenger-transport classification requirement; because no explicit passenger transport records currently exist in the database, the screen truthfully displays an honest empty state.
3. **Controlled Barabati Diagnostics Remediation**: Preconditions were confirmed, 0 intervening audit logs were verified, full JSON snapshots were captured before and after remediation, and `ce666666-6666-6666-6666-666666666666` was restored to its historical pending baseline (`status = 'pending'`, `verification_status = 'pending'`, `phone_e164 = NULL`). No fabricated admin audit log was created.
4. **Grocery Scope Preserved**: `PlatformCatalogScreen(vertical: 'grocery')` and its cart/order isolation remain intact without initiating Phase 2 grocery migration.
5. **Full Test Suite & Emulator Verification**: 146/146 Flutter tests passed (including 4 new regression tests in `test/doctor_transport_integrity_test.dart`), all Go backend tests passed (`go test ./internal/...`), and debug APK `708fd92...` was installed and visually verified on `Pixel_8` (`emulator-5554`).

---

## 2. Compliance with the Three Mandatory Safeguards

### Safeguard 1: Controlled Database Restoration of Barabati Diagnostics
- **Target Entity**: `Barabati Diagnostics & Health Clinic` (`id: ce666666-6666-6666-6666-666666666666`).
- **Pre-execution Verification**:
  - Script: `scripts/remediate_barabati.py`
  - Checked `audit_logs` for `target_id = 'ce666666-6666-6666-6666-666666666666'`: confirmed **0** rows. The prior mutation was executed via direct raw SQL without an admin session.
  - Verified business was in the reported mutated state: `status = 'approved'`, `verification_status = 'verified'`, `phone_e164 = '+916712345678'`.
- **Pre-remediation Snapshot**: Preserved in `scripts/barabati_pre_remediation_snapshot.json`.
- **Controlled Restoration**:
  ```sql
  UPDATE businesses
  SET status = 'pending',
      verification_status = 'pending',
      phone_e164 = NULL,
      updated_at = NOW()
  WHERE id = 'ce666666-6666-6666-6666-666666666666';
  ```
- **Post-remediation Verification**:
  - Preserved in `scripts/barabati_post_remediation_snapshot.json`.
  - Non-synthetic approved medical business count in PostgreSQL: **0**.
  - `status = 'pending'`, `verification_status = 'pending'`, `phone_e164 = null`.
  - No fake audit log was injected.

### Safeguard 2: Transport Operator Classification Integrity
- **Flawed Prior Approach**: Filtered `/businesses?category_slug=automotive` using substring keyword exclusions (`!name.contains('garage') && !name.contains('repair') ...`), allowing non-garage automotive workshops to masquerade as taxi drivers.
- **Remediation**:
  - Eliminated keyword string matching.
  - Requires an explicit verified classification: `b.categorySlug == 'passenger_transport'`.
  - Since the backend database currently categorizes all automotive businesses as `automotive` and has no verified passenger transport fleet, the screen cleanly renders an honest empty state:
    > *"No local transport operators listed yet. Passenger transport operators and direct driver booking are not yet active in [locality], [city]. Verified auto-rickshaw and taxi listings will appear as drivers join."*
  - Excised the misleading `Concept` badge from the `AppBar`.
  - Excised filter chips (`Auto`, `Cab`, `Taxi`, `Local Trips`).
  - Excised the fake `Book` button and booking sheet.
  - Excised fabricated fare claims (`"Local fare: Verified local rate..."`).

### Safeguard 3: Separation of Facility Verification from Doctor Availability
- **Flawed Prior Approach**: Rendered an illustrative card with `Dr. Visiting Consultant`, fake specialties, inferred consultation availability from facility operating hours, and rendered a `Verified` badge on the doctor card even though only the clinic was verified.
- **Remediation**:
  - Completely removed the fictional doctor profile and illustrative disclaimers.
  - Displays genuine facility records only (`_MedicalFacilityCard`).
  - Distinguishes facility verification (`Facility Verified`) from doctor credentials (no doctor credentials claimed).
  - Operating hours reflect the facility only (`Facility open now` / `Facility closed`), never inferred doctor consultation hours.
  - Contact button: Only displays `Call Clinic` if `phoneE164` is non-null and non-empty. If phone is missing, displays `'Contact phone not listed'` with disabled call action.
  - Excised `Booking` action and bottom sheet.
  - Displays truthful empty state when no approved medical facilities exist in the city:
    > *"No clinics or medical facilities listed yet. Registered clinics and healthcare centres near [locality] will appear here as they join."*
  - Informative banner:
    > *"Doctor consultation schedules are not available in this area yet. Contact registered clinics directly for specialist visiting hours."*

---

## 3. Implementation Details & File Manifest

| File | Status | Description |
|---|---|---|
| `apps/mobile/lib/core/screens/doctor_directory_screen.dart` | Modified | Truthful facility directory, honest notice banner, genuine facility card, call button only when phone exists, zero fictional doctor cards, zero booking actions. |
| `apps/mobile/lib/core/screens/local_transport_screen.dart` | Modified | Honest empty state, removed `Concept` badge, removed filter chips, removed fake fare claims, removed booking actions, no naive keyword filtering. |
| `apps/mobile/lib/core/screens/home_screen.dart` | Modified | Category tile updated from 'Doctors' to 'Clinics'; updated subtitles for Healthcare (`Find registered clinics and healthcare centres`) and Transport (`Registered auto-rickshaw and taxi directory`). |
| `apps/mobile/test/doctor_transport_integrity_test.dart` | Created | 4 comprehensive regression tests verifying doctor integrity, transport integrity, empty states, and truthful home subtitles. |
| `scripts/remediate_barabati.py` | Created | Controlled database remediation script verifying preconditions, zero audit logs, taking pre/post JSON snapshots, and restoring Barabati Diagnostics to pending. |
| `scripts/barabati_pre_remediation_snapshot.json` | Created | Snapshot of Barabati Diagnostics prior to restoration. |
| `scripts/barabati_post_remediation_snapshot.json` | Created | Snapshot of Barabati Diagnostics after restoration. |

---

## 4. Test Verification & Results

### A. New Regression Test Suite
Command: `flutter test test/doctor_transport_integrity_test.dart`
```
00:00 +0: loading test/doctor_transport_integrity_test.dart
00:00 +1: Doctor & Medical Facility Integrity Tests DoctorDirectoryScreen renders truthful empty state when no facilities exist
00:00 +2: Doctor & Medical Facility Integrity Tests DoctorDirectoryScreen displays genuine facility data and separates facility verification from doctor claims
00:00 +3: Local Transport Integrity Tests LocalTransportScreen excludes repair garages and renders honest empty state
00:01 +4: Home Screen Truthful Subtitles & Category Labels HomeScreen displays truthful category label and truthful subtitles
00:01 +4: All tests passed!
```

### B. Full Flutter Test Suite
Command: `flutter test`
- Total Tests: **146 passed / 0 failed** (100% PASS, up from 142 in Phase 01F).
- Zero regressions across customer cart, onboarding, role selection, order dispatch, saved screen, and platform catalog tests.

### C. Static Analysis
Command: `flutter analyze`
- Total Issues: **7 infos** in historical files (`merchant_availability_screen.dart`, `rider_workspace_screen.dart`).
- Zero errors, zero warnings.
- Zero issues in `doctor_directory_screen.dart`, `local_transport_screen.dart`, `home_screen.dart`, or `doctor_transport_integrity_test.dart`.

### D. Backend Tests
Command: `go test ./internal/...`
- All packages passed cleanly:
  - `auth`: PASS
  - `businessclaims`: PASS
  - `codcash`: PASS
  - `deliverydispatch`: PASS
  - `discovery`: PASS
  - `financialaccess`: PASS
  - `financialledger`: PASS
  - `merchantfinance`: PASS
  - `moderation`: PASS
  - `notifications`: PASS
  - `operations`: PASS
  - `payments`: PASS
  - `payouts`: PASS
  - `platformcatalog`: PASS
  - `platformcommerce`: PASS
  - `platformfulfillment`: PASS
  - `qafixtures`: PASS
  - `qaotpinbox`: PASS
  - `riderearnings`: PASS

---

## 5. Mobile Emulator Runtime Evidence

- **Emulator Serial**: `emulator-5554`
- **AVD**: `Pixel_8` (Customer QA)
- **Installed Package**: `local.grepmind.grepmind_mobile`
- **APK SHA-256**: `708fd9205537e4da1fce5430200a9f19bab8f6b3f49c8c14cbb9e12e90b3279b`

### Visual Evidence

| Screen | Evidence Image | Verified Truthful Behavior |
|---|---|---|
| **Home (Top)** | `docs/phases/evidence/abashyaka-01f1/phase01f1_home.png` | Category grid features **Clinics** tile; light-first theme; zero legacy Grepmind strings. |
| **Home (Sections)** | `docs/phases/evidence/abashyaka-01f1/phase01f1_home_sections.png` | Healthcare subtitle: *"Find registered clinics and healthcare centres"*; Transport subtitle: *"Registered auto-rickshaw and taxi directory"*. |
| **Clinics & Medical Facilities** | `docs/phases/evidence/abashyaka-01f1/phase01f1_clinics.png` | Honest empty state (*"No clinics or medical facilities listed yet"*); truthful notice banner (*"Doctor consultation schedules are not available in this area yet..."*); zero fictional doctor cards. |
| **Local Cab & Auto** | `docs/phases/evidence/abashyaka-01f1/phase01f1_transport.png` | Honest empty state (*"No local transport operators listed yet"*); truthful notice banner (*"Transport operator listings and direct booking will appear as verified drivers join."*); zero `Concept` badge; zero fake chips; zero fake booking. |

---

## 6. Precondition & Postcondition Verification Table

| Item | Pre-01F.1 Mutated / Regressed State | Phase 01F.1 Corrected State | Verification Method |
|---|---|---|---|
| **Barabati Diagnostics** | `status = 'approved'`, `verification_status = 'verified'`, `phone_e164 = '+916712345678'` | `status = 'pending'`, `verification_status = 'pending'`, `phone_e164 = null` | PostgreSQL inspection & snapshot json files |
| **Doctor Profile Card** | Fictional `Dr. Visiting Consultant` with placeholder credentials | Completely removed; shows genuine facility records or honest empty state | Widget tests & Emulator screenshot |
| **Doctor Availability** | Inferred from facility operating hours | Separated; facility open/closed only reflects facility, notice clarifies no doctor schedules exist | Widget tests & UI inspection |
| **Doctor Booking CTA** | Fictional `Booking` button opening booking sheet | Removed completely; facility cards only offer `Call Clinic` if phone is listed | Widget tests & UI inspection |
| **Transport Filter Chips** | Fictional chips (`Auto`, `Cab`, `Taxi`, `Local Trips`) matching strings | Removed completely | Widget tests & Emulator screenshot |
| **Transport Garages** | Keyword string matching attempted to exclude garages | Enforced explicit `categorySlug == 'passenger_transport'`, rendering honest empty state | Widget tests & Emulator screenshot |
| **Transport Fares** | `"Local fare: Verified local rate..."` | Removed completely | Widget tests & UI inspection |
| **Transport Booking CTA** | Fictional `Book` button opening driver booking sheet | Removed completely | Widget tests & UI inspection |
| **Home Subtitles** | Claimed to see doctors/schedules and transport fares/booking | Truthful directory subtitles for clinics and local operators | Widget tests & Emulator screenshot |
| **Grocery Scope** | Standard platform catalog grocery | Preserved without commerce migration | Code inspection & regression test |

---

## 7. Conclusion & Next Steps

Phase 01F.1 has eliminated all regressions and established complete data-integrity and truthfulness across Customer healthcare, transport, and discovery screens.

With Phase 01F.1 verified and passing on the emulator, the repository on `abashyaka-dev-01` is cleanly prepared for **Phase 02 Merchant Development**.
