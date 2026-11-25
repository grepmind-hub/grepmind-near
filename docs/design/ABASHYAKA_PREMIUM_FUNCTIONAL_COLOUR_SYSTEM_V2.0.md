# ABASHYAKA — PREMIUM BRAND & CUSTOMER COLOUR SYSTEM V2.0
*(Authoritative Public-Facing Brand Palette & Visual Distribution)*

## 1. Executive Summary & Core Brand Palette

Abashyaka's visual identity is built on the **Metallic Teal Abstract Fluid Wave + Pearl White Glossy UI** design language.
The public-facing customer application strictly adheres to the approved **6 core brand colours** and visual distribution ratio.

```
+---------------------------------------------------------------------------------------+
|                                CORE 6 BRAND COLOURS                                   |
+---------------------+---------------------+---------------------+---------------------+
| #00545B             | #007D80             | #00B3AE             | #F4B942             |
| Signature Teal      | Metallic Teal       | Luminous Aqua       | Metallic Gold       |
+---------------------+---------------------+---------------------+---------------------+
| #F5FAFA                                   | #FFFFFF                                   |
| Pearl White                               | Pure White                                |
+-------------------------------------------+-------------------------------------------+
```

### Visual Colour Distribution Ratio

| Percentage | Colour Family | Application Surface & Role |
|---|---|---|
| **45%** | **Pearl White** (`#F5FAFA`) | General application canvas, scaffold background, section backdrops, soft atmospheric fluid wave foundations. |
| **25%** | **Pure White** (`#FFFFFF`) | Elevated card surfaces, search bars, inputs, floating navigation bar, bottom sheets, modals, dialogs. |
| **15%** | **Metallic Teal Family** (`#00545B`, `#007D80`) | Primary branded action buttons, fluid wave header elements, hero banners, active tab indicators, brand wordmarks. |
| **8%** | **Light Aqua & Waves** (`#00B3AE`) | Wave crests, luminous border strokes (`0.5–1.0dp`), glowing focus rings, subtle badges. |
| **4%** | **Gold Accents** (`#F4B942`) | Rating stars, premium tags, sponsored badges, festive highlight accents. |
| **3%** | **Other Functional Colours** | Status chips (Success `#16A34A`, Error `#DC3545`, Warning `#F59E0B`). |

> *Suggested visual balance across typical light-theme interface surfaces, not a mandatory rigid pixel ratio.*

---

## 2. Colour Tokens Specification

### Primary Customer Brand Palette
- **Signature Teal**: `#00545B` (Deep, commanding teal for brand presence, primary gradient endpoints, hero headers)
- **Metallic Teal**: `#007D80` (Mid metallic teal for primary buttons, active states, icons)
- **Luminous Aqua**: `#00B3AE` (Vibrant cyan/aqua for accents, wave gradients, glowing highlights)
- **Metallic Gold**: `#F4B942` (Warm metallic gold for ratings, verified/premium badges, promotional stars)
- **Pearl White**: `#F5FAFA` (Soft pearl canvas background, preventing screen glare while maintaining premium light feel)
- **Pure White**: `#FFFFFF` (High-contrast card backgrounds, glossy containers, button text)

### Supporting Surface & Border Tokens
- **Ice Pearl White**: `#EAF7F7` (Secondary chip backgrounds, subtle card tints)
- **Aqua Silver Border**: `#DCEBED` (Refined 1px card borders with subtle aqua tone)
- **Glass Highlight**: `rgba(255, 255, 255, 0.40)` (Glossy top highlight on buttons and cards)
- **Teal Glass Tint**: `rgba(0, 125, 128, 0.08)` (Subtle teal backdrops for active filters/chips)

---

## 3. High-Contrast, Polished Typography System

Every text element is crafted for crisp readability, high contrast against Pearl White and Pure White, and modern editorial polish using **Plus Jakarta Sans** (with robust sans-serif fallback).

| Role | Font Family | Size / Weight | Line Height | Tracking | Text Colour | Hex | Usage |
|---|---|---|---|---|---|---|---|
| **Brand Wordmark** | Plus Jakarta Sans | 32–36 / ExtraBold 800 | 1.15 | -0.8px | Signature Teal | `#00545B` | App bar brand logo, splash title |
| **Display Heading** | Plus Jakarta Sans | 24–28 / Bold 800 | 1.25 | -0.5px | Premium Obsidian | `#101820` | Page heroes, modal main titles |
| **Page Title** | Plus Jakarta Sans | 20–22 / Bold 700 | 1.30 | -0.3px | Premium Obsidian | `#101820` | Section titles, header bar titles |
| **Card Title** | Plus Jakarta Sans | 15–16 / SemiBold 600 | 1.35 | -0.1px | Premium Obsidian | `#101820` | Business name, product title, pro name |
| **Body Large** | Plus Jakarta Sans | 15–16 / Regular 400 | 1.45 | 0.0px | Graphite Charcoal | `#374151` | Detail descriptions, long copy |
| **Body Medium** | Plus Jakarta Sans | 13–14 / Regular 400 | 1.40 | 0.0px | Graphite Charcoal | `#374151` | Subtitles, addresses, helper copy |
| **Caption / Helper** | Plus Jakarta Sans | 11–12 / Medium 500 | 1.35 | +0.1px | Graphite Charcoal | `#374151` | Timestamps, metadata, distance tags |
| **Category Label** | Plus Jakarta Sans | 11–12 / SemiBold 600 | 1.25 | 0.0px | Premium Obsidian | `#101820` | 3D category grid titles |
| **Button Primary** | Plus Jakarta Sans | 15–16 / Bold 700 | 1.20 | +0.3px | Pure White | `#FFFFFF` | Metallic teal primary button text |
| **Button Secondary** | Plus Jakarta Sans | 14–15 / SemiBold 600 | 1.20 | +0.2px | Signature Teal | `#00545B` | Outlined/ghost button text |
| **Rating Label** | Plus Jakarta Sans | 13–14 / Bold 700 | 1.20 | 0.0px | Deep Amber | `#92400E` | Rating score next to `#F4B942` gold star |
| **Odia Script** | sans-serif | 13–15 / Bold 700 | 1.30 | 0.0px | Signature Teal | `#00545B` | Regional greeting (ନମସ୍କାର, etc.) |

### Typography Principles:
1. **Never washed out**: Secondary text uses Graphite Charcoal `#374151` (contrast ratio > 7.1:1 against `#FFFFFF` / `#F5FAFA`), achieving full WCAG AAA requirements.
2. **Authoritative Headings**: Primary titles and headings use Premium Obsidian `#101820` (contrast ratio > 17.5:1 against `#FFFFFF`).
3. **Crisp hierarchy**: Distinct font weights (`800`, `700`, `600`, `400`) ensure users instantly parse primary titles vs metadata.
4. **Tight letter-spacing on headings**: `-0.3px` to `-0.8px` tracking provides a bespoke, high-end mobile app aesthetic.

---

## 4. Reusable Gradient & Glass Effects

### Metallic Teal Primary Button Gradient
```dart
LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0xFF00B3AE), // Luminous Aqua top highlight
    Color(0xFF007D80), // Metallic Teal body
    Color(0xFF00545B), // Signature Teal base
  ],
  stops: [0.0, 0.45, 1.0],
)
```

### Promotional & Hero Fluid Wave Gradient
```dart
LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    Color(0xFF00545B), // Signature Teal
    Color(0xFF007D80), // Metallic Teal
    Color(0xFF00B3AE), // Luminous Aqua glow
  ],
  stops: [0.0, 0.65, 1.0],
)
```

### Pearl White Background Canvas
```dart
Color(0xFFF5FAFA) // Pure pearl white surface with zero muddy grey
```

---

## 5. Screen-by-Screen Implementation Standard

1. **Screen 8 (Categories Directory)**:
   - Scaffold: `#F5FAFA` (Pearl White).
   - Category cards: `#FFFFFF` (Pure White) with `12px` rounded corners, `#DCEBED` 1px border, high-contrast `#101820` Premium Obsidian typography.
   - Filter tabs: Inactive `#FFFFFF` with `#374151` Graphite Charcoal text; Active Metallic Teal `#007D80` with `#FFFFFF` text.
2. **Screen 9 (Search & Results)**:
   - Search bar: `#FFFFFF` with `#DCEBED` border and `#007D80` icon.
   - Business cards: `#FFFFFF` elevated cards, `#F4B942` rating stars, `#00545B` pricing/title.
3. **Screen 10 (Nearby Interactive Map)**:
   - Pearl White header and floating search bar.
   - Interactive radar canvas with `#007D80` and `#00B3AE` ripple rings.
   - Bottom preview card: `#FFFFFF` card with Metallic Teal primary action button.
4. **Screens 11–12 (Business Profile & Product Details)**:
   - Fluid wave hero header with `#00545B` and `#007D80` gradients.
   - Pure White tab bar and detail cards.
   - Metallic Teal primary action buttons with glossy glass highlight.
