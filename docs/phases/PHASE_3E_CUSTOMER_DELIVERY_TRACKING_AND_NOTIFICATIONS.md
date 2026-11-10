# Phase 3E — Customer Delivery Tracking & Notifications

**Date:** 7–8 November 2026
**Scope:** Approved isolated QA only
**Current status:** PASS for isolated QA acceptance (9 November 2026). Kuanpal live SSE/reconnect acceptance remains accepted; Chhatia now passes a PostgreSQL-backed full locality-scoped delivery sequence, and a live Merchant Portal browser workflow passes against the isolated API. The historical ancillary Portal 500 did not reproduce; its exact earlier request was not captured, so its original trigger cannot be reconstructed.

## Objective and boundaries

Phase 3E extends the accepted Phase 3D delivery state machine with authenticated customer SSE updates, canonical API reconciliation, an ordered customer timeline, and recovery after reconnect or application restart. It does not add GPS, ETA prediction, payment collection, background push, or earnings. The QA order remained unpaid (`not_collected`).

## Implementation

- Reused the authenticated `/api/v1/events?order_id=...` SSE stream and existing order/delivery notifications. Client events are gated to the exact order ID, deduplicated by SSE event ID, and trigger canonical order, delivery-status, and event-history reads rather than mutating status from event arrival order.
- Added reconnect with bounded backoff, a connected-event reconciliation, periodic canonical refresh as a safety net, disposal on account changes/navigation, and terminal-state shutdown.
- Kept customer timeline milestones sourced from server history, preventing duplicate order-state rows. Added readable localized timestamps and labels for order/dispatch states.
- Fixed customer tracking reads before dispatch: an owned order without a `delivery_jobs` row now has a valid `not_dispatched` summary and its existing order history. A job with no active assignment must not be represented as a rider assignment. The corresponding database-backed regression test is included.
- Replaced runtime Google Fonts fetching in the mobile theme with Android's system sans font because the isolated emulator had no Google Fonts network access and the font fetch caused startup stalls/ANR. App visual styling and weights remain; this changes the runtime font face from Inter to the system sans face. No font package was added.
- No new database migration or public API shape change was introduced. The existing delivery-summary fields remain intact; their `execution_state` value is now truthful when no active rider assignment exists.

## QA environment and same-order evidence

### Final device acceptance run — 8 November 2026

- Used the approved Windows-host `wsl` command to run Flutter/Go work in the project Ubuntu environment. The isolated Phase 3E stack used the disposable PostGIS database on host port 55432 and API on port 18083; the shared development database and production were not migrated or modified.
- Built the customer APK with `API_BASE_URL=http://10.0.2.2:18083`, then installed/launched it on customer Pixel 8 `emulator-5554`. Rider Pixel 8 `emulator-5558` was also active. A previous APK build targeting the default port 80 was discarded; the final acceptance used the explicit isolated API URL.
- Created one Kuanpal QA Food order through the customer app: `GN-40E8FA3C` (`40e8fa3c-694d-4181-85bf-4a78ae9db0eb`). The same order was prepared by the partner, assigned to the approved QA rider, picked up, taken en route, and completed with customer verification on the rider device.
- While the customer remained on that order's tracking screen, the authenticated SSE connection delivered the rider-assignment, ready-for-pickup, rider-to-partner, arrived-at-partner, handover-verified, en-route, and delivered milestones. No manual refresh was used for those changes. The screen displayed `Live order updates connected`, then `Delivered with your confirmation`; no rider GPS or ETA was shown.
- After app restart, the exact delivered order reopened with its server-backed timeline and terminal state. The sanitized screenshot is `docs/phases/screenshots/phase3e-customer-delivered-after-restart.png`.
- API/PostgreSQL reconciliation for the same order showed customer order `delivered`, payment `not_collected`, delivery execution `delivered`, and zero active assignments. Each of the key arrival, pickup verification, en-route, and customer-OTP-verified lifecycle events was present exactly once.
- This run exposed a terminal-state presentation defect: after delivery, assignment release made the API summary appear as `not_started`, and the UI retained a dispatch/connectivity message. The backend summary now preserves terminal delivery execution state without an active assignment; Flutter resolves terminal delivery state ahead of dispatch state and shows `Order updates complete`. Focused regression tests cover the mapping and messaging.
- Deliberate network interruption during an active delivery and recovery of missed events after reconnect were not tested. Chhatia live-device acceptance and a live Merchant Portal browser workflow were not repeated during this final run. Earlier Merchant Portal interactions on the QA stack had shown an unexplained ancillary HTTP 500 toast; that remains unresolved.

- Used the disposable Phase 3E PostGIS database in a tmpfs-backed container, isolated API, MinIO container, Merchant Portal dev server, and Pixel 8 emulators `emulator-5554` (customer) and `emulator-5556` (rider). The database was migrated through 027 only; the shared development database was not migrated.
- A customer placed one platform Food order on emulator-5554. The authenticated Merchant Portal accepted it and started preparation. The customer screen displayed `Partner accepted` and `Partner is preparing` without tapping refresh; its connection card reported the authenticated live event stream connected. The same order was then marked ready for pickup in the Merchant Portal.
- After force-stopping and relaunching the latest APK, the customer session remained authenticated. My Orders listed that same order at `Ready for pickup`; reopening its exact order ID loaded the canonical timeline and showed the truthful no-rider-available state. Payment remained `not_collected`; no GPS or ETA appeared.
- Current PostgreSQL inspection confirmed that same QA order at `ready_for_pickup`, payment `not_collected`, a `no_rider_available` job, and zero active assignments. This is consistent with the customer screen. No delivery execution event exists yet for the order.
- A deliberate offline interval with a missed delivery update and restored-connectivity SSE recovery has **not** been proven. The brief network toggle did not establish a complete network outage, so no reconnect acceptance is claimed.
- The authenticated Admin dashboard and Dispatch board were verified visually in Chrome. The board showed the same order reference `GN-DDA410C8` in Kuanpal, Cuttack, with fulfillment `Ready For Pickup`, dispatch `No Rider Available`, active offer `None`, and rider `Not assigned`. This confirms Admin/customer/API records reconcile at the current pre-assignment state; it does not pass rider lifecycle acceptance.
- The user restarted and signed into the rider emulator directly. ADB now identifies it as `emulator-5558` (the emulator port changed during restart). The Rider dashboard was visually verified: QA rider access is approved for Kuanpal/Cuttack and delivery availability was online. No OTP was captured or returned to output.
- The Admin Retry action was then applied to a different, older QA job (`QA-ED81CEB2…` for `QA Dispatch Partner`) rather than the intended `GN-DDA410C8` order. The rider accepted that offer and advanced it to `arriving_at_pickup`; the subsequent arrival confirmation was correctly rejected because that old order was still `placed`, not `ready_for_pickup`. No further transition was attempted on that wrong order. Admin now shows the intended `GN-DDA410C8` still `Ready For Pickup`, `No Rider Available`, no active offer, and not assigned. This demonstrates a QA selection error on a dispatch board containing many similarly presented historical QA jobs, not a successful dispatch of the target order.
- A read-only database check after this attempt confirmed the intended order remained `ready_for_pickup:not_collected:no_rider_available`, with no active assignment. The QA rider has an active assignment to the stale `QA-ED81CEB2…` order, preventing reuse of that rider for the target under the one-active-delivery rule. Approved QA rider records exist, but none other than the assigned rider had an active online availability lease at the time of inspection. No database records were manually rewritten to force acceptance.
- The sandboxed ADB process failed with `fdevent_poll.cpp:62 failed to create fdevent interrupt socketpair: Invalid argument`; starting the existing ADB server through the approved elevated Windows-host path succeeded. The server initially listed emulator-5556 as offline; `adb reconnect offline` removed that stale transport. Following the user's restart, emulator-5558 is online and the customer emulator remains available.
- The Admin Rider Management view opened, but its current `submitted` application filter showed no applications; this is not evidence that no already-approved QA rider exists. Merchant Portal order actions did succeed, but it also displayed an ancillary `Request failed (500)` toast; no corresponding error detail appeared in the recent isolated API logs. Its source remains unresolved.

### Final reconnection acceptance — 9 November 2026

- Recreated the isolated tmpfs PostgreSQL/PostGIS database, API, and MinIO stack and applied migrations 001–027. The shared development database and production were not changed. The Windows-host `wsl` command was run with the approved elevated host path after the sandboxed invocation returned `Wsl/Service/E_ACCESSDENIED`.
- Installed the existing debug APK configured for `http://10.0.2.2:18083` on customer `emulator-5554` and rider `emulator-5558`. The QA customer authenticated in the app and opened the exact Kuanpal order `GN-A24CB71A` (`a24cb71a-85ca-4e96-96e2-ec3cd57e1a79`, delivery job `beec2888-7697-486b-9655-eacac17741f9`). The rider authenticated in the Rider app and was set online. Merchant and rider state transitions for this acceptance were performed through authenticated API calls against the disposable stack, not through Merchant Portal/Rider UI actions.
- Before interruption, the customer screen showed `Live order updates connected`; the API recorded an authenticated SSE connection for the QA customer. Airplane mode was enabled only on emulator-5554. The customer screen changed to `Reconnecting to live updates`, and order/history HTTP reads failed while the network was unavailable. The isolated API still accepted partner `ready_for_pickup`, rider arrival, pickup verification, and `en_route` transitions from the separate host-side QA workflow. No customer refresh control was tapped.
- On network restoration, the API logged the old customer SSE connection closing at 11:23:31 UTC and a new authenticated connection at 11:23:32 UTC. Within about ten seconds of restoring connectivity, the Pixel 8 showed `Live order updates connected` and the canonical timeline reconciled the missed Ready, rider-to-partner, arrived, handover-verified, and En route milestones. Recovery was through the new stream's connected event triggering authoritative API/history reads; this was not SSE event replay. The milestones appeared once and in order.
- The same order was then completed with customer delivery-code verification. The customer UI reached `Delivered` without manual refresh. The authenticated API reported `order_status=delivered`, `execution_state=delivered`, `payment_status=not_collected`, and no active rider assignment. PostgreSQL showed the same states; the delivery history contained one each of `customer_otp_verified`, `pickup_code_issued`, and `pickup_verified`, with three `state_changed` events (arrival, partner handover state, and en-route progression). No rider GPS or ETA appeared.
- The customer app was force-stopped and relaunched. Its QA session remained valid, My Orders listed the same order as Delivered, and reopening that exact order showed all ten ordered milestones through `Delivered with your confirmation`. Evidence: `docs/phases/screenshots/phase3e-reconnect-reconciled.png`, `phase3e-reconnect-timeline.png`, `phase3e-reconnect-delivered-final.png`, and `phase3e-reconnect-restart-final.png`.
- Fresh automated checks completed against unchanged source: full Go suite passed; the opt-in PostgreSQL dispatch/isolation integration test passed on the disposable `_qa` database; all 87 Flutter tests passed. Full `flutter analyze --no-pub` completed in 110.4 seconds with exit code 1 because it reported 18 existing diagnostics (3 warnings, 15 infos, 0 errors), matching the recorded 18-diagnostic baseline. The debug APK was installed and exercised on both designated emulators.
- QA cleanup removed the named API/MinIO/database containers, QA network and image, temporary auth/order files, temporary SDK overlay, and temporary accessibility captures. App data was cleared on both QA emulator profiles. `docker ps -a`, network, and image checks confirmed the named QA resources absent. Only `emulator-5554` and `emulator-5558` remain connected; the duplicate `localhost:5555` ADB alias was disconnected. Shared services/data were preserved.
- Chhatia was not exercised in this acceptance run. The existing dispatch integration test creates a Kuanpal fixture, and no Chhatia event-sequence integration test was found. Chhatia locality/event-sequence coverage and the earlier ancillary Merchant Portal 500 remain separate follow-ups.

## Security and truthfulness

- The SSE endpoint remains authenticated and customer-scoped. Existing Go tests cover foreign order/customer isolation; the mobile event gate rejects foreign order IDs, duplicate event IDs, and irrelevant event names.
- SSE carries state-change metadata, not pickup/delivery codes, KYC documents, precise rider coordinates, or private rider account fields. Customer summaries do not reveal a rider identity before policy allows it.
- Delivery, order, fulfillment, and payment states remain separate. No payment, rider position, ETA, or successful handover is fabricated.

## Validation from the earlier 8 November run (historical)

| Command/check | Result |
|---|---|
| `env -u TEST_DATABASE_DSN go test -count=1 ./...` | PASS; full Go suite, with opt-in DB tests excluded from this broad run. |
| `TEST_DATABASE_DSN="host=127.0.0.1 port=55432 user=qa3e password=… dbname=grepmind_3e_qa sslmode=disable" go test -count=1 ./internal/deliverydispatch -run TestDispatchPrepareOfferAcceptAndIsolation` | PASS against the disposable QA database, including no-assignment summary behavior and ownership checks. The password is omitted from this record. |
| `flutter test --no-pub` | PASS, 87 tests. |
| `flutter test --no-pub test/order_tracking_format_test.dart` | PASS, 5 focused terminal-state/timeline tests. |
| `flutter analyze --no-pub lib/core/screens/order_tracking_screen.dart` | PASS, no issues in the touched tracking screen. |
| `flutter analyze --no-pub` | Interrupted after prolonged `Analyzing mobile...` with no completion output; full analysis is unverified for this closeout. Historical 18-diagnostic result is not treated as a fresh result. |
| Debug APK | PASS, built with `API_BASE_URL=http://10.0.2.2:18083`, installed/launched on customer emulator-5554; same-order customer tracking and restart were visually verified. Rider workflow ran on emulator-5558. |
| Same-order SSE delivery flow | PASS through delivered on customer Pixel 8 without manual refresh; API/PostgreSQL terminal state and event counts matched. |
| Merchant Portal browser | Not exercised in the final run. Earlier QA portal workflow had an unexplained ancillary 500 toast. |

### Final reconnection rerun — 9 November 2026

| Command/check | Result |
|---|---|
| `wsl -e bash -lc 'cd /mnt/d/grepmind-near/backend && go test -count=1 ./...'` | PASS; all Go packages. Opt-in DB tests are separate. |
| `TEST_DATABASE_DSN=<disposable _qa DSN> go test -count=1 ./internal/deliverydispatch -run TestDispatchPrepareOfferAcceptAndIsolation` | PASS against the tmpfs-backed QA DB. The DSN/password is intentionally omitted. |
| `flutter test --no-pub` | PASS; 87 tests. |
| `flutter analyze --no-pub` | Completed; exit 1 with 18 diagnostics (3 warnings, 15 infos, 0 errors), equal to the recorded 18-diagnostic baseline. |
| Pixel 8 customer SSE interruption/recovery | PASS for Kuanpal order `GN-A24CB71A`: client showed reconnecting during network loss, backend progressed while the client was unavailable, a new authenticated SSE connection formed after restore, and canonical API reads filled missed timeline events without manual refresh. |
| Customer-code completion and restart | PASS; same order reached Delivered, then re-opened with the full timeline after app restart. API and PostgreSQL matched; payment remained `not_collected`. |
| Chhatia event sequence | NOT RUN; no existing Chhatia sequence integration test was found. No Chhatia device run was performed. |
| QA cleanup | PASS; named isolated resources and temporary QA files were removed; shared development and production were untouched. |

## Evidence

Sanitized screenshots are under `docs/phases/evidence/`:

- `phase3e-customer-live-accepted.png`
- `phase3e-customer-live-preparing.png`
- `phase3e-customer-restart-timeline-full.png`
- `screenshots/phase3e-customer-delivered-after-restart.png`

OTP/phone-entry screenshots are excluded from the deliverable evidence set. Screenshots containing any authentication code, real contact information, or secrets must not be retained.

## Remaining acceptance work

1. Review and resolve the 3 warnings/15 infos through a separately scoped analyzer cleanup; this is a quality backlog item, not a Phase 3E acceptance blocker.
2. Chhatia customer-device UI acceptance was not performed; the full locality-scoped lifecycle passed through PostgreSQL-backed integration coverage.
3. The exact historical request behind the ancillary Portal 500 toast cannot be reconstructed because no request/response capture or matching server error was retained. The current authenticated browser workflow against the full-migration isolated API passed with zero HTTP 5xx and zero uncaught page errors.

**Recommendation:** PASS for Phase 3E isolated-QA acceptance. The previously accepted Kuanpal Pixel 8 live SSE and reconnect results remain intact. Chhatia order `QA-CHHATIA-6336824f-3551-4298-9b70-d6fe6cc04d60` completed its locality-scoped dispatch and delivery sequence, with exactly one delivery job and job-created event, ordered customer milestones, one customer-verified Delivered milestone, payment `not_collected`, and zero active assignments. The live Merchant Portal accepted, prepared, and marked a Kuanpal QA order ready for pickup without a 5xx. The old toast is closed as non-reproducible in the current isolated stack; its historical trigger remains unknown and is not represented as a code fix. QA resources were removed. Phase 3F is not authorized and has not started.

### Targeted final closeout — 9 November 2026

**Chhatia locality lifecycle:** Disposable PostgreSQL/PostGIS database, migrations 001–027. Stable locality `02200000-0000-4000-8000-000000000201` (Jajpur → Chhatia) was verified active and delivery-enabled. A platform Food variant was explicitly mapped to an approved Chhatia partner. An approved Chhatia rider received and accepted the offer; an approved Kuanpal-only rider did not receive it. Partner accept → prepare created exactly one job and one `job_created` event → rider accept → ready for pickup → arrival → partner pickup verification → en route → customer-code delivery. Customer event history was asserted ordered and without duplicate milestones; pickup-code issuance was excluded. Final records: order `32021fbd-f61a-42a7-b60f-215a35814225`, reference `QA-CHHATIA-6336824f-3551-4298-9b70-d6fe6cc04d60`, job `cd95a147-f8f0-4145-899f-af34a5ce1209`; order and execution state `delivered`, payment `not_collected`, one delivered event, zero active assignments. This was backend/database acceptance; no Chhatia emulator run is claimed.

**Merchant Portal browser:** Temporary Next.js Merchant Portal on port 3311 proxied to the isolated API on port 18083. A real Playwright browser session signed in a synthetic manager, loaded workspace and order data, opened the order, and performed accept → prepare → ready for pickup. The run observed zero `/api/v1` HTTP 5xx responses and zero uncaught page errors. The customer order and PostgreSQL ended at `ready_for_pickup` / `not_collected`; dispatch reported no available rider and no active assignment. Screenshot: `docs/phases/screenshots/phase3e-merchant-browser-closeout-ready.png`.

The first browser attempt exposed an incorrect expected payment-copy string in the new test, then a subsequent request using the already-used synthetic phone hit the OTP rate limit. The test expectation was corrected and the successful run used a fresh synthetic QA manager identity; no OTP was printed or recorded.

The earlier `Request failed (500)` toast had no preserved request path, response body, browser trace, or matching API log. It was not reproduced in this complete API-backed workflow on the current code and fully migrated isolated database. No app/API source defect was confirmed, so no production-path code fix was made. This closes the current browser acceptance while retaining the historical evidence limitation.

**Checks executed:**

- `TEST_DATABASE_DSN=<disposable _qa DSN> go test -count=1 ./internal/deliverydispatch -run TestChhatiaDeliveryTimelineAndLocalityIsolation -v` — PASS.
- `env -u TEST_DATABASE_DSN go test -count=1 ./...` — PASS (full Go suite; opt-in DB tests excluded from this broad run).
- Live Playwright test `e2e/phase3e-closeout.live.spec.ts` against the isolated API — PASS (full merchant workflow, zero API 5xx, zero browser page errors).
- `npm run typecheck` in `apps/merchant-web` — PASS.
- Existing Kuanpal reconnection tests and Flutter results are prior accepted evidence, not rerun during this targeted closeout.

QA database, API/MinIO containers, network, image, temporary QA SQL, and temporary Portal process were removed after verification. Shared development data/services and production were untouched.
