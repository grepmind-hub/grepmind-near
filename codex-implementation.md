# Codex implementation — production hardening slice

## Scope

This change secures the critical request, notification, Server-Sent Event (SSE), media, and administrative-demand endpoints identified in the architecture review. It also removes the Explore screen's hard-coded category carousel so the customer experience is driven by the API's active category taxonomy.

## Security changes

- Booking creation now requires a valid bearer token. The authenticated user is the customer; the API no longer creates a user from a caller-supplied phone number or falls back to a shared demo account.
- A service request can be read only by its customer or an active member/owner of the receiving business.
- Notification listing, reading, SSE subscriptions, and media upload/listing require authentication.
- Notification and SSE scopes are checked against the current user, active business membership, and service-request ownership.
- The test broadcast endpoint and unserved-location demand reporting are now admin-only.

## Category behaviour

Categories are a platform-managed taxonomy. Customer mobile users can browse and select active categories but cannot create, update, or delete global categories. This preserves search integrity and prevents unreviewed or malicious taxonomy changes. The Explore carousel now reads `categoriesProvider`, which loads `GET /api/v1/categories`; no static category fixture remains there.

Future category administration should be an authenticated admin API and portal workflow with validation, audit logging, soft deletion (`is_active`), and integration tests. It must not be exposed through the customer mobile app.

### Merchant catalog categories (2 November 2026)

The merchant's own catalog categories are separate from the platform discovery taxonomy. Added migration `009_merchant_catalog_categories.sql` and authenticated GET/POST/PATCH/DELETE `/merchant/catalog-categories` routes. An optional `business_id` is checked against active business membership. Owners and managers may mutate categories; staff can read them. Names are trimmed, bounded to 80 characters, and unique per business without case sensitivity. The mobile Catalog toolbar opens a category manager with loading, retry, empty, save, and delete confirmation states. These groups are not yet assignable to individual catalog items.

The additive migration was applied to the local development database. Existing installations must apply migration 009 explicitly; no historical migration was edited.

## Additional security and real-data corrections

- Merchant web uploads and notification requests now send bearer authentication. SSE uses authenticated fetch streaming with cancellation and reconnect rather than unauthenticated EventSource.
- Media listing now filters by the authenticated user even when a purpose filter is provided. Upload MIME detection no longer falls back to a caller-controlled Content-Type header.
- Automatic bucket creation/public policy runs only in local development. Production bucket provisioning belongs to the selected cloud provider setup.
- Removed mobile request/response body logging to avoid leaking OTPs, tokens, and customer data.
- Non-local OTP requests fail closed until a real SMS provider adapter is implemented; development OTP responses must not be used in production.
- Removed fabricated business-detail fallback products, rooms, amenities, hours, and placeholder business. Missing business details show a retry state.
- Removed seeded in-memory customer order history. Hospitality checkout/order storage still needs a durable backend implementation; removing seed records does not make that workflow production-ready.
- Corrected existing integration-test compilation issues and added Flutter's SDK integration_test development dependency. Existing test selectors/flows still need end-to-end reconciliation.

## Validation for this continuation

- Go `go test ./...`: passed, including new anonymous rejection checks on eleven sensitive routes.
- `scripts/test_merchant_categories.ps1`: passed create, rename, persisted listing, delete, anonymous rejection, and staff/customer mutation denial against local Docker API/PostgreSQL.
- Docker Compose builds for API, worker, merchant web, and admin web: passed. Merchant web build includes TypeScript validation.
- Local and test Compose configuration parsing: passed with obsolete-version warnings.
- Flutter complete widget suite: 23 tests passed after replacing production seed-data dependencies with test-only fixtures and reconciling current labels. A service-status off-screen tap warning remains, so that test does not establish complete interaction coverage.
- New category widget test validates add, persisted reload, rename, and confirmed delete using controlled API responses.
- Appointment scheduler now rejects missing business IDs and failed/unpersisted API requests instead of reporting successful bookings. Fixed status-screen nested Flexible layout and formatted booking ID handling.
- Flutter application analysis: no compile errors, but 72 pre-existing warnings/info findings remain; the static-analysis gate is not clean.
- Android debug APK build: passed; installed successfully on emulator-5554. Visually confirmed live API categories and business listings on the emulator after restarting Nginx to refresh the recreated API upstream. Full merchant CRUD was tested through widget and real API integration tests, not yet through the emulator UI.
- Replaced the fabricated Explore sale banner with neutral discovery content and replaced raw networking exceptions in the empty state with bounded recovery text.

## Cuttack/Jajpur category automation (2 November 2026)

- Added `backend/cmd/validate-cities` and replaced the earlier fixed-account PowerShell test with a wrapper that discovers the repository path and passes configurable cities/API/manifest options.
- Categories come from the live API; accounts, phone numbers, IDs and catalog entries are generated per run. Actual local OTP APIs authenticate both customer and merchant roles. No credentials/tokens are persisted or printed.
- Completed two full runs across 19 categories in each city (38 combinations). Covered category/product/service CRUD, persisted customer visibility, city/category/query filtering, customer booking and merchant acceptance, anonymous/customer denial and cross-merchant isolation.
- Each run has deferred transactional cleanup, exact account ownership checks, an atomically updated recovery manifest and an explicit `-Cleanup` command. Both successful and failed runs cleaned their generated entries. Existing accounts/listings were preserved.
- Repeated runs exposed an intermittent API 401 (`token used before issued`). Added a bounded five-second allowance for issuance clock skew only; expiry and not-before remain strict. Added HS256, issuer, subject and clock-boundary tests. No automatic retries hide authentication failures.
- Corrected OTP login's fixed `customer` role response: profile fields and roles now come from the account database, and inactive accounts are rejected before token issuance. The automation checks returned customer/merchant roles as well as authenticated `/me` merchant access.
- Existing approved inventory after cleanup: Cuttack has one electrician and one hardware listing; Jajpur has one plumber listing. Remaining category tests used temporary fixtures, not fabricated permanent inventory.
- Fixed backend city filtering and query filtering. Added `/locations` for live city names, counts and centroids; removed fake GPS selection, fixed city counts, fixed expansion claims, and hard-coded Bhubaneswar search coordinates from Explore/Search. A city/category notifier regression also caught and fixed duplicate result insertion.
- Go suite passed; the existing 23 Flutter widget tests passed and the new city-discovery regression passed separately. Static analysis of affected discovery files had no compile errors, with lint information still reported. API Docker image rebuilt and local API/proxy restarted.
- Usage, coverage and crash recovery are documented in `scripts/CITY_VALIDATION.md`. This is API/database automation with injected local fixtures, not browser script injection or full emulator UI automation. Other app areas still contain hard-coded data and require separate work.
- Final post-fix run: all 38 combinations passed with actual customer/merchant login-role assertions; cleanup passed and both recovery manifest files were absent. Final city-aware Android debug APK built and installed successfully on emulator-5554. Existing approved city inventory remained two Cuttack listings and one Jajpur listing.

## Supported-city cleanup (2 November 2026)

- Per the explicit city-scope request, added migration 010 to archive and remove all non-Cuttack/Jajpur businesses from active tables. Local execution archived 11 businesses (8 from the removed capital-city scope and 3 from the removed coastal-city scope), plus dependent catalog, booking, notification, membership, report, favorite and demand records. There are 167 archived rows, recoverable through a reviewed restore migration. Historical migrations and immutable audit history were preserved; shared user accounts and object-store files were not deleted.
- Local active database now contains Cuttack: 2 approved and 1 pending businesses; Jajpur: 1 approved business. Added a database city constraint and API profile-update validation to reject out-of-scope business cities.
- Removed unsupported-city names, sample records and fallback addresses from mobile and web application source. Nearby map uses selected location instead of fixed coordinates. Removed arbitrary unsupported-town entry from Explore.
- Cleared sample admin/merchant portal arrays and mobile admin/claim listings, rather than relabeling them as genuine Cuttack/Jajpur records. Unconnected analytics show an unavailable state. The merchant desktop workspace now shows an explicit no-store-loaded state until its existing local-state model is connected to server account/store data. Mobile live merchant catalog remains available.
- Removed fake merchant web OTP/token generation and fixed OTP autofill; web login now calls the real OTP endpoints. It still requires local development code retrieval until an SMS provider is configured.
- Removed prefilled merchant registration identity/address fields and fake successful registration submission. The registration screen now reports that persistence/verification integration is unavailable. These limitations must be completed before claiming end-to-end registration support.
- Regression checks: Go tests passed; all 24 Flutter widget tests passed; all 38 city/category API combinations passed after database cleanup, with test-created entries removed. Flutter compile checks initially caught a const-expression error and portal builds caught narrowed-type/placeholder errors, which were corrected before rebuilding. Full Flutter analysis still has pre-existing lint findings.
- Final API/admin/merchant Docker images built and local services restarted. Final Android debug APK built successfully; the two-city category matrix includes rejection of unsupported profile-city updates. A source search found no removed-city names in application code under `apps/`; historical documents, migrations and recovery archives retain their original provenance.

## Remaining implementation limitations

This is an incremental implementation, not a completed production-readiness certification. Remaining work includes category-to-item assignment; merchant registration/claim persistence; durable food/table/hotel ordering and server-calculated totals; removal of remaining fixed business metrics, offers, and claims; SMS-provider integration; JWT/config hardening; request transition rules; database-backed tenant tests for all endpoints; migration tracking; CI repair; cloud private media/presigned access; full emulator flow validation and UI/accessibility QA. Do not deploy these changes to production until those gates pass.

## Storage boundary

MinIO remains local-development storage. The API continues to use an S3-compatible service boundary, so production can use a managed cloud object store through configuration. Production storage must use private objects/presigned access for non-public uploads and must not use development credentials.

## Validation performed

- `go test ./...` (WSL): passed.
- `docker compose -f docker-compose.yml config -q`: parsed; Docker reports the existing obsolete `version` warning.
- Before this change, `docker-compose.test.yml` failed parsing because `OTP_PROVIDER` was duplicated. The duplicate has been removed; the full Compose validation still needs to run in an environment with Docker available.

## Follow-up work

1. Add database-backed API tests for unauthorized access, service-request ownership, notification scope, and SSE scope.
2. Reconcile the OpenAPI contract with the registered Go routes before generating or validating clients.
3. Replace the remaining static category lists in merchant registration and map filters with API-driven category data.
4. Add a migration runner for existing environments; Docker init scripts alone only migrate new databases.
5. Implement status-transition rules and transactional event persistence for service requests.
