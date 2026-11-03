# Grepmind Near: Current Application Status

Audit date: 3 November 2026  
Scope: repository source and safe local checks. This is a code and configuration audit, not a penetration test or legal opinion.

## Executive summary

Grepmind Near is a functioning local-development vertical slice for discovery, merchant catalog maintenance, OTP development authentication, service inquiries, and a newer customer order/reservation backend. It is not ready for a public launch. The strongest verified areas are Go package tests, Flutter widget tests, Cuttack/Jajpur discovery plus catalog UI fixture automation documented in the repository, and the basic merchant/admin review API. The merchant web portal still boots from `mockData.ts` and mutates much of its workspace in browser state; admin analytics/KYC data arrays are empty. Merchant registration/claim is visibly non-persistent. Billing, account deletion, production OTP, FCM delivery, and Play release signing are absent.

The source and tests contradict several historical “complete/end-to-end” changelog statements. Those statements are treated as historical claims, not current proof. The latest operational booking work provides persistent server-side food/table/hotel orders, but it has only package/widget coverage and a local database migration run recorded in the prior implementation notes; the current audit reran Go and Flutter tests but did not rerun authenticated reservation transactions against a fresh test database.

## Architecture inventory

| Layer | Current source | Observed implementation |
|---|---|---|
| Android | `apps/mobile/lib` | Flutter app using Riverpod `StateNotifier` providers, Dio API client and a `MaterialApp`/`IndexedStack` navigator. GoRouter is declared in dependencies but the inspected app entrypoint does not use it. |
| API | `backend/cmd/api`, `backend/internal` | Go `net/http` method/path mux, modular packages for auth, discovery, moderation, media, notifications and operations. PostgreSQL access uses sqlx. |
| Database | `backend/migrations/001...011` | PostgreSQL 16/PostGIS schemas for users, businesses, catalog, services, slots, requests, moderation, notifications, media, category configuration, city archive, orders. Compose mounts SQL as init scripts; there is no migration ledger/runner for existing environments. |
| Merchant portal | `apps/merchant-web` | Next.js 14. It has API helpers for uploads/notifications and some authenticated calls, but the main workspace imports `mockData.ts` and stores businesses, catalog, requests, hours and team in React state/local storage. |
| Admin portal | `apps/admin-web` | Next.js 14 with relative `/api/v1` API client and protected moderation API helpers; analytics data constants are empty, and not every view is connected to DB-backed APIs. |
| Storage/proxy | Compose, `backend/internal/media`, Nginx | Local MinIO and S3-compatible Go client; Nginx routes API, web paths and media. Local Compose uses development defaults; staging config still points at MinIO. |
| Build/CI | `.github/workflows`, Dockerfiles | CI YAML exists but the actual workflow has configuration/dependency gaps described in the test and gap reports. Staging/production deploy workflow contains placeholder/inconsistent image steps. |

## Feature inventory

Status values follow the requested vocabulary. “Complete & verified” is reserved for source-backed behavior with an executed targeted test or reliable current evidence; a screen existing is not sufficient.

| Feature | Module | Status | Evidence | Priority |
|---|---|---|---|---|
| Splash/onboarding | Mobile | IMPLEMENTED, NOT VERIFIED | `apps/mobile/lib/core/screens/{splash_screen,onboarding_screen}.dart`; not part of targeted widget assertions beyond root build | Medium |
| Phone OTP | Mobile/API | PARTIALLY IMPLEMENTED | `backend/internal/auth/handlers.go`; local mode returns OTP in response; non-local fails closed. No SMS provider exists. | P0 |
| Session refresh/logout | API/mobile | PARTIALLY IMPLEMENTED | Auth handlers persist refresh hashes, but access JWTs are stateless and logout revokes by comparing access bearer to refresh hash; access tokens remain valid until expiry. | P0 |
| Role selection | Mobile/API | IMPLEMENTED, NOT VERIFIED | `role_selection_screen.dart`, `authProvider`; backend roles loaded after OTP; role-specific authorization still requires API checks. | High |
| Location selection/GPS | Mobile | PARTIALLY IMPLEMENTED | Explore/map and geolocator integrations; selected-city/radius filtering is present; user permissions, boundary quality and Play privacy disclosures are not verified. | High |
| Explore/discovery | Mobile/API/DB | IMPLEMENTED, NOT VERIFIED | `explore_screen.dart`, discovery service and city test documentation; source integration is live, but full authenticated emulator flow not rerun in this audit. | High |
| Categories | Mobile/API/DB | COMPLETE & VERIFIED | `categories_screen.dart`, discovery taxonomy API, `merchant_categories_test.dart`; Flutter suite passed. | High |
| Search/results | Mobile/API/DB | IMPLEMENTED, NOT VERIFIED | `search_results_screen.dart`, `Discovery.SearchBusinesses`; filter/radius behavior described in city automation; no focused search test rerun. | High |
| Nearby map | Mobile/API/DB | IMPLEMENTED, NOT VERIFIED | `nearby_map_screen.dart`, `Nearby`; uses live categories and city/radius results. Tile key is placeholder and map permission/device flow not verified. | High |
| Business profile/products/offers/reviews | Mobile/API/DB | PARTIALLY IMPLEMENTED | `business_detail_screen.dart`, detail/products/services/offers endpoints. Reviews are not backed by a review table/API and are explicitly unavailable. | High |
| Product details | Mobile/API | IMPLEMENTED, NOT VERIFIED | `product_detail_screen.dart`; product data comes from discovery API; no direct widget test found. | Medium |
| Professional profile | Mobile/API/DB | PARTIALLY IMPLEMENTED | `service_pro_screen.dart`, professional profile and services query; review aggregation and complete verified profile content are missing. | High |
| Service request submission | Mobile/API/DB | IMPLEMENTED, NOT VERIFIED | service request POST is authenticated; server validates business/service and optional slot, with database transaction/event behavior in `main.go`; targeted booking automation is documented but not rerun here. | P0 |
| Appointment scheduling | Mobile/API/DB | PARTIALLY IMPLEMENTED | `booking_scheduler_screen.dart`, persisted availability endpoint and slot counter transaction; no merchant API/UI to create/manage availability slots is exposed. | P0 |
| Saved businesses | Mobile/API/DB | IMPLEMENTED, NOT VERIFIED | favorites endpoints in discovery service and `saved_screen.dart`; no focused provider/widget persistence check in this audit. | Medium |
| Customer profile/settings | Mobile/API | PARTIALLY IMPLEMENTED | `profile_screen.dart`, `/me`; no customer data deletion endpoint. Privacy control UI is not evidence of a backend consent preference store. | P0 |
| Service request tracking | Mobile/API/DB | PARTIALLY IMPLEMENTED | `service_request_status_screen.dart` polls request endpoint, cancellation exists; events table is not exposed as timeline and timestamps/receipt/invoice remain unavailable. | High |
| Order history | Mobile/API/DB | IMPLEMENTED, NOT VERIFIED | `order_history_screen.dart`, `customer_orders_provider.dart`, `/customer/orders`; widget navigation fixture passed, but no live order record integration check rerun. | High |
| Food cart/checkout | Mobile/API/DB | IMPLEMENTED, NOT VERIFIED | `business_detail_screen.dart`, `operations.CreateOrder`; backend computes product amounts/fees. Payment/tax capture are not implemented. | High |
| Table reservation | Mobile/API/DB | PARTIALLY IMPLEMENTED | Persisted order_type endpoint and reservation fields exist. No table-slot/capacity calendar, so reservations are accepted based on capability and future date only. | High |
| Hotel booking | Mobile/API/DB | PARTIALLY IMPLEMENTED | Persisted order_type, room product and date range, backend total calculation. Room availability/inventory/overlap checks and payment are missing. | High |
| Delivery tracking | Mobile/API | UI ONLY / MOCKED | `order_tracking_screen.dart` now discloses courier location unavailable; no courier assignment/location feed/FCM. Order status API only supports merchant transitions. | Medium |
| Merchant registration/claim | Mobile/API/DB | UI ONLY / MOCKED | `merchant_registration_screen.dart`; `_submitRegistration` displays unavailable; claim success locally changes widget state and does not claim backend ownership. | P0 |
| Merchant workspace dashboard | Mobile/API/DB | UI ONLY / MOCKED | Mobile workspace uses API provider pieces, but action breadth and end-to-end role flow not fully verified; no subscription state. | High |
| Mobile merchant catalog CRUD | Mobile/API/DB | COMPLETE & VERIFIED | `merchant_catalog_screen.dart`, merchant endpoints; test suite passed and 38-category/city UI injection is documented as passed previously. | High |
| Mobile merchant category CRUD | Mobile/API/DB | COMPLETE & VERIFIED | `merchant_categories_screen.dart`, category endpoint, create/list/rename/delete and permission tests; suite passed. | High |
| Merchant hours/coverage | Mobile/API/DB | PARTIALLY IMPLEMENTED | Mobile provider reads and updates hours/coverage; empty schedule now requires explicit draft. Locality choices and actual customer coverage semantics are incomplete. | Medium |
| Notifications/SSE | Web/API | PARTIALLY IMPLEMENTED | `backend/internal/notifications/hub.go`, notification endpoints, merchant client authenticated fetch stream; native FCM integration is absent and broadcast/test route exists. | High |
| Merchant web login | Merchant/API | PARTIALLY IMPLEMENTED | OTP API use exists; token stored in `localStorage`; the main workspace still seeds state from mock data and session ownership is resolved from client-side fixtures. | P0 |
| Merchant web catalog/media | Merchant/API/DB/MinIO | PARTIALLY IMPLEMENTED | `CatalogManager.tsx`, upload helper and authenticated backend CRUD; main dashboard state and multi-module wiring remain disconnected. | High |
| Merchant web team/RBAC | Merchant/API/DB | PARTIALLY IMPLEMENTED | Backend member endpoints enforce owner authorization; TeamManager exists. Full browser E2E not executed, portal session data not yet consistently API-backed. | High |
| Admin authentication | Admin/API | PARTIALLY IMPLEMENTED | `/admin/session` and admin role middleware; portal stores bearer token in localStorage; credential/bootstrap setup and browser E2E were not verified. | P0 |
| Admin registry/KYC moderation | Admin/API/DB | PARTIALLY IMPLEMENTED | Backend pending/list/approve/reject/verify endpoints are DB-backed; admin frontend KYC constants are empty and some fields are presentation-only. | High |
| Admin reports/disputes/offers/audit | Admin/API/DB | PARTIALLY IMPLEMENTED | Go moderation endpoints and tables exist; portal pieces are mixed connected/local state; no browser E2E executed. | High |
| Admin analytics | Admin/API/DB | UI ONLY / MOCKED | `adminData.ts` analytics arrays are empty; several chart components expect static props/arrays, while backend stats only gives aggregate counts. | Medium |
| Merchant one-time registration fee | Merchant/API/DB | NOT IMPLEMENTED | No billing tables, payment endpoints, webhook or UI. | P0 |
| Merchant monthly/annual subscription | Merchant/API/DB | NOT IMPLEMENTED | No plans, subscription status, renewal, reminders or invoice entities. | P0 |
| Customer-paid marketplace checkout | N/A | NOT IMPLEMENTED | Out of scope for the stated merchant-funded model. | Post-launch |

## Verified versus unverified

Verified in this audit: `go test ./...` passed; Flutter widget suite passed (25 tests); all three Compose files parse with warnings; OpenAPI parses as YAML; prior local stack smoke evidence in `codex-implementation.md` says migration 011 was applied and `/api/v1/categories` returned 200. `flutter analyze` ran and reported 99 warnings/info findings, no errors; command exits nonzero because findings exist. Merchant/admin TypeScript checks fail because `@playwright/test` is missing from the installed package environment. Both Next production build attempts were started but could not complete in the available window (merchant attempted SWC package download; admin remained at build stage); no build pass is claimed.

Not verified in this audit: fresh database bootstrap through migration 011, end-to-end new customer reservation/order with live identity, merchant status updates from the web UI, owner/member isolation across all endpoints, media authorization against object storage, Playwright browser flows, emulator authenticated booking, Android release signing, backup restore, HTTPS production configuration, or any live payment/SMS/FCM.

## Known defects and technical debt

- Merchant web app's main state is initialized from `INITIAL_*` mock arrays and persisted browser session data, not consistently from backend IDs and authorized API state.
- Admin analytics arrays are empty; fallback API methods turn errors into zero/empty values, making service outages look like genuine zero activity.
- Auth code uses development OTP echo in local mode; refresh session hash handling uses bcrypt-generated hash strings, and access-token revocation is absent. Logout hashes the access token but sessions store refresh token hashes.
- Config has insecure development defaults and Compose exposes database, MinIO, API and Next ports directly.
- Migration SQL runs only when PostgreSQL creates its data directory. Existing databases need a reviewed, tracked migration runner; migration 010 has archival/destructive semantics and must never be casually replayed.
- Portal browser E2E tests depend on hard-coded OTP/account placeholders; installed `@playwright/test` dependency was absent in this audit environment.
- Merchant registration/claim, merchant subscription and account deletion are incomplete.
- Seed migrations contain demonstration/legacy cities and example records; the later city archive narrows active discovery but preserves historical migration provenance.
- Release build signs with the debug keystore; Maps key is a literal placeholder; app ID/label remain development branded.
- Some screens retain unused code/lint findings and API error fallbacks that hide operational details.
