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

## Remaining production work

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
