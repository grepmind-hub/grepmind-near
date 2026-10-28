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
| **10** | Nearby Interactive Map | 🟡 In Review | `apps/mobile/lib/core/screens/nearby_map_screen.dart` (Map markers with bottom card preview) |
| **11** | Business Profile & Tabs | ✅ Complete (Verified) | `apps/mobile/lib/core/screens/business_detail_screen.dart` (Hero cover, About, Products, Offers, Reviews) |
| **12** | Product Details Screen | ✅ Complete (Verified) | `apps/mobile/lib/core/screens/product_detail_screen.dart` (Pricing, discount, specs, store card, dual CTAs) |
| **13** | Service Professional Profile | ✅ Complete (Verified) | `apps/mobile/lib/core/screens/service_pro_screen.dart` (Experience badges, verified badge, services, rates, coverage, reviews) |
| **14** | Service Request Submission | ✅ Complete (Verified) | `apps/mobile/lib/core/screens/service_request_screen.dart` (Service dropdown, description, date/time) |
| **15** | Appointment Slot Scheduler | ⏳ **NEXT TASK** | Calendar date carousel + Morning/Afternoon/Evening slot picker |
| **16** | Saved / Bookmarked Businesses | ✅ Complete | `apps/mobile/lib/core/screens/saved_screen.dart` |
| **17** | Customer Profile & Settings | ✅ Complete | `apps/mobile/lib/core/screens/profile_screen.dart` |
| **18** | Service Request Status Tracker| ⏳ **QUEUED** | Multi-step progress tracker (Requested → Accepted → En Route → Completed) |
| **19** | Merchant Registration / Claim | ⏳ **QUEUED** | Onboarding for store owners / skilled pros |
| **20** | Merchant Workspace Dashboard | ✅ Complete | `apps/mobile/lib/core/screens/merchant_workspace_screen.dart` |
| **21** | Merchant Catalog Management | ⏳ **QUEUED** | Product & Service offerings editor |
| **22** | Merchant Hours & Coverage Setup| ⏳ **QUEUED** | Weekly operating hours & service radius setting |

### Next Recommended Implementation
- **Screen 15: Appointment Slot Scheduler** (`booking_scheduler_screen.dart`):
  - Interactive calendar day-selection strip (e.g. *Sun 13, Mon 14, Tue 15, Wed 16, Thu 17*).
  - Time slots categorized into *Morning (8:00 AM - 12:00 PM)*, *Afternoon (12:00 PM - 4:00 PM)*, and *Evening (4:00 PM - 8:00 PM)*.
  - Integration with `availability_slots` in database and Go backend.
