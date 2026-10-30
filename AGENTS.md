# AGENTS.md — Grepmind Near

## Project identity

Grepmind Near is a local business and service discovery platform under the Grepmind brand. Everything nearby. One tap away.

## Reference UI kit

Screen-by-screen reference images live in `ref-image/`:
- Onboarding and location
- Explore home
- Search and results
- Nearby map
- Business profile
- Service request
- Saved businesses
- Merchant workspace
- Admin web portal
- Color palette
- Reusable components
- Sample UI design

These images define the premium 2026 visual direction: light-first interface, deep blue (#2457D6) primary, teal (#0F766E) discovery, Inter typography, consistent outline icons, real local business photography, minimal elevation, 16px card radius, 4px base spacing.

## Technology

- Android application: Flutter and Dart (Riverpod state, GoRouter navigation, Dio networking)
- Backend: Go REST API (chi router, pgx/sqlx, PostgreSQL + PostGIS)
- Merchant and admin portals: Next.js and TypeScript
- API contract: OpenAPI (`api/openapi.yaml`)
- Local development: Docker Compose

## Architectural rules

1. Modular monolith for the initial backend.
2. Flutter code organized by feature; presentation separate from networking and persistence.
3. Treat OpenAPI as the authoritative HTTP contract.
4. Parameterized SQL and database constraints.
5. Business rules in application services, not HTTP handlers.
6. Minimal dependencies; explain material additions.
7. No microservices, Redis, Kafka, Kubernetes, or vector DBs without approved requirement.
8. No manual API schema duplication when generation is practical.
9. Versioned, reviewable database migrations.
10. Preserve existing behaviour unless explicitly authorized.

## Security rules

1. Enforce authorization and ownership on the backend.
2. Never trust client-supplied roles, verification status, price totals, or booking status.
3. Never commit secrets or log OTPs, access tokens, or sensitive location data.
4. Validate input and enforce bounded query parameters.
5. Use transactions for atomic operations.
6. Tests for unauthorized access and invalid state transitions.
7. Keep customer location data to the minimum required.

## UI rules

1. Follow documented design tokens and screen specifications.
2. Reuse existing design-system components.
3. Loading, empty, error and success states on every API-driven screen.
4. Accessible text scaling and screen readers.
5. Usable touch targets on Android (min 48 dp).
6. Never fabricate availability, verification, inventory, ratings or offers.
7. Clearly label sponsored content.
8. Responsive and performant on lower-end devices.

## Workflow

1. Inspect relevant code and documentation before editing.
2. Summarize planned changes for nontrivial tasks.
3. Smallest complete change satisfying the task.
4. Add or update tests.
5. Run formatters, static checks and tests.
6. Review diff for security, compatibility and unintended changes.
7. Report modified files, test results, assumptions and outstanding risks.

## Prohibited without explicit approval

- Deploying to production.
- Destructive production database commands.
- Rotating or exposing credentials.
- Rewriting shared API contracts or database history without migration plan.
- Adding substantial new infrastructure.
- Removing tests or weakening security controls to obtain a passing build.

## Completion standard

Do not claim success unless checks were actually executed. If a check cannot run, report it clearly.

## Implementation task template

Implement the following task for Grepmind Near:

TASK:
[One narrowly scoped feature or engineering task]

AUTHORITATIVE DOCUMENTS:
- AGENTS.md
- Relevant product specification
- Relevant screen specification
- api/openapi.yaml
- Relevant architecture and database documents

CONSTRAINTS:
- Preserve existing architecture.
- Do not implement unrelated features.
- Do not add dependencies without explaining why.
- Do not change public API contracts without approval.
- Use parameterized SQL and enforce authorization.
- Include appropriate tests and error handling.

PROCESS:
1. Inspect existing implementation and relevant documents.
2. Identify dependencies, assumptions and affected files.
3. Implement smallest complete vertical slice.
4. Add or update automated tests.
5. Run formatters, static analysis and tests.
6. Review diff for regressions and security issues.
7. Update documentation if behaviour changes.

FINAL REPORT:
- Summary of changes.
- Files created or modified.
- Tests actually executed and their results.
- Decisions or assumptions made.
- Known limitations and remaining risks.
- Recommended next task.

## 22-Screen UI Showcase Implementation Status

Authoritative showcase reference: `Grepmind Near UI_UX App Showcase.png`.

| # | Screen Name | Status | Location / Implementation Details |
|---|---|---|---|
| **1** | Splash Screen | ✅ Complete | `apps/mobile/lib/core/screens/splash_screen.dart` |
| **2** | Onboarding Carousel | ✅ Complete | `apps/mobile/lib/core/screens/onboarding_screen.dart` |
| **3** | Phone OTP Authentication | ✅ Complete | `apps/mobile/lib/core/screens/onboarding_screen.dart` (integrated flow) |
| **4** | Location Selection Modal | ✅ Complete | `apps/mobile/lib/core/screens/explore_screen.dart` (GPS & city picker sheet) |
| **5** | City / Locality Selection | ✅ Complete | Integrated in Location sheet modal |
| **6** | Location Permission Welcome | ✅ Complete | Modal permission primer in onboarding |
| **7** | Home / Explore Screen | ✅ Complete (Verified) | `apps/mobile/lib/core/screens/explore_screen.dart` (Hero banner, category chips, nearby business cards) |
| **8** | Categories Directory | ✅ Complete (Verified) | `apps/mobile/lib/core/screens/categories_screen.dart` (18 categories, search, section filter tabs) |
| **9** | Search & Filter Results | ✅ Complete (Verified) | `apps/mobile/lib/core/screens/search_results_screen.dart` (radius sheet, sort sheet, verified/open chips, empty recovery) |
| **10** | Nearby Interactive Map | ✅ Complete (Verified) | `apps/mobile/lib/core/screens/nearby_map_screen.dart` (Category chips, interactive radar canvas with concentric rings, interactive marker selection, bottom preview card with directions & view profile) |
| **11** | Business Profile & Tabs | ✅ Complete (Verified) | `apps/mobile/lib/core/screens/business_detail_screen.dart` (Hero cover, About, Products, Offers, Reviews) |
| **12** | Product Details Screen | ✅ Complete (Verified) | `apps/mobile/lib/core/screens/product_detail_screen.dart` (Pricing, discount, specs, store card, dual CTAs) |
| **13** | Service Professional Profile | ✅ Complete (Verified) | `apps/mobile/lib/core/screens/service_pro_screen.dart` (Experience badges, verified badge, services, rates, coverage, reviews) |
| **14** | Service Request Submission | ✅ Complete (Verified) | `apps/mobile/lib/core/screens/service_request_screen.dart` (Service dropdown, description, date/time) |
| **15** | Appointment Slot Scheduler | ✅ Complete (Verified) | `apps/mobile/lib/core/screens/booking_scheduler_screen.dart` (Pro profile header, scope & duration chips, 14-day date strip, morning/afternoon/evening time slots, notes & location, booking receipt confirmation sheet) |
| **16** | Saved / Bookmarked Businesses | ✅ Complete | `apps/mobile/lib/core/screens/saved_screen.dart` |
| **17** | Customer Profile & Settings | ✅ Complete | `apps/mobile/lib/core/screens/profile_screen.dart` |
| **18** | Service Request Status Tracker| ✅ Complete (Verified) | `apps/mobile/lib/core/screens/service_request_status_screen.dart` (Live timeline, pro contact card, receipt summary, cancel modal) |
| **19** | Merchant Registration / Claim | ✅ Complete (Verified) | `apps/mobile/lib/core/screens/merchant_registration_screen.dart` (4-step onboarding wizard, category picker, tax/artisan toggle, GPS locking, claim existing listing & OTP modal sheet) |
| **20** | Merchant Workspace Dashboard | ✅ Complete (Verified) | `apps/mobile/lib/core/screens/merchant_workspace_screen.dart` (Dashboard, stats, request management, quick actions) |
| **21** | Merchant Catalog Management | ✅ Complete (Verified) | `apps/mobile/lib/core/screens/merchant_catalog_screen.dart` (Products/Services tabs, stock status chips, search & filter, add/edit modals) |
| **22** | Merchant Hours & Coverage Setup| ✅ Complete (Verified) | `apps/mobile/lib/core/screens/merchant_hours_coverage_screen.dart` (7-day schedule, time pickers, radius slider, localities tags, on-demand toggle) |

### UI Showcase Milestone
- **All 22 screens** from the authoritative `Grepmind Near UI_UX App Showcase.png` are 100% implemented and verified end-to-end with the Go REST API backend and Android emulator!

### Merchant Desktop & Multi-User Access Management Milestone
- **Option 2 (Merchant Desktop Web Portal `apps/merchant-web`)**:
  - Containerized with Next.js 14 multi-stage Docker build on port 3001.
  - Reverse proxied through Nginx via `/merchant/` and virtual host `merchant.near.grepmind.com`.
  - Built-in multi-branch switcher, live bookings pipeline, catalog management, operating hours, and radius setup.
- **Merchant Team & Multi-User Access Control (RBAC)**:
  - Database: `business_members` table linking `users` with `businesses` with roles: `owner`, `manager`, `staff`.
  - Backfilled existing store owners as primary owners.
  - Endpoints: `GET /api/v1/merchant/businesses/{id}/members`, `POST /api/v1/merchant/businesses/{id}/members`, `DELETE /api/v1/merchant/businesses/{id}/members/{userId}`.
  - Security: Backend-enforced authorization ensuring only owners can invite/revoke members; protected store owners against deletion.
  - Web UI: Added "Team & Staff" tab in `apps/merchant-web` with hierarchy banner, member cards, and "+ Add Team Member" modal with phone OTP delegation.
- **Merchant-Level Data Isolation & Authentication Gateway**:
  - Gated workspace behind passwordless Phone OTP verification (`AuthLoginView.tsx`).
  - Unauthenticated visitors cannot access or view any merchant dashboard, orders, or inventory.
  - Upon authentication, strictly scopes accessible stores to those owned by the phone number or registered in `business_members`.
  - Zero cross-store leakage: customer requests, catalog items, team members, and operating hours are scoped strictly by `business_id`.
  - First-time merchant onboarding modal allows direct storefront registration from the web portal.
### Admin Web Portal & Operational Analytics Milestone
- **Option 3 (Admin Web Portal `apps/admin-web`)**:
  - Containerized with Next.js 14 multi-stage Docker build on port 3000.
  - Reverse proxied via Nginx path routing `http://localhost/admin/` and virtual host `admin.near.grepmind.com`.
  - Design adheres to 2026 Reference UI Kit (`ref-image/Admin web portal.png`): light-first interface, deep blue (`#2457D6`) primary, teal (`#0F766E`) accent, 16px card radius, Inter typography.
- **Graphical Metrics View & Analytics Engine**:
  - Multi-Series SVG Area Chart: Tracks daily service inquiry volume vs completed jobs vs cancellations with gradient fills and hover tooltip.
  - Comparative Multi-City Grouped Bar Chart: Direct comparative metrics between Bhubaneswar, Cuttack, Puri, and Jajpur across request volume and GMV revenue.
  - Category Volume Share Donut Chart: Trade breakdown across Electrical, AC & Refrigeration, Plumbing, Medical, Salon, and Handloom with animated segments and center volume display.
  - Diurnal Peak Hourly Booking Distribution: 08:00 to 22:00 histogram with morning and evening surge indicators.
  - Unserved Location Demand Radar: Real-time expansion alert cards tracking unfulfilled customer searches in Puri Sea Beach, Cuttack Chauliaganj, and Bhubaneswar Infovalley.
- **Merchant Listing Verification & KYC Moderation**:
  - Interactive KYC review queue for pending applications across Bhubaneswar, Cuttack, and Puri.
  - `KYCReviewModal`: Inspects Trade Licenses, Artisan Board registrations, Clinical Establishment certificates, and MSME Udyam credentials with simulated digital certificate stamp and compliance checklist.
  - Endpoints integrated: `POST /api/v1/admin/businesses/{id}/verify`, `POST /api/v1/admin/businesses/{id}/approve`, `POST /api/v1/admin/businesses/{id}/reject`.
- **Compliance, Disputes & Audit Trail**:
  - Dispute resolution center for customer/merchant tickets (`POST /api/v1/admin/reports/{id}/resolve`).
  - Immutable audit trail (`GET /api/v1/admin/audit-logs`) logging all administrative approvals, verifications, and notes to PostgreSQL.
- **Admin Access Control (RBAC) & Portal Data Pipeline Resolution**:
  - Unified Go REST API endpoints: `GET /api/v1/admin/admins`, `POST /api/v1/admin/admins`, `DELETE /api/v1/admin/admins/{userId}` protected by `requireAdmin` middleware.
  - New "Admins & Access" management view in `apps/admin-web`: list of active admins, root superadmin protection (`+910000000000`), and "+ Add Platform Admin" modal.
  - Same-origin API routing: Switched `api.ts` to relative `/api/v1` eliminating CORS blocks through Nginx reverse proxy.
  - Multi-city and locality filtering in Merchant Registry with live counts (`14 of 14`).
  - Full data rendering verified across Merchant Registry (14 stores), Reports & Disputes (2 tickets), Offers & Promos (4 campaigns), and Audit Trail (4 immutable logs).

### Direct Photo Upload to MinIO Milestone
- **Option 4 (Object Storage & Direct Media Upload)**:
  - Database: Applied `backend/migrations/006_media_uploads.sql` (`media_uploads` tracking table).
  - Go Backend: MinIO S3 integration (`backend/internal/media/service.go`) using `minio-go/v7@v7.0.66` (compatible with Go 1.22 in Docker).
  - Automatic bucket provisioning: Automatically verifies and creates bucket `grepmind-near` and attaches a public read policy (`s3:GetObject`).
  - Endpoints: `POST /api/v1/media/upload` (multipart with MIME validation, 10MB limit, timestamped UUID keying) and `GET /api/v1/media` (list media by purpose).
  - Reverse Proxy: Nginx proxies `/media/` directly to `http://minio:9000/grepmind-near/`.
  - API Contract: Documented in `api/openapi.yaml` under `media` tag.
  - Flutter Mobile: Added `uploadMedia` helper in `ApiClient` (`apps/mobile/lib/core/network/api_client.dart`).
  - Merchant Web Portal: Added `uploadMediaFile` in `apps/merchant-web/lib/api.ts` and interactive photo upload dropzone with preview thumbnail in `CatalogManager.tsx`.
  - Verification: Verified end-to-end multipart upload (HTTP 201 Created), direct Nginx image retrieval (HTTP 200 OK), and live modal UI rendering in the browser.

### Push Notifications & Real-Time Booking Updates Milestone
- **Option 5 (Server-Sent Events & Live Booking Updates)**:
  - Database: Applied `backend/migrations/007_realtime_events_and_request_stages.sql` updating `service_requests.status` check constraint (`in_progress`, `rescheduled`) and adding `notifications` table with multi-column indexes.
  - Go Backend: Built SSE hub (`backend/internal/notifications/hub.go`) using standard library `http.Flusher` (zero external dependencies).
  - Endpoints: `GET /api/v1/events?business_id=...&request_id=...`, `GET /api/v1/notifications`, `POST /api/v1/notifications/{id}/read`, and `POST /api/v1/notifications/broadcast-test`.
  - Nginx Proxy: Enabled streaming proxy with `proxy_buffering off;`, `proxy_cache off;`, and `proxy_read_timeout 3600s;`.
  - Merchant Web Portal:
    - Real-time `EventSource` subscription scoped to active storefront.
    - Web Audio API dual-tone chime (`playBookingChime()`) on incoming booking.
    - Real-time floating booking banner with instant "Inspect Booking" action.
    - Notification Bell in `Header.tsx` with unread badge counter, alert dropdown, and mark-as-read.
  - Mobile App (`apps/mobile`):
    - Added periodic live status polling in Screen 18 (`service_request_status_screen.dart`) with auto-cancel on final state.
  - API Contract: Documented in `api/openapi.yaml` under `notifications` tag.
  - Verification: Verified end-to-end event broadcast (HTTP 200 SSE text/event-stream), PostgreSQL notification persistence, and browser UI rendering.

### Hospitality, Hotels & Food Delivery Expansion Milestone
- **Food Home Delivery & Multi-Item Ordering**:
  - Database: Applied `backend/migrations/008_hospitality_and_food_delivery.sql` adding `delivery_enabled`, `delivery_time_mins`, `delivery_fee`, `min_order_amount`, `table_booking_enabled`, `room_booking_enabled`, `amenities` to `businesses` and `dietary_type`, `food_category`, `preparation_time_min` to `products`.
  - Go Backend: Extended `Business` and `Product` structs, updated `GetBusiness` to scan hospitality/amenity metadata and `ListProducts` to return dietary and food courses. Rebuilt and verified `grepmind_api` container.
  - Mobile Models (`apps/mobile/lib/core/models/business.dart`): Added delivery, booking, amenity properties and `isVeg` / `isNonVeg` getters to `Business` and `Product`.
  - Categories Directory (`apps/mobile/lib/core/screens/categories_screen.dart`): Added `hotel` ("Hotels & Stays") with `Icons.hotel_rounded` and Teal styling.
  - Business Detail Screen (`apps/mobile/lib/core/screens/business_detail_screen.dart`):
    - Replaced one-size-fits-all handyman button with dynamic category-aware bottom bars:
      - Restaurants & Cafes: Dual **"🛵 Order Delivery"** & **"🍽️ Reserve Table"** CTAs.
      - Hotels & Stays: Dual **"🏨 Book Stay / Room"** & **"📞 Call Desk"** CTAs.
      - Trades / Handyman: **"🔧 Request Service"**.
    - Food Menu Tab with course filtering pills (`All`, `Starters`, `Main Course`, `Breads & Rice`, `Desserts`, `Beverages`) and `🟢 Veg Only` toggle.
    - Dish cards with green 🟢 Veg / red 🔴 Non-Veg dietary markers, preparation time badges, descriptions, and interactive `+ ADD` / `[-] qty [+]` controls.
    - Sticky Floating Cart Bar: Displays real-time item count, total price, and "View Cart & Order" CTA.
    - Interactive Food Home Delivery & Checkout Sheet: Home Delivery vs. Takeaway toggle, delivery address, cooking notes, bill summary (Item total, Delivery fee, Taxes), order placement with SSE broadcast trigger and Order Confirmed celebration sheet.
    - Interactive Table Reservation Sheet: Guest count selector (1–8+), dining date, lunch/dinner time slots, seating area selection (Indoor AC, Rooftop, Garden), and confirmed table voucher dialog.
    - Interactive Hotel Room Booking Sheet: Check-in/Check-out stay duration, guest count, room tier selection, amenities showcase, and confirmed stay voucher dialog.
    - Seed Data: Seeded 8 authentic Odia & Mughlai dishes for *Spice Garden Restaurant* (Bhubaneswar) and luxury 5-star beachfront *Mayfair Coastal Lagoon & Resort* (Puri) with 3 room tiers.
    - Verification: `flutter analyze` 100% clean with zero errors, zero warnings.

### Phase 6 — Automated E2E Testing & CI/CD Pipeline
- **Option 6 (Automated End-to-End Integration Testing & CI/CD)**:
  - **Flutter Integration Tests**: `apps/mobile/integration_test/grepmind_e2e_test.dart` — OTP auth, search, service request, order history, merchant registration flows
  - **Go Backend Tests**: `backend/tests/auth_test.go` — JWT token issuance, expiry, invalid secret token validation (3 tests passing)
  - **Next.js Web Portal Tests**: `apps/merchant-web/e2e/merchant.workspace.spec.ts` and `apps/admin-web/e2e/admin.workspace.spec.ts` — Playwright E2E tests
  - **CI/CD Pipeline**: `.github/workflows/ci.yml` — Automated testing pipeline for Flutter, Go, and Next.js
  - **Deployment Pipeline**: `.github/workflows/deploy.yml` — Staging and production deployment pipeline
  - **Security Scanning**: `.github/workflows/security.yml` — SAST (Trivy), DAST (OWASP ZAP), dependency scanning
  - **Load Testing**: `load-test/k6-load-test.js` — Load testing with k6
  - **Docker Compose Test Stack**: `docker-compose.test.yml` — Isolated test environment (postgres, minio, api)
  - **Docker Compose Staging Stack**: `docker-compose.staging.yml` — Staging environment deployment
  - **Verification**: All services deployable, tests runnable via `docker compose -f docker-compose.test.yml up -d`

### Hospitality, Hotels & Food Delivery Expansion Milestone
- **Food Home Delivery & Multi-Item Ordering**:
  - Database: Applied `backend/migrations/008_hospitality_and_food_delivery.sql` adding `delivery_enabled`, `delivery_time_mins`, `delivery_fee`, `min_order_amount`, `table_booking_enabled`, `room_booking_enabled`, `amenities` to `businesses` and `dietary_type`, `food_category`, `preparation_time_min` to `products`.
  - Go Backend: Extended `Business` and `Product` structs, updated `GetBusiness` to scan hospitality/amenity metadata and `ListProducts` to return dietary and food courses. Rebuilt and verified `grepmind_api` container.
  - Mobile Models (`apps/mobile/lib/core/models/business.dart`): Added delivery, booking, amenity properties and `isVeg` / `isNonVeg` getters to `Business` and `Product`.
  - Categories Directory (`apps/mobile/lib/core/screens/categories_screen.dart`): Added `hotel` ("Hotels & Stays") with `Icons.hotel_rounded` and Teal styling.
  - Business Detail Screen (`apps/mobile/lib/core/screens/business_detail_screen.dart`):
    - Replaced one-size-fits-all handyman button with dynamic category-aware bottom bars:
      - Restaurants & Cafes: Dual **"🛵 Order Delivery"** & **"🍽️ Reserve Table"** CTAs.
      - Hotels & Stays: Dual **"🏨 Book Stay / Room"** & **"📞 Call Desk"** CTAs.
      - Trades / Handyman: **"🔧 Request Service"**.
    - Food Menu Tab with course filtering pills (`All`, `Starters`, `Main Course`, `Breads & Rice`, `Desserts`, `Beverages`) and `🟢 Veg Only` toggle.
    - Dish cards with green 🟢 Veg / red 🔴 Non-Veg dietary markers, preparation time badges, descriptions, and interactive `+ ADD` / `[-] qty [+]` controls.
    - Sticky Floating Cart Bar: Displays real-time item count, total price, and "View Cart & Order" CTA.
    - Interactive Food Home Delivery & Checkout Sheet: Home Delivery vs. Takeaway toggle, delivery address, cooking notes, bill summary (Item total, Delivery fee, Taxes), order placement with SSE broadcast trigger and Order Confirmed celebration sheet.
    - Interactive Table Reservation Sheet: Guest count selector (1–8+), dining date, lunch/dinner time slots, seating area selection (Indoor AC, Rooftop, Garden), and confirmed table voucher dialog.
    - Interactive Hotel Room Booking Sheet: Check-in/Check-out stay duration, guest count, room tier selection, amenities showcase, and confirmed stay voucher dialog.
    - Seed Data: Seeded 8 authentic Odia & Mughlai dishes for *Spice Garden Restaurant* (Bhubaneswar) and luxury 5-star beachfront *Mayfair Coastal Lagoon & Resort* (Puri) with 3 room tiers.
    - Verification: `flutter analyze` 100% clean with zero errors, zero warnings.
