# Abashyaka V2.0 on mobile screens 17–22

Abashyaka V2.0 is the visual standard on the existing Flutter Material 3 foundation. Shared brand, surface, typography, semantic and role colours live in `AbashyakaColors`. The affected screens resolve their former inline hex colours through the shared palette. The service tracker already used shared tokens and inherits the revised values. Existing wave assets, shared headers and compact functional app bars remain in their respective screen layouts.

Measured WCAG contrast ratios for the specified foreground and background pairs include primary text on Pearl White at 14.10:1, secondary text on Pure White at 8.14:1, and the status pairs between 4.63:1 and 6.47:1. White labels on the three metallic button stops measure 4.95:1, 8.68:1 and 11.67:1. The specified placeholder colour gives 4.40:1 on white, so Material input hints use the darker V2.0 Muted Text token.

All 33 Flutter tests across Profile, Service Request Status, Merchant Registration, Merchant Workspace, Merchant Catalog, and Hours & Coverage passed. Targeted analysis found only two redundant-argument informational diagnostics. The approved development debug APK built successfully with SHA-256 `D43F0CA8F1E1AA87E554AC1831C2BB6BBF76C4800570ACF54CBB3AC13F4D3322`.

The installed APK hash matched on Customer `Pixel_8` (`emulator-5554`), Merchant `Pixel_8_Merchant_QA` (`emulator-5556`), and Rider `Pixel_8_Rider_QA` (`emulator-5558`). Merchant reached the signed-in workspace. Local before-and-after captures cover the Dashboard, Catalog and product form, and Hours & Coverage. Rider reached onboarding.

| Screen | Status | Evidence outstanding |
|---|---|---|
| 17 Customer Profile | PARTIAL | Live paired Profile screenshots |
| 18 Service Request Status | PARTIAL | Paired live tracker screenshots with an authorized request |
| 19 Merchant Registration | PARTIAL | Paired live registration screenshots and keyboard checks |
| 20 Merchant Dashboard | PARTIAL | Profile-mode performance measurement |
| 21 Merchant Catalog | PARTIAL | Paired keyboard checks and profile-mode scrolling measurement |
| 22 Hours & Coverage | PARTIAL | Live save-and-reopen on the intended merchant and profile-mode scrolling measurement |

Full authenticated role acceptance and profile-mode performance measurements remain outstanding.
