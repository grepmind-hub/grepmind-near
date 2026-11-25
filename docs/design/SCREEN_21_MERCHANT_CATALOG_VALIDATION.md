# Screen 21 Merchant Catalog Management

The approved Merchant account opened **Merchant Workspace → Catalog** on `Pixel_8_Merchant_QA` (`emulator-5556`). The installed development APK SHA-256 was `51819E45A100EE6A2D817CEF7217AE44A36B64791ACC401530E83228CE8AA93B`.

- Created an unpublished draft product with a ₹10 price and left MRP blank.
- Renamed the draft and changed its stock status from In Stock to Out of Stock.
- Fully restarted the app and reopened Catalog. The edited name, Draft badge and Out of Stock status persisted.
- Deleted the validation draft through the UI and confirmed the catalog returned to its initial empty state.

The card displayed a ₹13 MRP and 20% discount despite the blank MRP. It also displayed a quantity of 10 while the in-stock draft used untracked inventory. Both values come from the card's display calculations. Catalog source and live service records were unchanged during this validation.

Eight Flutter tests passed across `merchant_catalog_test.dart` and `merchant_catalog_inventory_phase02d_test.dart`. Live acceptance covered the Merchant product flow. Live service creation and editing were outside this check.

The next showcase screen is **Screen 22, Merchant Hours & Coverage Setup**.
