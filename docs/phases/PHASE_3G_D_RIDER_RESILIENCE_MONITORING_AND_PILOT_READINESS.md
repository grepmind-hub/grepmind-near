# Phase 3G-D — Rider Operations Resilience, Monitoring & Pilot Readiness

**Status: PASS for isolated QA — Gate A and Gate B passed (10 November 2026)**
**Date:** 10 November 2026
**Scope:** Phase 3G-D only. Production, shared-database migration, payment collection, COD, real compensation, payouts, GPS and ETA remain unauthorized.

## Summary

This phase adds an authenticated Admin operational-alert read surface backed by delivery/recovery state, links an alert to its exact dispatch record, and improves Rider offer failure messaging. It also exercises the already implemented recovery model in disposable QA and installs one fresh debug APK on two Pixel 8 emulators.

The most concrete live result is a pre-pickup reassignment for QA order `GN-91B3F466`: Rider A's assignment remained released, Rider B accepted the retried offer, and the database showed exactly one active assignment. The Admin Dispatch board and Merchant Platform Orders view subsequently showed that same order assigned to Rider B. This does **not** prove all Phase 3G-D scenarios. Full lease-expiry recovery and the post-pickup return scenario were not completed in the live devices/portals, and emulator 5554 had a blank Flutter surface during final visual checks. Accordingly the acceptance result remains PARTIAL.

## Implementation

- Added a persisted operational-alert list endpoint in `backend/internal/deliverydispatch/alerts.go`, registered it in `backend/cmd/api/main.go`, and documented the actual endpoint in `api/openapi.yaml`.
- Extended Admin `apps/admin-web/components/DispatchBoardView.tsx` with loading, error, empty, refresh and filtering states, severity/type/duration summaries, and a “Review delivery record” action that targets the matching order reference in dispatch records.
- Added `riderOfferErrorMessage` handling in `apps/mobile/lib/core/screens/rider_workspace_screen.dart` and focused tests in `apps/mobile/test/rider_dispatch_test.dart`, distinguishing server rejection from connectivity failures.
- Added isolated QA helpers under `scripts/qa/phase3gd-*` for fixture setup, alert and rider status smoke checks, dispatch-state reads, QA order setup, and Rider B UI acceptance.
- No new migration was created for 3G-D. Migration 029 is required by the recovery domain but was applied only in disposable QA; it remains unapplied to the shared development and production databases.

Operational alerts are generated from persisted server state and do not auto-resolve from browser memory. During the observed reassignment, the open recovery/dispatch alert state cleared after the assignment was accepted and authoritative state no longer matched the alert condition. The alert list is a read view, not a durable event-delivery or background monitoring service.

## Fresh APK and devices

| Evidence | Result |
|---|---|
| Build command | `/home/grepmind/projects/flutter-setup/develop/flutter/bin/flutter build apk --debug --no-pub --dart-define=API_BASE_URL=http://10.0.2.2:18084` |
| Build result | Exit 0; APK timestamp 10 November 2026 03:53:44 UTC |
| Git revision | `b092268a239cb52001851be4db9d4f8db592c808` (worktree was dirty; build includes uncommitted files) |
| APK path/size | `D:\grepmind-near\apps\mobile\build\app\outputs\flutter-apk\app-debug.apk` — 205,687,328 bytes |
| Package | `local.grepmind.grepmind_mobile` |
| APK SHA-256 | `f20327babd4dde42e6656a1c1c73a5a63cd3dc192f5a1e495a1260aeb7cc7dbf` |
| Emulator A | `emulator-5558` (Pixel 8 Rider A); same APK hash installed; Rider A online screen captured |
| Emulator B | `emulator-5554` (Pixel 8 Rider B); same APK hash installed; Rider B accepted the targeted QA offer via visible UI automation and showed the assigned delivery in Flutter semantics |

Both devices reported booted/connected and installed the same build. Emulator 5554 produced a blank/splash-like screen capture on the final pass even though its UI accessibility tree exposed Rider state. That prevents claiming complete visual acceptance on both devices. Evidence files are in `docs/phases/evidence/phase3gd/`; specifically `rider-a-online.png`, `rider-b-online.png`, `rider-b-final.png`, `emulator-5554.png`, and `emulator-5558.png`. Some later captures reflect the renderer issue and should not be interpreted as successful visual proof.

## Live acceptance evidence

### Passed: pre-pickup recovery and reassignment

- QA order: `91b3f466-6ffa-4541-b189-479dad2aa832` / `GN-91B3F466`.
- Delivery job: `46c8b827-e149-41db-b41f-c4a72912bc82`.
- Rider A reported unable to continue before pickup. Merchant recorded no handover. Admin used exact-order confirmation to release and retry dispatch. Rider B came online and accepted the retried offer from the second emulator through the UI.
- PostgreSQL reconciliation showed Rider A's assignment `released`, Rider B's assignment `active`, and the delivery job `assigned`; order payment remained `not_collected`.
- The live Admin Dispatch board and Merchant Platform Orders view both showed `GN-91B3F466` assigned to QA Rider B after refresh.

### Passed: persistence across isolated API restart

The isolated API container was restarted while preserving the disposable PostGIS database. The API process returned to service, and the accepted assignment remained in persisted state with Rider A released and Rider B active. This verifies database persistence across API process restart for this accepted assignment. A full client-side authenticated reconciliation flow during the restart was not completed.

### Not completed in live acceptance

- No controlled Rider A heartbeat/lease-expiry window was completed with the emulator offline, then reconnected to prove the same active assignment reconciles without duplication.
- No separate live post-pickup order was carried through interruption, Admin Require Return, Merchant receipt (`not_restockable`), and Admin finalization in this 3G-D run.
- No full concurrent live API race matrix was executed. Existing automated tests and the 3G-B disposable PostGIS acceptance cover parts of recovery concurrency/idempotency; this is not equivalent to the full 3G-D matrix.
- Chhatia live device recovery was not tested.
- SSE reconnect durability remains bounded by the existing design: SSE is a live notification channel, while authenticated API reads are the canonical recovery mechanism. No durable replay guarantee is claimed.

## Test and build results

| Check | Result |
|---|---|
| `go test -count=1 ./...` (WSL) | PASS, all Go packages |
| `bash scripts/qa/phase3g_recovery_acceptance.sh` | PASS against a disposable tmpfs PostGIS database; migrations 001–029 applied there; targeted dispatch/isolation, Chhatia locality and Admin access tests passed; script removed its test container |
| `flutter test --no-pub` (Flutter 3.47.8 in WSL) | PASS, 93 tests |
| `flutter analyze --no-pub` | Completed, 18 diagnostics (3 warnings, 15 infos), exit 1 due diagnostics; matches documented baseline count, no new count increase reported |
| `node scripts/qa/phase3gd-alerts-smoke.mjs` | PASS: Admin endpoint HTTP 200, customer denied with 403, response contract checked; current alert count was zero after recovery |
| Admin `npm run typecheck` | PASS |
| Admin `npx next build --webpack` (WSL) | PASS, exit 0 |
| Merchant `npm run typecheck` | PASS |
| Merchant `npm run build` (Next.js 14.2.15, WSL) | PASS, exit 0 |
| `git diff --check` | No whitespace errors in checked changes; Git emitted line-ending conversion warnings for existing Windows worktree files |
| OpenAPI parse and migration validation | No new migration; route schema was added to OpenAPI. The complete migration chain was exercised by the disposable PostGIS acceptance script. |

The Windows sandboxed Flutter/WSL attempt returned `Wsl/E_ACCESSDENIED`; the approved Windows-host WSL execution path was used for successful Go/Flutter checks. A Windows Admin build attempt also failed to create a Turbopack worker in the restricted process context; the WSL Webpack production build succeeded. These are environment-specific command outcomes, not accepted application failures.

## Security, financial and inventory observations

- Admin alerts require Admin authorization; the smoke check confirmed an ordinary customer receives 403.
- Rider offers and state changes remain tied to the authenticated rider identity; the accepted QA reassignment was reconciled to the Rider B assignment.
- Merchant order visibility remained scoped to the assigned partner business in the live view. The recovery test suite includes merchant isolation and Admin role-boundary checks.
- Alert records avoid presenting customer phone/address or rider KYC fields. The currently authorized rider delivery detail includes the operational destination/contact information required to fulfill an assigned order; production privacy review should confirm the minimum field set and retention policy.
- Payment remained `not_collected`. This phase created no payment, COD, payout, or live compensation workflow.
- The live 3G-D reassignment did not exercise inventory return disposition or earnings posting. Prior automated recovery tests cover return inventory safeguards; no 3G-D live return or earnings reconciliation is claimed.
- No new OTP limiter or KYC-storage change was made. Production KYC malware scanning/private-storage authorization and retention/deletion controls remain separate release blockers.

## Performance observations

No representative load or latency benchmark was collected. The QA checks establish functional response and build completion only. The alerts view uses an explicit refresh/read request and does not create a new polling worker or SSE subscription. Production alert query latency, index plans under production-like volume, and memory impact remain unmeasured.

## Pilot runbook and readiness checklist

### Incident: rider offline with an accepted assignment

1. Search Admin Dispatch by the exact order reference and verify delivery-job and assignment IDs.
2. Check rider lease/heartbeat time and custody state; do not treat lease expiry as release.
3. Contact the assigned rider through the approved operational channel and read canonical assignment state from the API.
4. Before pickup, use the audited Admin release/retry workflow only after the required merchant no-handover evidence and exact-order confirmation.
5. After pickup, do not reassign automatically. Preserve custody, open/continue the return investigation, and follow the authorized Merchant receipt and Admin disposition steps.
6. Reconcile assignment, order, inventory reservation, audit events, payment state and any earnings entry before closing the incident.

### Incident: return or inventory disposition is unresolved

1. Confirm the exact order, delivery job, rider assignment and custody state.
2. Obtain Merchant evidence of physical receipt before disposition.
3. Use `not_restockable` when returned goods cannot be resold; never restore stock solely because an order was returned.
4. Require an authorized Admin disposition and verify the final order/job state plus a single inventory adjustment in PostgreSQL.
5. Confirm no completed-delivery earning or payment is fabricated for a failed/returned delivery.

### Pilot go/no-go items (not approval to launch)

- [ ] Isolated QA acceptance gates below closed, including lease expiry/reconnect, post-pickup return interruption, and concurrent races.
- [ ] Backup and restore rehearsal; migration rehearsal and explicit approved rollout/rollback plan for migrations 025–029.
- [ ] Legal/privacy review for rider documents, worker classification, retention/deletion, customer location and rider contact exposure.
- [ ] Production private object-storage authorization, malware scanning and KYC access audit.
- [ ] Production secrets, TLS, rate limits, security logging, alert ownership, escalation coverage and incident support rota reviewed.
- [ ] Merchant and rider onboarding readiness, locality coverage and no-rider/no-partner exception policy approved.
- [ ] Unpaid-order operational policy approved; do not infer COD from `not_collected`.
- [ ] Commercial compensation policy approved before enabling posting; payouts remain a separate capability.
- [ ] Load/performance baseline and observability thresholds measured.
- [ ] Separate explicit production deployment authorization obtained.

## Migration, rollback and cleanup

No Phase 3G-D migration was added. Recovery domain migration 029 was used only by disposable QA. It remains unapplied to shared development and production. Any later rollout must take a verified backup, rehearse the migration chain on a production-like copy, record the pre/post schema version, and define a tested rollback/forward-fix plan before approval.

This run used disposable QA database/API resources and temporary portal processes. The 3G-B acceptance script removed its own tmpfs test container. The shared development and production databases were not migrated or intentionally modified. **Full cleanup of the live 3G-D fixture/API/portal resources and their exact IDs was not verified at report time**; treat the remaining QA environment as requiring a final cleanup inventory before reuse. No commit or push was created. The worktree contains broad unrelated changes predating this phase; they were preserved.

## Acceptance decision

**PARTIAL — do not start another phase.**

Passed: fresh identical APK build/install on two emulators, Rider B UI offer acceptance, one pre-pickup Rider A → Rider B reassignment, same-order Admin/Merchant reconciliation, Admin alert authorization smoke, Go/Flutter tests, Admin/Merchant builds, and API-restart persistence for the accepted assignment.

Pending mandatory gates: live post-pickup return after interruption and the explicitly requested full concurrency race matrix. No production readiness is asserted.

## Phase 3G-D completion pass — 10 November 2026

This closeout supersedes the earlier pending notes above where the new evidence below is more recent. It does not change the phase decision from PARTIAL.

### Fresh build, device recovery and functional checks

- Rebuilt with Flutter 3.47.8 in WSL using `flutter build apk --debug --no-pub --dart-define=API_BASE_URL=http://10.0.2.2:18084`. Exit 0. APK: `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`, SHA-256 `b29b9d96b768a3919277ecff637ae8bf38b097ccd50d19b91de4f45159ba866e`, package `local.grepmind.grepmind_mobile`.
- The same APK was installed on `emulator-5558` (Pixel 8 Rider A; package last-update 16:12:12 local) and `emulator-5554` (Pixel 8 Rider B; 16:11:39 local). Both timestamps postdate the build at 16:10:29. Both app sessions were cleared after evidence capture; the APK remains installed.
- Rider A force-stop exceeded the 90-second online lease. PostgreSQL showed the assignment still `active`, Rider A offline with an expired lease, and payment `not_collected`. After relaunch, Rider A's Deliveries screen showed the same assigned QA delivery and retained the recovery actions. Admin's authenticated dispatch alert showed the matching order/job/assignment as stale and recommended investigation while retaining assignment custody. Merchant's authenticated order view showed that same order as preparing and assigned to Rider A. The screenshot `docs/phases/evidence/phase3gd/rider-a-active-assignment-message.png` confirms the corrected server-conflict message for refusing to go online while an active assignment exists.
- Rider B's fresh APK Deliveries screen was visually inspected and showed the currently assigned QA delivery, pickup action, and unable-to-continue action after recovering from an Android system “isn't responding” dialog. The screenshot was not retained in the report because it displayed a QA contact number and full test address. The system dialog was waited out; no Grepmind fatal exception was observed in the checked log excerpt. This is a successful final visual observation, not a performance or device-stability claim.
- The two tested live orders remain separate scenarios: `GN-91B3F466` was the earlier Rider A → Rider B reassignment; `GN-EFE5BA51` was used for Rider A lease expiry/reconnect and Admin stale-assignment monitoring. No order was falsely marked delivered or paid.

### Fresh automated checks

| Check | Result |
|---|---|
| `go test -count=1 ./...` (WSL) | PASS, all packages |
| `bash scripts/qa/phase3g_recovery_acceptance.sh` | PASS in a disposable tmpfs PostGIS container; targeted dispatch, Chhatia locality and Admin access tests passed; script removed its own container |
| `flutter test --no-pub` (WSL, Flutter 3.47.8) | PASS, 95 tests |
| `flutter analyze --no-pub` | Completed with 18 diagnostics (3 warnings, 15 infos), no errors, matching the recorded count. The shell wrapper did not preserve Flutter's exit code; do not classify analyzer as exit-code PASS. |
| `flutter test --no-pub test/rider_dispatch_test.dart` | PASS, 6 focused tests after the availability-message correction |
| Admin typecheck and Webpack production build | PASS in the earlier 3G-D run; not repeated in this closeout |
| Merchant typecheck and production build | PASS in the earlier 3G-D run; not repeated in this closeout |
| Admin alert authorization smoke | PASS in the earlier 3G-D run: Admin 200, customer 403; not repeated in this closeout |

The stale-lease integration test creates a recovery case and retains the active assignment rather than automatically releasing custody. Automated concurrency coverage includes same-offer acceptance, pickup verification, delivery completion, recovery cancellation/idempotency and return-resolution retries. This is useful coverage, but does not establish every requested cross-operation race (for example, concurrent lease sweep versus heartbeat or release versus pickup verification) as a complete race matrix.

### Performance observation

A local sequential sample of 20 requests to the QA API health endpoint measured min 1.9 ms, median 2.1 ms, p95 2.5 ms and max 46.7 ms. This is only a local health-check latency sample, not a representative API workload, concurrency, portal-render, emulator-frame or production benchmark. Admin alert refresh took approximately 4 seconds end-to-end including browser automation and UI state observation; this is not a server latency measurement.

### QA cleanup verification

- Removed only the named isolated QA containers `grepmind_3gd_qa_api`, `grepmind_3e_qa_api`, `grepmind_3e_qa_minio`, and `grepmind_3e_qa_db`, plus their now-unused network `grepmind_3e_qa_net`.
- Confirmed those containers had zero mounts; no QA volumes were present. The earlier tmpfs acceptance container had already removed itself.
- Confirmed shared development containers (`grepmind_api`, `grepmind_merchant_web`, `grepmind_admin_web`, `grepmind_worker`, `grepmind_nginx`, `grepmind_minio`, `grepmind_postgres`) remained running. No migration was applied to shared or production databases. No QA fixture database remains to inspect after container removal.
- Cleared Grepmind app data on emulator serials 5558 and 5554 to remove QA sessions. The production-like shared web containers were not stopped. The temporary Windows portal PIDs recorded earlier no longer existed at closeout.

### Final decision

**PARTIAL — completion pass closed; do not start another phase.**

Verified in this pass: fresh identical APK on both Pixel 8 emulators; Rider A lease expiration and app reconnect with assignment/custody retained; Admin stale-assignment alert and Merchant assignment reconciliation; fresh Go and Flutter suites; existing disposable PostGIS recovery acceptance; app session cleanup; isolated QA container/network cleanup; shared services preserved.

Still incomplete: a live post-pickup interruption → Admin Require Return → Merchant receipt/disposition → Admin finalization scenario in this 3G-D completion pass, and the full specified concurrent-operation race matrix. The prior automated suite covers several but not all race combinations. The performance sample is limited to the health endpoint. Hence the mandatory resilience acceptance remains **PARTIAL**, despite the verified pre-pickup lease-expiry recovery. Migration 029 remains unapplied to shared development and production; no production operations are authorized. No commit or push was created.

### Final two-gate acceptance attempt — 10 November 2026

This targeted pass attempted only the post-pickup interruption/return gate and the requested eight-case concurrency matrix. It did not change application source code.

| Check | Fresh result |
|---|---|
| Windows-host WSL and Docker | PASS when invoked through the approved elevated `wsl` path; the isolated QA stack was reachable. A non-elevated invocation still returned `Wsl/Service/E_ACCESSDENIED`. |
| Existing isolated QA checkout | Order `GN-B46C76B8` was still `placed`, payment `not_collected`, with no delivery job or active assignment. No state transition was attempted because the isolated Admin browser did not reach a usable login page. |
| Fresh APK | SHA-256 `8C658C3D789F0B45886432B408C737CEFE9E2DADB1EC9D6035AEA5CBC58DF954`; installed on `emulator-5558` and `emulator-5554`. Both packages were present after install. QA app data was cleared on both at cleanup. |
| Full Go suite | PASS: `wsl bash -lc 'cd /mnt/d/grepmind-near/backend && go test -count=1 ./...'`; all packages passed. |
| Disposable PostGIS recovery suite | PASS: `bash scripts/qa/phase3g_recovery_acceptance.sh` applied migrations 001–029 in its own tmpfs container, passed the existing dispatch/isolation, Chhatia and Admin role-boundary tests, then removed the container. This is not the full eight-race matrix. |
| Flutter tests | PASS: `flutter test --no-pub`; 95 tests passed. |
| Flutter analyzer | Completed with 18 diagnostics: 3 warnings and 15 infos, no errors. The shell wrapper did not preserve a numeric exit code in its captured output; do not classify the analyzer command as exit-code PASS. |
| Live Admin/Merchant recovery browser flow | NOT VERIFIED. The shared Admin server already owned the app's `.next` state, so an initial parallel dev-server attempt was rejected. Isolated `/tmp` source copies avoided that collision, but the Admin route remained compiling/unresponsive during the bounded readiness checks. No order mutations were made through API substitutes. |
| Eight-case concurrency matrix | NOT PASSED / INCOMPLETE. Existing database-backed tests cover same-offer acceptance retries, pickup verification, delivery completion, recovery idempotency/finalization retries, and cancellation retries. They do not cover all eight requested competing operations (notably acceptance-vs-expiry, Admin release-vs-pickup, Require Return-vs-delivery completion, heartbeat-vs-lease expiry, and reassignment-vs-stale recovery) with deterministic synchronization and per-case audit/inventory/earnings assertions. |
| Cleanup | PASS for resources created in this pass. Removed only `grepmind_3e_qa_api`, `grepmind_3e_qa_minio`, `grepmind_3e_qa_db`, and `grepmind_3e_qa_net`; removed temporary `/tmp/grepmind-3gd-admin` and `/tmp/grepmind-3gd-merchant` copies; stopped the managed temporary portal sessions; cleared app data on both emulators. Verified the shared Grepmind API, Admin/Merchant web, worker, Nginx, MinIO and PostgreSQL containers remained running. |

**Final recommendation remains PARTIAL.** Gate A did not reach the post-pickup phase and cannot pass without authenticated live Rider/Admin/Merchant actions on the same order plus PostgreSQL reconciliation. Gate B remains incomplete because the existing tests do not exercise all eight race pairs. No migrations were applied to shared or production databases, no order was advanced, no financial state changed, and no commit/push was created.

## Final blocker-resolution pass — 10 November 2026

**Scope:** Phase 3G-D Gate A post-pickup interruption/return and Gate B deterministic database race matrix only. No production deployment, shared database migration, or new phase was started.

### Portal readiness and isolated QA

- The isolated Admin and Merchant apps were built before serving, used separate QA copies/output directories, separate ports `3312` and `3313`, and the same disposable API on port `18083`. Authenticated Admin Delivery Dispatch and Merchant Platform Orders routes loaded API-backed order data.
- The previous portal compilation/startup failure was avoided by this prebuild-and-serve setup. Its original root cause was not conclusively isolated; do not treat the workaround as a definitive diagnosis.
- The isolated PostgreSQL/PostGIS/API/MinIO services were `grepmind_3e_qa_db`, `grepmind_3e_qa_api`, and `grepmind_3e_qa_minio` on `grepmind_3e_qa_net`. Migration 029 was present only in this disposable database; shared development and production databases were not modified.

### Gate A — live post-pickup interruption and return: PASS

New isolated Kuanpal QA order:

| Record | Value |
|---|---|
| Public order reference | `GN-708CC557` |
| Order UUID | `708cc557-d76e-42c1-854e-0be8849dbcea` |
| Delivery job UUID | `f7fdeb39-4eb4-409d-ba18-562e6325005f` |
| Assignment UUID | `1af158ff-99d0-49be-8181-cbb2cb1e8080` |
| Locality | Kuanpal, Cuttack |

The Merchant browser accepted/prepared the order and marked it ready. Rider A accepted it on Pixel 8 emulator `emulator-5558`, verified the partner handover, and submitted Unable to Continue after pickup. Admin opened the exact order/job, confirmed custody, and used the live Require Return workflow. Network was disabled on Rider A; PostgreSQL retained `out_for_delivery`, active assignment and `return_required`. After network restoration, the Rider UI reconciled the same assignment and return action in about 23 seconds. This is observed API reconciliation/polling; no SSE delivery is claimed.

Merchant then recorded physical receipt and `not_restockable` in the authenticated portal. Admin finalized the return through the authenticated recovery UI. The automation helper failed to observe the finalization HTTP response and did not save the intended final-state screenshot, so UI response/toast evidence is incomplete; PostgreSQL's finalization audit and persisted result provide confirmation that the action committed.

PostgreSQL reconciliation for the exact order:

- Order status `returned`; payment `not_collected`.
- Delivery execution `returned`; dispatch/job state remains `assigned` as a separate dimension.
- Assignment state `released`; there are zero active assignments.
- Return receipt disposition `not_restockable`; `finalized_at` is set.
- Inventory reservation is `consumed`, so the item was not put back into available stock. The tested mapping quantity remained 19; no restock increment occurred.
- Both relevant recovery cases are `resolved`; one Admin `delivery.return_finalized` audit row exists. Append-only recovery history contains rider report, Admin return requirement, Merchant receipt/disposition, and finalization.
- Rider earnings entry count is zero. No delivery-completion earning or payment was fabricated.

Sanitized screenshots:

- Pre-fix Rider state after reconnect, with address/contact redacted; this capture documents the stale-banner defect and is not final visual acceptance evidence: `docs/phases/evidence/phase3gd-final/rider-a-return-required-sanitized.png`.
- Admin custody/Require Return page: `docs/phases/evidence/phase3gd-final/admin-require-return.png`.
- Merchant return receipt and `not_restockable` disposition: `docs/phases/evidence/phase3gd-final/merchant-return-receipt.png`.
- A final Admin post-finalization success screenshot was not captured. Other raw Rider screenshots in the evidence folder contain QA address/contact data and are not sanitized; do not share them.

Screenshot review exposed a stale Rider success banner: after the API refreshed the job to `return_required`, the card showed the correct return action but the old banner still told the rider to wait for operations. The refresh logic now clears that report banner when authoritative state advances to return, return-in-progress, returned, cancelled, or delivered. A focused widget regression test verifies `return_required` shows “Start return to partner” and removes the stale text. The live order flow was not repeated after this presentation fix because the QA API had already been cleaned up; the final APK was rebuilt, installed, and launched on both emulators.

### Gate B — eight deterministic concurrency races: NOT PASSED

The existing DB integration suite was rerun, but its concurrent checks are not the requested deterministic eight-pair matrix. In particular, it does not orchestrate and assert all competing transaction outcomes for:

1. Two distinct riders accepting the same offer.
2. Offer acceptance versus expiry.
3. Admin release versus pickup verification.
4. Admin Require Return versus delivery completion.
5. Concurrent duplicate Merchant return receipts.
6. Concurrent duplicate Admin finalization.
7. Rider heartbeat versus lease expiry processing.
8. Reassignment versus a stale recovery action.

Existing tests cover some concurrent same-offer retries, pickup verification, delivery completion, idempotent recovery and other related behavior. Those results are useful but do not substitute for explicit synchronization barriers, competing real service/API transaction paths, final-state assertions, and audit/inventory/earnings invariants for each of the eight pairs. No race-matrix PASS is claimed and no race test suite or race-related source fix was added in this closeout; the Rider banner correction is a separate UI consistency fix.

### Fresh closeout validation

| Check | Result |
|---|---|
| Fresh debug APK build (Flutter 3.47.8, WSL) | PASS; API base `http://10.0.2.2:18083` |
| APK SHA-256 | `4A090C36D92B21A1A803865984C765F17BA5F075CC1AE1C44A557B05AF4FFF7A` |
| Emulator installs | PASS on `emulator-5558` and `emulator-5554`; same SHA-256; app data was cleared before final install; both app activities launched |
| `go test -count=1 ./...` | PASS |
| `bash scripts/qa/phase3g_recovery_acceptance.sh` | PASS; migration chain through 029 and focused PostGIS tests ran in a disposable tmpfs container, removed by the script |
| `flutter test --no-pub` | PASS; 96 tests, including the stale recovery-banner regression |
| `flutter analyze --no-pub` | Completed, 18 diagnostics (3 warnings, 15 infos), 0 errors; exit code 1 due diagnostics |
| Admin/Merchant production builds | PASS earlier in this Phase 3G-D run; not rerun in this final closeout |
| `node --check scripts/qa/phase3gd_portal_acceptance.cjs` | PASS |
| Targeted `git diff --check` | PASS for phase files and targeted mobile changes |

### Cleanup and final decision

Removed only the identified QA containers, the isolated QA network, two temporary portal directories and their exact Next.js processes. Cleared the Grepmind app data on both emulator serials while leaving the same APK installed. Verified the QA ports were released and shared `grepmind_api`, Admin/Merchant web, worker, Nginx, MinIO and PostgreSQL containers remained running. No QA volumes existed, no shared/production migration was applied, and no shared/production data was modified.

**Final status: PARTIAL — Gate A PASS; Gate B pending.** The phase cannot receive a full isolated-QA PASS until all eight deterministic race cases and their state/audit/inventory/earnings assertions are implemented and executed. No subsequent phase is authorized by this report.

## Gate B deterministic concurrency acceptance — 10 November 2026

This closeout supersedes the earlier Gate B pending statements above. Gate B was implemented in the disposable-PostGIS integration suite and the complete QA script was run twice against two separately created tmpfs PostgreSQL/PostGIS containers. Each run applied migrations 001–029, ran the Chhatia locality test, the complete dispatch/recovery integration scenario (including all eight race cases), and Admin role-boundary test, then removed only its own container. Both runs passed; no shared database, Docker volume, or production system was changed.

| # | Competing operations | Deterministic result and verified invariants |
|---|---|---|
| 1 | Assigned rider accepts an offer while a different rider attempts the same offer | One `200`, one `404`; only the assigned rider can accept; exactly one active assignment and one acceptance audit event. A single offer has one rider identity, so this exercises the same-offer ownership race without inventing a second valid offer owner. |
| 2 | Offer acceptance versus expiry processing | Expiry wins at the controlled boundary: acceptance returns `409`, offer is expired, no assignment is created from it, one expiry event is written, and dispatch advances to the next sequential offer. |
| 3 | Admin pre-pickup release versus pickup verification | One safe winner. Either pickup is verified and custody remains with the active rider, or the exact assignment is released before pickup. State, assignment, pickup event and release event assertions prohibit both effects from winning. |
| 4 | Admin Require Return versus customer-code delivery completion | One `200` and one `409`. Final execution/order/assignment state is internally consistent; only the winning return or delivery event is recorded. Payment remains `not_collected`; no completion earning is created by the return path. |
| 5 | Two concurrent duplicate Merchant return receipts | Both requests are successful/idempotent; exactly one receipt, one return audit entry and one return execution event are persisted. |
| 6 | Two concurrent duplicate Admin return finalizations with the same idempotency key | Both requests succeed idempotently and exactly one finalization audit effect is recorded; inventory/order/payment assertions in the scenario remain consistent. |
| 7 | Rider heartbeat versus lease-expiry processor | When expiry wins after heartbeat's initial read, heartbeat returns `409 AVAILABILITY_EXPIRED`; persisted rider availability remains offline. This exposed and fixed a race where heartbeat could report success after losing its conditional update. |
| 8 | Concurrent exact-reference reassignment/release versus stale recovery replay | One recovery releases the old assignment and emits one release event; competing/stale reference is denied (`404` or `409`). Replacement offer is accepted by the new rider, and replay against the old assignment leaves the replacement rider active. |

The offer accept/expiry race also exposed a PostgreSQL deadlock (`40P01`) caused by inconsistent row-lock order: acceptance held the offer then needed the job while expiry held the job then needed the offer. `RespondOffer` now locks the job before the offer, matching dispatcher processing order. A regression test synchronizes the real competing paths at PostgreSQL row locks. The stale-recovery test accepts either documented conflict/not-found denial (`409`/`404`) while verifying the new owner is untouched.

### Gate B implementation and fresh verification

- Changed `backend/internal/deliverydispatch/service.go`: consistent job→offer row locking; heartbeat checks conditional-update affected rows and returns `409 AVAILABILITY_EXPIRED` if lease expiry wins; nil-by-default synchronization hooks are used only to coordinate deterministic integration tests.
- Changed `backend/internal/deliverydispatch/integration_test.go`: eight DB-backed race cases use bounded PostgreSQL lock-wait barriers or a controlled service boundary, and assert status, custody/assignment, event/audit, inventory, payment and earnings invariants appropriate to each transition.
- Commands executed from the Windows host using `wsl`:
  - `wsl bash -lc 'cd /mnt/d/grepmind-near && bash scripts/qa/phase3g_recovery_acceptance.sh && bash scripts/qa/phase3g_recovery_acceptance.sh'` — PASS twice; both isolated containers removed by the script.
  - `wsl bash -lc 'cd /mnt/d/grepmind-near/backend && go test -count=1 ./...'` — PASS.
  - `wsl bash -lc 'cd /mnt/d/grepmind-near/backend && gofmt -w internal/deliverydispatch/service.go internal/deliverydispatch/integration_test.go'` — completed before the final two acceptance runs.
- A preliminary direct package invocation without `TEST_DATABASE_DSN` reported PASS while skipping database tests; it is not counted as acceptance evidence. The two disposable PostGIS script runs are the database-backed evidence.
- No new migration was added. Migration 029 was applied only to the two ephemeral tmpfs databases and remains unapplied to shared development/production.
- The script's EXIT cleanup printed `Removed disposable Phase 3G-B PostGIS container.` after each run. No commit or push was made. No emulator/browser run was repeated because Gate B only changed backend transaction handling and DB integration tests; prior Gate A evidence remains the live/device evidence.

### Final Gate B limitations and phase decision

The matrix proves the listed transaction races under deterministic local PostGIS barriers; it is not a production load test and does not replace monitoring, operational runbooks, production migration rehearsal, or an approved real-world compensation/payment policy. Phase 3G-D is **PASS for isolated QA** based on Gate A's previously documented live recovery and this fresh Gate B matrix. Production deployment and shared-database migration remain unauthorized. The existing 18 Flutter analyzer diagnostics and earlier noted ~23-second rider reconciliation / lack of fresh live banner-flow confirmation remain quality follow-ups, not claims of production readiness. Stop at Phase 3G-D and await explicit approval before any later phase.
