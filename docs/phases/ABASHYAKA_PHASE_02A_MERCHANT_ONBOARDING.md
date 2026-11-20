# ABASHYAKA — PHASE 02A & 02B MERCHANT ONBOARDING & DASHBOARD ACCEPTANCE REPORT

**Repository**: `D:\grepmind-near`  
**Branch**: `abashyaka-dev-01`  
**Phase Date**: 19 November 2026  
**Status**: **PASS (Isolated QA & Mobile Multi-Emulator Verified)**  

---

## 1. Executive Summary

Phase 02 Merchant Development implements the merchant experience for Abashyaka, directly referencing `design-reference/abashyaka/merchant/Abashyaka Merchant App Screen Collection.webp`.

### Key Deliverables Completed:
1. **Phase 02A — Merchant Onboarding & Business Setup**:
   - **Screen 2: Merchant Welcome**: Created `MerchantWelcomeScreen` featuring *"Grow Your Business with Abashyaka"*, branded storefront canopy artwork, 3 value propositions (*"Get more customers in your locality"*, *"Manage catalog, stock & orders easily"*, *"Increase your sales with zero hidden fees"*), and dual primary/secondary action buttons (*"Get Started"* and *"Already registered? Sign In"*).
   - **Screen 3: Merchant Login**: Modernized `OnboardingScreen` in merchant mode to feature *"Merchant Login"*, phone input in Abashyaka Emerald theme (`#0B6B4A`), *"Send OTP"* button, Google OAuth button, and *"Switch to Customer Login"* toggle.
   - **Screen 4: Verify OTP**: Implemented 6-cell PIN verification view in emerald branding with automatic focus progression and resend countdown timer.
   - **Screen 5 & 6: Business Details Wizard**: Aligned `MerchantRegistrationScreen` with 4-step enterprise classification, basic info, GPS location locking, and operations. Replaced legacy coral button accents with Abashyaka Emerald (`#0B6B4A`).
   - **Screen 7: Verification Under Review**: Implemented review status view featuring large checkmark badge, *"This usually takes up to 24 hours"* notice, live application reference ID badge, and *"Go to Dashboard"* navigation button.
2. **Phase 02B — Merchant Dashboard & Workspace Navigation**:
   - **Screen 8: Merchant Workspace Dashboard**: Implemented Screen 8 header and **Today's Summary** card in `MerchantWorkspaceScreen` featuring 4 core metrics:
     - **Orders**: Today's incoming order count
     - **Sales**: Today's recorded revenue (₹0 in QA)
     - **Bookings**: Today's active service bookings
     - **Fulfillment**: 98% fulfillment rate badge
     - **Store Open**: Real-time status pill
   - **Quick Actions**: Modernized quick-action grid (*"View Requests"*, *"Edit Profile"*, *"Manage Catalog"*, *"+ Add Item"*, *"Hours & Coverage"*, *"Service Radius"*, *"Earnings & Payouts"*, *"Bank Beneficiary"*).
   - **5-Tab Merchant Navigation**: Verified full tab switching across `Dashboard`, `Orders`, `Catalog`, `Earnings`, and `Profile`.
3. **Rigorous Multi-Emulator Acceptance**:
   - Dedicated Merchant QA Emulator: `Pixel_8_Merchant_QA` (`emulator-5556`)
   - Synthetic merchant identity: `+919990000172` (`Phase 3E QA Merchant` / `Cuttack Chandi Paints & Hardware`)
   - Unattended secure QA OTP entry: Validated using `scripts/qa/auth-otp-02-windows-ui.ps1` with zero log leaks or bypass tokens.
   - Dedicated Customer QA Emulator: `Pixel_8` (`emulator-5554`) checked for zero regression.

---

## 2. Evidence & Emulator Verification

| Artifact | File Reference | Verification Detail |
|---|---|---|
| **Merchant Welcome** | `docs/phases/evidence/abashyaka-02a/01_merchant_welcome.png` | Screen 2: Branded storefront canopy, 3 value propositions, "Get Started", "Already registered? Sign In". |
| **Merchant Login** | `docs/phases/evidence/abashyaka-02a/02_merchant_login.png` | Screen 3: "Merchant Login", "+91 Mobile number", emerald "Send OTP", "Switch to Customer Login". |
| **Onboarding Wizard** | `docs/phases/evidence/abashyaka-02a/03_merchant_onboarding_wizard.png` | Screen 6: 4-step wizard, enterprise classifications, emerald step indicators and "Save & Continue". |
| **Dashboard Today's Summary** | `docs/phases/evidence/abashyaka-02a/04_merchant_dashboard_today_summary.png` | Screen 8: "Today's Summary" (Orders, Sales, Bookings, Fulfillment 98%), "Store Open" pill, Welcome banner. |
| **Quick Actions** | `docs/phases/evidence/abashyaka-02a/05_merchant_quick_actions.png` | Screen 8: View Requests, Edit Profile, Manage Catalog, + Add Item, Hours & Coverage, Earnings & Payouts. |
| **Catalog Management** | `docs/phases/evidence/abashyaka-02a/06_merchant_catalog_tab.png` | Products / Services tabs, stock status chips, search input, empty state with "+ Add First Product". |
| **Earnings & Payouts** | `docs/phases/evidence/abashyaka-02a/07_merchant_earnings_tab.png` | Read-only finance banner, pending/net payable cards, simulated settlements, real payouts disabled. |
| **Partner Orders** | `docs/phases/evidence/abashyaka-02a/08_merchant_orders_tab.png` | Partner fulfillment hub, Abashyaka branding, live status filters. |
| **Merchant Profile** | `docs/phases/evidence/abashyaka-02a/09_merchant_profile_tab.png` | "Phase 3E QA Merchant", `+919990000172` (Verified), Account Status: Active. |
| **Customer Regression Check** | `docs/phases/evidence/abashyaka-02a/10_customer_emulator_regression_check.png` | `Pixel_8` (`emulator-5554`): Customer Home intact, Kuanpal delivery location, 8 category grid, zero regression. |

---

## 3. Test & Quality Summary

### Flutter Test Suite
```text
00:41 +150: All tests passed!
```
- **Total Tests**: 150 passed (0 failed, 0 skipped).
- **Phase 02A Dedicated Tests**: `test/merchant_onboarding_phase02a_test.dart` (4/4 passed).
- **Merchant Registration Tests**: `test/merchant_registration_test.dart` (5/5 passed).
- **Workspace Navigation Tests**: `test/workspace_navigation_test.dart` (passed).

### Go Backend Test Suite
```text
ok  	grepmind-near/backend/internal/auth	(cached)
ok  	grepmind-near/backend/internal/businessclaims	(cached)
ok  	grepmind-near/backend/internal/codcash	(cached)
ok  	grepmind-near/backend/internal/deliverydispatch	(cached)
ok  	grepmind-near/backend/internal/discovery	(cached)
ok  	grepmind-near/backend/internal/financialaccess	(cached)
ok  	grepmind-near/backend/internal/financialledger	(cached)
ok  	grepmind-near/backend/internal/merchantfinance	(cached)
ok  	grepmind-near/backend/internal/moderation	(cached)
ok  	grepmind-near/backend/internal/notifications	(cached)
ok  	grepmind-near/backend/internal/operations	(cached)
ok  	grepmind-near/backend/internal/payments	(cached)
ok  	grepmind-near/backend/internal/payouts	(cached)
ok  	grepmind-near/backend/internal/platformcatalog	(cached)
ok  	grepmind-near/backend/internal/platformcommerce	(cached)
ok  	grepmind-near/backend/internal/platformfulfillment	(cached)
ok  	grepmind-near/backend/internal/qafixtures	(cached)
ok  	grepmind-near/backend/internal/qaotpinbox	(cached)
ok  	grepmind-near/backend/internal/riderearnings	(cached)
```
- All backend tests passing.

### Static Analysis
- Zero errors, zero warnings across all newly authored/modified mobile files (`merchant_welcome_screen.dart`, `onboarding_screen.dart`, `merchant_registration_screen.dart`, `merchant_workspace_screen.dart`, `merchant_onboarding_phase02a_test.dart`).

### Debug APK Build
- **APK Path**: `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`
- **SHA-256**: `D648EA6FDCDD38CE798F309571ED7AB2D91E5CC5522944FE74DFF49005407618`
- **Package**: `local.grepmind.grepmind_mobile`

---

## 4. Invariants & Scope Integrity

1. **Financial Read-Only Boundaries Preserved**:
   - No real-money transaction or bank payout activation occurred.
   - Earnings screens display simulated settlements and read-only ledgers adhering to Phase 4D/5B.
2. **Multi-Emulator Discipline Maintained**:
   - Merchant operations validated on dedicated AVD `Pixel_8_Merchant_QA` (`emulator-5556`).
   - Customer operations validated on dedicated AVD `Pixel_8` (`emulator-5554`).
3. **Authentication Invariants Preserved**:
   - No hardcoded universal OTPs or bypass tokens used.
   - Verified via challenge-bound isolated QA inbox reader (`scripts/qa/auth-otp-02-windows-ui.ps1`).
4. **Branding Consistency**:
   - Replaced legacy text instances with Abashyaka.
   - Clean color palette adhering to `#0B6B4A` Emerald primary for merchants and `#FF8A00` Saffron accent.

---

## 5. Recommended Next Steps

- **Phase 02C: Merchant Orders & Kitchen/Fulfillment Pipeline** (Screens 9 to 11 of the Merchant showcase: New Orders, Active Prep, Ready for Pickup, Handover to Rider).
- **Phase 02D: Merchant Catalog & Product Inventory Management** (Screens 12 to 14 of the Merchant showcase: Add/Edit Product Modal, Photo Upload, Inventory Stock Steppers, Category Management).
