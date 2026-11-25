# ABASHYAKA — PREMIUM UI VISUAL CORRECTION V2.0

## Role

Act as a senior Flutter UI architect, premium mobile UI designer, 3D visual asset specialist, Android startup engineer and performance optimization specialist.

## Objective

Correct the existing Abashyaka Flutter implementation to closely match the approved six-screen visual reference.

The required design language is:

**Metallic Teal Abstract Fluid Wave + Pearl White Glossy UI**

The current implementation has basic teal colours and layouts but does not adequately reproduce the approved metallic, glossy and premium visual quality.

Do not mark visual acceptance as PASS merely because the screens are functional.

## 1. Mandatory reference files

Read:

- Existing AGENTS.md
- docs/design/ABASHYAKA_UI_DESIGN_SYSTEM.md
- docs/design/reference/premium_six_screens.png
- docs/design/reference/current_implementation_comparison.png
- docs/design/reference/current_native_splash.png

Inspect all existing Flutter screens, assets, theme definitions and native Android splash configuration.

Compare the approved reference and actual emulator implementation screen by screen.

## 2. Existing functionality protection

Preserve all working functionality, including:

- Phone OTP authentication.
- OTP verification and resend.
- Google Sign-In.
- FCM notifications.
- Trusted-session restoration.
- Secure token storage.
- Riverpod providers.
- Dio API integration.
- Backend API contracts.
- Location selection.
- Business discovery.
- Category capability engine.
- Customer, Merchant and Rider mode switching.
- Existing navigation routes.
- Food and grocery ordering.

Do not modify backend architecture merely to implement visual changes.

Do not remove working features because they are absent from the generated reference image.

## 3. Correct the native Android splash

Identify the cream-background screen with the orange-and-teal Abashyaka logo that currently appears immediately after tapping the launcher icon.

Determine whether it is controlled by flutter_native_splash, Android launch themes, Android 12 splash configuration or another startup mechanism.

Replace its cream background with Deep Metallic Teal #00545B.

Use the approved white or light-aqua variant of the official Abashyaka logo.

Ensure the logo is correctly centered and sized within Android's supported splash icon area.

Inspect Android 12+ configuration, older Android launch backgrounds and post-splash theme transitions.

Prevent white flashes and unwanted background changes.

Preserve the existing launcher icon unless a separate approved launcher-icon change is requested.

Do not attempt to implement an unsupported full-screen metallic artwork inside the Android system splash.

The native splash must transition seamlessly into the premium Flutter splash.

## 4. Correct application startup sequence

Required logical sequence:

Android Native Splash → Flutter Premium Splash → Session and Onboarding Check → Correct Destination.

First-time users:

Opening / Brand Introduction → Get Started → Login → OTP Verification or Google Sign-In → Appropriate Home or Onboarding Destination.

Returning authenticated users:

Flutter Premium Splash → Restore Trusted Session → Appropriate Home or Workspace.

Unauthenticated returning users:

Flutter Premium Splash → Login.

Preserve existing location and permission route guards.

Do not introduce artificial delays or duplicate splash routes.

## 5. Correct the official logo

The approved visual concept uses a shopping-bag and location-pin logo.

The actual application uses an A-shaped Abashyaka logo.

Preserve the official existing logo geometry rather than silently changing the brand identity.

Prepare or obtain the following consistent variants:

- Original full-colour logo.
- Premium metallic teal logo.
- White monochrome logo.
- Light aqua logo.
- Compact logo.
- Logo and wordmark combination.
- Android-native-splash-compatible logo.

Reuse vector source assets when available.

Do not use screenshots cropped from the visual reference as production logo assets.

Do not introduce distortion, rectangular backgrounds, inconsistent proportions or excessive empty padding.

## 6. Asset generation phase

Before modifying screen layouts, audit the existing assets.

Identify assets that are missing, low quality, incorrectly cropped, inconsistent or unsuitable.

Generate new original decorative assets using an available image-generation capability where possible.

If the coding agent cannot generate images directly, prepare exact image-generation prompts and an asset manifest. Report asset generation as BLOCKED until the required artwork is provided.

Do not claim that images have been generated without actual files.

Required assets:

- premium_light_wave.webp
- premium_dark_wave.webp
- auth_wave_top.webp
- auth_wave_bottom.webp
- home_header_wave.webp
- odisha_heritage_3d.webp
- onboarding_local_3d.webp
- otp_security_3d.webp
- shopping_bags_3d.webp
- Consistent 3D category icon set
- Approved logo variants

All generated decorative backgrounds must contain no text, no buttons, no fake status bars, no phone frames and no embedded UI controls.

Individual illustrations should have actual transparent backgrounds where required.

Inspect image quality and alpha channels before integration.

Store assets in organized branding, backgrounds, illustrations and category-icon directories.

Optimize WebP compression and decode sizes while preserving metallic lighting and image quality.

## 7. Visual rendering architecture

Use a hybrid implementation.

Complex photorealistic metallic wave artwork may use optimized static background images.

Simple reusable waves, gradients, highlights and buttons should use native Flutter rendering.

Use:

- CustomPainter for scalable abstract fluid curves.
- LinearGradient for metallic transitions.
- RadialGradient for soft glossy illumination.
- ClipRRect for polished rounded edges.
- Stack for layered composition.
- Positioned for decorative artwork.
- RepaintBoundary selectively where profiling supports its benefit.
- LayoutBuilder for responsive sizing.
- SafeArea for interactive foreground content.

Do not implement expensive real-time liquid glass effects.

Avoid unnecessary BackdropFilter, continuous animations and repeated offscreen rendering.

Never use a full generated screen image as the interactive application interface.

## 8. Colour system

Preserve centralized approved design tokens:

- Dark Ocean Teal: #003F46
- Deep Metallic Teal: #00545B
- Metallic Teal: #008C95
- Bright Teal: #00B3AE
- Aqua Glow: #55D6CD
- Light Aqua: #B8EFEB
- Pure White: #FFFFFF
- Pearl White: #F3F7F8
- Luminous White: #FAFDFE
- Ice Aqua White: #EAF7F7
- Silver Glass: #DCE8E8
- Ink Black: #102A33
- Secondary Text: #607680

Use Pearl White as the main screen surface.

Use Pure White for input fields, cards, Google Sign-In button and floating navigation.

Use light aqua gradients and metallic wave highlights to create visual depth.

Do not substitute unrelated pastel category backgrounds or introduce inconsistent brand colours.

## 9. Opening screen corrections

Current problems:

- Flat solid-colour waves.
- Small logo and wordmark.
- Flat landmark illustration.
- Excessive empty space.
- Insufficient glossy lighting.

Required:

- Luminous pearl-white background.
- Sculpted metallic teal upper and lower waves.
- Large approved metallic logo.
- Prominent Abashyaka wordmark.
- Realistic Odisha architectural heritage illustration near the bottom.
- Smooth natural artwork blending.
- Existing approved regional text, arranged without compromising the visual hierarchy.
- No unnecessary loading or navigation controls.

## 10. Flutter Splash corrections

Replace flat dark backgrounds with a rich metallic teal composition.

Require:

- Deep ocean teal base.
- Dark-to-light metallic gradients.
- Broad sculpted curved wave layers.
- Luminous aqua edge reflections.
- Soft radial highlights.
- Large approved white logo.
- Prominent white Abashyaka wordmark.
- Three lightweight loading dots or equivalent actual loading state.

Avoid unrelated controls and artificial delays.

Ensure consistent transition from native splash.

## 11. Get Started corrections

Require:

- Pearl White background.
- Glossy upper abstract wave artwork.
- Transparent realistic 3D onboarding illustration.
- Larger hero artwork.
- Bold Ink Black heading.
- Readable supporting text.
- Rounded white Skip control.
- Teal pagination indicators.
- Full-width metallic teal Get Started button.
- Appropriate vertical spacing.

Avoid showing rectangular image backgrounds around the hero artwork.

Preserve onboarding completion and existing accessibility preferences.

## 12. Login corrections

Remove the large enclosing rectangular form-card treatment where it conflicts with the approved design.

Require:

- Full-screen luminous Pearl White auth background.
- Premium metallic wave header.
- Subtle bottom aqua waves.
- Large standalone metallic logo.
- Abashyaka wordmark.
- Login to Continue title.
- Full-width floating Pure White mobile-number pill input.
- Glossy metallic Send OTP button.
- Clean divider.
- Pure White rounded Google Sign-In button.
- Official Google brand icon.
- Rounded outline security indicators.
- Existing legal links and merchant sign-in option.

Preserve working authentication and existing validation.

Ensure keyboard-safe responsive layout.

## 13. OTP Input corrections

Reuse the premium auth background from Login.

Require:

- Back navigation.
- Approved metallic logo and wordmark.
- Verify OTP heading.
- Existing destination phone number, masked where appropriate.
- OTP input count matching the existing backend contract.
- Individually rounded glossy OTP boxes.
- Metallic teal focus border.
- Pure White default input surface.
- Ice Aqua completed state where appropriate.
- Accessible invalid-code and expiry states.
- Server-compatible resend countdown.
- Verify & Continue metallic button.
- Change-number action.
- Realistic 3D teal shield, checkmark and golden padlock artwork.
- Bottom metallic wave composition.

Preserve paste, autofill and existing OTP functionality where supported.

Do not introduce automatic submission without understanding existing behavior.

Capture screenshots with both keyboard visible and keyboard hidden.

When the keyboard appears, prioritize form usability. Reduce or hide decorative artwork as required.

## 14. Home screen corrections

Required visual hierarchy:

1. Integrated premium header.
2. Prominent Abashyaka logo and wordmark.
3. Location selector and notifications.
4. Floating rounded search field.
5. Metallic promotional banner.
6. Compact 3D category grid.
7. Nearby actual business listings.
8. Floating rounded bottom navigation.

Replace flat category symbols with realistic, consistently lit 3D icons.

Use Pure White category cards with subtle shadows and refined borders.

Retain actual category identifiers, routes and capabilities.

Do not fabricate categories, businesses, ratings or distances.

Move the promotional banner above the category grid as shown in the approved visual reference.

Use glossy teal gradient artwork and transparent 3D shopping bags.

Keep headings, subtitles and CTA buttons as Flutter widgets.

Replace the conventional rectangular bottom bar with a floating rounded Pure White navigation surface.

Maintain the actual existing destination architecture.

Keep Saved Items accessible through the previously approved Profile arrangement.

Preserve all existing functional Home sections even if some must be positioned below the initial viewport.

## 15. Typography and component verification

Use approved Plus Jakarta Sans typography where configured.

Maintain the appropriate Odia font fallback.

Inspect actual typography sizes against the reference.

Increase logo prominence, title weights and readability where the current implementation is visually undersized.

Maintain consistent spacing, rounded borders, gradient buttons and soft shadows.

Use minimum 48 logical pixel touch targets.

Do not shrink text merely to fit a reference screenshot.

## 16. Implementation stages

Phase V0 — Repository, asset and startup audit.

Phase V1 — Generate or obtain correct visual assets and logo variants.

Phase V2 — Correct native Android splash and Flutter startup behavior.

Phase V3 — Correct shared metallic wave backgrounds and premium components.

Phase V4 — Correct Opening and Flutter Splash.

Phase V5 — Correct Get Started.

Phase V6 — Correct Login and OTP Input.

Phase V7 — Correct Home, category assets and floating navigation.

Phase V8 — Visual comparison, accessibility, regression and performance verification.

Complete each stage with evidence.

## 17. Visual acceptance requirements

Capture actual emulator screenshots for:

- Android Native Splash.
- Opening.
- Flutter Splash.
- Get Started.
- Login.
- OTP with keyboard closed.
- OTP with keyboard visible.
- Home.

Use the same emulator dimensions for visual comparisons.

Crop decorative phone frames and normalize reference viewport sizes before comparing.

Review:

- Colour appearance.
- Metallic wave depth.
- Gradient quality.
- Logo size and consistency.
- Illustration quality.
- Element positioning.
- Typography.
- White surface separation.
- Card dimensions.
- Button appearance.
- Navigation appearance.

Create a side-by-side comparison report.

Do not use an arbitrary percentage as proof of exact visual matching.

Document remaining intentional differences, including official logo and functional navigation differences.

Do not report visual PASS until the implemented screens have been reviewed against the approved reference.

## 18. Performance acceptance

Measure profile-mode performance before and after the correction.

Report cold and warm startup latency, frame timings, jank, asset size changes and memory behavior.

Target smooth 60 FPS on the selected reference device.

Avoid substantial startup and scrolling regressions.

Run Flutter analyzer and relevant tests.

Verify authentication, OTP, Google Sign-In, notifications, onboarding, location, search, category navigation and existing role switching.

Report only actual measured results.

## 19. Final deliverables

Provide:

- Repository audit.
- Native splash configuration changes.
- Asset-generation and optimization report.
- Approved logo variants.
- Modified file inventory.
- Updated shared UI components.
- Actual emulator screenshots.
- Side-by-side visual comparison.
- Analyzer and regression results.
- Performance comparison.
- Remaining blockers and differences.
- Final PASS, PARTIAL or BLOCKED assessment.

Save all approved design corrections and asset specifications inside docs/design.

Start with Phase V0 and do not proceed blindly without inspecting the existing implementation.