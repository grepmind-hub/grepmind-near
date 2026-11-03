# Feature Gap Analysis

Audit date: 3 November 2026. This report reflects the current source tree, not the historic milestone language.

## Release blockers (P0)

1. **Production authentication is unavailable.** `backend/internal/auth/handlers.go` intentionally returns 503 outside local mode because no SMS adapter exists. Local OTP is echoed in the response. A supported SMS OTP provider, delivery monitoring, abuse controls and verified production configuration are launch prerequisites.
2. **JWT/session revocation is incomplete.** Access tokens are stateless and not checked against session state. Logout attempts to revoke by hashing the access token even though stored session hashes represent refresh tokens. Refresh token hash storage uses bcrypt output as a lookup key, which is nondeterministic and unsuitable for exact indexed equality. Rotation/reuse handling needs a secure design and tests.
3. **Merchant registration and claim do not persist.** The mobile form deliberately reports submission unavailable; claim UI sets local success state. The merchant desktop's New Store modal also mutates in-memory state. No reliable merchant onboarding journey can create/claim a real listing and enter KYC review.
4. **Merchant workspace is still mock-backed.** `apps/merchant-web/app/page.tsx` imports `INITIAL_BUSINESSES`, requests, products, services, hours and team. Browser local storage is not authoritative tenant isolation. The real API must be the source for IDs, memberships, updates and branch selection.
5. **Billing is absent.** No merchant registration fee, plan, subscription, payment attempt, webhook, renewal, invoice, reminder or admin billing endpoint/table/UI exists.
6. **Android release configuration is development-only.** `apps/mobile/android/app/build.gradle.kts` release uses debug signing. `AndroidManifest.xml` contains `YOUR_GOOGLE_MAPS_API_KEY_HERE`; app label/application ID remain development values. No Crashlytics/Sentry integration was found.
7. **Privacy/account deletion is incomplete.** Profile has privacy/delete-style UI but no matching account deletion API. Customer location, phone, requests, uploads and analytics retention/deletion rules need product and legal review.
8. **No full production migration process.** Compose's init directory does not migrate existing persistent DBs. Migration tracking, deployment ordering, backups, rollback/forward-fix policy and restore drills are absent.

## High-impact partial features

| Gap | Evidence | Required outcome |
|---|---|---|
| Availability management | Slots exist and customer booking increments them; merchant endpoints to create/update/close slots are absent | Merchant can publish availability; API validates timezone, overlap, ownership and capacity; tests race concurrent booking. |
| Table reservations | Reservation date and guest count persist; no table capacity or time-slot inventory | Define business-configured reservation windows/capacity, prevent overbooking, merchant accept/decline workflow. |
| Hotel bookings | Room product price is persisted and total calculated; no room inventory, date-overlap or booking state lifecycle | Add room inventory/availability constraints and merchant confirmation/refund policy before representing “confirmed.” |
| Food fulfillment | Order rows and merchant status API exist; no payment collection, courier assignment, address geocoding, FCM or stock reservation | Keep payment state explicit; define acceptance/out-of-stock/cancellation; show tracking only with actual provider data. |
| Customer service timeline | `service_request_events` added/backfilled, but GET response does not return events and merchant updates have limited event coverage | Return event timeline, insert every transition transactionally, avoid fabricated stage times. |
| Reviews | No review schema/API found; UI now shows no ratings/reviews when absent | Verified completed-request review flow, moderation/reporting, aggregate calculation, anti-abuse limits. |
| Offers | Backend offer moderation exists; merchant API/desktop authoring and audience rules are partial | Add merchant offer CRUD, validation and published display lifecycle. |
| Admin analytics | Backend offers aggregate counts; no full reporting endpoints; admin chart constants empty | Use bounded DB queries, city/category filters, clear period/timezone and unavailable state on failure. |
| Notifications | SSE and DB notification records exist; native FCM absent; request/customer scoping and reconnect/mobile background behavior need tests | Use FCM for background mobile notifications; keep SSE for active web; prove authorization per user/business. |
| Error observability | API handlers sometimes leak raw DB error details; frontend fallbacks can suppress errors | Structured logs with request IDs, redaction, safe client errors, health/readiness/metrics, crash reporting. |
| City/location accuracy | Cuttack/Jajpur filters and radius tests exist; no municipality boundary dataset/proof; map API key absent | Clarify city selection vs administrative boundary; validate GPS permission UX, geocoding and no-location paths on device. |
| Web session security | Merchant and admin bearer tokens are stored in `localStorage` | Evaluate secure HttpOnly same-site cookie/BFF or document threat tradeoff; add CSP and XSS controls. |
| Role model | General user roles plus business membership; web local session can diverge from backend authority | Require backend membership for every tenant call; test owner/manager/staff permissions endpoint by endpoint. |

## Security and privacy gaps

- **Rate limiting:** configuration exposes `RATE_LIMIT_AUTH`/`RATE_LIMIT_API`, but no HTTP rate-limiter middleware was found. OTP has per-phone resend/attempt checks, not robust per-IP/device throttling, concurrency-safe attempt updates, bot controls or carrier abuse detection.
- **OTP concurrency:** OTP attempt increment and verification marking are separate ignored-error updates. Concurrent verification can race; request should atomically lock/increment/consume and use constant, generic errors.
- **JWT:** enforce algorithm, issuer, subject, `iat`/`exp` and bounded clocks; production secret must be mandatory/strong. Access revocation should use short TTL or session version/denylist. Refresh tokens should be opaque random secrets stored as SHA-256/HMAC digest, rotated transactionally, and reuse detected.
- **Authorization:** many merchant handlers resolve only the primary owner via `businesses.owner_user_id`; ensure member role rules are consistently enforced. Audit object-level checks for every path and body business ID. Keep root superadmin protection, then test it at API level rather than only UI.
- **Sensitive errors/logs:** inspect `backend/cmd/api/main.go` for responses embedding `err.Error()` and remove SQL/error details from external responses. Avoid phone, OTP, tokens and precise location in logs.
- **Storage:** local migration/service historically creates a public bucket policy. Verify current local-only guard and production provider configuration; production KYC/media should be private by default with short-lived presigned URLs and retention controls. No malware/content scanning or image re-encoding was verified.
- **Transport/config:** local Compose uses HTTP and insecure defaults; staging Compose uses HTTP MinIO, `sslmode=disable`, ports exposed and empty-env interpolation. Production TLS termination, secure headers, secret manager, network ACLs and restricted admin endpoints are not present in repository evidence.
- **SSE:** verify stream filtering for customer `request_id`, business membership for merchant streams, connection limits, backpressure and token expiry. The test broadcast endpoint should be disabled outside local/test.
- **Database:** backups/restore not documented/automated; use least-privilege DB roles, production TLS, encrypted backups, retention and restore drills. No evidence of PITR.
- **Mobile:** secure storage dependency is present; verify access and refresh tokens are only stored there. Debug logging and release obfuscation/crash capture need review. No signing secret should be in repo.
- **Compliance:** determine personal-data roles, lawful purposes, notices, consent, retention, user rights and grievance process under applicable Indian data protection law with qualified counsel. The app's location, phone, merchant KYC and booking data raise material privacy obligations. Confirm current effective rules and implementation obligations before release; this audit is not a legal determination.

## Engineering debt

- API contract drift: registered routes and OpenAPI paths differ in naming. Recent order additions document one route shape; service request contract uses `/service-requests` while router uses `/requests` and `/businesses/{id}/requests`. Validate contract against a route snapshot in CI.
- `AGENTS.md` and changelog say GoRouter, complete screens, FCM, complete web/API integration and passing E2E; actual `main.dart` uses `MaterialApp`/manual `IndexedStack`, FCM delivery absent, merchant state mocked, and CI/test environment incomplete.
- `docker-compose.yml` and CI have obsolete Compose `version` keys. `docker-compose.test.yml` has no healthcheck parity for services; CI service definitions and migration bootstrap need validation.
- `ci.yml` runs only `go test ./tests/...` in backend job, missing `./...`; web tests use Playwright without setup/install browser step; Flutter integration workflow combines emulator service syntax incorrectly for GitHub Actions service containers; deployment image publishing is not present in workflow although deploy pulls images.
- Staging/deploy workflow includes production health-check placeholder and is not production deployment automation. Do not treat its presence as a release gate passed.
- Seed/demo records in immutable historical migrations and stub assets mean fresh DB can contain nonproduction content; migrations must be reviewed/cleanly seeded for test and production profiles.
- `RateLimit*` config values are currently declarative only; choose and test in-memory single-instance rate limit for MVP or edge proxy protection, then reassess if horizontally scaled.

## Required before public launch

1. Production SMS OTP, throttle/abuse controls, refresh rotation/revocation, secret management, authorization matrix tests.
2. Real merchant create/claim, verification/KYC storage/private media and account state transitions.
3. Merchant API-backed web workspace and mobile workspace with tenant isolation tests.
4. Decide first-launch scope: discovery + inquiry may launch before food/hotel operations only if hidden/unavailable operational claims are removed; otherwise implement and test the full operational lifecycles.
5. Billing design and payment provider/webhook reconciliation for merchant fees/subscriptions; do not collect marketplace customer money.
6. Play signing, package identity, privacy policy, Data safety, account deletion, location disclosure, screenshots/listing, support contact and crash handling.
7. Versioned migration runner, backup restore test, HTTPS staging deployment, smoke tests and security scan review.
8. Fix/complete CI so Go, Flutter, web builds/E2E, OpenAPI route validation and migration boot all run reproducibly.
