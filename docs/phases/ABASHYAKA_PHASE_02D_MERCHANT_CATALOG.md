# ABASHYAKA — PHASE 02D: MERCHANT CATALOG & PRODUCT INVENTORY MANAGEMENT REPORT

## Executive Summary

Phase 02D implements **Merchant Catalog Management & Product Inventory Management** for the Abashyaka Merchant mobile application, faithfully matching the design and layout specified in the authoritative showcase `design-reference/abashyaka/merchant/Abashyaka Merchant App Screen Collection.webp`:
- **Screen 12: Catalog Management**: Products and Services segmented tabs with item counts, search input with clear button, filter chips (*All*, *In Stock*, *Limited*, *Out of Stock*, *Live*, *Draft*), product cards with selling price, crossed-out MRP, discount badge (`20% OFF`), and direct live/draft toggle.
- **Screen 13: Add / Edit Product Modal**: Product title, price, MRP, unit/weight chips (`1 kg`, `500 g`, `250 g`, `1 pc`, `Pack of 2`, `Custom`), stock status, inventory tracking mode, description, photo pickers (camera, gallery, sample photos sheet), and published switch.
- **Screen 14: Category & Inventory Stock Management**: Direct `-` and `+` quick stock steppers on product cards that update available quantity and stock status via debounced/asynchronous backend PATCH requests.

Validation was conducted under the **Mandatory Multi-Emulator Agent Validation Rule** using synthetic QA merchant identity `+919990000172` on designated Merchant emulator `Pixel_8_Merchant_QA` (`emulator-5556`).

---

## 1. Scope & Implementation Details

### Screen 12: Catalog Management (`apps/mobile/lib/core/screens/merchant_catalog_screen.dart`)
- **Segmented TabBar**: Products and Services tabs with emerald indicator and dynamic badges displaying the count of items in each category.
- **Search & Filter Controls**:
  - Search field with clear button.
  - Horizontal filter chip strip: *All*, *In Stock*, *Limited*, *Out of Stock*, *Live*, *Draft*.
- **Product Card Architecture**:
  - Image preview with fallbacks to high-resolution category photography (`category_sample_image.dart`).
  - Selling price in Abashyaka Emerald (`#0B6B4A`, bold font).
  - Crossed-out MRP (`TextDecoration.lineThrough`).
  - Automatic discount percentage pill (`20% OFF` in amber styling).
  - Stock status pill (*In Stock*, *Limited*, *Out of Stock*).
  - Quick action toolbar: Live/Draft visibility switch, Edit button, and Delete button.

### Screen 13: Add / Edit Product Modal
- Full bottom sheet modal featuring:
  - Form fields for Product Title, Selling Price (`₹ INR`), and MRP (`₹ INR`).
  - Pre-defined Unit / Measure selection chips: `1 kg`, `500 g`, `250 g`, `1 pc`, `Pack of 2`, `Custom`.
  - Stock status selector (*In Stock*, *Limited / Low Stock*, *Out of Stock*).
  - Inventory tracking mode (*Track quantity* vs *Do not track*).
  - Detailed product description input.
  - Photo selection sheet with Camera, Gallery, and Sample Photos picker.
  - "Publish immediately to live storefront" switch.
  - Emerald CTA button (`Add Product` / `Save Changes`).

### Screen 14: Category & Inventory Stock Management
- **Quick Stock Stepper**:
  - Interactive `[-] Qty: X [+]` stepper container on each product card.
  - Decrement `[-]` and Increment `[+]` buttons wrapped with `Material` and touch-target padding (min 48dp guideline compliant).
  - Immediate optimistic state update followed by backend persistence: `PATCH /api/v1/merchant/products/{id}`.
  - Automatic stock status adjustment: `qty == 0` transitions to `out_of_stock`, `qty <= 5` transitions to `limited`, `qty > 5` transitions to `in_stock`.

---

## 2. Test Execution & Verification

### Automated Unit & Widget Tests
Executed via Flutter test runner:
- `apps/mobile/test/merchant_catalog_inventory_phase02d_test.dart` (3/3 PASS):
  - `Phase 02D: Screen 12 catalog renders product cards with price, MRP and discount`: PASSED
  - `Phase 02D: Screen 14 quick stock steppers increment and decrement inventory`: PASSED
  - `Phase 02D: Screen 13 Add Product modal accepts MRP, unit chip, and price`: PASSED
- `apps/mobile/test/merchant_catalog_test.dart` (5/5 PASS):
  - `renders catalog management screen with tabs`: PASSED
  - `renders empty state when no products or services`: PASSED
  - `filters products by search query`: PASSED
  - `opens add product modal on fab tap`: PASSED
  - `deletes product on confirmation`: PASSED

### Static Analysis
```
flutter analyze lib/core/screens/merchant_catalog_screen.dart test/merchant_catalog_inventory_phase02d_test.dart
Analyzing 2 items...
No issues found! (ran in 5.1s)
```

---

## 3. Emulator Acceptance Evidence

- **AVD Verified**: `Pixel_8_Merchant_QA`
- **Serial**: `emulator-5556`
- **APK SHA-256**: `1514DEE770C1B41393B62E39B0F76178D2225F3346EAAA6499A9B156DE1C0BDC`
- **Role Identity**: Merchant `+919990000172` (Business: `Phase 3E QA Food Partner`)
- **Captured Artifacts**:
  1. `docs/phases/evidence/abashyaka-02d/01_screen12_catalog_products_listing.png`: Screen 12 showing Products (3), Services (0) segmented tabs, filter chips, and 3 product cards (`Asian Paints Apex 20L`, `Brass Padlock 65mm`, `Dr. Fixit Waterproofing 1L`) displaying selling price, crossed-out MRP, `20% OFF` discount badge, and `[-] Qty: X [+]` steppers.
  2. `docs/phases/evidence/abashyaka-02d/02_screen13_edit_product_modal.png`: Screen 13 Edit Product modal opened on `Brass Padlock 65mm` with pre-filled title, Price (`₹ 320`), MRP (`₹ 400`), Unit chip (`1 pc`), stock status, and quantity (`4`).
  3. `docs/phases/evidence/abashyaka-02d/03_screen13_add_product_modal.png`: Screen 13 Add Product modal with empty fields and unit measure chips.
  4. `docs/phases/evidence/abashyaka-02d/04_screen13_modal_scrolled.png`: Screen 13 scrolled showing description, photo options, publish switch, and emerald CTA.

---

## 4. Architectural & Safety Compliance

1. **MRP & Price Integrity**: MRP and selling price are stored as explicit integer paise/minor units on backend, preventing floating point inaccuracy.
2. **Backend Scoping**: Every product and service mutation is strictly verified against the authenticated user's ownership of `business_id`.
3. **No Legacy Mixing**: Catalog items are scoped strictly to the merchant's business entity without cross-merchant pollution.
