# Abashyaka Mobile App — UI/UX Analysis Report

> **Date:** 26 November 2026  
> **Scope:** Flutter mobile application (`apps/mobile/lib/`)  
> **Analyst:** Automated codebase review  
> **Status:** Analysis only — no production code changed

---

## Executive Summary

The Abashyaka mobile app has a **well-structured, premium design system** rooted in the *Metallic Teal Abstract Fluid Wave + Pearl White Glossy UI* language. The design token infrastructure (`AbashyakaColors`, `AbashyakaSpacing`, `AbashyakaRadius`, `AbashyakaTypography`, `AbashyakaShadows`) is thorough and correctly enforces brand consistency across most of the app. The widget library covers all critical UI patterns — shimmer skeletons, metallic buttons, floating navigation, fluid-wave headers, and premium cards — and is reused consistently.

However, significant technical debt exists in screen-level implementation: several screens bypass the shared design system entirely by using raw `Colors.*` literals or hardcoded hex values, file sizes reach 4,000+ lines (clear candidate for extraction), `Navigator.push` is used in 86 places instead of the declared GoRouter router, and inline `debugPrint` calls remain scattered throughout.

**Overall UI Rating: 7.4 / 10**

| Dimension | Score | Notes |
|---|---|---|
| Design system coverage | 9/10 | Tokens, typography and shadows well defined |
| Visual consistency | 7/10 | Breaks down in older/partial screens |
| Accessibility | 5/10 | Limited semantic labels; no dark mode |
| Navigation consistency | 6/10 | Mixed GoRouter + imperative Navigator |
| Performance / rendering | 7/10 | Good skeleton loaders; some excessive rebuilds |
| Code maintainability | 6/10 | Several god-screen files >2000 lines |
| Animation & micro-interactions | 8/10 | Fluid wave & radar animations are strong |
| Error & empty states | 8/10 | Most screens cover loading/error/empty |

---

## 1. Design System — Strengths

### 1.1 Color Tokens
`AbashyakaColors` defines **75+ named tokens** covering brand colors, role colors (customer / merchant / rider / admin), functional states (success / error / warning / info), and glass/surface effects. This is production-grade and consistent with the AGENTS.md V2.0 specification.

```
signatureTeal  #00545B  — Primary brand anchor
metallicTeal   #007D80  — Interactive / active states
luminousAqua   #00B3AE  — Gradient highlight
metallicGold   #F4B942  — Premium accent
pearlWhite     #F5FAFA  — Background canvas
```

### 1.2 Typography
`AbashyakaTypography` uses **Plus Jakarta Sans** (via `google_fonts`) with eight well-named roles: `brandWordmark`, `displayHeading`, `pageTitle`, `sectionTitle`, `cardTitle`, `bodyLarge`, `bodyMedium`, `supportingText`, `categoryLabel`, `buttonText`, `ratingText`, plus `odiaScript` for localisation. Font sizes range correctly from 10 px (labels) to 34 px (wordmark). Line heights and letter-spacing are set per role.

### 1.3 Spacing & Radius Tokens
`AbashyakaSpacing` exports `xxs=4`, `xs=8`, `sm=12`, `md=16`, `lg=24`, `xl=32` and enforces the 48 dp minimum touch target. `AbashyakaRadius` provides named border radii from `xs=8` to `button=28`.

### 1.4 Component Library
The widget library is comprehensive and well-factored:

| Component | File | Quality |
|---|---|---|
| `MetallicButton` | `metallic_button.dart` | ✅ Semantic label, loading state, 48 dp min |
| `PremiumCard` | `premium_card.dart` | ✅ Clipped corners, correct shadows, tap feedback |
| `FloatingBottomNavigation` | `floating_bottom_navigation.dart` | ✅ Correct tokens, 68 dp height |
| `SkeletonLoader` | `skeleton_loader.dart` | ✅ Shimmer + multiple variants |
| `AbashyakaPremiumHeader` | `abashyaka_premium_header.dart` | ✅ Reusable, fluid wave, brand row |
| `FluidWavePainter` | `fluid_wave_painter.dart` | ✅ Custom painter, smooth |
| `BusinessCard` | `business_card.dart` | ⚠️ Uses raw hex inside (see §3) |

---

## 2. Screen-by-Screen Assessment

### Screen 1: Splash Screen (278 lines) — ✅ Good
- Lightweight implementation.
- Uses design tokens correctly.
- **Suggestion:** Add a progress indicator animation keyed to asset loading completion.

### Screen 2 & 3: Onboarding / OTP (1,136 lines) — ✅ Good
- Complex but well-organized; SMS autofill, FCM OTP, Google Sign-In, resend timer all handled.
- OTP input uses a 6-box pattern — consistent with modern UX.
- **Suggestion:** Add `Semantics` labels to OTP digit boxes for screen reader support. The current focus traversal may be incorrect for assistive technology.

### Screen 7: Explore / Home (2,054 lines) — ⚠️ Needs Refactoring
- Quick-filter logic, search bar, category chips, hero banner, business feed, and sticky cart bar are all embedded in one `ConsumerStatefulWidget`.
- The `_getFilteredBusinesses()` method uses string-matching on `categorySlug` which is fragile.
- `Navigator.push` (non-GoRouter) used for navigation to `SearchResultsScreen`.
- **Suggestion:** Extract `_QuickFilterBar`, `_HomeFeedSection`, and `_HeroBannerSection` into separate widgets. Migrate navigation to GoRouter context routes.

### Screen 8: Categories Directory (1,348 lines) — ✅ Good
- 18-category taxonomy rendered correctly.
- Uses `AbashyakaTypography` and `AbashyakaGradients` throughout.
- Two-tab pattern (Categories / Listings) is clear.
- **Suggestion:** Category grid icons could use the custom `Category3DIcon` widget instead of `Icon(Icons.*)` for visual consistency with the design reference.

### Screen 9: Search & Filter Results (774 lines) — ✅ Good
- Radius filter sheet, sort sheet, verified/open chips are well-implemented.
- Empty-state recovery with illustration is in place.
- **Suggestion:** The filter sheet uses a plain `showModalBottomSheet` with a local `StatefulBuilder` — this widget is duplicated across at least three screens. Extract to a shared `FilterBottomSheet` widget.

### Screen 10: Nearby Map (1,630 lines) — ✅ Good
- Radar canvas with animated sweep beam is a standout feature.
- Fallback gracefully uses `AnimationController` + custom painter when Google Maps is unavailable.
- 18-category domain-specific CTAs implemented correctly.
- **Suggestion:** `_loadSequence` integer guard for concurrent requests is a manual locking pattern — replace with Riverpod `AsyncNotifier` to avoid state race conditions on rapid filter changes.

### Screen 11: Business Detail (3,945 lines — **LARGEST FILE**) — 🔴 Critical Refactor
- This is the most critical file. At nearly 4,000 lines it contains: hero cover, tab bar (About, Products, Offers, Reviews), food ordering flow with cart, table reservation, service booking, review modal, and several special-category overrides.
- Hardcoded review data (`_getAllReviews`) with fake static authors (Debabrata Sahu, Ananya Patnaik, Rajesh Mohanty) is embedded directly in the screen — this is placeholder data that should not live in screen logic.
- Multiple `Colors.white.withValues(alpha: 0.9)` calls instead of using `AbashyakaColors.glassHighlight` or `pearlWhite`.
- **Suggestions:**
  1. Extract `_BusinessAboutTab`, `_BusinessProductsTab`, `_BusinessOffersTab`, `_BusinessReviewsTab` into separate files.
  2. Remove static fake review data. Replace with empty state + API fetch.
  3. Move the food ordering mini-cart widget to `core/widgets/`.
  4. Move the review submission modal to `core/widgets/write_review_modal.dart`.

### Screen 12: Product Detail (444 lines) — ✅ Good
- Clean structure with pricing, discount badges, specs, and dual CTAs.
- **Suggestion:** Discount percentage computation could be extracted to a utility method.

### Screen 13: Service Pro (903 lines) — ✅ Good
- Experience badges, verified badge, services list, rate display — well-structured.

### Screen 14: Service Request (224 lines) — ✅ Good
- Lightweight; service dropdown, description field, date/time handled cleanly.

### Screen 15: Booking Scheduler (1,467 lines) — ⚠️ Needs Attention
- 14-day calendar strip, morning/afternoon/evening slots, sticky booking bar are correct.
- `Colors.white` appears 26+ times instead of `AbashyakaColors.pureWhite`.
- `Colors.black.withValues(alpha: 0.02)` used instead of `AbashyakaShadows.*`.
- **Suggestion:** Replace all raw color literals with design tokens. Extract the `_CalendarDayStrip` and `_TimeSlotGroup` sections into sub-widgets.

### Screen 16: Saved / Bookmarked (980 lines) — ✅ Good
- 2026 Premium Obsidian tokens, fluid-wave header, category chips, context-aware CTAs implemented.
- One `debugPrint` call remains (`SAVED_SCREEN_BUILD: isLoading=…`) — should be removed before release.
- **Suggestion:** Replace `CircularProgressIndicator` with the shared `SkeletonLoader` pattern used on other screens.

### Screen 17: Customer Profile (1,790 lines) — ⚠️ Needs Attention
- Mixes authenticated and unauthenticated states in one `build()` method.
- Address loading is done inside `build()`-triggered `initState` — this pattern can cause double-fetches on rebuild.
- **Suggestion:** Use a Riverpod `FutureProvider` for address fetching to prevent redundant API calls.

### Screen 20: Merchant Workspace (1,665 lines) — ⚠️ Needs Attention
- Uses a 3-tab `TabBarView` correctly.
- AppBar `titleTextStyle` falls back to `fontFamily: 'sans-serif'` from `app_theme.dart` instead of the declared `PlusJakartaSans`.
- Uses `Navigator.push` for sub-screen routing instead of GoRouter.
- **Suggestion:** Ensure the AppBar title style consistently uses `AbashyakaTypography.pageTitle()`.

### Rider Workspace (3,548 lines) — 🔴 Critical Refactor
- The second largest file. Contains all rider delivery workflow states in one god-class.
- **Suggestion:** Extract each delivery state (available, assigned, pickup, delivery, handover) into dedicated widgets or sub-screens.

---

## 3. Cross-Cutting Issues

### 3.1 Hardcoded Color Values (Critical)

The codebase contains **1,047 raw `Color(0x...)` literals** across screen files, and additional `Colors.white` / `Colors.black` usages not routed through the design token system.

**Examples found in `business_card.dart`:**
```dart
// ❌ Current — raw literals
color: const Color(0xFFE4E7EC),
color: const Color(0xFF15803D),
color: const Color(0xFF9AA5B1),
color: const Color(0xFFF59E0B),

// ✅ Should use tokens
color: AbashyakaColors.aquaSilverBorder,
color: AbashyakaColors.success,
color: AbashyakaColors.disabledText,
color: AbashyakaColors.ratingStar,
```

**Recommendation:** Conduct a systematic sweep using the mapping below:

| Hardcoded Value | Replace With |
|---|---|
| `Colors.white` | `AbashyakaColors.pureWhite` |
| `const Color(0xFFFFFFFF)` | `AbashyakaColors.pureWhite` |
| `const Color(0xFFF5FAFA)` | `AbashyakaColors.pearlWhite` |
| `const Color(0xFF102B32)` | `AbashyakaColors.primaryText` |
| `const Color(0xFF374151)` | `AbashyakaColors.secondaryText` |
| `const Color(0xFFE2E8F0)` | `AbashyakaColors.softGrey` |
| `const Color(0xFFF59E0B)` | `AbashyakaColors.ratingStar` |
| `const Color(0xFF047857)` | `AbashyakaColors.success` |
| `const Color(0xFFBE123C)` | `AbashyakaColors.error` |

### 3.2 Navigation Inconsistency (High Priority)

**GoRouter is declared as the routing solution** (`go_router: ^14.2.0`) but `Navigator.push` / `Navigator.pop` is used **86 times** across screen files.

This creates inconsistency in:
- Back-stack management
- Deep link handling
- Route guarding / auth redirect
- Transition animations

**Recommendation:** Define named routes in a central router file and migrate `Navigator.push<T>(context, MaterialPageRoute(...))` calls to `context.push('/route-name')`.

### 3.3 God-Screen Files (High Priority)

| Screen | Lines | Action |
|---|---|---|
| `business_detail_screen.dart` | 3,945 | Extract 4+ tab widgets into separate files |
| `rider_workspace_screen.dart` | 3,548 | Extract delivery-state widgets |
| `merchant_registration_screen.dart` | 2,475 | Extract form steps as separate widgets |
| `merchant_catalog_screen.dart` | 2,470 | Extract product form/list |
| `home_screen.dart` | 2,342 | Extract section widgets |
| `explore_screen.dart` | 2,054 | Extract filter bar, feed section |
| `order_tracking_screen.dart` | 1,877 | Extract status timeline widget |

### 3.4 Debug Statements in Production Code

Three `debugPrint` calls were found in screen files. These expose internal state to Android logcat in release mode:

```dart
// saved_screen.dart:42
debugPrint('SAVED_SCREEN_BUILD: isLoading=${state.isLoading}, ...');
```

**Recommendation:** Remove all `debugPrint` calls from screen/widget files before release. Use `kDebugMode` guards if logging is genuinely needed.

### 3.5 Deprecated API Usage

`withOpacity()` is deprecated in Flutter ≥3.19 (replaced by `withValues(alpha: ...)`). **1 remaining instance** found in `abashyaka_premium_header.dart`:

```dart
// ❌ Deprecated
color: AbashyakaColors.silverGlass.withOpacity(0.8),

// ✅ Modern
color: AbashyakaColors.silverGlass.withValues(alpha: 0.8),
```

The `// ignore_for_file: deprecated_member_use` suppressor at the top of `explore_screen.dart` indicates additional suppressions — these should be investigated and resolved.

### 3.6 Fake Placeholder Data in Production Code (Critical)

`business_detail_screen.dart` contains hardcoded review records:

```dart
// ❌ Static fake reviews embedded in screen logic
final defaultReviews = [
  {'author': 'Debabrata Sahu', 'time': '2 days ago', 'rating': 5, ...},
  {'author': 'Ananya Patnaik', 'time': '1 week ago', 'rating': 5, ...},
  {'author': 'Rajesh Mohanty', 'time': '2 weeks ago', 'rating': 4, ...},
];
```

This fake data appears to real customers as genuine verified reviews. **This is a trust and compliance risk.** Remove all static review data and replace with an empty state + API-sourced reviews.

### 3.7 Missing Accessibility Semantics

A systematic review shows that:
- Most interactive elements (`InkWell`, `GestureDetector`) lack `Semantics` wrappers.
- Icon buttons in the notification header (`AbashyakaPremiumHeader`) do not have meaningful `tooltip` or `semanticLabel` values.
- Rating displays using `★` glyphs are not wrapped with `Semantics(label: '4.8 stars out of 5')`.
- OTP digit input fields lack screen-reader-compatible labels.
- No `ExcludeSemantics` is applied to purely decorative elements (wave painters, glassmorphism overlays).

### 3.8 No Dark Mode Support

The app is exclusively light-mode. All backgrounds use `AbashyakaColors.pearlWhite` / `Colors.white`, and there is no `ThemeMode` switch or `MediaQuery.platformBrightness` check in `AppTheme.theme()`.

**Recommendation (Medium Priority):** Introduce a `AbashyakaDarkColors` token class and wire a `darkTheme` parameter to `MaterialApp`. This is architecturally easy given the existing token abstraction.

### 3.9 Image Loading — No Explicit Error Budget

`BusinessCard` uses `Image.network(url, errorBuilder: ...)` directly without `CachedNetworkImage`. Several other screens do the same. The `cached_network_image` package is already a dependency — it should be used uniformly for all network images to avoid redundant fetches and jank on slow networks.

```dart
// ❌ Current — no cache
Image.network(business.coverPhotoUrl!, fit: BoxFit.cover, errorBuilder: ...)

// ✅ Recommended
CachedNetworkImage(imageUrl: url, fit: BoxFit.cover, placeholder: ..., errorWidget: ...)
```

### 3.10 Asset Duplication

The `assets/abashyaka/` directory contains multiple variant logo files with similar names:
- `brand_logo.png`, `brand_logo_metallic_teal.png`, `brand_logo_teal_aqua.png`, `brand_logo_white_pure.png`, `brand_logo_white_teal.png`
- `home_header.png`, `home_header_clean.png`, `home_header_full_wave.png`, `home_header_test.png`, `home_header_top150.png`, `home_header_unified.png`, `home_header_unified - Copy.png`

Build artifacts and intermediate test assets inflate the APK size unnecessarily.

**Recommendation:** Delete all unused/intermediate asset variants. Run `flutter build apk --analyze-size` to quantify savings.

---

## 4. Performance Observations

### 4.1 Excessive `setState` in Large Screens

`explore_screen.dart` calls `setState(() => _isSearching = ...)` on every keystroke, which rebuilds the entire 2,054-line widget tree. At minimum, extract the search bar into its own `StatefulWidget` or use `ValueNotifier`.

### 4.2 `LayoutBuilder` in Headers

`AbashyakaPremiumHeader` wraps content in `LayoutBuilder` but only reads `constraints` for the custom painter dimensions — this is correct usage. However, in screens that stack multiple `LayoutBuilder` or use `MediaQuery.of(context)` deeply inside lists, layout passes can multiply. Prefer `MediaQuery.sizeOf(context)` over `MediaQuery.of(context).size` to reduce rebuild scope (available from Flutter 3.10+).

### 4.3 `SingleTickerProviderStateMixin` Overuse

Screens that declare `SingleTickerProviderStateMixin` but only use it for one `AnimationController` are correct. However, `NearbyMapScreen` and `BusinessDetailScreen` both use the mixin alongside complex state — ensure the animation controller is disposed in `dispose()` (confirmed for `NearbyMapScreen`; verify for others).

### 4.4 SSE / WebSocket Stream Lifecycle

`OrderTrackingScreen` manages an SSE stream with custom `CancelToken`, reconnect timer, and reconciliation timer — a total of four `Timer?` / `StreamSubscription?` fields. The dispose chain is manually managed. A missed `cancel()` will cause memory leaks on fast navigation.

**Recommendation:** Wrap the SSE lifecycle in a dedicated `OrderTrackingStreamController` class (or Riverpod `StreamNotifier`) so its lifecycle is managed by the framework.

---

## 5. Specific UI/UX Improvement Suggestions

### 5.1 Bottom Navigation — Active Indicator Enhancement

The `FloatingBottomNavigation` currently differentiates active items only by icon variant and text color. Industry standard (Material 3 NavigationBar) uses a **pill/indicator background** behind the active icon.

```
Current:  [🏠] [🗺️] [💾] [👤]  (color-only distinction)
Proposed: [🏠◉] [🗺️] [💾] [👤]  (rounded pill indicator on active tab)
```

### 5.2 Search Bar — Voice Search & Barcode Scan

The `PremiumSearchBar` has space for trailing icons. Adding a microphone icon (voice search) and QR/barcode icon would match user expectations on Android, where voice search is a primary input method.

### 5.3 Onboarding — Progress Dots vs. Skip

The onboarding screen has a skip button but no visual slide progress indicator. Adding 3–4 animated dots below the hero illustration would reduce user uncertainty about remaining steps.

### 5.4 Business Detail — Collapsible Header

The hero cover image on `BusinessDetailScreen` should use a `SliverAppBar` with `flexibleSpace` and `expandedHeight` so the cover photo collapses to a compact title bar on scroll. Currently the layout appears to use a fixed-height header that occupies space regardless of scroll position.

### 5.5 Order Tracking — Timeline Stepper

The order tracking screen should display a **vertical timeline stepper** (Placed → Confirmed → Preparing → Ready → Rider Assigned → Delivered) in addition to the status text. This is a standard UX pattern that reduces support contacts.

### 5.6 Nearby Map — Filter Bottom Sheet

The map category filter is a horizontal carousel that truncates on small screens. Consider replacing with a compact filter pill row + a "More filters" sheet, similar to the `SearchResultsScreen` approach.

### 5.7 Empty States — Illustration Consistency

Some screens use `ScreenIllustrationCard` for empty states; others use a plain `Icon(Icons.*)` + `Text`. All empty states should use the shared illustrated card for consistency.

### 5.8 Merchant Workspace AppBar Typography

The `MerchantWorkspaceScreen` AppBar `title: const Text('Merchant Workspace')` does not set an explicit `style`, falling back to `AppTheme.appBarTheme.titleTextStyle` which uses `fontFamily: 'sans-serif'` — bypassing `PlusJakartaSans`. This is inconsistent with the declared typography system.

### 5.9 Haptic Feedback on Actions

No haptic feedback (`HapticFeedback.selectionClick()`, `HapticFeedback.lightImpact()`) is used on button presses, cart add actions, or booking confirmations. Android users expect subtle vibration on key CTAs — this is a one-line addition to `MetallicButton.onTap`.

### 5.10 Pull-to-Refresh

`ExploreScreen` and `SavedScreen` both have refresh mechanisms triggered by an action button. Neither implements `RefreshIndicator` for the standard swipe-to-refresh gesture. This is a user expectation on Android.

---

## 6. Architecture Recommendations

### 6.1 Router Consolidation

Create a single `app_router.dart` file that declares all named routes using GoRouter:

```dart
// Recommended structure
GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, __) => const ExploreScreen()),
    GoRoute(path: '/business/:id', builder: (_, state) => BusinessDetailScreen(businessId: state.pathParameters['id']!)),
    GoRoute(path: '/categories', builder: (_, __) => const CategoriesScreen()),
    GoRoute(path: '/search', builder: (_, state) => SearchResultsScreen(...)),
    GoRoute(path: '/booking/:businessId', builder: ...),
    // etc.
  ],
);
```

This enables deep linking, predictable back-stack, and testable navigation.

### 6.2 Screen Decomposition Pattern

Adopt a consistent pattern for all complex screens:

```
screens/
  business_detail/
    business_detail_screen.dart        (≤300 lines — layout orchestrator)
    _business_about_tab.dart           (private sub-widget)
    _business_products_tab.dart
    _business_offers_tab.dart
    _business_reviews_tab.dart
    _write_review_modal.dart
```

### 6.3 Riverpod for All Remote State

Replace all `initState + apiClient.get()` patterns with `FutureProvider` or `AsyncNotifier`:

```dart
// ❌ Manual — in profile_screen.dart
Future<void> _loadProfileDetails() async {
  final response = await apiClient.get('/customer/addresses');
  setState(() => _addresses = ...);
}

// ✅ Riverpod
final customerAddressesProvider = FutureProvider<List<CustomerAddress>>((ref) async {
  final response = await apiClient.get('/customer/addresses');
  return (response.data['data'] as List).map(CustomerAddress.fromJson).toList();
});
```

This gives automatic caching, loading/error state management, and testability.

### 6.4 Shared Modal Widgets

Extract repeated modal patterns into the shared widget library:

| Pattern | Current State | Proposed Widget |
|---|---|---|
| Radius filter sheet | Duplicated ×3 | `RadiusFilterSheet` |
| Sort options sheet | Duplicated ×2 | `SortOptionsSheet` |
| Write review modal | Inline in screen | `WriteReviewModal` |
| Delete/clear confirmation | Inline in several screens | `ConfirmationDialog` |

---

## 7. Dependency Audit

| Package | Version | Status | Notes |
|---|---|---|---|
| `flutter_riverpod` | ^2.5.1 | ✅ Current | Good |
| `go_router` | ^14.2.0 | ✅ Current | Underutilised |
| `google_fonts` | ^6.2.1 | ✅ Current | PlusJakartaSans loaded at runtime |
| `cached_network_image` | ^3.3.1 | ⚠️ Installed but underused | Use for all network images |
| `shimmer` | ^3.0.0 | ✅ Used | Good |
| `google_maps_flutter` | ^2.7.0 | ✅ Used | Has radar fallback |
| `firebase_messaging` | ^17.1.0 | ✅ Used | FCM OTP delivery |
| `sms_autofill` | ^2.6.1 | ✅ Used | OTP autofill |
| `geolocator` | ^11.1.0 | ✅ Used | Location permission handled gracefully |
| `image_picker` | ^1.2.0 | ✅ Used | Photo upload |
| `equatable` | ^2.0.5 | ✅ Declared | Verify usage in models |
| `custom_lint` | ^0.7.0 | ✅ Dev | Good for enforcing token usage |
| `riverpod_lint` | ^2.3.3 | ✅ Dev | Enforce Riverpod patterns |

**Missing packages to consider:**
- `flutter_animate` — declarative micro-animations for page transitions, card entrances
- `gap` — cleaner spacing than repeated `SizedBox(height: N)` / `SizedBox(width: N)` 
- `auto_route` or additional GoRouter configuration — for route guard enforcement

---

## 8. Prioritized Action Plan

### 🔴 P0 — Critical (Before Next Release)

1. **Remove static fake review data** from `business_detail_screen.dart` — trust/compliance risk.
2. **Remove all `debugPrint` calls** from production screen files.
3. **Fix deprecated `withOpacity()`** in `abashyaka_premium_header.dart` and any suppressed usages in `explore_screen.dart`.

### 🟠 P1 — High (Next Sprint)

4. **Migrate `BusinessCard` colors** to `AbashyakaColors` tokens — highest-visibility component.
5. **Migrate `BookingSchedulerScreen`** color literals (26+ `Colors.white` occurrences) to tokens.
6. **Extract `BusinessDetailScreen`** into tab sub-widgets (target <600 lines per file).
7. **Add `RefreshIndicator`** to `ExploreScreen` and `SavedScreen`.
8. **Replace `Image.network`** with `CachedNetworkImage` in `BusinessCard` and other list cards.

### 🟡 P2 — Medium (Next Quarter)

9. **Migrate navigation** from `Navigator.push` to GoRouter for the 86 remaining call sites.
10. **Add haptic feedback** to `MetallicButton` and cart-add actions.
11. **Refactor `RiderWorkspaceScreen`** (3,548 lines) into delivery-state sub-widgets.
12. **Replace `initState` API calls** with Riverpod `FutureProvider` patterns.
13. **Add pull-to-refresh** to remaining list screens.
14. **Add `SliverAppBar`** collapsible hero to `BusinessDetailScreen`.

### 🟢 P3 — Low (Backlog)

15. **Dark mode** — add `AbashyakaDarkColors` and wire `MaterialApp.darkTheme`.
16. **Accessibility pass** — add `Semantics` labels to interactive and decorative elements.
17. **Asset cleanup** — remove unused intermediate logo/header variants.
18. **Active NavBar indicator pill** — add background container to active `FloatingBottomNavigation` item.
19. **Voice search icon** in `PremiumSearchBar`.
20. **Onboarding progress dots**.

---

## 9. Files Requiring the Most Attention

| Priority | File | Lines | Primary Issue |
|---|---|---|---|
| 🔴 | `business_detail_screen.dart` | 3,945 | Fake reviews, god-class, mixed colors |
| 🔴 | `rider_workspace_screen.dart` | 3,548 | God-class, requires decomposition |
| 🟠 | `booking_scheduler_screen.dart` | 1,467 | 26+ raw `Colors.white` |
| 🟠 | `explore_screen.dart` | 2,054 | Mixed navigation, full-tree setState |
| 🟠 | `merchant_registration_screen.dart` | 2,475 | Form steps not extracted |
| 🟡 | `business_card.dart` | 406 | 9 raw hex color literals |
| 🟡 | `profile_screen.dart` | 1,790 | Manual `initState` API fetch |
| 🟡 | `order_tracking_screen.dart` | 1,877 | Manual timer/stream lifecycle |

---

## 10. What's Working Well — Don't Change

- ✅ `AbashyakaColors` / `AbashyakaTypography` / `AbashyakaSpacing` — excellent token coverage
- ✅ `MetallicButton` — loading state, Semantics, 48 dp min, correct gradient
- ✅ `PremiumCard` — clipping, shadow, tap ripple all correct
- ✅ `SkeletonLoader` / `SkeletonLine` / `SkeletonImageGrid` — well-factored shimmer system
- ✅ `FloatingBottomNavigation` — correct tokens, 68 dp height, touch target
- ✅ `AbashyakaPremiumHeader` — multi-variant, well-structured, reusable
- ✅ `NearbyMapScreen` radar animation — high quality custom painter
- ✅ Category taxonomy mapping (18 categories) — comprehensive and consistent
- ✅ Error / empty / loading states — present in most screens
- ✅ Location permission handling — graceful fallback chain
- ✅ OTP flow — FCM + SMS autofill + resend timer all correct
- ✅ Test coverage — 47 test files with broad screen/widget coverage

---

*Report generated from static source analysis of `apps/mobile/lib/`. No code was modified. All line counts reflect the state of the repository at time of analysis.*
