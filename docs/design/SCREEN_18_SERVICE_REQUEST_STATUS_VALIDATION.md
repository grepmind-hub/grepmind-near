# Screen 18 Service Request Status Tracker

Visual polish pass on 25 November 2026.

## Changes

- The tracker uses the shared fluid-wave header, pearl-white cards, and centralized teal and Obsidian tokens. The current status is announced as a live region and repeated as a highlighted timeline row.
- Declined and cancelled requests show their closing status. The timeline displays a submission time when the request supplies one. A proposed appointment is visible above the confirmation action.
- The receipt displays available request details. The UI no longer supplies a fixed arrival time, quote, or payment method. The professional card displays verification and rating from the supplied business record.
- The action bar and cancellation sheet adapt to narrow screens and large text. Existing polling, cancellation, reschedule confirmation, provider contact, and navigation handlers remain in use.

## Checks

- Dart formatting and targeted analysis passed for the changed screen and test file. Analysis reported zero issues.
- The tracker, booking scheduler, app entry, onboarding, and role-selection suites passed all 26 tests. The seven tracker tests include 320 dp at 200% text, dismissal of the cancellation sheet, the existing cancellation POST and its failure behavior, the reschedule control, and four-second polling through a terminal update.
- Flutter widget renders at 390 × 844 were compared with the [premium screen references](reference/premium_five_screens.webp) and [role-selection reference](reference/Abashyaka%20Choose%20Your%20Role%20Screen.png). The renders use synthetic request data and are saved locally under `apps/mobile/build/screen18-ui/`.
- The documented development debug build succeeded. Android package `com.abashyaka.app.dev` reports version `1.0.0`, build `1`. APK SHA-256 is `76F58D8CAA4266A11FE21DA885BBF5E480AFB01B754B3B383FC5D84896C9C02A`.

## Android acceptance

ADB verified the same installed APK hash on all three assigned emulators.

| Role | AVD and serial | Observed startup |
| --- | --- | --- |
| Customer | `Pixel_8`, `emulator-5554` | Existing session resumed to the Customer workspace. |
| Merchant | `Pixel_8_Merchant_QA`, `emulator-5558` | Onboarding opened. |
| Rider | `Pixel_8_Rider_QA`, `emulator-5556` | Onboarding opened with the Android notification prompt. |

Live tracker acceptance is **partial**. Its two app entry points follow a successful service-request submission. This pass used the existing app environment and exercised the tracker through widget tests with stubbed responses. Live request creation, cancellation, and authenticated Merchant and Rider acceptance remain unverified.

## Next screen

Proposed next polish pass is Screen 19, Merchant Registration / Claim. Review step labels, field grouping, and small-screen layout while preserving the existing registration, claim, and verification flows.
