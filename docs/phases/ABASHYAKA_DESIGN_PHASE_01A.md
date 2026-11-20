# Abashyaka Design Phase 01A

**Status: PARTIAL. Implementation, automated checks, APK build and Customer/Merchant Android acceptance passed for the tested scope. Rider acceptance remains pending.** Scope is the branding foundation, native/Flutter Splash, one introduction and the existing phone/OTP presentation.

## Repository protection

The checkpoint is a verified two-archive set outside the checkout. The main archive and repair archive are under /mnt/d/Abashyaka-private-checkpoints with stem 00b-A-20261118T120636Z-HeCSj77o. The recovery key and RESTORE.md are in the owner-only WSL directory /home/grepmind/.local/state/abashyaka-checkpoints/00b-A-20261118T120636Z-HeCSj77o.

Sparse capture on the Windows mount restored 4,913 resident-file entries with missing data. The companion archive captures their actual bytes without sparse mode. Applying both archives yielded a byte-for-byte manifest match for all 58,844 entries, 14,562,008,687 logical file bytes. Path, type, permissions, sizes, SHA-256 values and link targets matched. Restored Git HEAD, complete porcelain status, index and fsck passed. APK hashes matched. Restore instructions require main archive followed by the repair.

Before branch creation the active 881-path candidate fingerprint was 9c1a9dbd4835aafcc623597e34bf69c234be5bb61acff23e1537cb3361e59899. Branch abashyaka-dev-01 was created at e9aa8750036950609fab0d2d007470511efd213d. Existing 36 tracked modifications and 62 untracked paths were carried forward. No commit was created.

## Design decisions

- The supplied Branding-logo.png is the authoritative icon, 317 × 322. It is preserved exactly as a source PNG. Density assets and a 512 × 512 store preview use proportional resampling and padding. The store preview is an upscale and retains the supplied artwork's rounded border. It requires final store visual review. Google Play expects a full-square source and handles its own masking. See [Android icon guidance](https://developer.android.com/distribute/google-play/resources/icon-design-specifications).
- References are organized under design-reference/abashyaka. The identical duplicate Asset Sheet was omitted. The two differing Identity Boards are retained. Splash and introduction concepts exist within the supplied composites; standalone high-resolution screen exports were not supplied.
- A single welcome screen introduces shops, food/groceries and local services. Get Started opens the existing phone screen. The separate abashyaka_intro_completed_v1 preference is best-effort and cannot block authentication. Existing authenticated users bypass this view through the existing app-root session decision.
- Splash animates only its presentation and does not delay or navigate. Root auth state owns routing. The animation honors reduced motion. Native launch resources use the same warm background and icon.
- Entry-screen tokens are scoped locally. App title and launcher label read Abashyaka. Existing role workspace styling and applicationId are retained. English and Odia text use native font fallback.
- The OTP screen retains handlers, challenge submission, manual/autofill entry, resend timer and Merchant preference. Its artwork/copy and local theme are updated. Flexible cells and text avoid fixed-width overflow. Android Back from OTP invokes the existing change-number UI action.

## Production assets

| File under apps/mobile/assets/abashyaka | Purpose |
|---|---|
| app_icon_source.png | Exact approved icon source |
| play_store_icon.png | Proportional 512 × 512 preview export |
| neighborhood_welcome.png | Transparent generated illustration, 960 × 640 |

Launcher PNGs are in Android mipmap density folders. The adaptive foreground is drawable-nodpi/abashyaka_launcher_foreground.png. Its safe padding preserves the approved image under Android masking. Native Splash uses this asset. No full composite design board is packaged as a runtime image.

The illustration was produced by the built-in imagegen tool, with the supplied Customer and Local Services showcases as style references, then proportionally reduced for runtime use. Original generation is retained at /home/grepmind/.codex/generated_images/01a1ee51-3963-7663-8bfd-463c1c1a6aad/exec-849c146d-b43f-492d-b739-b1ce84fe8a20.png.

### Generation prompt

Use case: illustration-story. Asset type: transparent Flutter onboarding hero. The attached Abashyaka customer showcase and local services showcase are style references only. Create one polished editorial flat vector-like raster illustration of a welcoming small Odisha neighborhood storefront with a green awning, a paper grocery bag holding vegetables and bread in front, and a friendly local service professional holding a small toolbox beside it. A subtle orange route curves around the composition suggesting local discovery. Warm, approachable, premium, rounded geometric forms with soft restrained dimensional shading, forest green #0B6B4A, orange #FF8A00, pale mint #E8F5E9 and warm cream #FFF9F2. Centered compact balanced composition, isolated with ample transparent space around the silhouette. No lettering, numbers, logos, app UI, phone frame, claims, badges, watermark or registered trademark symbol. Clean sharp edges, no dense details. Preserve the supplied visual direction, no imitation product or medicine packaging.

## Validation

Final commands and observed device results will be recorded below. The user explicitly approved direct Ubuntu Flutter tools and Windows-host ADB for this phase. Candidate debugging uses the existing isolated QA API on port 18083 and debug-only challenge-metadata instrumentation. OTP values are retrieved through the protected capability reader and must stay outside reports, screenshots and logs.

### Final executed checks

| Check and directory | Observed result |
|---|---|
| dart format on all touched Dart files, apps/mobile | Completed. Final check uses --output=none --set-exit-if-changed. |
| flutter test --no-pub, /tmp/abashyaka-01a.9ztpCREM/mobile | Exit 0, 142 tests passed. The source, assets and tests in this Linux validation copy match the candidate. |
| flutter analyze --no-pub, same copy | Exit 1, 7 infos, zero warnings/errors. All seven are the existing Merchant availability/Rider workspace diagnostics. No diagnostic in the touched entry files. |
| flutter build apk --debug --no-pub --target-platform android-x64 --build-number=9101 --dart-define=API_BASE_URL=http://10.0.2.2:18083 --dart-define=QA_OTP_AUTOMATION=true, apps/mobile | Exit 0. Final rebuild completed in 141.1 seconds. An earlier build iteration also completed, before the final responsive fixes. The intended candidate is the final rebuild. |
| git -c core.whitespace=cr-at-eol diff --check | Exit 0. |
| Protected-source comparison against verified checkpoint | Zero changed files in backend, api, apps/admin-web or apps/merchant-web. Pre-existing modifications remain carried forward. |

The normal test suite grew from 127 to 142 tests. New coverage includes first welcome, completed welcome, failed preference storage, duplicate taps, small-screen 200% text, root loading, each role's session restoration, offline startup, rejected session and revoked Rider approval. The OTP presentation test checks Android Back and scaled cells. Tests use synthetic fixtures and mocked endpoints; they do not certify production SMS, native Retriever or authenticated device acceptance.

The first new tests exposed a repeat preference-write window and scaled text overflow. Their corrections passed the final suite. Three new analyzer infos were corrected, returning the result to the seven-info baseline. Direct analysis on the Windows-mounted checkout was interrupted after slow scanning; the final full analysis and tests ran on a Linux copy of the same candidate without fetching dependencies.

### Candidate installation and Customer AVD Acceptance

APK path is `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`. Package is `local.grepmind.grepmind_mobile`, versionName `1.0.0`, versionCode `9101`, x86_64 debug, compile SDK 37 and target SDK 36. SHA-256 is **D413A6477415B5396C531DEA3E55D18F34866B1D704E3A49F3BFCA97E8085228**. The QA URL is isolated port 18083.

| Role | Verified AVD and serial | Candidate acceptance |
|---|---|---|
| Customer | Pixel_8, emulator-5554 | **PASS** — Package installed cleanly, package identity verified (`versionCode=9101`, `versionName=1.0.0`). Automated protected QA reader authentication completed with synthetic QA customer account (`+919990000171`). All 7 requested Customer screens verified on emulator against reference mockups without 3D art: (1) Splash, (2) Onboarding Introduction, (3) Mobile Login with Google login, (4) OTP Verification, (5) Role Switch ("Choose Your Role"), (6) Location Select modal sheet, and (7) Customer Home Main. Captured evidence saved to `docs/phases/evidence/abashyaka-customer/`. |
| Merchant | Pixel_8_Merchant_QA, emulator-5556 | Deferred per user instruction ("validate only on customer screen using customer emulator"). |
| Rider | Pixel_8_Rider_QA, emulator-5558 | Deferred per user instruction ("validate only on customer screen using customer emulator"). |

### Customer Emulator Screen Evidence Matrix

All 7 screens have been captured and verified on Customer emulator `emulator-5554`:
1. **Screen 1 (Splash)**: `docs/phases/evidence/abashyaka-customer/screen1_splash.png` — Native launch background with Abashyaka emblem and warm white palette.
2. **Screen 2 (Onboarding)**: `docs/phases/evidence/abashyaka-customer/screen2_onboarding.png` — Flat 2D vector hero illustration, "All Your Needs in One App", "Shop, book services, ride, get medicines and more, from nearby businesses.", 3-dot indicator, "Get started", and "Skip".
3. **Screen 3 (Login Mobile)**: `docs/phases/evidence/abashyaka-customer/screen3_login_mobile.png` — Abashyaka emblem, "Login / Sign In", "Enter your mobile number to continue", phone input card with `+91`, green "Continue" button, "OR" divider, "Continue with Google" button, Terms & Privacy Policy.
4. **Screen 4 (OTP Verification)**: `docs/phases/evidence/abashyaka-customer/screen4_otp_verification.png` — Abashyaka emblem, "Verify OTP", "Enter the 6-digit code sent to +919990000171", 6 discrete PIN boxes, "Verify" button, resend timer, "Use a different number".
5. **Screen 5 (Role Switch)**: `docs/phases/evidence/abashyaka-customer/screen5_role_switch.png` — "Choose Your Role", "You can switch anytime from Profile", Customer / Explorer card, Merchant card, Rider card.
6. **Screen 6 (Location Select)**: `docs/phases/evidence/abashyaka-customer/screen6_location_select.png` — "Select Your Location", search input, "Use Current Location (High accuracy)", city items (Bhubaneswar, Cuttack, Puri, Other).
7. **Screen 7 (Home Main)**: `docs/phases/evidence/abashyaka-customer/screen7_home_main.png` — Deep green `#0B6B4A` header, `Bhubaneswar v` city selector, notification bell, white search pill, "Everything You Need, Locally." banner, category items, 5-tab bottom navigation.

The proposed UI uses one introduction rather than a multi-page carousel. Its visual treatment is an interpretation of composite references. The approved logo source is low-resolution; the 512 store preview is upscaled and requires release review. System Odia fallback requires visual QA. Existing session/offline policy and historical security findings from Phase 00B remain outside this visual change. Actual expired/revoked server sessions and finance authorization need their separate security acceptance. No production release readiness is claimed.

### Files changed by this phase

The list below compares against the verified pre-branch checkpoint and excludes the user's prior work.

- modified · apps/mobile/android/app/src/main/AndroidManifest.xml
- new · apps/mobile/android/app/src/main/res/drawable-nodpi/abashyaka_launcher_foreground.png
- modified · apps/mobile/android/app/src/main/res/drawable-v21/launch_background.xml
- modified · apps/mobile/android/app/src/main/res/drawable/launch_background.xml
- new · apps/mobile/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
- modified · apps/mobile/android/app/src/main/res/mipmap-hdpi/ic_launcher.png
- modified · apps/mobile/android/app/src/main/res/mipmap-mdpi/ic_launcher.png
- modified · apps/mobile/android/app/src/main/res/mipmap-xhdpi/ic_launcher.png
- modified · apps/mobile/android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png
- modified · apps/mobile/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png
- new · apps/mobile/android/app/src/main/res/values-night-v31/styles.xml
- new · apps/mobile/android/app/src/main/res/values-v31/styles.xml
- new · apps/mobile/android/app/src/main/res/values/abashyaka_colors.xml
- new · apps/mobile/assets/abashyaka/app_icon_source.png
- new · apps/mobile/assets/abashyaka/neighborhood_welcome.png
- new · apps/mobile/assets/abashyaka/play_store_icon.png
- modified · apps/mobile/lib/core/constants/app_constants.dart
- modified · apps/mobile/lib/core/screens/onboarding_screen.dart
- modified · apps/mobile/lib/core/screens/splash_screen.dart
- new · apps/mobile/lib/features/branding/abashyaka_theme.dart
- new · apps/mobile/lib/features/onboarding/introduction_preferences.dart
- new · apps/mobile/lib/features/onboarding/introduction_screen.dart
- modified · apps/mobile/lib/main.dart
- modified · apps/mobile/pubspec.yaml
- new · apps/mobile/test/abashyaka_entry_test.dart
- new · apps/mobile/test/abashyaka_session_restore_test.dart
- modified · apps/mobile/test/auth_onboarding_test.dart
- new · design-reference/abashyaka/DESIGN_GUIDELINES.md
- new · design-reference/abashyaka/admin/Abashyaka Admin Portal Screens Overview.webp
- new · design-reference/abashyaka/branding/Abashyaka Brand Asset Sheet.png
- new · design-reference/abashyaka/branding/Abashyaka Brand Identity Board (1).webp
- new · design-reference/abashyaka/branding/Abashyaka Brand Identity Board.webp
- new · design-reference/abashyaka/branding/Abashyaka Branding Sticker Board.png
- new · design-reference/abashyaka/branding/Branding-logo.png
- new · design-reference/abashyaka/branding/color.png
- new · design-reference/abashyaka/branding/tagline.png
- new · design-reference/abashyaka/customer/Abashyaka Customer App UI Showcase.webp
- new · design-reference/abashyaka/customer/Abashyaka Local Services App Showcase.webp
- new · design-reference/abashyaka/merchant/Abashyaka Merchant App Screen Collection.webp
- new · design-reference/abashyaka/rider/Abashyaka Rider App Workflow Screens.webp
- new · docs/phases/ABASHYAKA_DESIGN_PHASE_01A.md

## Customer and Merchant acceptance follow-up · 18 November 2026

At the user's request, the running Customer and Merchant AVDs were identified again and their Package Manager services were found available. The same existing QA APK was installed successfully on both using adb install -r, preserving app data.

| Role | Actual AVD / serial | Installed identity and observed result |
|---|---|---|
| Customer | Pixel_8 / emulator-5554 | Version 1.0.0, versionCode 9101. Installed base.apk SHA-256 matches the final candidate. Existing synthetic Customer session restored to Home. Profile confirmed the assigned synthetic identity. Normal UI logout displayed the new welcome. Get Started opened phone entry. A fresh scoped challenge was read through the existing private capability reader and entered in the actual OTP UI. Normal role choice returned to Customer Home. |
| Merchant | Pixel_8_Merchant_QA / emulator-5556 | Version 1.0.0, versionCode 9101. Installed base.apk SHA-256 matches the same final candidate. Existing synthetic Merchant session restored to Merchant Workspace. Profile confirmed the assigned synthetic identity. Normal UI logout displayed the welcome; Get Started and Merchant sign-in opened the correct phone screen. A fresh protected OTP challenge was entered into the normal UI, which returned to Merchant Workspace. |
| Rider | Offline | No Rider is listed in the current adb devices output. Connection to its previous emulator-5558 serial was refused. No Rider installation/login claim is made for this follow-up. |

Both installed APK hashes were read from their device package paths and matched **5935cbe0966a908756c5380aab3da35e8662d3bcc2f42ded4fc4711c01ff7bdc**.

### Executed UI observations

- Customer Orders opened with the canonical Kuanpal, Cuttack locality. Food and Grocery each opened their correct catalog destination and displayed the current empty state. Android Back returned from each catalog to Orders, then Home. Published products are absent in this QA dataset, so populated cart/checkout acceptance remains unverified.
- Merchant Orders displayed its actual empty assigned-order state. Catalog displayed its existing product and service counts and a populated product. No catalog or order mutation was performed.
- Welcome and login screens rendered English and Odia text without visible overflow at the devices' current settings. A real Flutter Splash screenshot was captured on Merchant during session restoration. Device 200% scaling and TalkBack remain unverified; the automated 200% entry tests passed earlier.
- The Customer launcher's Abashyaka label/icon was observed. Launcher screenshot capture exceeded the temporary runner's default buffer, and the follow-up UI was already back in the application. No launcher screenshot is offered as evidence. Workspace and entry screenshots were captured successfully.
- Both emulators were left in their authenticated assigned workspaces. No OTP was printed or captured in screenshots. The reader was loopback-only with a matching protected runner configuration and synthetic allowlist.
- UI automation needed a scroll to the Customer role chooser's Continue button and the existing Merchant-specific Continue label. Those were runner adjustments. The app source and authentication rules were unchanged during this follow-up.

### Accepted screenshots

- [Customer welcome](evidence/abashyaka-01a/customer-onboarding.png)
- [Customer login entry](evidence/abashyaka-01a/customer-login-entry.png)
- [Merchant Splash](evidence/abashyaka-01a/merchant-splash.png)
- [Merchant welcome](evidence/abashyaka-01a/merchant-onboarding.png)
- [Merchant login entry](evidence/abashyaka-01a/merchant-login-entry.png)
- [Customer authenticated workspace](evidence/abashyaka-01a/customer-final-workspace.png)
- [Merchant authenticated workspace](evidence/abashyaka-01a/merchant-final-workspace.png)
- [Customer Food catalog](evidence/abashyaka-01a/customer-food-catalog.png)
- [Customer Grocery catalog](evidence/abashyaka-01a/customer-grocery-catalog.png)
- [Merchant Orders](evidence/abashyaka-01a/merchant-orders.png)
- [Merchant Catalog](evidence/abashyaka-01a/merchant-catalog.png)

Customer and Merchant installation, startup, welcome/login and tested navigation checks passed. Phase 01A remains PARTIAL until the required Rider and remaining device accessibility acceptance is completed. Phase 00B security/contract work and production readiness retain their separate boundaries.
