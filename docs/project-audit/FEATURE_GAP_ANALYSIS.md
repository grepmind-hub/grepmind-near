# Grepmind Near — Current Feature Gap Analysis

Audit date: 5 November 2026. This report supersedes the 3 November baseline where current code or executed checks show that work has since landed. It records production risks, not merely missing UI.

## P0 — Public-launch blockers

| Gap | Current evidence | Risk and required outcome |
|---|---|---|
| Production OTP delivery | Auth has a provider interface, local stub and OTP request/verify throttles; no production SMS adapter or credentials/configuration are selected. Non-local config fails closed. | Customers and merchants cannot authenticate in production. Select a compliant SMS provider, implement delivery/receipt/error handling, verify abuse controls across multiple API instances, and validate staging without exposing OTPs. |
| Database migration operations | `backend/migrations/001`–`016` exist; Compose only mounts files into `/docker-entrypoint-initdb.d`. No migration ledger/runner or rollout verification exists. | Existing-volume deployments silently miss new schema. Add an ordered, checksummed runner and a fresh/existing database upgrade test; preserve migration history and specifically review migration 010. |
| Backups and restore | No backup/restore script, scheduled job, Compose service, or restore evidence found. A named PostgreSQL volume is not a backup. | Data loss can be permanent. Define retention/encryption/offsite policy, automated backups, monitoring, and a tested restore runbook before real users. External cloud backup status requires operator confirmation. |
| Android release configuration and privacy | Release variant uses debug signing; Maps key is a placeholder. Profile explicitly says account deletion is unavailable. No complete Play Data Safety / retention evidence is in code. | App cannot ship as a production release and fails important trust/compliance readiness. Configure protected release signing, restrict Maps key, provide deletion/retention workflows and accurate disclosures with professional policy review. |
| Authenticated cross-platform E2E | Go and Flutter unit coverage is substantial; Admin E2E's authenticated case requires `E2E_ADMIN_PHONE_E164`; Merchant E2E covers only entry/unauthenticated access. Local browser run failed before assertions because Chromium is absent. | Most customer/merchant/admin operations are not regression-protected through the same UI and live API. Provide a dedicated disposable E2E environment, browser install, dynamic OTP fixtures, and deterministic cleanup. |

## P1 — High-impact product and reliability gaps

### Order and reservation operations

- Customer food ordering and order history/cancel are persisted, and the server computes totals. The merchant portal source does not include a merchant orders pipeline/UI, although a merchant order status endpoint exists. Add merchant review, accept/decline, preparation, ready/fulfilled/cancel transitions and customer-visible errors before marketing order fulfillment.
- Table reservation stores date/time and guest count but does not reserve a configured table capacity or enforce an overlapping reservation window. Hotels store check-in/out and room product but lack room inventory and overlapping-stay checks. Until those rules exist, avoid presenting these as guaranteed confirmed reservations.
- Delivery tracking has no courier assignment/location service; do not present live courier progress. Customer online payment remains intentionally deferred.

### Category capability model

- The active taxonomy is present at 19 categories and confirmed by local DB count. This does not yet constitute the proposed 19-category Capability Engine: category-specific fields, permitted actions, validation, workflow, and merchant configuration are not driven by a capability registry. Existing code has select hospitality-specific branches (restaurant/hotel) and generic service/catalog behavior.
- Define an explicit capability matrix before implementing a generic engine. Keep category-specific experiences limited to verified backend support, and do not expose fake availability, inventory, ratings or fulfillment.

### Real acceptance gaps

- Admin: dashboard, KYC, moderation, claims, reports, offers, audit, activity and access controls now call API-backed helpers and surface fetch errors. Current source has improved since the previous mock/empty-data finding. Authenticated tab actions, role changes, claim transfer, and API failure UI still need browser E2E against disposable records.
- Merchant: current workspace loads authorized directory/snapshot data and uses authenticated API calls for product/service CRUD, media, hours, coverage, offers, members, requests, notifications and SSE. This supersedes the old `mockData.ts` finding. End-to-end authenticated web CRUD, tenant-switching and all role permissions remain unverified.
- Onboarding/claim: new business creation and secure claim submission/review persistence exist. Admin approval changes ownership/member role in a transaction. KYC document handling and the whole mobile-to-admin approval path require a real acceptance run and private object-storage review.
- Catalog/images: APIs and screens exist, with previous category automation documented. This audit ran widget tests but did not re-run emulator/browser persistence and deletion assertions.
- Search/location: the two-city active category data exists. City boundary accuracy, GPS permission behavior and map SDK key/configuration are not certified by current API/unit test evidence.

### Observability and API reliability

- There is health reporting and basic structured logging, but this audit did not find a complete production alerting, tracing, crash-reporting or SLO setup.
- Admin UI now distinguishes global load failure from zero-valued data, but API-client helpers often normalize absent `data` to an empty list. Preserve and test explicit service errors rather than allow malformed success envelopes to become empty states.
- Verify body limits, timeouts, rate limits and safe error messages consistently across every mutation; local-only API error tests are not a production penetration test.
- SSE authorization is tested at API level, but multi-instance fanout is not implemented. Current in-process SSE only reaches clients attached to the same API process; this is acceptable for a single-instance MVP, but must be explicit before horizontal scaling.

## P2 — Deferred trust and growth features

- Verified reviews and ratings: absent schema/API and anti-abuse moderation workflow.
- Native FCM: not integrated; active web SSE is not a background notification solution.
- Merchant fee/subscription billing using UPI: entirely absent. Define fees, tax/invoice, refunds, grace periods, entitlement states, gateway and webhook rules after identity and migration controls. Do not add customer checkout payments to this feature.
- Google Sign-In: remains a backlog item; no client token flow is implemented.
- Support/dispute intake and operational service levels: admin report moderation exists, but full customer support intake, assignment and response tracking are incomplete.

## Superseded findings from the November 3 audit

The following historical statements must no longer be repeated as current facts without new contrary evidence:

1. Refresh-token lookup, rotation and logout/session revocation were subsequently hardened and now have unit tests; the fresh Go suite passed.
2. Merchant web state is no longer initialized from `INITIAL_*` mock fixtures; the main workspace reads authenticated API snapshots and mutations.
3. Merchant new-business registration and existing-listing claim are no longer UI-only. Their persistence-backed API and claim decision service exist, but full UI acceptance remains outstanding.
4. Merchant slot creation/date exceptions and customer rescheduling are now present. Atomic rescheduling has fresh PostgreSQL integration coverage and a previous Cuttack/Jajpur emulator pass.
5. Admin dashboard/API has live stats/trends, listing activity and API-backed operations with visible global/section errors. It is not yet browser-verified in this audit.
6. The active category set is 19 in the current local database, rather than the old 18-category note.

## Verification boundaries

This audit did not access production, send SMS, make payments, deploy, run destructive migrations, or mutate persistent production data. The isolated database test created and removed a temporary schema. The local Compose data itself is development data. Browser authenticated paths, mobile device flows, backups and provider configuration remain unverified as detailed in `AUDIT_TEST_RESULTS.md` and `CROSS_PLATFORM_ACCEPTANCE_MATRIX.md`.
