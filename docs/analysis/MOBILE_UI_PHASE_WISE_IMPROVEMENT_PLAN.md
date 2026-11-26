# Abashyaka Mobile App — Phase-by-Phase UI/UX Improvement Plan

> **Date:** 26 November 2026  
> **Source Analysis:** [MOBILE_UI_ANALYSIS_REPORT.md](file:///d:/grepmind-near/docs/analysis/MOBILE_UI_ANALYSIS_REPORT.md)  
> **Target Branch:** `abashyaka-dev-4-analysis-fix` (branched from `abashyaka-dev-03`)  
> **Scope:** `apps/mobile/lib/`  
> **Baseline Rating:** `7.4 / 10` → **Projected Target:** `9.1 – 9.2 / 10`

---

## Overview & Branch Strategy

```text
abashyaka-dev-03 (source)
   └── abashyaka-dev-4-analysis-fix
          ├── Phase 1 — P0 Critical Fixes (Safety, Compliance & Deprecations)
          ├── Phase 2 — P1a Color Token Sweep (AbashyakaColors Consistency)
          ├── Phase 3 — P1b Typography & Font Consistency (Plus Jakarta Sans)
          ├── Phase 4 — P1c Image Caching, Pull-to-Refresh & Skeletons
          ├── Phase 5 — P1d Premium Interactions & Micro-UX Polish
          ├── Phase 6 — P2 Premium Layout Upgrades & Screen Decomposition
          └── Phase 7 — P2/P3 Architecture, GoRouter, Dark Mode & Accessibility (Optional/Follow-up)
```

### Guardrails (Every Phase)
1. **Preserve all business logic, API contracts, Riverpod state, and QA OTP security** (per `AGENTS.md`).
2. **One phase = one isolated commit** on `abashyaka-dev-4-analysis-fix` so any phase can be reviewed or reverted independently.
3. **Run static analysis and relevant widget tests** (`flutter analyze`, `flutter test`) after each phase before committing.
4. **No new third-party dependencies** unless explicitly approved.

---

## Phase 1 — P0 Critical Fixes (Safety, Compliance & Deprecations)

**Priority:** 🔴 P0 — Critical  
**Risk:** 🟢 Zero  
**Projected Rating Gain:** `7.4 → 7.7 (+0.3)`

### Objectives
Eliminate trust/compliance risks (static fake reviews), release-build log leaks (`debugPrint`), and deprecated Flutter API calls (`withOpacity`).

### Exact Targets & Changes

1. **Remove static fake review data**
   - **File:** `apps/mobile/lib/core/screens/business_detail_screen.dart`
   - **Issue:** `_getAllReviews(Business biz)` previously returned hardcoded fake reviews (`Debabrata Sahu`, `Ananya Patnaik`, `Rajesh Mohanty`) that appeared as real customer reviews.
   - **Change:**
     - Return only user-submitted reviews (`List.unmodifiable(_customReviews)`) or API-fetched reviews.
     - Render a clean empty state (`Icons.rate_review_outlined` + `"No reviews yet"` + `"Be the first to review this business"`) when no reviews exist.
     - Note: *Partial edits already staged in working tree on `abashyaka-dev-4-analysis-fix` (`business_detail_screen.dart`, 70 lines changed) — verify & finalize before committing.*

2. **Remove `debugPrint` calls from production screen code**
   - **File:** `apps/mobile/lib/core/screens/saved_screen.dart`
   - **Issue:** `debugPrint('SAVED_SCREEN_BUILD: ...')` inside `build()` leaked internal state on every rebuild.
   - **Change:** Remove all `debugPrint` statements in screen `build()` methods. *(Already applied in working tree on `saved_screen.dart` — verify before committing.)*

3. **Resolve deprecated `withOpacity()` & `deprecated_member_use` suppressors**
   - **Files:**
     - `apps/mobile/lib/core/widgets/abashyaka_premium_header.dart` (1 instance — *already updated in working tree*)
     - `apps/mobile/lib/core/widgets/floating_bottom_navigation.dart` (1 instance at line 43)
     - `apps/mobile/lib/core/widgets/category_3d_icon.dart` (1 instance)
     - `apps/mobile/lib/core/widgets/fluid_wave_painter.dart` (33 instances)
     - `apps/mobile/lib/core/screens/explore_screen.dart` (line 1: `// ignore_for_file: deprecated_member_use`)
   - **Change:** Replace `.withOpacity(x)` with `.withValues(alpha: x)` and remove `// ignore_for_file: deprecated_member_use` where no longer needed.

### Verification Gate
- `flutter analyze` shows zero new warnings/errors on modified files.
- `flutter test test/business_detail_screen_test.dart test/saved_screen_test.dart` passes.
- Commit message: `fix(mobile/p0): remove fake reviews, debugPrint, and deprecated withOpacity`

---

## Phase 2 — P1a Color Token Sweep (`AbashyakaColors` Consistency)

**Priority:** 🟠 P1 — High  
**Risk:** 🟢 Very Low  
**Projected Rating Gain:** `+0.4` (Visual Consistency `7.0 → 8.5`)

### Objectives
Eliminate raw `Color(0x...)` literals (**1,047 occurrences** across `core/screens/`) and raw `Colors.white` literals (**462 occurrences** across `core/screens/`) so every screen strictly follows the *Metallic Teal Abstract Fluid Wave + Pearl White Glossy UI* V2.0 palette.

### Token Mapping Standard

| Raw Literal | Official Token |
|---|---|
| `Colors.white` / `Color(0xFFFFFFFF)` | `AbashyakaColors.pureWhite` |
| `Color(0xFFF5FAFA)` / `Color(0xFFF8FAFC)` | `AbashyakaColors.pearlWhite` |
| `Color(0xFF102B32)` / `Color(0xFF101820)` | `AbashyakaColors.primaryText` |
| `Color(0xFF374151)` / `Color(0xFF36545C)` | `AbashyakaColors.secondaryText` |
| `Color(0xFFE2E8F0)` / `Color(0xFFE4E7EC)` | `AbashyakaColors.softGrey` / `AbashyakaColors.aquaSilverBorder` |
| `Color(0xFFF59E0B)` | `AbashyakaColors.ratingStar` |
| `Color(0xFF047857)` / `Color(0xFF15803D)` | `AbashyakaColors.success` |
| `Color(0xFFBE123C)` | `AbashyakaColors.error` |
| `Color(0xFF9AA5B1)` | `AbashyakaColors.disabledText` |
| `Colors.white.withValues(alpha: 0.4–0.9)` | `AbashyakaColors.glassHighlight` / `AbashyakaColors.pearlWhite.withValues(...)` |
| `Colors.black.withValues(alpha: 0.02–0.05)` | `AbashyakaShadows.card` |

### Execution Batches
1. **Batch 2A — High-Visibility Shared Widgets:**
   - `apps/mobile/lib/core/widgets/business_card.dart` (9+ raw hex literals in status pills, borders, and stars)
2. **Batch 2B — Core Customer Discovery & Booking Screens:**
   - `apps/mobile/lib/core/screens/booking_scheduler_screen.dart` (26+ `Colors.white` & raw shadow alphas)
   - `apps/mobile/lib/core/screens/business_detail_screen.dart` (glass overlays & modal sheet backgrounds)
   - `apps/mobile/lib/core/screens/search_results_screen.dart`
   - `apps/mobile/lib/core/screens/saved_screen.dart` (`Color(0xFFF8FAFC)` scaffold background → `AbashyakaColors.pearlWhite`)
3. **Batch 2C — Remaining Customer, Merchant & Rider Screens:**
   - `explore_screen.dart`, `profile_screen.dart`, `order_tracking_screen.dart`, `merchant_workspace_screen.dart`, `rider_workspace_screen.dart`.

### Verification Gate
- `Select-String` count of `Color(0x` and `Colors.white` in `core/screens/` & `business_card.dart` drops by >80%.
- `flutter test test/home_screen_test.dart test/booking_scheduler_test.dart test/search_results_screen_test.dart` passes.
- Commit message: `style(mobile/p1): migrate raw color literals to AbashyakaColors tokens`

---

## Phase 3 — P1b Typography & Font Consistency (`Plus Jakarta Sans`)

**Priority:** 🟠 P1 — High  
**Risk:** 🟢 Very Low  
**Projected Rating Gain:** `+0.2` (Visual & Brand Polish)

### Objectives
Replace inline `TextStyle(fontSize: ..., fontWeight: ...)` declarations (**1,105 occurrences** in `core/screens/`) with `AbashyakaTypography.*` roles so **Plus Jakarta Sans** (with unified letter-spacing and line-height) renders consistently across every screen, AppBar, and navigation bar.

### Exact Targets & Changes

1. **Fix `AppTheme.appBarTheme.titleTextStyle` fallback**
   - **File:** `apps/mobile/lib/core/theme/app_theme.dart`
   - **Issue:** `appBarTheme.titleTextStyle` hardcodes `fontFamily: 'sans-serif'`, causing `MerchantWorkspaceScreen`, `ProfileScreen`, and others without explicit styles to lose `Plus Jakarta Sans`.
   - **Change:** Set `titleTextStyle: AbashyakaTypography.pageTitle()`.

2. **Standardize `FloatingBottomNavigation` label typography**
   - **File:** `apps/mobile/lib/core/widgets/floating_bottom_navigation.dart`
   - **Issue:** Overrides `AbashyakaTypography.categoryLabel(...).copyWith(fontSize: 10)` inline.
   - **Change:** Use a clean `AbashyakaTypography.categoryLabel(..., fontSize: 10.5)` token or dedicated `navLabel` helper in `AbashyakaTypography`.

3. **Migrate inline `TextStyle(...)` in priority screens to `AbashyakaTypography`:**
   - `business_card.dart` (card title, rating, locality, status pills)
   - `saved_screen.dart` (AppBar title & subtitle)
   - `merchant_workspace_screen.dart` (AppBar, dashboard KPIs, request cards)
   - `business_detail_screen.dart` (review modal, headers, section titles)
   - `booking_scheduler_screen.dart` (date strip, time slot chips, sticky bar)

### Verification Gate
- `flutter analyze` passes cleanly.
- `flutter test test/merchant_workspace_test.dart test/profile_screen_test.dart` passes.
- Commit message: `style(mobile/p1): enforce AbashyakaTypography Plus Jakarta Sans across screens`

---

## Phase 4 — P1c Image Caching, Pull-to-Refresh & Skeleton Loaders

**Priority:** 🟠 P1 — High  
**Risk:** 🟡 Low  
**Projected Rating Gain:** `+0.3` (Performance `7.0 → 8.2`, UX Consistency `8.0 → 8.8`)

### Objectives
Eliminate redundant network image fetches on scroll, add standard Android pull-to-refresh gestures, and replace plain spinners with branded shimmer skeletons.

### Exact Targets & Changes

1. **Replace `Image.network()` with `CachedNetworkImage` (18 occurrences across 11 files)**
   - `home_screen.dart` (3)
   - `luxe_components.dart` (3)
   - `merchant_catalog_screen.dart` (2)
   - `merchant_workspace_screen.dart` (2)
   - `nearby_map_screen.dart` (2)
   - `business_card.dart` (1)
   - `business_detail_screen.dart` (1)
   - `explore_screen.dart` (1)
   - `home_new_near_you_screen.dart` (1)
   - `merchant_registration_screen.dart` (1)
   - `product_detail_screen.dart` (1)
   - **Change:** Create or reuse a `PremiumNetworkImage` helper wrapping `CachedNetworkImage` with `SkeletonLoader` as `placeholder` and `CategoryThemedPlaceholder` / fallback icon as `errorWidget`.

2. **Add `RefreshIndicator` (Pull-to-Refresh)**
   - **Files:**
     - `apps/mobile/lib/core/screens/explore_screen.dart`
     - `apps/mobile/lib/core/screens/saved_screen.dart`
     - `apps/mobile/lib/core/screens/order_history_screen.dart` (if missing)
   - **Change:** Wrap scrollable list bodies in `RefreshIndicator(color: AbashyakaColors.metallicTeal, backgroundColor: AbashyakaColors.pureWhite, onRefresh: ...)`.

3. **Upgrade `SavedScreen` loading state**
   - **File:** `apps/mobile/lib/core/screens/saved_screen.dart`
   - **Change:** Replace `CircularProgressIndicator` (lines 114–118) with a list of `SkeletonLoader` cards matching `BusinessCard` dimensions.

### Verification Gate
- Zero raw `Image.network(` calls remaining in `apps/mobile/lib/core/`.
- `flutter test` on `home_screen_test.dart`, `saved_screen_test.dart`, `nearby_map_test.dart` passes.
- Commit message: `perf(mobile/p1): adopt CachedNetworkImage, RefreshIndicator, and SkeletonLoader`

---

## Phase 5 — P1d Premium Interactions & Micro-UX Polish

**Priority:** 🟡 P1/P2 — High-Impact Polish  
**Risk:** 🟢 Low  
**Projected Rating Gain:** `+0.3` (Animation & Micro-interactions `8.0 → 8.8`)

### Objectives
Elevate tactile feel, visual hierarchy, and component polish without altering core navigation or API logic.

### Exact Targets & Changes

1. **Haptic feedback on primary CTAs**
   - **File:** `apps/mobile/lib/core/widgets/metallic_button.dart`
   - **Change:** Trigger `HapticFeedback.lightImpact()` inside `MetallicButton` and `PremiumSecondaryButton` `onTap` handlers, and on cart-add buttons.

2. **Active pill indicator on `FloatingBottomNavigation`**
   - **File:** `apps/mobile/lib/core/widgets/floating_bottom_navigation.dart`
   - **Change:** Wrap the active tab icon in an `AnimatedContainer` pill (`AbashyakaColors.iceAquaWhite` / `AbashyakaColors.tealTint`, `BorderRadius.circular(14)`) with smooth `200ms` transition.

3. **Standardize card radii & bottom sheet shapes**
   - Audit modal bottom sheets (`showModalBottomSheet`) across `search_results_screen.dart`, `business_detail_screen.dart`, and `explore_screen.dart` to use consistent `RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AbashyakaRadius.xl)))` (`24.0`) and a shared drag-handle pill.

4. **Empty-state consistency**
   - Replace plain `Icon + Text` empty states (e.g., `profile_screen.dart` unauthenticated view) with `ScreenIllustrationCard` for uniform brand presentation.

### Verification Gate
- `flutter test test/widget_test.dart test/workspace_navigation_test.dart` passes.
- Commit message: `feat(mobile/p1): add haptic feedback, active nav pill, and modal polish`

---

## Phase 6 — P2 Premium Layout Upgrades & Screen Decomposition

**Priority:** 🟡 P2 — Medium  
**Risk:** 🟠 Medium (requires careful state preservation)  
**Projected Rating Gain:** `+0.4` (Maintainability `6.0 → 8.5`)

### Objectives
Break down oversized "god-screen" files, upgrade key customer journeys (`BusinessDetailScreen` hero, `OrderTrackingScreen` stepper), and isolate rebuild scopes for smoother 60fps scrolling.

### Exact Targets & Changes

1. **`BusinessDetailScreen` decomposition & `SliverAppBar` hero**
   - **Current:** `business_detail_screen.dart` (**3,945 lines**).
   - **Changes:**
     - Split into `apps/mobile/lib/core/screens/business_detail/`:
       - `business_detail_screen.dart` (orchestrator + collapsible `SliverAppBar` hero cover)
       - `widgets/business_about_tab.dart`
       - `widgets/business_products_tab.dart`
       - `widgets/business_offers_tab.dart`
       - `widgets/business_reviews_tab.dart`
       - `widgets/write_review_modal.dart`
     - Upgrade fixed cover header to `SliverAppBar(expandedHeight: 240, pinned: true, ...)` so the hero photo smoothly collapses into the Metallic Teal app bar on scroll.

2. **`ExploreScreen` rebuild isolation**
   - **Current:** `explore_screen.dart` (**2,054 lines**), calls `setState` on every search keystroke.
   - **Changes:**
     - Replace `_isSearching` `setState` with `ValueNotifier<bool>` / `ValueListenableBuilder` around the search bar clear button.
     - Extract `_QuickFilterBar` and `_HeroBannerSection` into dedicated sub-widgets.

3. **`OrderTrackingScreen` vertical timeline stepper & SSE lifecycle**
   - **Current:** `order_tracking_screen.dart` (**1,877 lines**).
   - **Changes:**
     - Add a clear vertical timeline stepper (`Placed → Confirmed → Preparing → Ready → Rider Assigned → Delivered`) with `AbashyakaColors.metallicTeal` active/completed nodes.
     - Extract the 4-timer SSE/reconciliation lifecycle into a dedicated controller/provider to prevent leak risk on fast navigation.

4. **`RiderWorkspaceScreen` decomposition**
   - **Current:** `rider_workspace_screen.dart` (**3,548 lines**).
   - **Change:** Extract delivery-state views (`available`, `assigned`, `pickup`, `handover`) into modular widgets under `screens/rider_workspace/`.

### Verification Gate
- Run full relevant widget test suite: `business_detail_screen_test.dart`, `home_screen_test.dart`, `order_tracking_format_test.dart`, `rider_dispatch_test.dart`.
- Commit each sub-decomposition cleanly or as Phase 6.

---

## Phase 7 — P2/P3 Architecture & Backlog (Separate Dedicated Sprints)

These items carry higher structural scope or cross-cutting risk and should be executed in dedicated follow-up sprints after Phases 1–6 are QA-verified:

1. **GoRouter Consolidation (86 `Navigator.push` sites)** — 🔴 High risk. Migrate screen groups incrementally in a central `app_router.dart` with route guards and constructor-arg → `extra`/path-param mapping.
2. **Riverpod `FutureProvider` Migration** — Replace manual `initState` API calls (e.g., `profile_screen.dart` addresses) with cached providers.
3. **Accessibility (`Semantics`) Pass** — Add `Semantics` labels to OTP digit fields, `★` rating badges, `AbashyakaPremiumHeader` notification bell, and `ExcludeSemantics` on decorative `FluidWavePainter`s.
4. **Dark Mode (`AbashyakaDarkColors`)** — Add dark-mode token palette and wire `MaterialApp.darkTheme`.
5. **Asset Cleanup** — Audit and remove unused intermediate variants in `assets/abashyaka/` (`home_header_*`, duplicate `brand_logo_*`) and verify APK size reduction via `flutter build apk --analyze-size`.

---

## Summary Scorecard (Projected)

| Phase | Focus | Risk | Rating After Phase |
|---|---|---|---|
| Baseline | Current codebase | — | **7.4 / 10** |
| Phase 1 | P0 safety, fake reviews, `debugPrint`, `withOpacity` | 🟢 Zero | **7.7 / 10** |
| Phase 2 | Color token sweep (`AbashyakaColors`) | 🟢 Very Low | **8.1 / 10** |
| Phase 3 | Typography (`Plus Jakarta Sans` everywhere) | 🟢 Very Low | **8.3 / 10** |
| Phase 4 | `CachedNetworkImage`, `RefreshIndicator`, skeletons | 🟡 Low | **8.6 / 10** |
| Phase 5 | Haptics, active nav pill, modal & empty-state polish | 🟢 Low | **8.8 / 10** |
| Phase 6 | `SliverAppBar`, timeline stepper, god-screen split | 🟠 Medium | **9.0 / 10** |
| Phase 7 | GoRouter, Accessibility, Dark mode, Asset cleanup | 🔴 High (GoRouter) | **9.2 / 10** |
