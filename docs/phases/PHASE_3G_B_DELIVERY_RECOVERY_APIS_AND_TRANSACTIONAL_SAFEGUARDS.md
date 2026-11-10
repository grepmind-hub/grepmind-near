# Phase 3G-B — Delivery Recovery APIs & Transactional Safeguards

**Date:** 9 November 2026  
**Status:** PASS for backend and isolated QA scope  
**Next approval gate:** Phase 3G-C — Admin, Rider, and Merchant recovery workflows  
**Database:** Migration 029 tested only in a disposable tmpfs PostGIS database; not applied to shared development or production.

## Scope and boundaries

This phase implemented backend recovery contracts and database safeguards only. It did not add Admin, Merchant, or Rider UI, enable production dispatch, modify shared or production data, or implement GPS, ETA, customer payments, COD, rider payouts, or real compensation posting. Existing feature gating remains authoritative.

Pre-existing worktree changes were preserved. No commit or push was created.

## Implemented recovery model

Recovery is an incident overlay around the existing order, dispatch, and delivery execution state machines. Lease expiry and rider-reported inability create auditable cases; neither event releases an assignment or implies abandonment. A recovery action includes the expected assignment and execution state, so an out-of-date operator request fails with `409`.

Pre-pickup release or cancellation requires a durable, assignment-specific partner confirmation that the goods were not handed over. The API also checks for pickup-verification history and invalidates outstanding verification codes. Reassignment releases the old assignment transactionally and then resumes the existing sequential dispatch flow. Cancellation closes the job, assignment, offer/run state, cancels the order, and releases reserved inventory once.

After pickup, these recovery actions cannot release custody. A return remains a separate path: the partner records physical receipt, the partner records an explicit inventory disposition, and a delivery operator finalizes it. `restockable` releases the inventory reservation; `not_restockable` consumes it without increasing stock. The customer order becomes `returned` only at finalization. Payment remains `not_collected`.

## Database changes

Added additive migration `029_delivery_recovery_safeguards.sql`:

- `delivery_recovery_cases` and append-only `delivery_recovery_events` for incident and resolution history.
- `delivery_recovery_idempotency` for actor/key scoped request hashes and saved results.
- `delivery_return_receipts` for physical receipt, inspection disposition, and operator finalization.
- `delivery_recovery_partner_confirmations` for durable no-handover evidence tied to the exact assignment and business.
- A `delivery_operator` role, restricted to the existing primary-superadmin role-management path or the protected primary-superadmin account.
- Additive `returned` order/status-event values and `rider_unable_to_continue` exception type.
- Composite foreign keys binding recovery cases/events, return receipts, confirmations, orders, jobs, assignments, and businesses to the same underlying records.

Historical migrations were not edited. Fresh application of migrations 001–029 succeeded in the disposable QA database.

## API contracts

| Endpoint | Authorization | Behavior |
|---|---|---|
| `POST /api/v1/rider/delivery-jobs/{jobId}/unable-to-continue` | Current approved rider middleware and active assignment ownership | Opens one reasoned incident; does not release the assignment. Requires `Idempotency-Key`. |
| `POST /api/v1/merchant/businesses/{businessId}/delivery-jobs/{jobId}/recovery/no-handover` | Active membership in the exact assigned business | Records assignment-bound no-handover evidence. Requires `Idempotency-Key`. |
| `GET /api/v1/admin/delivery-recovery-cases` | Primary superadmin or active Admin with `delivery_operator` | Returns a bounded open recovery queue without customer contact, rider KYC, or precise location. |
| `POST /api/v1/admin/delivery-jobs/{jobId}/recovery` | Same delivery-operator authorization | Performs only `release_and_reassign_before_pickup` or `cancel_before_pickup`, with expected state/assignment, reason, partner evidence, and idempotency key. |
| `POST /api/v1/merchant/businesses/{businessId}/delivery-jobs/{jobId}/return/disposition` | Active membership in the exact assigned business | Records `restockable` or `not_restockable`; does not itself change inventory. Requires `Idempotency-Key`. |
| `POST /api/v1/admin/delivery-jobs/{jobId}/return/finalize` | Same delivery-operator authorization | Finalizes return status and applies the explicit inventory outcome. Requires `Idempotency-Key`. |

The existing `POST .../return/confirm` now records physical receipt and leaves the order `out_for_delivery` until disposition and operator finalization. Repeating this receipt is idempotent.

The OpenAPI contract was updated, including the new role and `returned` order status. Same actor/key with a different operation, route, or request payload is rejected with `409 IDEMPOTENCY_CONFLICT`.

## Security and concurrency controls

- Delivery-operator routes require an active Admin account plus the explicit role, except the protected root account. Ordinary Admin access is denied.
- Rider reports are bound to the caller's active assignment and approved rider/locality checks.
- Merchant evidence and return inspection are bound to active membership and the exact assigned `business_id`.
- Database row locks serialize order/job/assignment transitions; unique partial indexes prevent duplicate open incidents for the same assignment and incident.
- Transaction advisory locks serialize idempotency keys; side effects and saved response commit together.
- Recovery history is append-only. Administrative actions and partner confirmation are also written to the existing audit log.
- Stale lease processing opens a case but deliberately retains the assignment because lease expiry cannot prove physical handover state.
- No OTP values, private rider location, KYC, customer phone, or settlement prices are returned by recovery APIs.

## Validation executed

Commands ran through the approved Windows-host WSL path (`wsl`, project at `/mnt/d/grepmind-near`):

- `go test -count=1 ./...` — PASS.
- `bash scripts/qa/phase3g_recovery_acceptance.sh` — PASS. The script created a unique PostGIS container with PostgreSQL data on tmpfs, applied migrations 001–029, ran `TestChhatiaDeliveryTimelineAndLocalityIsolation`, `TestDispatchPrepareOfferAcceptAndIsolation`, and `TestAdminUserAccessRoleBoundaries`, then removed the container.
- Database-backed tests verified active-assignment heartbeat renewal, stale-lease case creation without assignment release, rider unable-to-continue and replay, partner no-handover evidence, missing-evidence denial, concurrent same-key cancellation, changed-payload idempotency conflict, post-pickup recovery denial, one-time inventory release on cancellation, return receipt/disposition/finalization, foreign merchant denial, returned order status, and unchanged `not_collected` payment.
- `python3 -c "import yaml; yaml.safe_load(open('api/openapi.yaml'))"` — PASS; OpenAPI YAML parsed as 3.0.3.
- `bash -n scripts/qa/phase3g_recovery_acceptance.sh` — PASS.
- Targeted `git diff --check` — PASS (Git emitted only its existing LF/CRLF working-copy notices).
- Cleanup check `docker ps -aq --filter name=grepmind_3gb_ | wc -l` — `0` containers remaining.

No Flutter tests, portal/browser tests, APK build, or emulator checks were run because this was a backend-only phase with no UI changes. No production or shared database was accessed.

## Remaining limitations and risks

- Migration 029 remains unapplied to shared development and production. Deployment requires a separately approved migration rollout and backup/restore plan.
- Phase 3G-C must add operator-facing recovery flows; these APIs are not yet exposed as UI controls.
- The Admin queue is intentionally bounded to 200 rows and does not yet have paging, filtering, or ownership assignment.
- Idempotency storage needs an operational retention policy. This phase does not add a scheduled cleanup process.
- Existing SSE is an in-memory post-commit notification mechanism, not a durable event outbox. Clients must reconcile through authoritative APIs.
- No comprehensive per-IP/device rate limiter was added for recovery endpoints. Case uniqueness and idempotency constrain duplicate effects but are not a substitute for a general rate-limit policy before live operations.
- Post-pickup rider replacement remains unsupported; physical custody requires a separately designed, auditable handover protocol.
- Returned-order status represents operational disposition only; no refund, payment, or earnings effect is implied.

## Recommendation

**PASS for Phase 3G-B backend and isolated QA acceptance.** Stop here. Phase 3G-C requires separate explicit approval.
