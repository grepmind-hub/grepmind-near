# Phase 3B — Rider Onboarding & Approval

**Review date:** 7 November 2026
**Status:** **PASS for Phase 3B QA acceptance** (7 November 2026)
**Scope:** Application, private verification images, Admin review, approved workspace access. No delivery operations.

## Summary

Phase 3B adds rider applications to the existing Grepmind Near identity and Flutter application. A `rider` role by itself no longer unlocks Rider mode: the backend checks the current role, active user account, and an approved rider profile on every protected rider request. Admin approval grants the role and requested locality permissions in one transaction. Suspension removes the rider role and revokes sessions in the same transaction; a stale access JWT is denied on the next protected request.

The rider application uses stable locality IDs and only returns currently enabled localities. With the current location configuration, the selectable areas are Kuanpal (Cuttack) and Chhatia (Jajpur). Planned localities remain unavailable. Approval grants only the localities explicitly selected by the reviewer; omitted requested localities are recorded as rejected.

The rider workspace is informational. It shows the approved rider profile and locality grants, and clearly labels Deliveries, Map/GPS, Earnings, dispatch and online availability as unavailable. No delivery job, assignment, payment or location data is created.

## Lifecycle and authorization

`draft → submitted → under_review → approved | changes_requested | rejected → (approved) suspended → approved`

- Applicants can create/edit drafts in draft, changes-requested, or rejected states and submit once per editable draft.
- Configured required evidence must be uploaded before submission. No legal document requirements are seeded by this migration.
- A reviewer cannot approve their own application. Application and document decisions are checked against current state under database row locks.
- Approval requires at least one requested, enabled locality and completed review of uploaded documents. Only selected localities receive the approved state.
- Approved Rider API access is checked against live database state, not client role selection or JWT claims alone.
- Suspension atomically changes application state, removes rider entitlement, revokes existing sessions and records both the application event and Admin audit entry. Reactivation restores the entitlement only when approved localities remain.
- Admin document opens are recorded in `audit_logs` before private content is streamed. The append-only application event table records status changes without object keys or document contents.

## Database and migration

Added `backend/migrations/025_rider_onboarding.sql` only. It defines rider profiles, configurable document requirements, private document metadata, requested/approved locality grants, and append-only application events. Profile deletion is restricted so account removal cannot silently cascade-delete reviewed history; an explicit retention/anonymization policy is still required.

The migration was exercised by database-backed Go integration tests in a disposable schema. **Migration 025 was not applied to the shared development database**, and this task did not alter shared database records or MinIO objects. Existing migrations were not edited.

## API contracts

Applicant endpoints (authenticated):

- `GET /api/v1/rider/localities`
- `GET /api/v1/rider/document-requirements`
- `GET|PUT /api/v1/rider/application`
- `POST /api/v1/rider/application/submit`
- `POST /api/v1/rider/application/documents`
- `GET /api/v1/rider/profile` (approved rider only)

Admin endpoints (existing Admin authentication/RBAC; requirement mutations restricted to the primary superadmin):

- `GET /api/v1/admin/rider-applications?status=...`
- `GET /api/v1/admin/rider-applications/{id}`
- `POST /api/v1/admin/rider-applications/{id}/review`
- `POST /api/v1/admin/rider-documents/{id}/review`
- `GET /api/v1/admin/rider-documents/{id}/content`
- `GET|POST /api/v1/admin/rider-document-requirements`
- `POST /api/v1/admin/riders/{id}/suspend`
- `POST /api/v1/admin/riders/{id}/reactivate`

OpenAPI was updated in `api/openapi.yaml`. The implementation adds no delivery/dispatch API.

## Private document handling

Rider evidence is stored in the separately configured `S3_PRIVATE_BUCKET` (default name `grepmind-near-private`), not the public listing-media bucket. Uploads are authenticated and owner-scoped, capped at 8 MiB, MIME-sniffed to JPEG/PNG/WebP, assigned unguessable object keys, and stored without returning bucket names, keys, or public URLs. Admin retrieval is authenticated, non-cacheable, content-sniffing protected, and audited. A public wildcard bucket policy causes uploads to fail closed.

Limitations: the current Flutter picker accepts images only (not PDF); malware scanning and an automated object-expiry/deletion job are not implemented. The service uses the configured S3 credentials, so production deployment should grant those credentials only the needed private-bucket permissions. The initial implementation pass did not upload evidence; the final acceptance recovery below exercised a synthetic image upload, private Admin retrieval, anonymous denial, review, and disposable-object cleanup.

## Portal and mobile changes

- Flutter adds the application/status screen, API-backed locality and requirement selection, image upload, and an approved rider dashboard/profile. Profile and role selection show application status and only expose Rider mode after refreshed backend approval.
- The Admin Portal adds rider queue filters, application/history detail, document review and private viewing, locality approvals, reasoned decisions, suspension/reactivation, and primary-superadmin requirement configuration. Data is API-backed; failures are shown rather than converted to empty mock data.
- Customer, Merchant and existing commerce navigation are preserved in source and covered by the full Flutter suite. No new package was added.

## Verification evidence

| Check | Result |
|---|---|
| `go test -count=1 ./...` with database-backed security fixture | PASS; all Go packages passed. The fixture applies migration 025 in an isolated schema and cleans it up. |
| Rider-specific integration coverage | PASS in the final disposable PostGIS run: unauthenticated and cross-account access, role-only/pending/rejected rider denial, disabled locality rejection, required document flow, self-approval and non-admin denial, duplicate submit, omitted locality decision, concurrent review, approval, stale-token denial after suspension, session revocation, audit/event history, and non-primary-admin denial for rider requirement mutation. |
| `flutter test --no-pub` | PASS; 75 tests. Includes backend-approved rider role gating and role-selection regression coverage. |
| `flutter analyze --no-pub` | 18 diagnostics: 3 warnings and 15 infos, 0 errors; matches the recorded Phase 2E baseline. Flutter exits 1 because of these pre-existing diagnostics. Changed rider Dart screens also passed focused `dart analyze` with no issues. |
| Admin `npm run typecheck` | PASS. |
| Admin production build | PASS with `npm exec next build -- --webpack` on Next.js 16.4.5. The default Turbopack build hit a Windows process-spawn `EPERM`; the webpack production build compiled, type-checked, generated all static pages and routes, and completed successfully with normal host permissions. |
| Admin targeted ESLint | PASS for the new Rider Management component, shared Admin portal client, navigation and route wrappers. |
| OpenAPI parse | PASS; OpenAPI 3.0.3 parsed, 123 paths. |
| APK build | PASS; WSL Flutter 3.47.8 built `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`. |
| Pixel 8 install and launch | PASS. The existing debug APK was installed and launched on `emulator-5554`; the app used the dedicated QA API at `http://10.0.2.2:18082`. |
| Admin browser against live Phase 3B API | PASS. Authenticated Playwright exercised primary-superadmin requirement setup, non-primary Admin denial without persistence, review of the same Pixel-submitted application, private evidence retrieval (200 `image/png`), evidence acceptance, locality approval, suspension, and reactivation. |
| Rider onboarding, approval and suspension through emulator UI | PASS. Pixel 8 submitted the QA application and image; Admin approved Kuanpal; the rider entered the Flutter Rider dashboard. Suspension revoked the existing session and removed Rider access. After reactivation and fresh OTP login, access returned. Force-stop/relaunch restored the approved Rider dashboard. Screenshots: [submitted application](screenshots/phase3b-pending.png), [approved workspace](screenshots/phase3b-rider-workspace.png), [session restore](screenshots/phase3b-rider-session-restore.png), [suspended access](screenshots/phase3b-suspended-roles.png). |
| PostgreSQL and private object storage | PASS in disposable QA. Final rows showed profile `approved`, Kuanpal locality `approved`, document `accepted` (`image/png`, 196389 bytes), and persisted approval, suspension, and reactivation events. Anonymous MinIO object access returned 403; authenticated Admin retrieval returned 200. The uploaded image was synthetic QA evidence, not an identity document. |
| Shared DB migration/data and QA cleanup | PASS. Migrations 001–025 and QA-only historical prerequisites were used only in a tmpfs-backed disposable DB. QA containers, network, images, and database were removed. Migration 025 was not applied to shared development. |
| `git diff --check` | PASS for the Phase 3B implementation paths; only Windows line-ending notices were emitted. |

## Remaining risks and launch gate

1. Obtain counsel/privacy review for rider eligibility, vehicle-specific evidence, agreements, insurance, worker classification, notice/consent, retention duration, and deletion/anonymization. No verification requirements are seeded to avoid inventing a legal checklist.
2. Define the retention/deletion workflow before collecting real rider documents. The schema deliberately prevents implicit cascade deletion; hard account deletion is not implemented for rider records.
3. Add malware scanning and document formats/business rules approved by counsel. Verify bucket IAM and private-object access in a disposable MinIO QA stack.
4. Apply migration 025 and deploy a matching API only to an approved QA/development target before rollout; it remains unapplied to the shared development database.
5. The Admin reviewer uses the repository's current Admin role; finer-grained reviewer RBAC is not present. Requirement configuration is restricted to the primary superadmin.

## Final acceptance recovery — 7 November 2026

The WSL and ADB blockers were checked from the Windows host. The WSL denial occurred in this restricted, non-elevated Codex process. Running the user's `wsl` command in the authorized host context successfully entered Ubuntu at `/mnt/d/grepmind-near`, and Docker remained accessible. No Flutter SDK, Android SDK, signing, or project WSL configuration defect was found.

The runner's alternate Windows ADB port 58991 failed its daemon handshake; a restricted foreground ADB start also reported `fdevent_poll.cpp:62 failed to create fdevent interrupt socketpair: Invalid argument`. The installed Windows SDK ADB worked from the authorized host context on the existing port 5037. It exposed both `emulator-5554` and `localhost:5555`, so device actions had to specify `-s emulator-5554`; commands without a serial were ambiguous. This was a host process/ADB daemon/transport issue, not an app or SDK build defect. No permanent environment changes were made.

An isolated PostGIS/API/Admin/MinIO stack applied migrations 001–025 only to a disposable tmpfs database, with two QA-only prerequisites for historical migrations. Shared development services and data were untouched.

### Verified in the final recovery

- Full `go test -count=1 ./...` passed against the disposable PostGIS database, including ownership, role, locality, evidence, concurrent review, approval, suspension, stale-token denial, session revocation, audit/event, and non-primary Admin requirement-mutation checks.
- The live Admin Playwright test `apps/admin-web/e2e/rider-acceptance.live.spec.ts` passed against the disposable API and real Admin UI. It verified primary-superadmin requirement configuration, 403 denial/no persistence for a regular Admin, private evidence retrieval, document acceptance, Kuanpal approval, old-session denial after suspension, and reactivation. Installed host Chrome was used because Playwright browser download was unavailable.
- The same QA rider submitted an application through the Pixel 8 UI, uploaded synthetic PNG evidence, and requested Kuanpal only. Admin reviewed and accepted the evidence, approved Kuanpal, and approved the rider. The app then displayed the enabled `Approved rider` selector and entered the Rider dashboard. The dashboard showed the approved locality and explicitly stated dispatch, delivery jobs, GPS and earnings are unavailable.
- Admin suspension removed Rider access in the app role picker and invalidated the already-issued token (Rider profile API returned 401/403). After Admin reactivation and fresh OTP login, Rider workspace access returned. Force-stop/relaunch restored the approved Rider dashboard. The disposable database showed profile/locality/document states of `approved`/`approved`/`accepted`; immutable history included approval, suspension, and reactivation. Anonymous MinIO object access returned 403, while Admin private-content access returned 200.
- Screenshots: [Admin checklist](screenshots/phase3b-admin-checklist.png), [non-primary Admin denial](screenshots/phase3b-admin-regular-admin-denied.png), [submitted application](screenshots/phase3b-pending.png), [evidence accepted](screenshots/phase3b-upload-verified.png), [suspended access](screenshots/phase3b-suspended-roles.png), [approved workspace](screenshots/phase3b-rider-workspace.png), and [session restoration](screenshots/phase3b-rider-session-restore.png). Login/OTP captures were removed to avoid retaining phone and verification-code data.
- This final runtime recovery did not rerun Flutter tests/analyzer or rebuild the APK; previously reported checks remain the evidence for those items (75 Flutter tests passed, 18 existing analyzer diagnostics, APK build passed). The already-built APK was used for device validation. `git diff --check` is rerun after documentation cleanup.

### Cleanup and remaining launch gates

- Disposable QA PostGIS, API, Admin and MinIO containers, network, QA-only API/Admin images and database have been removed. The synthetic evidence object disappeared with the disposable MinIO container. Migration 025 was not applied to shared development; no shared accounts, business records or orders were created or modified.
- Before onboarding real riders, obtain legal/privacy review for eligibility, document requirements, consent, retention/deletion, insurance and worker classification. Malware scanning and production private-bucket IAM configuration remain outstanding. The synthetic QA upload does not establish legal suitability of an evidence checklist.
- Admin UI rejection/changes-requested interaction was not exercised in this final browser run; state authorization is covered by Go integration tests. Dispatch, payment collection, GPS and rider earnings remain disabled. Phase 3C has not started.

### Final recommendation

**PASS for Phase 3B QA acceptance.** The Pixel 8, live Admin Portal, Go API, PostgreSQL and private MinIO were exercised together for application, document review, approval, Rider workspace access, suspension/revocation, reactivation and session restoration with one QA identity. This does not approve collection of real rider documents or enable delivery operations. Migration 025 remains unapplied to shared development, legal/privacy review is a pre-production gate, and Phase 3C requires separate authorization.
