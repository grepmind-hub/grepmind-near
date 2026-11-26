# AGENTS.md — Abashyaka

## Project identity

Abashyaka is a local business and service discovery platform under the Grepmind brand. Everything nearby. One tap away.


## Abashyaka Official Mobile UI Design Standard

All Flutter UI implementation and visual modifications must follow the approved Abashyaka Premium UI Design System.

Design language:

Metallic Teal Abstract Fluid Wave + Pearl White Glossy UI.

Required references:

- `docs/design/ABASHYAKA_MOBILE_AGENT_GUIDE.md`
- `docs/design/ABASHYAKA_UI_DESIGN_SYSTEM.md`
- `docs/design/ABASHYAKA_CATEGORY_TAXONOMY_V2.0.md`
- `docs/build/BUILD_COMMANDS.md`
- `docs/design/reference/premium_five_screens.png`
- `docs/design/reference/Abashyaka Choose Your Role Screen.png`

Read these references before implementing or modifying mobile UI screens.

Use the centralized theme, colour tokens, spacing tokens, reusable premium headers, fluid-wave painters, glossy buttons and shared UI components.

Do not independently introduce new colours, design systems, fonts, navigation patterns or expensive visual effects without approval.

Preserve all existing authentication logic, API contracts, providers, authorization, user data and business functionality.

Prioritize lightweight Flutter rendering and validate performance on representative Android hardware.

All visual changes must be tested and compared with the approved reference design.

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

## Mandatory multi-emulator agent validation rule

Applies to all current and future implementation phases, regression testing, release preparation, and end-to-end acceptance. Every Codex agent must follow this rule. It supersedes older instructions that permit Customer, Merchant, or Rider UI validation to be skipped.

### Dedicated role assignments

#### Customer

- AVD: `Pixel_8`; expected serial: `emulator-5560`.
- Use this emulator exclusively for Customer validation and authenticate with an authorized synthetic Customer QA identity.
- Validate Customer screens, checkout, orders, payments, refunds, delivery tracking, notifications, and profile changes.
- Backend/API tests do not replace Customer UI acceptance.

#### Merchant

- AVD: `Pixel_8_Merchant_QA`; expected serial: `emulator-5558`.
- Use this emulator exclusively for Merchant Android validation and authenticate with an authorized synthetic Merchant QA identity.
- Merchants operate primarily through Android. Validate the Merchant workspace, order acceptance, preparation, ready-for-pickup, catalog, notifications, role permissions, and read-only earnings/payable/settlement screens when available.
- Merchant Web is complementary. Validate it using the same synthetic business when relevant, but merchants must not be required to use the web portal to view financial information.

#### Rider

- AVD: `Pixel_8_Rider_QA`; expected serial: `emulator-5556`.
- Use this emulator exclusively for Rider validation and authenticate with an authorized synthetic Rider QA identity.
- Validate availability, assignment, pickup verification, customer handover, COD collection, cash liability, remittance, delivery history, and notifications.
- Customer or Merchant emulator sessions cannot substitute for Rider validation.

#### Admin

- Platform: web browser only.
- Authenticate with an authorized synthetic Admin identity. Finance is an Admin permission/workflow duty, not a fifth application role.
- Validate dispatch, finance review, settlement simulation, reconciliation, permissions, and audit history.
- Do not use an Android emulator for Admin validation.

### Emulator identity verification

Before installation or login:

1. Run `adb devices -l`.
2. Query the AVD name for each emulator serial.
3. Confirm each mapping matches the role assignments above.
4. If serials changed, identify the correct AVD by name; do not assume serial numbers are permanent.
5. Record the actual serial-to-AVD mapping in the QA report.
6. Never install or operate against an unidentified emulator.

### Mandatory APK installation

All debug and QA validation APKs must be built using the authoritative command below. Missing parameters will break backend API connectivity and FCM push OTP delivery:

```bash
cd /mnt/d/grepmind-near/apps/mobile && /home/grepmind/projects/flutter-setup/develop/flutter/bin/flutter build apk --debug --no-pub --flavor development --dart-define=API_BASE_URL=https://api.abashyaka.com --dart-define=FCM_TEST_OTP_ENABLED=true --dart-define=GOOGLE_SERVER_CLIENT_ID=666331814501-v2vtkg0t27b5ld6edavtqkm8dlkr94l3.apps.googleusercontent.com
```

Whenever a new debug APK is built for validation:

1. Compute and record its SHA-256.
2. Install the same APK build on all three assigned emulators.
3. Verify installation succeeds on each emulator and verify installed package/build identity.
4. Launch the app on each emulator and confirm it reaches the expected role/login state.
5. Authenticate with the assigned role and record the APK hash and actual emulator serials.
6. Do not claim all-emulator validation if any installation or login failed.

If no APK was built in a phase, confirm whether the installed build is compatible with the isolated QA API and current backend contract.

### Mobile-first acceptance

For every relevant phase, validate Customer Android, Merchant Android, Rider Android, Merchant Web Portal, Admin Web Portal, and PostgreSQL/API/ledger reconciliation. Interleave the order where the lifecycle requires it, but do not omit any affected Android role. Every affected role must be authenticated and tested through its assigned surface.

### Isolated QA authentication

Use the existing secure QA OTP delivery mechanism and synthetic allowlisted QA identities. Preserve OTP expiry, replay protection, and rate limits. Reuse authenticated sessions when safe to avoid unnecessary OTP requests.

Never return OTPs in ordinary API responses, print OTPs in application logs, use fixed universal OTPs, disable OTP verification, bypass login with fabricated JWTs, or use production Customer identities. If an authorized login cannot be completed without weakening these protections, stop and report PARTIAL/BLOCKED. Exception for local QA troubleshooting only: the Admin PowerShell Playwright wrapper may display a fresh, challenge-bound OTP in the invoking terminal when the operator explicitly selects `-ManualEntry -Headed`; this is never the default, is limited to the isolated QA reader and synthetic allowlisted account, and must not be copied into application logs, screenshots, reports, or shared transcripts.

### Shared environment protection

Use isolated QA databases and APIs for migrations not applied to shared services. Never point a QA APK at an incompatible shared API or apply unapproved migrations to shared or production databases. Preserve unrelated emulator application data and shared containers; clean up only QA-owned resources.

### Acceptance evidence

Record actual emulator serial/AVD mapping, APK SHA-256, Customer login and screenshots, Merchant Android login and screenshots, Rider login and screenshots, Merchant Web Portal evidence, Admin Web Portal evidence, same-order references, backend/PostgreSQL reconciliation, executed test commands/results, blockers, and known limitations.

Do not report full PASS when required authenticated role validation is missing.

### Stop conditions

Stop and report PARTIAL if a required emulator cannot be identified, APK installation fails on a required emulator, required role login fails, a role is validated only through API calls when Android UI acceptance is required, QA OTP security would need to be weakened, shared/production migrations would be required, a financial transaction cannot be reconciled, or real money/payout functionality would be activated.

## Prohibited without explicit approval

- Deploying to production.
- Destructive production database commands.
- Rotating or exposing credentials.
- Rewriting shared API contracts or database history without migration plan.
- Adding substantial new infrastructure.
- Removing tests or weakening security controls to obtain a passing build.

## Completion standard

Do not claim success unless checks were actually executed. If a check cannot run, report it clearly.

## Phase execution and approval gates

- Phase records and current approval boundaries are maintained in `docs/phases/README.md`; phase evidence must distinguish implemented, tested, blocked, and planned work.
- Phase 0 repository audit and Phase 0B runtime baseline are historical records. Recheck current source and runtime before reusing any finding.
- Phase 1 Unified Customer/Merchant/Rider navigation passed its documented validation on 6 November 2026. This does not imply that every historic screen inventory workflow is production-ready.
- Phase 2A commerce audit/design was accepted. Phase 2B/2C and Phase 2D implementation records describe the earlier business-selected merchant-menu ordering model; those files are historical evidence and must not be rewritten as platform-catalog work. Phase 2R's Grepmind-owned catalog direction is accepted and documented in `docs/phases/PHASE_2_ARCHITECTURE_CORRECTION_PLATFORM_CATALOG.md`. Phases 2R.1–2R.4 passed for their documented scopes; see their phase reports. Migrations 023 and 024 remain unapplied to the shared development database. The Flutter analyzer baseline is 18 diagnostics (3 warnings, 15 infos); the latest full analysis attempt timed out, so do not assume the count remains unchanged. Run Go/Flutter commands from the user's interactive Windows-host PowerShell using plain `wsl` to enter Ubuntu. Do not invoke WSL through the sandboxed command bridge: it may return `Wsl/Service/E_ACCESSDENIED` even when interactive host PowerShell works. Phase 2E is approved; see the current acceptance status below.
- The accepted platform-commerce direction is a Grepmind-owned customer catalog with explicit local-partner mappings and server-side one-partner fulfillment. Preserve existing `customer_orders` / `customer_order_items` for legacy orders, table reservations, and hotel bookings; extend them compatibly instead of introducing a competing legacy order model.
- Customer online payment collection and claims that an order is paid remain out of scope through Phase 2. The approved payment roadmap is Phase 4: sandbox integration only after Phase 4A design review, with server-side provider verification. Phase 4A-Build, Phase 4B-A, and Phase 4B-B passed isolated QA; migrations 030–034 remain unapplied to shared development/production. Real-money activity, COD cash handling, merchant transfers, and rider payouts remain disabled during Phase 4 implementation and QA; see `docs/phases/README.md` and the corresponding Phase 4 reports.
- Keep each Phase 2 subphase independently reviewable and validated. Stop at each stated gate; do not start a later subphase automatically.
- Never treat older changelog claims, design mockups, QA fixtures, or local database counts as proof of current behavior. Cite actual files, executed commands, and runtime evidence. Phase 3F Rider Earnings is PASS for isolated QA only; migration 028 remains unapplied to shared development/production and real compensation/payouts remain disabled. Phase 3G-A is complete as a documentation/source audit; Phases 3G-B/C/D passed their documented isolated-QA scopes; migration 029 remains unapplied to shared development/production. No Phase 3 acceptance authorizes production recovery, customer payments/COD, payouts, GPS/ETA, or real compensation activation. Phase 4A design, 4A-Build, 4B-A, 4B-B, 4B-C, 4C and 4D passed their documented isolated-QA scopes. Phase 4C used synthetic QA only; migration 034 remains unapplied to shared development/production, and no physical cash or real-money transaction occurred. Phase 4D is PASS for isolated QA: both ₹220 UPI/COD payable batches were simulated and reconciled with balanced journals, and Merchant Web/Android read-only finance views matched; migrations 035/037 remain unapplied to shared/production and no real funds moved. Phase 4E.1–4E.3 passed their documented isolated-QA gates (G1, G2 and G3). Phase 4E.4 passed G4-B and its hardening suite for isolated QA. G4-C production provider activation remains disabled and unauthorized. G1's decision remains: backend may determine payable eligibility, but actual posting is explicit Admin `finance.post`; do not auto-post or add a fifth Finance role. The 30-race matrix was not executed as a whole; cite gate-specific executed scenarios only. Phase 3H remains deferred. Phase 5B is authorized for read-only Merchant/Rider Android settlement visibility only; no payout action, live money movement, migration, or additional application role is authorized. See `docs/phases/README.md` and the phase reports.

## Implementation task template

Implement the following task for Abashyaka:

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

Authoritative showcase reference: `Abashyaka UI_UX App Showcase.png`.

| # | Screen Name | Status | Location / Implementation Details |
|---|---|---|---|
| **1** | Splash Screen | ✅ Complete | `apps/mobile/lib/core/screens/splash_screen.dart` |
| **2** | Onboarding Carousel | ✅ Complete | `apps/mobile/lib/core/screens/onboarding_screen.dart` |
| **3** | Phone OTP Authentication | ✅ Complete | `apps/mobile/lib/core/screens/onboarding_screen.dart` (integrated flow) |
| **4** | Location Selection Modal | ✅ Complete | `apps/mobile/lib/core/screens/explore_screen.dart` (GPS & city picker sheet) |
| **5** | City / Locality Selection | ✅ Complete | Integrated in Location sheet modal |
| **6** | Location Permission Welcome | ✅ Complete | Modal permission primer in onboarding |
| **7** | Home / Explore Screen | ✅ Complete (Verified) | `apps/mobile/lib/core/screens/explore_screen.dart` (Hero banner, category chips, nearby business cards) |
| **8** | Categories Directory | ✅ Complete (Verified) | `apps/mobile/lib/core/screens/categories_screen.dart` (19 taxonomy entries in the audited local database, search, section filter tabs) |
| **9** | Search & Filter Results | ✅ Complete (Verified) | `apps/mobile/lib/core/screens/search_results_screen.dart` (radius sheet, sort sheet, verified/open chips, empty recovery) |
| **10** | Nearby Interactive Map | ✅ Complete (Verified) | `apps/mobile/lib/core/screens/nearby_map_screen.dart` (18 category nature badges, domain-specific CTAs such as Book Ride / Book Appointment / Enquire Now / Book Service, interactive radar canvas with concentric rings and sweep beam, synchronized list & radar filtering, premium wave background art) |
| **11** | Business Profile & Tabs | ✅ Complete (Verified) | `apps/mobile/lib/core/screens/business_detail_screen.dart` (Hero cover with role_selection_background.webp, dynamic nature badges, About, Products, Offers, interactive user review submission modal, verified reviews count increment) |
| **12** | Product Details Screen | ✅ Complete (Verified) | `apps/mobile/lib/core/screens/product_detail_screen.dart` (Pricing, discount, specs, store card, dual CTAs) |
| **13** | Service Professional Profile | ✅ Complete (Verified) | `apps/mobile/lib/core/screens/service_pro_screen.dart` (Experience badges, verified badge, services, rates, coverage, reviews) |
| **14** | Service Request Submission | ✅ Complete (Verified) | `apps/mobile/lib/core/screens/service_request_screen.dart` (Service dropdown, description, date/time) |
| **15** | Appointment Slot Scheduler | ✅ Complete (Verified) | `apps/mobile/lib/core/screens/booking_scheduler_screen.dart` (Pro profile header, scope & duration chips, 14-day date strip, morning/afternoon/evening time slots, notes & location, booking receipt confirmation sheet) |
| **16** | Saved / Bookmarked Businesses | ✅ Complete (Verified) | `apps/mobile/lib/core/screens/saved_screen.dart` (2026 Premium Obsidian tokens, fluid-wave header art, category nature badge chips, context-aware CTAs, explore recommendations empty state) |
| **17** | Customer Profile & Settings | UI polish complete. Customer screen verified. Role acceptance partial. | [Screen 17 validation](docs/design/SCREEN_17_CUSTOMER_PROFILE_VALIDATION.md) |
| **18** | Service Request Status Tracker | UI polish complete. Widget checks passed. Live tracker acceptance partial. | [Screen 18 validation](docs/design/SCREEN_18_SERVICE_REQUEST_STATUS_VALIDATION.md) |
| **19** | Merchant Registration / Claim | UI polish complete. Widget checks passed. Live role acceptance partial. | [Screen 19 validation](docs/design/SCREEN_19_MERCHANT_REGISTRATION_VALIDATION.md) |
| **20** | Merchant Workspace Dashboard | ✅ Complete (Verified) | `apps/mobile/lib/core/screens/merchant_workspace_screen.dart` (Dashboard, stats, request management, quick actions) |
| **21** | Merchant Catalog Management | Live draft flow verified. Category units and optional GST estimate implemented. | [Screen 21 validation](docs/design/SCREEN_21_MERCHANT_CATALOG_VALIDATION.md) |
| **22** | Merchant Hours & Coverage Setup | UI and widget tests passed. Live save verification pending for the intended merchant. | [Screen 22 validation](docs/design/SCREEN_22_MERCHANT_HOURS_COVERAGE_VALIDATION.md) |

### UI Showcase Milestone
- The 22 rows above are the showcase screen inventory, not blanket proof that every workflow is production-complete. Verify current source, API, database behavior, tests, and runtime evidence before describing an item as complete or verified. Historical audit evidence is indexed in `docs/phases/` and `docs/project-audit/`.
- **Screen 10 (Nearby Interactive Map) Verification Summary**:
  - Authentic category nature mapping across all 18 categories (`Transport`, `Healthcare`, `Education`, `Service`, `Dining`, `Salon`, `Fitness`, `Auto Care`, `Events`, `Agriculture`, `Construction`, `Home Decor`, `Furniture`, `Electronics`, `Fashion`, `Grocery`, `Pharmacy`, `Shop`).
  - Context-aware action buttons: `Cab & Auto` -> `Book Ride` with taxi icon; `Doctors & Clinics` -> `Book Appointment` with calendar icon; `Education` -> `Enquire Now`; `Services` / `Events` / `Auto Care` -> `Book Service`; `Hotels & Stays` -> `Book Stay`; `Food` -> `Order Food`; retail -> `View Store` / `Shop Now`.
  - Integrated `assets/backgrounds/premium/home_background.webp` for Screen 8, Screen 9, and Screen 10 headers with pearl white fluid wave overlay.
  - Fully synchronized radar canvas projection (concentric circles + sweep beam), marker selection, and list view with admin-approved service places and real km/meter distances.
  - Automated tests passing: `nearby_map_test.dart`, `search_results_screen_test.dart`, `categories_directory_test.dart`.
- **Screen 11 (Business Profile & Tabs) Verification Summary**:
  - Hero cover backdrop integrated with `assets/backgrounds/premium/role_selection_background.webp` and signature teal gradient overlay.
  - Category nature pill badge (`TRANSPORT`, `DINING`, `HEALTHCARE`, etc.) matching the 18 top-level taxonomy categories.
  - Interactive User Review Submission Flow: "Give Review · Write Your Feedback" button opens bottom sheet modal with 1-5 star selector, customer name, experience feedback field, and validation.
  - Real-time review publishing: submitted review immediately inserts at top of the reviews list with "Just now", 5 stars, author, comment, and verified review count increments live.
  - Nearby Map (Screen 10) Filter Refinement: Row 1 master types (`All Places`, `Shops`, `Services`, `Open Now`), Row 2 dynamic category carousel synchronized with master type, Row 3 radius dropdown with real-time count summary and list view toggle.
  - Offline/curated showcase fallback in `BusinessDetailNotifier` wired to `CategoryListingsData.allListings` ensuring flawless navigation and business detail rendering across all admin-approved service places (`Chhatia`, `Kuanpal`, `Jagatpur`, `Tangi`, `Chandikhol`).
  - Automated tests passing: `business_detail_screen_test.dart` and `nearby_map_test.dart`.
  - Android emulator verification: Tested live on `emulator-5554` (`Pixel_8`) with APK SHA-256 `DB61ABCB757A0DB5D0CE99F92E2D9C626169DAE076F832F89F35030BF44DC11B`.
- **Screen 16 (Saved / Bookmarked Businesses) Verification Summary**:
  - Integrated 2026 Metallic Teal & Pearl White Fluid Wave header with Obsidian typography tokens (`#101820` / `#374151`).
  - Dynamic filter chips: `All`, `Shops & Retail`, `Services & Pros`, `Cab & Auto`, `Food & Dining`, `Doctors & Healthcare`, `Hotels & Stays`.
  - Context-aware action buttons on saved cards: `Cab & Auto` -> `Book Ride` with taxi icon; `Doctors & Clinics` -> `Book Appointment` with calendar icon; `Food & Dining` -> `Order Food` / `View Menu` with dining icon; `Services` -> `Book Service`; retail -> `View Store` / `Shop Now`.
  - Full empty-state fallback with curated recommendation cards across approved service places (`Chhatia`, `Kuanpal`, `Jagatpur`, `Tangi`, `Chandikhol`) and one-tap bookmark removal.
  - Category nature mapping fix verified across Business Detail Screen: Cab & Auto correctly displays `TRANSPORT` nature pill, `Call Driver` phone action, `Book Ride` CTA, `Rides & Fares` catalog tab, and direct modal booking options instead of generic store labels.
  - Automated tests passing: `saved_screen_test.dart` and `business_detail_screen_test.dart`.
  - Android emulator verification: Tested live on `emulator-5554` (`Pixel_8`) with APK SHA-256 `ACB62E4FD1789343547394906B2572F10C027F32E92B0F1D932441DDC7E6F85F`.
- **Screen 17 Customer Profile & Settings** received a visual-only polish pass on 25 November 2026. The [validation record](docs/design/SCREEN_17_CUSTOMER_PROFILE_VALIDATION.md) documents the APK, widget tests, Customer screen checks, and role acceptance limits.
- **Screen 18 Service Request Status Tracker** received a visual-only polish pass on 25 November 2026. The [validation record](docs/design/SCREEN_18_SERVICE_REQUEST_STATUS_VALIDATION.md) covers the status presentation, responsive layout, polling and cancellation tests, and Android acceptance limits.
- **Screen 19 Merchant Registration / Claim** received a visual polish pass. The [validation record](docs/design/SCREEN_19_MERCHANT_REGISTRATION_VALIDATION.md) covers wizard progress, register and claim entry points, and Android acceptance limits.
- **Screen 20 Merchant Workspace Dashboard** received a visual polish pass. The [validation record](docs/design/SCREEN_20_MERCHANT_WORKSPACE_VALIDATION.md) covers dashboard hierarchy, provider-backed metrics, and Android checks.
- **Screen 21 Merchant Catalog Management** passed its live draft-product create, edit, stock status, and relaunch checks. The [validation record](docs/design/SCREEN_21_MERCHANT_CATALOG_VALIDATION.md) tracks category-based units, optional GST, and the MRP and stock display fixes.
- The next showcase screen is **Screen 22, Merchant Hours & Coverage Setup** (`apps/mobile/lib/core/screens/merchant_hours_coverage_screen.dart`).

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

### AUTH-OTP-01 security and QA rules
- The Go service generates and verifies OTPs. Normal auth responses and application logs must never contain the OTP. The Fast2SMS production adapter exists and has mocked tests, but production credentials/template are not configured and live delivery is unverified; without a configured provider, auth must fail closed rather than echo a local code.
- Login challenges are opaque, phone/purpose scoped, expiring, attempt-limited, invalidated on resend, and single use. Clients should submit the returned `challenge_id` with verification.
- Android may use SMS Retriever and the one-time-code autofill hint, but must keep manual entry and avoid broad SMS inbox permissions. Web inputs may advertise `autocomplete="one-time-code"`; do not claim desktop browsers retrieve Android SMS.
- The legacy `qa_file` transport is isolated-QA-only, explicitly enabled, synthetic-allowlist- and per-run-bound, and has no HTTP read endpoint. Do not use the retired broad Docker-exec OTP reader. Current authenticated QA uses the dedicated `qa_http` writer plus root-owned mode-0700 tmpfs inbox helper; its loopback-only reader requires a single-use capability bound to run, challenge, phone, purpose, expiry, and runner. Keep writer and runner secrets separate, never expose the reader through Nginx, and never allowlist a real root admin to bypass authentication or finance separation of duties.
- Migration 036 is additive; it is applied only to the tmpfs-backed isolated QA database and remains unapplied to shared development/production. AUTH-OTP-01 passed isolated-QA acceptance on 13 November 2026: the dedicated root-owned inbox helper uses a run/challenge/phone/purpose/expiry/runner-scoped, atomic single-use capability, and Customer, Merchant, Rider, and Admin authenticated through normal UI flows. See the R2 report for current APK, AVD, test, and evidence details. Production SMS remains unconfigured; do not treat isolated QA OTP delivery as production readiness. The previous R1 Docker-exec reader and missing-run-ID findings are historical and superseded; do not use the retired broad reader.
- AUTH-OTP-02 passed isolated-QA automatic-entry acceptance on 13 November 2026: a trusted runner retrieved four fresh role challenges through the existing private reader and entered them into the actual Customer, Merchant, Rider, and Admin login UIs. The debug-only `QA_OTP_AUTOMATION` instrumentation exposes challenge metadata only, never a code, and must not be enabled in release builds. The final APK/hash, AVD mapping, screenshots, tests and Merchant build limitation are recorded in `docs/phases/AUTH_OTP_02_QA_AUTOMATIC_ENTRY_AND_FAST2SMS.md`. This QA path does not validate native Android SMS Retriever; real Fast2SMS delivery is also untested. AUTH-OTP-01's single-use reader and OTP verification rules remain unchanged.


### Phase 2R.4 — Partner Fulfillment & Order Preparation (6 November 2026)
- PASS for the scoped milestone. Added additive migration 024 and partner-scoped platform-order list/detail/accept/reject/prepare/ready APIs. Partner responses omit customer contact/address and customer/supply prices; tenant scope is enforced from active membership and assigned `business_id`.
- Rejection reason, immutable status event, and one-time finite inventory reservation release are transactional. Concurrent/invalid transitions are covered by database-backed tests. Customer SSE uses the `order.status` event consumed by order tracking.
- Pixel 8 created one unpaid QA order through the customer UI against a disposable API/database. The authorized QA partner advanced it through the API; customer tracking rendered `Ready for pickup` with four status events. Migration 024 and migration 023 remain unapplied to shared development data; only the disposable QA database used them and was removed after verification.
- Full Go suite passed, full Flutter suite passed (73), focused Dart analysis passed, Merchant Portal typecheck/build and two mocked-API Playwright tests passed. Full Flutter analysis timed out; do not claim it passed. No commit was created. Phase 2E was awaiting approval at that report date; the approval and current result are recorded below. Details and screenshots: `docs/phases/PHASE_2R_4_PARTNER_FULFILLMENT_AND_ORDER_PREPARATION.md`.

### Phase 2E — End-to-End Commerce Acceptance (7 November 2026)

- Phase 2E was approved and exercised against disposable PostGIS/API/Nginx/MinIO services. Migrations 023 and 024 were applied only to that disposable database and remain unapplied to the shared development database.
- The final QA order `dce70c14-7da8-480a-9161-d73aa0563b59` (`GN-DCE70C14`) was created through the Pixel 8 customer checkout. The authenticated live Merchant Portal moved the assigned order through accept → prepare → ready for pickup. Pixel 8 then displayed and manually refreshed that exact order's timeline; customer-authenticated API and PostgreSQL both matched `placed → accepted → preparing → ready_for_pickup`. Payment stayed `not_collected`; rider/ETA data was absent.
- Earlier Phase 2E suites passed as recorded in the report: Go suite, Flutter tests (73), Admin/Merchant typecheck/build, OpenAPI, and DB-backed ownership, isolation, idempotency, stock, concurrency and rejection coverage. Flutter analysis had 18 diagnostics (3 warnings, 15 infos, no errors; exit code 1). These suites were not rerun during the final device-only check.
- **Current result: PASS for Phase 2E.** Evidence screenshot and final report: `docs/phases/screenshots/phase2e-final-pixel8-ready-for-pickup.jpg` and `docs/phases/PHASE_2E_END_TO_END_COMMERCE_ACCEPTANCE.md`. The disposable QA DB, accounts, order, catalog records, containers, network and QA-only images were removed. Shared development and production data were not changed.

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
