# Phase PP-03: Customer Home Tab Premium Redesign & Acceptance Specification

## 1. Architectural Objective

Transform the Customer Home screen into a fast, sophisticated, and location-aware 2027 local marketplace feed that delivers high visual appeal without performance overhead.

---

## 2. Component Blueprint

```
+-----------------------------------------------------------------------------------+
| StatusBar (Dark Icons / Transparent Background)                                   |
+-----------------------------------------------------------------------------------+
| [Signature Header: Refined Emerald Gradient #075E45 -> #073B32]                   |
|                                                                                   |
|  [Logo & Tagline]         [Delivering to: Chhatia, Cuttack v]   [Notification (3)]|
|                                                                                   |
|  +-----------------------------------------------------------------------------+  |
|  | [Search Icon] Search shops, food, medicines, services...                    |  |
|  +-----------------------------------------------------------------------------+  |
+-----------------------------------------------------------------------------------+
| [Brand Hero Banner: Branded artwork, local offer / value proposition]             |
+-----------------------------------------------------------------------------------+
| [Approved 4x2 Category Grid]                                                      |
|   [Food]         [Grocery]         [Medicines]         [Clinics / Doctors]        |
|   [Cab & Auto]   [Services]        [Shops]             [More]                     |
+-----------------------------------------------------------------------------------+
| [Nearby Stores Section] - Real local merchants with delivery time & distance chips|
+-----------------------------------------------------------------------------------+
| [Popular Near You Section] - Highest-rated food & essentials                      |
+-----------------------------------------------------------------------------------+
| [Verified Local Services Section] - Certified trades (Electrician, Plumber, etc.) |
+-----------------------------------------------------------------------------------+
| [Bottom Navigation: Home (Active) | Explore | Nearby | Orders | Profile]          |
+-----------------------------------------------------------------------------------+
```

---

## 3. Section Specifications

### A. Signature Header
- **Gradient:** Subtle linear transition from Signature Emerald (`#075E45`) to Deep Forest (`#073B32`).
- **Logo:** Approved `Abashyaka` logo with Odia tagline `ସବୁ ଆବଶ୍ୟକତା, ଆପଣଙ୍କ ପାଖରେ।`.
- **Location Selector:** Displays currently selected locality and town (`Delivering to: Chhatia, Cuttack`), with dropdown chevron. Tapping opens the locality sheet.
- **Notification Icon:** Bell icon with high-contrast amber/red badge showing real unread count (`ref.watch(unreadNotificationCountProvider)`).

### B. Unified Search Bar
- **Styling:** Pure White container inside header with soft border, 14dp radius, search icon, and clear action.
- **Placeholder:** Rotating contextual hint ("Search shops, food, medicines, services...").
- **Debounced Routing:** Tapping opens quick suggestions or routes to `SearchResultsScreen`.

### C. 4×2 Category Grid
- **Categories:**
  1. **Food** (Restaurants, cloud kitchens, bakeries)
  2. **Grocery** (Kirana, supermarkets, daily essentials)
  3. **Medicines** (Pharmacies, OTC wellness)
  4. **Clinics / Doctors** (Local practitioners, consultations)
  5. **Cab & Auto** (Local transport, rides)
  6. **Services** (Electricians, plumbers, appliance repairs)
  7. **Shops** (Retail, apparel, hardware, electronics)
  8. **More** (Full directory navigation)
- **Visuals:** Consistent 56×56dp tile with rounded 16dp corners, soft mint tint background (`#E8F5EF`), and crisp 13sp medium labels.

### D. In-App Notification Centre (Linked to Header Bell)
- **Route:** Pushed when tapping the notification bell.
- **Header:** Back button, title `Notifications`, and `Mark all read` action.
- **Filter Tabs:** `All`, `Orders`, `Updates`.
- **Card States:**
  - Unread dot indicator (`#075E45`).
  - Leading status icon inside soft rounded container.
  - Title, body summary, and relative timestamp ("2 min ago", "1 hour ago").
  - Tapping an order notification routes directly to `OrderTrackingScreen`.

### E. Real Backend Feeds
- **Nearby Stores:** Sourced from `GET /api/v1/home/feed?city=...` or `GET /api/v1/businesses/nearby`.
- **No Synthetic Data:** If no merchants are active in a category, a clean empty state or discovery card is shown; fake stores are strictly prohibited.

---

## 4. Performance & Acceptance Criteria (2027 Benchmark)

| Metric | Target | Measurement Method |
|---|---|---|
| **Scroll Frame Rate** | 60 FPS | Flutter DevTools Performance overlay on Android emulator. |
| **Cold Startup Time** | ≤ 2.5s | Measured from process start to first interactive frame. |
| **Home Usable Latency** | ≤ 1.5s | Measured from token validation to cached/fresh feed display. |
| **Touch Interaction Response** | ≤ 300ms | Immediate feedback on button, category, and tab taps. |
| **Layout Integrity** | Zero Overflow | Verified across small (360dp) and large (440dp+) widths. |
| **Text Scaling** | Up to 200% | Verified with Android accessibility font scaling enabled. |
