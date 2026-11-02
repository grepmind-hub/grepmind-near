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
