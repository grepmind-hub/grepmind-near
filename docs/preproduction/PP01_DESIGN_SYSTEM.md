# Phase PP-01: Premium Design System & Brand Identity Specification

## 1. Current Application Audit & Findings

### 1.1 Screen-by-Screen Inspection

| Screen Surface | Current State & Visual Assets | Inconsistencies & Issues Identified |
|---|---|---|
| **Splash Screen** | Uses `assets/abashyaka/splash_emblem.png` and `splash_landscape.png` with bilingual Odia/English taglines. | Visually clean, but transition duration (500ms) could be tighter; uses hardcoded colors instead of centralized tokens. |
| **Onboarding Carousel** | 3-page carousel with `onboarding_customer_hero.png` and permission modal sheet. | Primary button uses solid heavy green `#0B6B4A` without subtle depth. Carousel indicator dots lack smooth animation. |
| **Login / Phone OTP** | Custom 6-digit cells, Google OAuth button, and rate-limit SnackBar. | Functionally verified. Visual appearance is clean, but the solid green button and header text can be unified with the 2027 token set. Retain all artwork! |
| **Role Selection** | "Select Portal Experience" with Customer, Merchant, Rider cards. | Card outlines and icon badges have slight variations in elevation and radius (16dp vs 24dp). |
| **Home Screen (`home_screen.dart`)** | Solid deep green header container (`#123D36` / `#0B6B4A`), search bar, horizontal offers carousel, and category chips. | **Visual Clutter & Weight:** The header block is currently a heavy solid green rectangle that feels dense and visually intrusive. Search input has inconsistent internal padding. Category chips use varied tinting. |
| **Bottom Navigation Bar** | 5 tabs (Home, Explore, Nearby, Orders, Profile). | Icon sizes vary (20dp to 26dp); selected label font weight and indicator pills need unified Material 3 styling. |

---

## 2. Approved 2027 Color Palette & Dual-Button Design System (Theme B)

Per user directive:
**Finalized Authoritative Palette**:
- **Action Green (`#087F0D`)**: Replaces Signature Emerald for accessible buttons with white text
- **Vibrant Green (`#09A110`)**: Primary action accent and interactive highlights
- **Signature Orange (`#FF8A00`)**: Offers and notification indicators

### 2.1 Complete Color Tokens Specification

| Color Token | Hex Code | Role & Application | Contrast Ratio (vs White / Canvas) |
|---|---|---|---|
| **Action Green** | `#087F0D` | Accessible buttons with white text, primary interactive controls. | 5.1:1 (WCAG AA Compliant) |
| **Vibrant Green** | `#09A110` | Primary action accent, focus rings, selected badges, high-impact buttons. | 3.8:1 (Vivid action punch) |
| **Deep Emerald** | `#064D3A` | Header gradient base, branding, headings. | 10.5:1 (WCAG AAA Compliant) |
| **Fresh Leaf** | `#78CE65` | Illustrations and highlights, success indicators. | 1.8:1 (Fresh graphic tint) |
| **Soft Lime** | `#DDF5A6` | Premium promotional banners, quick-commerce banners. | 1.2:1 (Soft banner background) |
| **Light Mint** | `#E4F7E3` | Header text, category chip backgrounds, selected states. | 1.15:1 (Subtle surface tint) |
| **Pearl Green** | `#F3FAF0` | Subtle section backgrounds, divider tints, surface variant. | Subtle warm tint |
| **Signature Orange** | `#FF8A00` | Offers, notification indicators, shopping bag badge. | 3.1:1 on dark, 3.4:1 on light |
| **Warm Peach** | `#FFE4D1` | Food category background. | Warm food pastel |
| **Sky Blue** | `#DFEEFF` | Healthcare / clinics category background. | Clean medical pastel |
| **Pure White** | `#FFFFFF` | Cards, input fields, and main background. | Crisp elevated surface |
| **Carbon** | `#172820` | Primary text and headlines. | 16.5:1 (Ultra-readable) |
| **Muted Slate** | `#64748B` | Secondary metadata, timestamps, subtitles, outlines (`#E2E8F0`). | 4.6:1 (WCAG AA Compliant) |

### 2.2 Button Design Standards

1. **Vibrant & Action Green Primary Button (`AbashyakaPrimaryButton`):**
   - Background: `Action Green` (`#087F0D`) or `Vibrant Green` (`#09A110`)
   - Text/Icon: Pure White (`#FFFFFF`, 16sp, SemiBold/Bold 700)
   - Height: 54 dp, Corner Radius: 28 dp (smooth rounded pill as shown in reference)
   - Usage: "Continue", "Verify", "Select this address", "Save", "Order Now", "Book Slot".
2. **Signature Orange Secondary / Offer Button:**
   - Background: `Signature Orange` (`#FF8A00`)
   - Text/Icon: Pure White (`#FFFFFF`, 16sp, Bold 700)
   - Usage: Limited-time offers, high-visibility promotional actions.
3. **Outlined / Surface Secondary Button:**
   - Background: Pure White (`#FFFFFF`), Border: 1.5dp `#E2E8F0`
   - Text/Icon: Action Green (`#087F0D`) or Carbon (`#172820`)
   - Height: 48–52 dp, Corner Radius: 28 dp
   - Usage: "Change location", "View details", "Filter & Sort".
   - Usage: "Change location", "View details", "Filter & Sort".

---

## 3. Typography Standards

| Role | Font Family | Size (sp) | Weight | Line Height | Tracking |
|---|---|---|---|---|---|
| **Display / Hero** | Plus Jakarta Sans | 26–28 sp | Bold (700) | 1.25 | -0.4 |
| **Headline Medium** | Plus Jakarta Sans | 20–22 sp | SemiBold (600) | 1.3 | -0.2 |
| **Section Header** | Plus Jakarta Sans | 18–20 sp | Bold (700) | 1.35 | 0.0 |
| **Body Primary** | Plus Jakarta Sans | 14–15 sp | Regular / Medium (400/500) | 1.45 | 0.0 |
| **Secondary Metadata** | Plus Jakarta Sans | 12–13 sp | Medium (500) | 1.4 | +0.1 |
| **Odia Regional Text** | Noto Sans Oriya | 13–15 sp | Regular / SemiBold | 1.5 | 0.0 |

*Note: Fonts are bundled locally into `assets/fonts/` without relying on runtime Google Fonts network downloads.*

---

## 4. Shared Reusable Component Inventory

To prevent duplication and guarantee visual consistency:

1. **`AbashyakaHeader`**: Unified brand header supporting logo, location dropdown, notification bell with unread badge, and optional GPS action.
2. **`AbashyakaSearchBar`**: Sticky/sliver search input with rounded corners (16dp), contextual hints, and clear button.
3. **`AbashyakaCategoryGrid`**: High-performance 4×2 grid featuring consistent 56×56dp category tiles, 8dp pill radius, and readable labels.
4. **`AbashyakaBusinessCard`**: Horizontal and vertical merchant/shop cards with 16dp radius, verified badge, rating tag, distance, and ETA chips.
5. **`AbashyakaPrimaryButton`**: 54dp minimum height, rounded 16dp radius, accessible touch target, and integrated loading state.
6. **`AbashyakaBottomSheet`**: Standard modal bottom sheet with 24dp top corner radius, drag handle, and auto-dismiss keyboard management.
7. **`AbashyakaSkeletonLoader`**: GPU-friendly shimmer placeholders matching exact card shapes to eliminate layout shift during data fetches.

---

## 5. Performance Acceptance Baseline

- **Scrolling Frame Rate:** 60 FPS target via `CustomScrollView` and lazy sliver builders (`SliverList.builder`, `SliverGrid`).
- **Memory Optimization:** Image assets loaded with explicit `cacheWidth` and `cacheHeight` constraints based on device pixel ratio.
- **Widget Rebuild Isolation:** Riverpod `select()` used across location, cart count, and notification unread counts to prevent full-screen re-renders.

---

## 6. Proposed Files for Modification in PP-01

- `apps/mobile/lib/features/branding/abashyaka_theme.dart` (Token consolidation and 2027 color constants)
- `apps/mobile/lib/core/theme/app_theme.dart` (Unified typography, card radius, button heights)
- `apps/mobile/lib/core/widgets/abashyaka_header.dart` (Reusable brand header)
- `apps/mobile/lib/core/widgets/category_chip.dart` (Consistent 4×2 category presentation)
- `apps/mobile/lib/core/widgets/marketplace_cards.dart` (Card elevation and border harmonization)
