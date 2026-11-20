# ABASHYAKA — PHASE 02C: MERCHANT ORDERS & KITCHEN/FULFILLMENT PIPELINE REPORT

## Executive Summary

Phase 02C implements the **Orders Hub & Kitchen/Fulfillment Pipeline** for the Abashyaka Merchant mobile application, faithfully matching the design and layout specified in the authoritative showcase `design-reference/abashyaka/merchant/Abashyaka Merchant App Screen Collection.webp`:
- **Screen 9: Orders Hub & Pipeline**: Pipeline tabs (*All*, *New Orders*, *Preparing*, *Ready for Pickup*, *History*) with live badge counters, order type/delivery mode tags, customer contact & locality info, payment status badge (*UPI Verified*, *COD Pending*, *COD Collected*, *Unverified UPI*), stage transitions (*Accept*, *Reject* with reason, *Start preparation*, *Mark ready for pickup*).
- **Screen 10: Order Detail & Kitchen Ticket**: Bottom sheet modal showing reference code, items table, quantities, customizations, special kitchen instructions, and stage action.
- **Screen 11: Order Handover & Pickup Verification**: Presence verification prompt, single-use 8-character code issuance (`/merchant/businesses/{id}/delivery-jobs/{jobId}/pickup-code`), and live countdown timer dialog.

Validation was conducted under the **Mandatory Multi-Emulator Agent Validation Rule** using synthetic QA merchant identity `+919990000172` on designated Merchant emulator `Pixel_8_Merchant_QA` (`emulator-5556`).

---

## 1. Scope & Implementation Details

### Screen 9: Orders Hub & Pipeline (`apps/mobile/lib/core/screens/merchant_platform_orders_screen.dart`)
- **Scrollable Pipeline TabBar**: 5 filter states (*All*, *New Orders*, *Preparing*, *Ready for Pickup*, *History*) styled with Abashyaka Emerald underline indicator (`#0B6B4A`) and rounded count badges displaying exact counts per pipeline stage.
- **Store Status Header**: Emerald status container displaying total orders count, pending response count, and live store operating indicator.
- **Card Metadata & Tagging**:
  - Vertical-specific icon & badge (`Food order`, `Grocery order`).
  - Pipeline status pill (`Awaiting response`, `Preparing`, `Ready for pickup`, `Picked up`, `Completed`, `Cancelled`).
  - Delivery locality display (`Kuanpal, Cuttack`).
  - Payment verification badge: Explicit distinctions between `UPI Verified`, `Unverified UPI` (with clear acceptance gate), `COD Pending`, and `COD Collected`.
  - Item preview with count pills (`× 1`, `× 2`).
  - Customer special kitchen instructions box with note icon.
- **Stage Action Buttons**:
  - `New Orders`: Accept / Reject (with stage rejection reason selector).
  - `Preparing`: "Mark Ready for Pickup" CTA.
  - `Ready for Pickup`: "Issue Pickup Code" CTA.

### Screen 10: Order Detail & Kitchen Ticket Modal
- Modal bottom sheet displaying full item breakdown:
  - Header: `KITCHEN TICKET` with order reference and vertical tag.
  - Delivery destination locality.
  - Itemized quantity list with custom unit measures.
  - Highlighted "Special Notes & Cooking Instructions" alert card.
  - Emerald "Back to Orders" dismiss action.

### Screen 11: Order Handover & Pickup Code Verification
- Pickup code dialog displaying single-use 8-character verification token.
- Secure in-memory token generation with 10-minute live countdown timer (`_PickupCodeDialog`).
- Strict non-logging security rule: tokens are never persisted or printed to application logs.

---

## 2. Test Execution & Verification

### Automated Unit & Widget Tests
Executed via Flutter test runner:
- `apps/mobile/test/merchant_orders_pipeline_phase02c_test.dart` (2/2 PASS):
  - `Phase 02C: pipeline tabs filter orders and display badge counts`: PASSED
  - `Phase 02C: kitchen ticket bottom modal displays items and instructions`: PASSED
- `apps/mobile/test/merchant_platform_orders_test.dart` (6/6 PASS):
  - `renders platform orders tab`: PASSED
  - `renders empty state when no platform orders`: PASSED
  - `renders platform orders list with payment badge`: PASSED
  - `shows reject confirmation sheet when reject pressed`: PASSED
  - `shows issue pickup code button when ready for pickup`: PASSED
  - `shows payment not verified warning for pending UPI`: PASSED

### Static Analysis
```
flutter analyze lib/core/screens/merchant_platform_orders_screen.dart test/merchant_orders_pipeline_phase02c_test.dart
Analyzing 2 items...
No issues found! (ran in 5.1s)
```

---

## 3. Emulator Acceptance Evidence

- **AVD Verified**: `Pixel_8_Merchant_QA`
- **Serial**: `emulator-5556`
- **APK SHA-256**: `1514DEE770C1B41393B62E39B0F76178D2225F3346EAAA6499A9B156DE1C0BDC`
- **Role Identity**: Merchant `+919990000172` (Business: `Phase 3E QA Food Partner`, Locality: `Kuanpal, Cuttack`)
- **Captured Artifacts**:
  1. `docs/phases/evidence/abashyaka-02c/01_screen09_orders_pipeline.png`: Orders Hub showing All (3), New Orders (1), Preparing (1), Ready for Pickup (1) tabs with live counter badges and order cards.
  2. `docs/phases/evidence/abashyaka-02c/02_screen09_order_card_expanded.png`: Order card expanded showing COD payment status, kitchen ticket CTA, item preview, customer instructions (`Less spicy, extra raita please`), and Accept/Reject buttons with payment verification rule.
  3. `docs/phases/evidence/abashyaka-02c/03_screen10_kitchen_ticket_modal.png`: Kitchen ticket bottom sheet modal showing order items and special notes.

---

## 4. Architectural & Safety Compliance

1. **Payment Acceptance Gate**: Merchant UI strictly checks payment verification; unverified UPI orders cannot be accepted by the merchant until verified on the backend.
2. **Pickup Token Security**: 8-digit pickup token is strictly ephemeral and generated with an expiring countdown; no tokens are exposed via unauthenticated endpoints or persisted insecurely.
3. **Data Isolation**: All order queries are strictly scoped to the authenticated merchant's `business_id`.
