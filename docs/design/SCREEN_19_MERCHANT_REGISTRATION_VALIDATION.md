# Screen 19 Merchant Registration / Claim

Visual polish pass on 25 November 2026.

- The register and claim switcher uses the shared fluid-wave header, Pearl White surfaces, and centralized teal and Obsidian tokens. Both modes have wrapping labels and 48 dp minimum touch targets.
- The registration wizard shows the active step title, step count, and progress on a shared glossy card. Its primary action and the listing review action reuse the metallic button. The wizard footer respects Android navigation insets.
- Registration, lookup, review submission, and verification continue through the existing handlers.

## Checks

- Dart formatting and targeted analysis passed. Analysis reported zero issues.
- All 16 widget tests passed across merchant registration, merchant onboarding, and profile. They cover wizard progression, switching between modes, category search, and the existing claim submission path with stubbed responses.
- The documented development APK build succeeded. The installed `com.abashyaka.app.dev` APK matched SHA-256 `C07410320191F49EE582D1B6932444784FF4783A9BE69BB143C6DA8550C49FD4` on Customer `Pixel_8` (`emulator-5554`), Merchant `Pixel_8_Merchant_QA` (`emulator-5558`), and Rider `Pixel_8_Rider_QA` (`emulator-5556`).
- Merchant reached onboarding and Rider reached the notification-permission prompt. Authenticated role acceptance remains partial.
- On the assigned Customer emulator, the existing session opened Screen 19 from Profile. Register New and Claim Existing both opened, and Save & Continue advanced to Step 2. The two mode captures were compared with the approved premium references and kept locally under `apps/mobile/build/screen19-ui/emulator-5554/`. Live application and claim submission remain unverified.

## Next screen

Proposed next polish pass is Screen 20, Merchant Workspace Dashboard. Review dashboard hierarchy, card readability, and small-screen layout while preserving existing business controls and permissions.
