# Screen 23 Merchant Order Details & Fulfillment

Tap an assigned order in **Merchant Workspace → Orders** to expand its details. The screen uses the Abashyaka V2.0 Pearl White canvas, white order cards, teal controls and shared status colours. It shows the available location, payment information, item quantities, kitchen instructions and recorded status events. The current Merchant Orders API does not send the fulfillment type, so the detail heading omits that label unless the API supplies it. The kitchen ticket scrolls for longer orders, and order status badges can wrap at narrow widths.

Existing order actions, payment eligibility, backend authorization, dispatch polling and short-lived pickup-code handling are retained. Opening the screen or expanding an order does not trigger a fulfillment action.

Targeted Dart analysis reported zero issues. All eight tests in `merchant_platform_orders_test.dart` and `merchant_orders_pipeline_phase02c_test.dart` passed. The suites cover the details timeline, kitchen ticket, payment gate and pickup-code behavior.

The documented development APK built successfully. SHA-256 `3FD9D6FBA3F7D0C4B5A402C8E73D6750851696D1E78914211809542E0718B051` matched on Customer `Pixel_8` (`emulator-5554`), Merchant `Pixel_8_Merchant_QA` (`emulator-5556`), and Rider `Pixel_8_Rider_QA` (`emulator-5558`). Merchant opened the updated Orders tab. Before-and-after screenshots show the pipeline and its empty state. Rider reached onboarding. Full authenticated role acceptance remains partial.

Live order-detail acceptance is **PARTIAL**. The Merchant session had zero assigned orders and displayed the handover-status warning. A live order-detail check requires an assigned test order. No orders or payments were created during this check.
