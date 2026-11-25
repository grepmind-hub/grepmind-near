# Screen 17 Customer Profile & Settings

Visual polish pass completed on 25 November 2026.

## Presentation

- The Customer identity card sits on the approved role-selection wave artwork and shared `AbashyakaPremiumHeader`. The screen uses Pearl White, Signature Teal, Premium Obsidian, and Graphite Charcoal from the mobile theme. Dark Android status icons remain legible on the light canvas.
- Glossy `PremiumCard` surfaces group Personal Details, Account & Portals, and Security & Preferences. Phone and role labels wrap on narrow screens. The profile photo and edit controls have at least 48 dp touch targets.
- The existing profile edit, photo picker, copy account ID, saved businesses, addresses, order history, portal switching, privacy, notification settings, and sign-out actions use their existing handlers. Sign-in and profile data handling remain on the existing app paths.

## Checks

- `dart format` and targeted `dart analyze` passed for the screen and its test file. Analysis reported zero issues.
- `flutter test --no-pub test/profile_screen_test.dart test/abashyaka_entry_test.dart test/auth_onboarding_test.dart test/role_selection_test.dart` passed all 23 tests, including all seven profile tests. The profile suite checks a 360 dp viewport at 200% text scaling, the compact account ID, and the photo, saved businesses, edit, security, and notification entry points.
- The development debug build specified in [AGENTS.md](../../AGENTS.md#mandatory-apk-installation) succeeded. The APK is `com.abashyaka.app.dev` version `1.0.0` (build `1`). Final SHA-256 is `CE9F2593D32B1BD4081AC87278A16114C46DDA6FC67B2CE2A358705F18AAA12B`.
- ADB verified the installed APK hash on Customer `Pixel_8` (`emulator-5554`), Merchant `Pixel_8_Merchant_QA` (`emulator-5558`), and Rider `Pixel_8_Rider_QA` (`emulator-5556`).

## Android screen checks

- The existing Customer session resumed on the updated APK after selecting **Wait** at Android's startup prompt. On Screen 17, the fluid wave, white cards, typography, and grouping were compared with the [premium screen references](reference/premium_five_screens.webp) and [role-selection reference](reference/Abashyaka%20Choose%20Your%20Role%20Screen.png).
- The camera control opened the gallery and camera choices. Edit Profile opened and was cancelled. Saved businesses opened Saved Places. Sign-in & security opened the OTP explanation. Notification Settings opened the existing preferences screen. The checks used the existing session and left the account fields and settings intact.
- Merchant and Rider reached onboarding and the Android notification permission prompt. Authenticated Merchant and Rider checks are pending, so overall role acceptance is **partial**. This pass covered Screen 17 and the installed Android build.
- The final APK opened Screen 17 in the existing Customer session. The `customer-final.png` capture confirmed dark Android status icons against the pearl-white background. Captures are in the local ignored `apps/mobile/build/screen17-ui/emulator-5554/` folder.

## Next screen

Proposed next polish pass is Screen 18, Service Request Status Tracker. Start with its current timeline, status hierarchy, and responsive layout. Keep the existing status polling, cancellation, and navigation behavior.
