# Abashyaka Pre-Production Master Roadmap (2027 UI/UX & Functional Polish)

## Executive Summary

Abashyaka is entering controlled pre-production polishing and final functional acceptance. 
Having achieved verified single-use challenge FCM OTP authentication and Google OAuth sign-in on Android, this programme systematically elevates the application into a world-class, premium, 2027-standard local commerce and service discovery platform.

The architectural foundation remains immutable:
- **Client**: Flutter Android (Material Design 3, Riverpod state management, Dio networking).
- **Backend**: Go modular monolith (REST API, chi router, pgx/sqlx, PostgreSQL + PostGIS, SSE).
- **Storage & Infrastructure**: MinIO, Cloudflare Tunnel, Nginx reverse proxy, Firebase Cloud Messaging.
- **Portals**: Merchant and Admin Web Portals (Next.js 14, TypeScript).
- **Authoritative API Base**: `https://api.abashyaka.com`

---

## The 15-Phase Pre-Production Roadmap

| Phase | Title | Scope Summary | Gate & Status |
|---|---|---|---|
| **PP-00** | **Authentication & Baseline** | FCM OTP development authentication, rate-limiting, and Google Sign-In end-to-end validation. | ✅ **COMPLETED** (Commit `a043655`) |
| **PP-01** | **Premium Design System & Branding** | 2027 visual language, typography (Plus Jakarta Sans / Noto Sans Oriya), refined color palette, shared tokens, and component inventory. | 🟡 **IN PROGRESS (Audit & Spec Stage)** |
| **PP-02** | **Location, GPS & PIN Code Serviceability** | Contextual GPS detection, manual 6-digit PIN fallback, server-authoritative PostGIS serviceability, and "Outside Service Area" recovery. | ⏳ **PLANNED (Segment 1 Scope)** |
| **PP-03** | **Customer Home Tab Premium Redesign** | Brand header, live location picker, unified search, branded hero banner, 4×2 category grid, backend discovery feeds, and notification hub icon. | ⏳ **PLANNED (Segment 1 Scope)** |
| **PP-04** | **Explore, Categories & Search** | 19-category taxonomy navigation, debounced multi-facet search, sorting sheets, filter chips, and empty-state recovery. | ⏳ Planned |
| **PP-05** | **Orders & Shopping Experience** | Active food delivery tracking, table reservations, appointment bookings, and historical orders hub. | ⏳ Planned |
| **PP-06** | **Product Details, Cart & Checkout** | Local partner menu/product presentation, variant selection, unified cart, address confirmation, and server-side serviceability revalidation. | ⏳ Planned |
| **PP-07** | **Order Tracking & Delivery Experience** | Live order status timeline, partner contact card, delivery verification, and rider assignment awareness. | ⏳ Planned |
| **PP-08** | **Notification Centre** | Centralized notification inbox (All / Orders / Updates), FCM/SSE deduplication, read/unread status sync, and deep linking. | ⏳ Planned |
| **PP-09** | **Profile, Saved & Account Settings** | Customer identity card, saved addresses, bookmarked shops/services, language preferences, and security settings. | ⏳ Planned |
| **PP-10** | **Merchant Workspace Polishing** | Mobile-first merchant operations: live bookings pipeline, order preparation, catalog management, operating hours, and radius setup. | ⏳ Planned |
| **PP-11** | **Rider Workspace Polishing** | Rider availability toggle, assignment queue, pickup confirmation, customer handover, and delivery earnings review. | ⏳ Planned |
| **PP-12** | **Admin Web Portal Final Review** | Operational analytics, KYC moderation, multi-city demand radar, dispute resolution, and audit logs. | ⏳ Planned |
| **PP-13** | **Performance, Security & Accessibility** | 60 FPS scrolling, cold start ≤ 2.5s, UI response ≤ 300ms, text scaling up to 200%, WCAG contrast, and token security audit. | ⏳ Planned |
| **PP-14** | **Physical Device & Complete Lifecycle Testing** | Multi-AVD validation (`Pixel_8` Customer, `Pixel_8_Merchant_QA`, `Pixel_8_Rider_QA`) + physical Android device lifecycle acceptance. | ⏳ Planned |
| **PP-15** | **Production Release Readiness** | Production build variants, release signing, ProGuard optimization, API health gates, and rollout protocol. | ⏳ Planned |

---

## Scope Boundary for Current Segment: PP-01, PP-02, PP-03

Only **PP-01**, **PP-02**, and **PP-03** are authorized for active engineering in this segment.
- The **Notification Centre** is implemented to the extent required for the Home notification bell icon, unread counter badge, and preview drawer/screen.
- No changes will be introduced to unrelated workspaces or tabs (Orders, Merchant, Rider) until the Home experience and location serviceability pass acceptance gates.

---

## Architectural Principles & Strict Constraints

1. **Preserve Working Infrastructure:**
   - Single-use challenge FCM OTP authentication and Google OAuth sign-in must not be broken or regressed.
   - Do not restart the Flutter codebase or alter Go backend architecture.
   - No Redis, microservices, or new third-party paid services without explicit authorization.
2. **Screen-by-Screen Execution:**
   - Audit first -> propose tokens and specifications -> seek gate approval -> implement smallest vertical slice -> validate on emulator with screenshots.
3. **True Backend Data Over Placeholders:**
   - Never fabricate availability, ratings, verification badges, or fictional inventory. Empty states must be informative, elegant, and actionable.
4. **Target Performance Standards (2027 Benchmark):**
   - **60 FPS** smooth scrolling on mid-range Android devices.
   - **≤ 2.5s** cold startup to usable splash/login.
   - **≤ 1.5s** Home feed usability with cached location.
   - **≤ 300ms** UI interaction latency.
