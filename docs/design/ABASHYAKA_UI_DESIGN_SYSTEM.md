# ABASHYAKA — PREMIUM FLUTTER UI DESIGN SYSTEM V1.0

## Role

Act as a senior Flutter UI/UX architect, mobile application engineer, motion designer and performance optimization specialist.

You are working on the EXISTING Abashyaka mobile application, an Odisha-first local business discovery, services, food and grocery delivery platform.

Implement a production-ready premium UI that closely matches the supplied five-screen reference image.

## 1. Primary objective

Implement the following official design language:

**Metallic Teal Abstract Fluid Wave + Pearl White Glossy UI**

The application must look premium, luminous, polished, modern and distinctive while remaining lightweight and responsive on budget and mid-range Android devices.

Do not implement an expensive real-time liquid glass rendering engine.

Simulate glossy surfaces through native Flutter gradients, static abstract fluid waves, subtle translucent layers, polished borders, optimized illustrations and soft shadows.

## 2. Existing application protection

Before writing code:

- Audit the existing Flutter repository.
- Identify current screens, routes, providers, themes, authentication logic, assets and reusable widgets.
- Record baseline analyzer diagnostics and test results.
- Preserve all working features.
- Preserve Phone OTP authentication.
- Preserve Google Sign-In.
- Preserve FCM notifications.
- Preserve JWT and trusted-session behavior.
- Preserve Riverpod state management.
- Preserve Dio API integration.
- Preserve backend authorization.
- Preserve Customer, Merchant and Rider role switching.
- Do not change Go backend contracts merely to support UI changes.
- Do not fabricate API data.
- Do not implement duplicate routes or screens.
- Do not reset existing user data.
- Do not introduce unrelated packages or dependencies.

The current task is primarily a presentation-layer redesign.

## 3. Reference image

Use the supplied premium five-screen image as the primary visual reference.

Reproduce its visual hierarchy, metallic teal wave artwork, pearl white surfaces, polished buttons, typography, 3D illustrations, card design and floating controls as closely as reasonably possible.

Maintain responsive layouts rather than hard-coding screenshot coordinates.

Treat reference-image sample data as illustrative only.

Use the approved Abashyaka brand logo. If the reference logo or required illustrations are unavailable as approved assets, identify the asset gap rather than silently introducing a new official brand identity.

## 4. Official colour tokens

Create a centralized colour system with the following exact values.

Brand colours:

- darkOceanTeal: #003F46
- deepMetallicTeal: #00545B
- metallicTeal: #008C95
- brightTeal: #00B3AE
- aquaGlow: #55D6CD
- lightAqua: #B8EFEB

White and neutral colours:

- pureWhite: #FFFFFF
- pearlWhite: #F3F7F8
- luminousWhite: #FAFDFE
- iceAquaWhite: #EAF7F7
- silverGlass: #DCE8E8
- softGrey: #E8EFF1
- inkBlack: #102A33
- secondaryText: #607680

Functional colours:

- success: #16A34A
- error: #DC3545
- warning: #F59E0B
- information: #2563EB
- ratingStar: #FFB020
- favourite: #EF476F

Do not scatter hard-coded colour values throughout feature screens.

## 5. White surface rules

Use Pearl White as the main Scaffold background.

Use Pure White for:

- Content cards
- Category cards
- Search bars
- Input fields
- Modal sheets
- Dialogs
- Floating bottom navigation
- Secondary buttons
- Nearby business cards

Use Luminous White for glossy surface highlights.

Use Ice Aqua White for subtle header transitions and selected surfaces.

Use Silver Glass for delicate borders and dividers.

Target an approximate overall composition of 45% Pearl White, 35% Pure White, 15% Metallic Teal and 5% decorative highlights.

This is a visual guideline, not a rigid requirement for every screen.

## 6. Premium abstract fluid-wave background

Create a reusable FluidWavePainter using CustomPainter.

Requirements:

- Use normalized coordinates based on canvas width and height.
- Draw smooth overlapping cubic and quadratic Bézier curves.
- Use two to four decorative wave layers.
- Use translucent layers with controlled opacity.
- Add subtle white or aqua highlights along selected wave edges.
- Avoid heavy blur.
- Avoid animated gradients by default.
- Avoid real-time reflection calculations.
- Keep the background visually consistent across screen sizes.
- Implement shouldRepaint based on actual configuration changes.
- Ensure decorative painting does not interfere with accessibility or gestures.

Use the following Flutter technologies:

- CustomPainter for abstract curved shapes.
- LinearGradient for metallic colour transitions.
- RadialGradient for soft glossy lighting.
- ClipRRect for polished rounded edges.
- RepaintBoundary when it provides measurable repaint isolation benefits.
- Stack for background, text, logo and 3D illustrations.
- Positioned for decorative artwork placement.
- LayoutBuilder for responsive dimensions.
- SafeArea for foreground content positioning.
- BoxDecoration for standard surfaces, borders and shadows.

Create configurable variants:

- brandLight
- brandDark
- onboarding
- auth
- discovery
- compact
- commerce
- promotional
- tracking
- profile
- merchant
- rider

Create reusable AbashyakaPremiumHeader and PremiumBackground components.

## 7. Typography

Use locally bundled Plus Jakarta Sans where practical.

Provide appropriate Odia script fallback.

Use:

- Brand wordmark: 36–40 logical px, weight 800.
- Display heading: 28–32 logical px, weight 800.
- Page title: 24 logical px, weight 700.
- Section title: 20 logical px, weight 700.
- Card title: 16 logical px, weight 600.
- Body text: 14–16 logical px.
- Supporting text: 12–14 logical px.
- Category labels: 11–12 logical px, weight 600.
- Button text: 16 logical px, weight 700.

Support Android text scaling.

Do not prevent accessibility scaling merely to match the design image.

## 8. Spacing and shape tokens

Create reusable spacing tokens: 4, 8, 12, 16, 24 and 32 logical pixels.

Create radius tokens: 8, 12, 16, 20, 24, 28 and 30 logical pixels.

Default screen horizontal padding: 16 logical pixels.

Use 16–18 px radius for category cards.

Use 20–24 px radius for banners and larger cards.

Use 26–28 px radius for search fields and primary buttons.

Use 26–30 px radius for floating navigation.

Maintain a minimum interactive touch target of 48 × 48 logical pixels.

## 9. Premium button design

Create reusable MetallicButton, PremiumSecondaryButton and PremiumOutlineButton components.

MetallicButton gradient:

- Top: #00B3AE
- Middle: #008C95
- Bottom: #00545B
- Gradient stops: 0.0, 0.45, 1.0
- Direction: top center to bottom center

Primary button height: 54–56 logical pixels.

Radius: 28 logical pixels.

Text: Pure White, 16 px, weight 700.

Include subtle top-edge lighting and low-opacity shadow.

Support loading, disabled, pressed and error-related states.

Prevent duplicate submissions during asynchronous operations.

Secondary buttons use Pure White surfaces, Silver Glass borders and Ink Black or Deep Teal content.

## 10. Screen 01 — Opening screen

Implement a premium brand introduction matching the supplied reference.

Background:

- Pearl White transitioning to Pure White.
- Metallic teal abstract waves at the top.
- Dark metallic teal abstract waves at the bottom.
- Subtle RadialGradient lighting.

Center:

- Approved Abashyaka logo, 104–120 logical pixels.
- Abashyaka wordmark, 36–40 logical pixels, weight 800.
- Deep Metallic Teal wordmark colour.
- Tagline: Local Shops • Services • Food • Grocery.
- Ink Black tagline colour.

Lower section:

- Optimized Odisha-inspired landmark illustration.
- Approximate illustration height: 160–200 logical pixels.
- Blend the illustration naturally with the lower fluid waves.

No unnecessary buttons.

Use a short fade if appropriate.

Do not introduce a mandatory artificial loading delay.

Opening screen may be limited to first-launch branding based on existing navigation behavior.

## 11. Screen 02 — Splash screen

Create a premium dark metallic teal splash screen.

Use brandDark background variant.

Base gradient:

- #003F46
- #00545B
- #008C95

Draw broad abstract fluid waves with #55D6CD and #B8EFEB highlights.

Use the approved light version of the Abashyaka logo.

Logo size: 100–112 logical pixels.

Wordmark: Pure White, 36 logical pixels, weight 800.

Place a lightweight loading indicator below the logo.

Display loading only while required initialization is pending.

Coordinate Android native splash branding with Flutter splash to prevent blank white flashes.

Preserve existing trusted-session restoration and route guards.

Do not request an OTP for already authenticated trusted sessions.

Do not add redundant network calls or timers.

## 12. Screen 03 — Get Started / Onboarding

Use Pearl White as the main background.

Use onboarding premium header variant with subtle upper abstract fluid waves.

Header decorative height: approximately 140–180 logical pixels.

Place a small Pure White rounded Skip button near the upper right safe area.

Use large optimized 3D illustrations representing:

- Local shops and smartphone discovery.
- Food and grocery.
- Local service professionals.
- Delivery parcels.

Reference illustration size: 230–280 logical pixels.

Primary heading:

Everything Local At Your Doorstep

Font: 28–30 logical pixels, weight 800, Ink Black.

Supporting text:

Discover shops, book services, order food & grocery — all in one app.

Use centered secondary text and appropriate line height.

Use Metallic Teal active page indicators.

Use a full-width MetallicButton labeled Get Started with a white right-arrow icon.

Use PageView.builder when onboarding involves multiple pages.

Preserve existing onboarding-completion persistence.

Do not display onboarding again for existing completed users unless explicitly reset.

## 13. Screen 04 — Login

Use Pearl White background.

Use auth premium header variant.

Use flowing metallic teal and light aqua waves at the top.

Include subtle light aqua decorative waves at the bottom without interfering with forms.

Include:

- Back navigation when appropriate.
- Approved centred logo.
- Abashyaka wordmark.
- Login to Continue title.
- Indian phone number input.
- Existing country-code handling.
- Send OTP primary metallic button.
- Divider with or continue with text.
- Continue with Google secondary white button.
- Official Google identity asset.
- Subtle security and privacy indicators.
- Terms of Service and Privacy Policy links where supported by the application.

Phone input:

- Pure White background.
- Height 56 logical pixels.
- Radius 28 logical pixels.
- Silver Glass border, 1 logical pixel.
- Input text 16 logical pixels.
- Secondary Text placeholder.
- Clear inline validation.

Reuse existing OTP and Google authentication providers and repositories.

Preserve all secure token storage and session behavior.

Handle keyboard appearance without overflow.

Maintain loading, validation, error and account-switching behavior.

Apply the same auth theme to the existing OTP verification screen.

Do not claim security features that are not implemented.

## 14. Screen 05 — Home

Use Pearl White Scaffold background.

Use discovery premium header variant containing a light abstract metallic teal wave composition.

The premium header should integrate:

- Approved Abashyaka logo.
- Brand wordmark.
- Existing location selector.
- Notification bell.
- Existing notification badge.
- Floating search field.

Header approximate height: 160–190 logical pixels, adapting to safe-area and content needs.

Logo: 30–36 logical pixels.

Wordmark: 22–24 logical pixels, weight 800.

Search field:

- Pure White.
- Height 48–52 logical pixels.
- Radius 26 logical pixels.
- Rounded search icon.
- Search placeholder.
- Microphone icon only if existing voice-search functionality is available.

Preserve actual search, notifications and location-selection behavior.

### Promotional banner

Create a reusable PremiumBanner using Stack, ClipRRect, CustomPainter and LinearGradient.

Banner height: approximately 145–165 logical pixels.

Radius: 20–24 logical pixels.

Gradient:

- #003F46
- #008C95
- #55D6CD

Direction: bottom-left to top-right.

Use overlapping fluid curves with low-opacity glossy highlights.

Heading:

Everything local.

Subtitle:

At your doorstep.

Add a Pure White rounded Explore now button with Deep Metallic Teal text.

Use an optimized static transparent 3D shopping illustration.

Keep heading, subtitle and button as independent Flutter widgets.

Do not bake text into a banner image.

Connect CTA to an existing relevant route.

### Category grid

Use Pure White rounded glossy cards arranged in a responsive grid.

Reference layout: four columns on a standard mobile screen.

Card height: 84–92 logical pixels.

Radius: 16–18 logical pixels.

Icons: 40–48 logical pixels, realistic static 3D artwork.

Labels: 11–12 logical pixels, weight 600.

Card shadow: subtle teal-tinted shadow.

Example categories:

- Food
- Grocery
- Shops
- Services
- Pharmacy
- Electronics
- Home Needs
- More

Map cards to the actual existing category identifiers and capability engine.

Do not replace or hard-code the existing category architecture.

### Nearby business cards

Use Pure White card surfaces.

Use actual business images and API data.

Include business name, category, distance, ratings when available and favourite control.

Implement consistent image placeholders, error states and loading skeletons.

Never fabricate business ratings, prices or availability.

### Floating bottom navigation

Use a floating Pure White navigation surface.

Height: 68–74 logical pixels.

Horizontal margin: 12–16 logical pixels.

Bottom margin: 8–12 logical pixels plus safe area.

Radius: 26–30 logical pixels.

Active items use Metallic Teal or Light Aqua.

Inactive icons use Ink Black.

Use rounded outline icons.

Preserve the existing navigation architecture and route state.

Apply the approved decision to keep Saved Items accessible through Profile rather than restoring a dedicated Saved tab solely because it appears in the reference image.

Do not add a redundant Cart destination without inspecting the existing commerce navigation.

## 15. Icons and illustrations

Use realistic, visually consistent static 3D category illustrations.

Use rounded outline vector icons for:

- Search
- Location
- Notifications
- Back
- Arrow
- Profile
- Orders
- Cart
- Settings
- Favourite
- Security
- Help and Support

Do not mix unrelated icon styles.

Use locally bundled assets for stable brand graphics.

Prefer compressed WebP for raster illustrations.

Prefer SVG for suitable flat vector artwork.

Do not embed all full-size images without appropriate decode-size optimization.

Use actual asset dimensions appropriate for their rendered size.

Where approved artwork is missing, create an asset requirement list and use clearly identified temporary placeholders.

## 16. Shared components

Create or update centralized reusable components:

- AbashyakaTheme
- AbashyakaColors
- AbashyakaGradients
- AbashyakaTypography
- AbashyakaSpacing
- AbashyakaRadius
- AbashyakaShadows
- FluidWavePainter
- AbashyakaPremiumHeader
- PremiumBackground
- MetallicButton
- PremiumSecondaryButton
- PremiumOutlineButton
- PremiumCard
- PremiumTextField
- PremiumSearchBar
- PremiumBanner
- Category3DIcon
- FloatingBottomNavigation
- PremiumSkeleton

Integrate these components into the existing architecture instead of introducing competing theme systems.

## 17. Performance requirements

The application must remain responsive on budget and mid-range Android phones.

Use static painted curves instead of real-time liquid glass distortion.

Avoid BackdropFilter in scrolling cards.

Disable expensive decorative blur by default.

Avoid unnecessary saveLayer operations.

Avoid large animated shadows.

Avoid continuously animated backgrounds.

Use const constructors where appropriate.

Use lazy-building lists and grids.

Limit provider-driven rebuilds to affected subtrees.

Use properly sized and compressed images.

Avoid repeated decoding of identical assets.

Do not preload all application assets at startup.

Use RepaintBoundary selectively and verify its effect through profiling.

Target:

- Smooth 60 FPS on supported reference devices.
- Frame budget of approximately 16.67 ms on 60 Hz displays.
- No measurable significant regression compared with the existing cold-start baseline.
- Target cold startup under 2.5 seconds on an agreed mid-range reference device, subject to measurement.
- Static category image target approximately 10–30 KB per icon where visual quality permits.
- No introduction of new persistent memory-growth problems.

These are engineering and validation targets, not unverified completion claims.

## 18. Accessibility and responsive layout

Support narrow and wide Android screens.

Use 390 × 844 logical pixels as the reference design viewport.

Test at least:

- 320–360 px narrow viewport.
- 390–412 px standard viewport.
- Larger Android viewport.
- Increased system font scaling.
- Keyboard-visible login.
- Status bar and bottom navigation insets.

Ensure adequate colour contrast.

Keep interactive controls accessible.

Provide semantic labels where needed.

Respect reduced-animation preferences.

Avoid clipping important text.

## 19. Implementation phases

Phase A — Repository audit and baseline measurements.

Phase B — Centralized design tokens, theme, shared gradients and painters.

Phase C — Opening and splash screen redesign.

Phase D — Get Started and onboarding redesign.

Phase E — Login and OTP verification redesign.

Phase F — Home, premium header, banners, category cards and floating navigation.

Phase G — Performance, accessibility and regression testing.

Do not expand the redesign to every application screen until these five initial screens are visually reviewed.

Complete each phase with implementation evidence before moving to the next phase.

## 20. Acceptance criteria

The implemented screens must visually resemble the supplied reference image.

Verify:

- Correct Pearl White and Pure White surface separation.
- Consistent metallic teal styling.
- Smooth abstract fluid curves.
- Appropriate 3D imagery.
- Polished rounded buttons.
- Responsive layout.
- No text overflow.
- Working authentication.
- Working location selection.
- Working search.
- Working notifications.
- Working category navigation.
- Working existing navigation destinations.
- No unauthorized access changes.
- No new analyzer errors.
- Existing relevant tests pass.
- New widget and golden tests cover major visual components.
- Profile-mode performance is measured on the available reference hardware.
- Debug and release/profile build results are reported accurately.

Capture screenshots of all five screens on the same emulator dimensions for comparison.

Report any differences from the supplied design image.

Do not report PASS for visual or runtime acceptance unless actually verified.

If emulator, assets, credentials or runtime access is blocked, report the exact blocker and classify the affected acceptance result as PARTIAL or BLOCKED.

## 21. Final delivery

Provide:

1. Repository audit findings.
2. Design system implementation summary.
3. Modified file list.
4. Reusable component inventory.
5. Asset inventory and missing-artwork report.
6. Screenshots of the five redesigned screens.
7. Flutter analyzer and test results.
8. Performance comparison against baseline.
9. Known limitations and remaining differences.
10. Recommended next screen-polishing phase.

Save the approved design documentation under the repository's design documentation folder.

Document the reference image location.

Do not overwrite unrelated application logic.

Begin with Phase A. Inspect and understand the existing implementation before making changes.