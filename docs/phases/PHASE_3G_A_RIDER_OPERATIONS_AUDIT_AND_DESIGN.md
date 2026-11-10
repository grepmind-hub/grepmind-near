# Phase 3G-A — Rider Operations Audit & Architecture Design

**Date:** 9 November 2026
**Status:** COMPLETE — documentation and source audit only
**Phase 3F:** Accepted PASS for isolated QA, per the accepted Phase 3F record.
**Next gate:** Phase 3G-B is proposed, not approved.

## Scope and evidence boundary

This milestone reviewed repository documentation, source, migrations, OpenAPI, and existing test code to identify operational recovery gaps and propose a design. No application code, migration, runtime, shared database, or production service was changed. No tests were run for this documentation-only audit. Existing Phase 3B–3F test and device results cited below are historical evidence from their phase reports; they were not rerun here. The shared database migration version was not queried.

The worktree contained extensive pre-existing modifications and untracked files. They were preserved. This report does not treat their presence, historical QA fixtures, or phase claims as proof of current runtime state.

## Executive assessment

Grepmind already has substantial delivery operations: approved-rider/locality eligibility, sequential expiring offers, transactional assignment, rider availability leases, pickup and customer-delivery OTP verification, exception reporting and return flow, Admin retry/manual assignment, customer-scoped SSE, and an append-only earnings ledger. The most consequential gap is **recovery after a rider has accepted an assignment**. A stale heartbeat only takes the rider offline; it does not create a visible incident or safely release/reassign the active job. Admin manual assignment currently applies before assignment, while retry handles exhausted dispatch, so a job can remain assigned to a disconnected rider indefinitely.

The design must distinguish lost connectivity from abandonment and physical custody. Before pickup, a reviewed, conditional release-and-reassign may be safe after partner-confirmed non-handover and invalidation of pickup verification credentials. After pickup, automatic reassignment is unsafe; preserve custody and use a controlled continuation or verified return. A returned delivery also needs an explicit terminal order disposition: current return completion closes delivery execution but does not itself establish a customer-order disposition or inventory outcome.

Recommendation: implement in three gated subphases: 3G-B transactional recovery contracts and audit trail; 3G-C focused Admin/Rider/Merchant operations UX and least-privilege access; 3G-D failure-injection and full Kuanpal/Chhatia acceptance plus runbooks. Keep GPS, ETA, customer payment/COD, payout, and real compensation posting disabled.

## Existing-versus-missing capability matrix

| Area | Existing evidence | Assessment / gap |
|---|---|---|
| Rider approval and API authorization | `backend/internal/riders/`; rider handlers use current approved-profile checks; Phase 3B report | Implemented. Revalidate status on every protected operation; no Phase 3B rerun in this audit. |
| Locality eligibility | `backend/internal/deliverydispatch/service.go`; migration 025 rider localities; Chhatia integration test | Implemented for configured localities. Planned localities must remain unavailable unless explicitly enabled. |
| Sequential offer lifecycle | `deliverydispatch.Service.Process`, offer accept/decline/expiry, retry; migration 026 offer/run tables and uniqueness constraints | Implemented for unaccepted offers. Expiration advances to the next candidate. |
| Concurrent assignment protection | Transactional offer acceptance and partial unique indexes in migration 026 | Implemented in schema/service; existing DB integration tests cover conflicting acceptance. |
| Rider online lease | `SetAvailability`, `Heartbeat`, periodic dispatch `Process` in `service.go` | Lease expiry marks the rider offline and records `lease_expired`; it does not surface or resolve active assigned-job risk. |
| Admin dispatch operations | `AdminBoard`, `Retry`, `ManualAssign`, cancel-offer and exception resolution in `deliverydispatch/service.go`; `DispatchBoardView.tsx` | Retry and manual assignment exist. No dedicated safe release/reassign of an already assigned rider; Admin routes use broad `requireAdmin`. |
| Pickup and delivery execution | `backend/internal/deliverydispatch/execution.go`; migration 027 | Arrival, partner pickup verification, picked-up, en-route, customer-code delivery, failure and return transitions exist. OTPs are HMAC-stored, expiring, attempt-bounded, and purpose-scoped. |
| Exception handling | Rider exception API and Admin `require_return` / `cancel_before_pickup`; `DispatchBoardView.tsx` | Basic exception flow exists. No unified incident lifecycle for stale rider, failed contact, reassignment, or final customer/order disposition after return. |
| Return finalization | `ConfirmReturn` in `execution.go`; return state and assignment release in migration 027 | Delivery becomes `returned`, assignment closes, and exceptions resolve. Order and inventory disposition are not finalized there. Migration 027 prevents cancellation after pickup, including returned state; define a compatible terminal disposition before operations. |
| Reassignment after accepted offer | Admin assignment and retry methods in `service.go` | Missing. Manual assign rejects an already assigned job. No API atomically releases the current active assignment and creates a recovery dispatch run. |
| Post-pickup rider replacement | No verified custody-transfer workflow found | Missing and intentionally unsafe to infer. Requires partner/platform custody evidence and explicit handover protocol; do not implement as a generic reassign. |
| Customer tracking and SSE | `backend/internal/notifications/`; order event authorization; Phase 3E report | Customer ownership checks and reconnect-to-authoritative-read design exist. SSE is in-memory/best-effort, not a durable event queue; events are hints, not the ledger. |
| Rider UI resilience | `apps/mobile/lib/core/screens/rider_workspace_screen.dart` | 25-second heartbeat/poll behavior and basic delivery actions exist. No explicit stale-assignment recovery workflow or durable incident resolution UI. |
| Admin operational visibility | `apps/admin-web/components/DispatchBoardView.tsx` | Board, history and exceptions exist. No heartbeat/lease age, stale-assignment classification, recovery queue, or unified order/job/execution/earning disposition view. |
| Merchant handover support | Merchant platform order screens and pickup/return confirmation APIs | Pickup/return confirmations exist. Partner-confirmed “not handed over” evidence for pre-pickup reassignment is not a distinct audited recovery contract. |
| Earnings consistency | `backend/internal/riderearnings/service.go`; migration 028; Phase 3F report | Append-only, idempotent delivery completion posting and audited adjustments exist; real policy/posting remains disabled. Recovery, cancellation, failed delivery, and reassignment compensation policy is not approved. |
| Rate limiting / abuse controls | OTP and delivery-code attempt/expiry controls in migration 027 and service | Per-code attempts/cooldown exist. Repository config includes rate-limit settings, but this audit found no general rate-limit middleware application; verify and add bounded endpoint throttling before live dispatch. |
| Operational observability | Existing logs, DB events, Admin board and phase runbooks | No evidence found of alerting/SLOs for stuck assignments, dispatch loop lag, failed event publication, or unresolved returns. Add before production. |

## Current state machines (as observed)

### Dispatch job and offers

`pending_dispatch → offered → assigned` or `no_rider_available`; retry returns exhausted work to `pending_dispatch`. Offers are sequential and expire/decline before another candidate is selected. Assignment and active-offer constraints are enforced in PostgreSQL. The job model does not currently provide a general assigned-job recovery transition.

### Delivery execution

`assigned → arriving_at_pickup → at_pickup → picked_up → en_route → delivered`.

Exception and return paths include `pickup_failed`, `customer_unreachable`, `delivery_failed`, `return_required`, `return_in_progress`, `returned`, and `cancelled`, subject to current transition checks. Pickup code issuance is separate from physical handover; code generation must not imply pickup. Delivered completion verifies customer OTP and creates the configured ledger effect transactionally; customer payment remains separately `not_collected`.

### Recommended operational incident overlay

Do not overload order, delivery-job, or execution statuses with every operational incident. Add an auditable recovery case linked to job, order, active assignment, rider, locality, incident type, and resolution. This keeps business state machines comprehensible while permitting multiple recovery attempts and explicit operator decisions.

Suggested case states: `open → investigating → action_pending → resolved` or `open/investigating/action_pending → escalated`. Terminal resolution records a resolution code, actor, reason, source evidence, related assignment/run, and timestamps. Do not allow hard delete or silent rewrite.

Suggested incident kinds: `assignment_heartbeat_stale`, `rider_reports_unable_to_continue`, `partner_handover_not_completed`, `pickup_verification_failed`, `customer_unreachable`, `delivery_failed`, `return_disposition_pending`, `dispatch_exhausted`, and `transition_conflict`. Avoid creating multiple open cases for the same active assignment and incident key.

## Proposed safe recovery architecture

### Invariants

1. A heartbeat timeout is a signal for investigation, not proof the rider abandoned the order. It must not automatically release an accepted assignment.
2. All recovery actions lock and re-read the order, job, execution, active assignment, rider approval, locality, offer/code state, and expected versions in one transaction.
3. Every action includes an expected active assignment ID and expected execution state/version. Stale Admin screens receive `409` and must reload.
4. Before pickup, reassignment requires explicit Admin authorization, reason, confirmation that the partner did not hand over the goods, and invalidation/revocation of outstanding pickup credentials. The old assignment is atomically released before a new dispatch run starts.
5. After pickup, no automatic release or reassignment. Rider retains custody until verified delivery or a controlled return/handover path is recorded. A second rider can take custody only through a separately designed, dual-actor handover with proof and an auditable custody chain.
6. Cancellation is allowed only when the order and inventory policy permit it. Never restore inventory twice; never infer saleable stock from a returned delivery.
7. Failed/returned delivery must end in explicit order disposition (`delivered`, `cancelled_before_pickup`, or a future reviewed `returned_to_partner`/`refund_pending` disposition). Never map `returned` to paid/refunded or create a payout effect automatically.
8. Earnings remain append-only and idempotent. Reassignment/recovery does not post, reverse, or split real compensation while policy is disabled. Future approved policies must define attribution for completed, partial, returned, and cancelled work first.
9. Publish customer/merchant/rider SSE events only after commit; clients reconcile by authoritative API. Where durable delivery is required, add an outbox in the same transaction rather than treating the current in-memory hub as durable.

### Proposed Admin recovery actions

| Action | Preconditions | Atomic effects | Result |
|---|---|---|---|
| `release_and_reassign_before_pickup` | Active assignment; execution before `picked_up`; partner confirms no handover; reason and expected assignment/version valid; rider/target locality eligibility rechecked | Lock order/job/execution/assignment; invalidate pickup OTP; close old assignment with reason; append recovery + delivery + admin audit events; set job pending; create a new dispatch run | Sequential offer cycle starts; old rider cannot act on job; customer sees truthful dispatch update |
| `cancel_before_pickup` | No physical handover; current cancellation policy permits; expected version valid | Lock and cancel job/order through existing compatible transaction; invalidate all codes; release finite stock exactly once; append event and audit | Terminal cancelled state; no earnings or payment success |
| `require_return` | Post-pickup exception; rider still authorized/current assignment | Record Admin decision and reason; require current assigned rider to enter return flow | Remains in rider custody until partner verifies return |
| `finalize_return` | Merchant confirms receipt; return evidence and assigned job match; explicit order disposition selected and allowed | Lock delivery/order/assignment; close custody; persist return disposition; resolve incident; preserve immutable history; stock disposition only by separate authorized inventory operation | Terminal operational result, no fabricated refund/payment or stock restoration |
| `escalate` | Open incident | Record escalation owner/severity and audit | No state-machine shortcut |

### Proposed API contract (design only; not implemented)

- Extend `GET /api/v1/admin/delivery-jobs` with `active_assignment_id`, `execution_state`, `last_rider_heartbeat_at`, `lease_expires_at`, `stale_since`, and `open_recovery_case_id`; avoid exposing precise rider location or private KYC.
- Extend `GET /api/v1/admin/delivery-exceptions` or add `/api/v1/admin/delivery-recovery-cases` with bounded pagination, locality/status/age filters, event history, and explicit owner.
- Add `POST /api/v1/admin/delivery-jobs/{jobId}/recovery` with an allowlisted `action`, `reason`, `expected_assignment_id`, `expected_execution_state`, optional eligible target rider, explicit partner non-handover evidence, and required `Idempotency-Key` for mutating recovery.
- Add `POST /api/v1/rider/delivery-jobs/{jobId}/unable-to-continue` for the currently assigned, backend-authorized rider to report reason and safe state; this opens an incident and does not release custody by itself.
- Extend merchant return confirmation to include the exact job/assignment and receipt condition; final order disposition remains a separately authorized and explicit decision.
- Actor identity, role, timestamps, and tenant scope are server-derived. Never accept client-supplied role, rider approval, order status, price, or settlement amount.
- Use documented errors: `401` unauthenticated, `403` unauthorized/ownership, `404` absent or non-visible resource, `409` stale state/assignment/idempotency conflict, `422` invalid action/precondition, `429` abuse throttling, `503` dispatch disabled/unavailable.

All routes must be added to OpenAPI and use bounded payloads. Do not return customer OTPs, rider KYC, private contact data, or partner settlement data in Admin board/event payloads unless strictly required by an authorized role.

## Database design proposal (no migration created)

Inspect the actual latest migration version and shared database version before choosing a migration number. Migration 029 is only a tentative next slot based on the repository’s current 028 history; this audit did not query a database.

Prefer a small additive recovery schema:

- `delivery_recovery_cases`: UUID, job/order, incident type, status, severity, locality, active assignment/rider snapshot, opened/updated/resolved timestamps, assigned operator, resolution code, reason, and optimistic version.
- `delivery_recovery_events`: append-only event ID, case/job/order/assignment references, event type, actor type/ID, reason, bounded JSON metadata, created time. Deny update/delete to application role or enforce immutable trigger consistent with existing event tables.
- Partial unique index for one unresolved case per job/assignment/incident key; indexes for locality/status/age and job history.
- Idempotency key uniqueness scoped to actor and operation. Store response identity/result, not bearer tokens or OTPs.
- Do not duplicate existing `delivery_events`, `delivery_execution_events`, or `audit_logs`; link recovery events to them where possible and define one authoritative owner for each fact.
- Do not add inventory-ledger or payout functionality in this phase. Return stock disposition must be a future explicit, audited operation.

Potential order-disposition schema/API changes must be designed against the current order status constraint and migration 027 trigger. Do not edit migration 027. A separate additive migration and backward-compatible transition must be reviewed and tested on disposable PostgreSQL/PostGIS before any shared rollout.

## Admin, Rider, Merchant and customer experience

### Admin Portal

- Add a “Recovery” queue with age/severity, locality, order reference, current rider/assignment, last heartbeat age, pickup/custody state, exception, and next safe action.
- Use exact order identity in all action dialogs. Require typed/explicit confirmation for release, reassignment, cancel, and return disposition; display “before pickup” vs “custody active” prominently.
- Show immutable history across dispatch offer, assignment, execution, exception, recovery, merchant handover, and earnings effect. Distinguish stale telemetry from confirmed failure.
- Add role-specific permission checks and visible API errors; avoid silently treating failures as zero incidents.

### Rider Flutter

- Show connection state and last successful heartbeat. On reconnect, fetch authoritative active assignment and event history before enabling mutations.
- Add “Report a problem” and explicit safe next steps. Never silently discard an accepted job when app is backgrounded or closed.
- If current rider no longer owns the active assignment, disable all state buttons and explain that operations reassigned/resolved it.
- Keep one active job invariant; preserve offline/error state and bounded retry. No GPS, ETA, or earnings/payout behavior is added here.

### Merchant Portal

- Provide explicit “not handed over” evidence for a pre-pickup incident and exact return receipt confirmation for an in-custody return.
- Keep customer address/contact limited to the merchant’s assigned order and current operational need.

### Customer tracking

- Display only committed canonical events. During recovery, use truthful states such as “Grepmind is resolving a delivery issue”; do not claim a new rider is assigned until backend assignment commits.
- SSE remains a notification mechanism; reconcile via scoped API after reconnect and app restart.

## Security, concurrency and reliability requirements

- Enforce current approved rider identity plus active assignment ownership for every rider operation; recheck suspension on each request.
- Enforce merchant membership and exact assigned `business_id`; enforce customer ownership on reads/SSE.
- Replace broad Admin-only role where possible with explicit delivery read, dispatch, recovery, and financial permissions; preserve root-superadmin protections for financial operations.
- OTP controls: keep purpose-bound HMAC, expiry and attempts; add layered per-account, per-job, per-IP/device abuse throttles with non-enumerating responses and monitoring. Never log codes or include codes in SSE/audit metadata.
- Serialize transitions with row locks and expected-version checks; use unique constraints for active assignments/cases/idempotency. Test races with concurrent requests and transaction rollback.
- Treat all event publication as post-commit. A transactional outbox is recommended before claiming durable notifications; continue API reconciliation for missed SSE.
- Add metrics/alerts for oldest pending dispatch, expired offer backlog, stale active assignments, no-rider duration, unresolved exceptions/returns, dispatch loop failures/lag, OTP throttles, and event publication failures. Avoid personal phone/address labels in metrics.
- Define retention/access rules for rider verification artifacts and location data before onboarding real riders; no continuous GPS is in scope.

## Proposed implementation plan and gates

| Subphase | Scope and dependencies | PASS criteria | PARTIAL / stop criteria |
|---|---|---|---|
| **3G-B — Recovery domain and APIs (L)** | After approval; inspect live migration version; additive recovery schema; transactional pre-pickup release/reassign, cancel, incident/return disposition design; idempotency, version checks, auth/throttling; OpenAPI and DB tests. Depends on existing 025–028 behavior. | Disposable PostGIS tests prove stale assignment detection without auto-release, exact-owner release/reassign, single active assignment, OTP invalidation, no-handover precondition, cancellation stock release exactly once, post-pickup reassignment denied, returned order explicitly finalized, duplicate/racing requests safe, no unauthorized access, no earning/payment side effects. | Any implicit custody transfer, ambiguous return/order status, shared DB migration, race, or silent failure stops acceptance. Do not move to UI until API/state contracts pass review. |
| **3G-C — Operational UX and permissions (M)** | Depends on 3G-B contract. Admin recovery queue and exact-target confirmation; Rider connection/problem state; Merchant non-handover/return receipt; customer truthful recovery state; role permissions and runbook links. | Browser/device flows against disposable API show one same incident through report → review → safe resolution; unauthorized roles denied; exact order/assignment visible; accessible loading/error/retry; no fake GPS/ETA/payment/earnings; existing dispatch/tracking/ledger screens regress cleanly. | Any action bypasses 3G-B preconditions, hides backend errors, exposes sensitive records, or mutates financial state. |
| **3G-D — Resilience acceptance and operations (M)** | Depends on 3G-B and 3G-C. Failure injection, Kuanpal and Chhatia full acceptance, monitoring dashboards/alerts and incident runbooks; isolated cleanup. | Full lifecycle and recovery scenarios pass on disposable stack: declined/expired offers, stale pre-pickup connection, reassignment, post-pickup connectivity loss with custody preserved, failed delivery/return disposition, idempotency/concurrency, SSE reconnect/API reconciliation, Admin/Merchant/Rider/customer DB/UI agreement, QA cleanup. Operational runbooks and rollback tested. | Chhatia backend-only or historical tests do not substitute for required UI acceptance; unresolved return or ledger reconciliation remains PARTIAL. |

Complexities are solo-developer planning estimates, not commitments: 3G-B large, 3G-C medium, 3G-D medium-to-large due to multiple portals/devices and isolated infrastructure.

## Production risk register and runbooks

| Risk | Severity | Required control before live operations |
|---|---|---|
| Accepted rider disconnect strands job | High | Recovery case, lease-age visibility, human review, safe pre-pickup release/reassign; alert on age. |
| Reassign after physical handover breaks custody | Critical | Hard server-side prohibition after `picked_up`; verified handover protocol only in a separate reviewed feature. |
| `returned` delivery leaves customer order unresolved | High | Explicit order disposition, customer communication policy, stock disposition policy, and reconciled terminal state. |
| Broad Admin role can perform dispatch override | High | Fine-grained delivery permissions, strong audit, exact-target confirmation, root-protection preservation. |
| OTP brute force / enumeration | High | Per-account/job/IP throttling, alerts, generic errors, secret-safe logs, test lockout and recovery. |
| In-memory SSE loss | Medium/High | Outbox if durable delivery is required; API reconciliation remains authoritative. |
| Compensation disagreement after reassignment/return | High | Approved policy before real posting; append-only corrections; no automatic posting until explicitly enabled. |
| Unpaid order operations unclear | High | Written operational rule before production; `not_collected` never implies COD or rider collection. |
| Migration/storage/KYC rollout | High | Backup/restore rehearsal, migration approval/rollback plan, private object-store IAM, malware scanning, retention/deletion and legal review. |

Runbooks to deliver with 3G-D:

1. **No rider available:** verify locality and eligibility configuration; inspect dispatch-run and candidate exclusion reasons; do not manually assign an ineligible rider; communicate only confirmed status; escalate by age threshold.
2. **Rider heartbeat stale before pickup:** contact rider/partner; verify no handover; inspect exact assignment and codes; use audited pre-pickup recovery only after all checks; confirm old rider loses access and new assignment is unique.
3. **Rider disconnects after pickup:** preserve assignment/custody; contact rider and customer through approved channels; do not reassign automatically; escalate to operations and follow controlled return/physical handover policy.
4. **Delivery OTP unavailable or exhausted:** do not mark delivered; verify customer identity through approved recovery; issue bounded resend/attempt process; preserve event/audit trail.
5. **Return received but order unresolved:** keep case open until merchant receipt and explicit order disposition; do not restore stock or claim refund/payment absent authorized operation.
6. **Dispatch/event service degraded:** disable new dispatch via existing feature gate if necessary; keep reads available; reconcile canonical API/DB after recovery; record incident and verify no duplicate assignment.
7. **Schema rollout/rollback:** backup and restore rehearsal, migration lock/version verification, additive migration review, isolated rehearsal, stop dispatch during incompatible rollout; never rewrite historical migrations.

## Decisions required before implementation approval

1. Set initial stale-assignment alert threshold based on measured heartbeat interval and expected mobile network gaps. The audit does not prescribe a production timeout; a future QA default may be two missed leases, clearly labeled configurable.
2. Confirm who may approve release/reassignment (delivery operator vs any admin) and whether two-person approval is needed for post-incident exceptions.
3. Confirm merchant evidence required to prove “not handed over” before reassignment.
4. Define final customer-order status, refund/customer communication ownership, and inventory disposition after return. This remains unresolved and blocks safe production return operations.
5. Define operational contact and escalation SLA for Kuanpal and Chhatia.
6. Keep real rider compensation posting disabled until policy approval; define attribution for reassigned, cancelled, partial, and returned deliveries before enabling.
7. Confirm OTP request throttling values and retention/privacy review with responsible legal/security reviewers.

## Audit conclusion

The current foundation is suitable for a carefully scoped recovery implementation, but not yet evidence of production-ready exception operations. The immediate highest-priority gap is stranded accepted assignments; the most important safety invariant is custody-aware recovery. The return/order disposition gap must be resolved before failed deliveries can be considered operationally complete. Proceed only with an explicit Phase 3G-B approval after the decisions above are resolved or explicitly deferred with safe behavior.

**Recommendation:** Phase 3G-A COMPLETE as a design milestone. Phase 3G-B NOT STARTED / NOT APPROVED. No tests, runtime validation, database inspection, migrations, code changes, commits, or deployments were performed in this audit.
