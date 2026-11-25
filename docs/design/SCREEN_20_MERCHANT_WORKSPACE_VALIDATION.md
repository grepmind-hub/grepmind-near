# Screen 20 Merchant Workspace Dashboard

- The dashboard uses the shared fluid-wave header, pearl-white cards, and the existing teal and Obsidian tokens. Quick actions use outlined white tiles with wrapping labels.
- The dashboard highlights request counts and customer views from the existing providers. The hardcoded sales estimate, fulfillment percentage, and store-open badge were removed.
- Existing tabs, quick-action destinations, refresh, permissions, and data handlers remain in place.

## Checks

- Dart formatting and targeted analysis passed with zero issues.
- All eight merchant workspace and role-selection widget tests passed. The suite verified the Requests shortcut, customer-view metrics, profile editing with a test double, role visibility, and the removal of unsupported dashboard indicators.
- The documented development debug build succeeded. ADB verified the installed `com.abashyaka.app.dev` APK on all three AVDs with SHA-256 `F00219597E1E7FA20D91C7B09D5C390C6A088CA81623A9547C6B858C40E01A25`.
- ADB mapped `Pixel_8` to `emulator-5554`, `Pixel_8_Merchant_QA` to `emulator-5556`, and `Pixel_8_Rider_QA` to `emulator-5558`. The Merchant and Rider serials differed from the expected assignments, so installation was verified by AVD name.
- Customer resumed its existing session and Rider reached onboarding. The Merchant AVD opened the normal sign-in screen. Authenticated dashboard validation remains **pending** until an authorized Merchant session is available on that AVD.

## Next screen

Proposed next polish pass is Screen 21, Merchant Catalog Management. Review product and service tabs, search, inventory labels, and mobile form layout while preserving catalog operations.
