# Screen 21 Merchant Catalog Management

The approved Merchant account opened **Merchant Workspace → Catalog** on `Pixel_8_Merchant_QA` (`emulator-5556`). The installed development APK SHA-256 was `51819E45A100EE6A2D817CEF7217AE44A36B64791ACC401530E83228CE8AA93B`.

- Created an unpublished draft product with a ₹10 price and left MRP blank.
- Renamed the draft and changed its stock status from In Stock to Out of Stock.
- Fully restarted the app and reopened Catalog. The edited name, Draft badge and Out of Stock status persisted.
- Deleted the validation draft through the UI and confirmed the catalog returned to its initial empty state.

The card displayed a ₹13 MRP and 20% discount despite the blank MRP. It also displayed a quantity of 10 while the in-stock draft used untracked inventory. Both values come from the card's display calculations. Catalog source and live service records were unchanged during this validation.

Eight Flutter tests passed across `merchant_catalog_test.dart` and `merchant_catalog_inventory_phase02d_test.dart`. Live acceptance covered the Merchant product flow. Live service creation and editing were outside this check.

The next showcase screen is **Screen 22, Merchant Hours & Coverage Setup**.

## Selling units and optional GST

Add Product now suggests selling units based on the merchant's shop category. A custom unit supports pack sizes and legacy labels. The product editor saves the selected label and entered MRP through the existing catalog API. Cards show a discount only when a saved MRP exceeds the price. Quantity controls display for tracked inventory with a recorded count.

GST is optional. The merchant chooses an offered rate or enters a custom percentage. The form shows the estimated GST and total, rounded to paise. This is a merchant catalog estimate. Checkout uses its existing price and tax rules. Migration 050 adds the nullable per-product rate. The app shows a preview and prevents saving a GST rate while the live API lacks that capability.

The Add Product action uses a teal pill with a smaller label and consistent padding. The Merchant dashboard uses the supplied `login_background.webp` edge to edge behind its content.

Ten Flutter catalog and workspace tests passed. An isolated PostGIS test verified saved unit, MRP, GST and price, rejection of an invalid rate, clearing optional values, and a finite stock update. On 26 November 2026, migration 050 was applied to the WSL deployment and the catalog API replacement passed its container and public health checks.

Debug APK SHA-256 `BECBE7F473A24A5CEB1F889E659DAEB57C3B598758A7E2A8AF1AD7E7909779B1` matched on Customer `Pixel_8` (`emulator-5554`), Merchant `Pixel_8_Merchant_QA` (`emulator-5556`), and Rider `Pixel_8_Rider_QA` (`emulator-5558`). Customer reached Explore, Merchant opened the updated product form, and Rider reached onboarding. Full authenticated acceptance across all roles remains partial.
