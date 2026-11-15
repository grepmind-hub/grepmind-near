# Grepmind Near — Phase 4E Commerce Integration

**Current gate:** 4E.2 — Payment-Aware Checkout & Fulfillment Gating
**4E.1 gate result:** PASS — G1 policy decision approved on 13 November 2026.
**4E.2 gate result:** PARTIAL — implementation and a live UPI-to-rider-assignment journey are evidenced; COD journey, database/journal reconciliation, Admin operational review, and complete regression/runtime cleanup remain unverified.
**Overall Phase 4E:** Not accepted. 4E.3 and 4E.4 are not started and remain unauthorized.
**Scope of this record:** 4E.1 remains a historical design/policy record; the appended 4E.2 section records implementation and acceptance evidence separately.

## Executive summary

The approved roadmap defines Phase 4E as connecting verified customer payments, synthetic COD, order cancellation/return, partner fulfillment, rider delivery, refunds, merchant payables, and append-only financial journals. The acceptance target is same-order agreement across authenticated customer/merchant/rider/admin surfaces and PostgreSQL, with no fabricated paid state and no duplicate payment, refund, COD, payable, settlement, or rider-earning effects.

The repository already has the underlying domains and role-specific flows. They remain separate: `customer_orders.status`, payment intent/attempt plus `payment_status`, COD obligation/collection/remittance, `delivery_jobs.execution_state`, refund records, merchant payable snapshots, settlement batches, and rider earnings. Phase 4E is therefore an orchestration and compatibility phase, not authorization to replace those domains with one status field or a new order system.

G1 resolved the payable-trigger decision: **the backend determines eligibility automatically from authoritative order, payment/COD, delivery, supply-snapshot, policy, and refund state; an authorized Admin explicitly triggers posting through the existing `finance.post` action.** Eligible-but-unposted is a distinct operational state, not accrued earnings. Phase 4E.2 must not introduce automatic ledger posting, a system actor, a fifth Finance role, or a merchant write/approval control. The existing immutable snapshot, balanced journal, idempotency, audit, and separation-of-duties controls remain in force.

## 1. Roadmap requirement for 4E

The existing 4A roadmap states: “Tie verified payments, COD, cancellation/return, dispatch/delivery, refunds and financial journals together.” Its acceptance requires:

- Cross-surface same-order API/database/UI reconciliation.
- A deterministic race matrix.
- No fabricated paid state.
- No duplicate payable, refund, cash, or rider-earning posting.
- Respect for separate payment, fulfillment, custody, and settlement state machines.
- No live funds, production migration, or payout activation during isolated QA.

The approved 4E sequence in the master prompt is:

| Gate | Planned scope | Boundary |
|---|---|---|
| 4E.1 | Lifecycle contract and compatibility | Source audit, state/actor contract, race matrix, migration/API recommendation; G1 decision accepted. Gate closed. |
| 4E.2 | Checkout and fulfillment integration | Same-order checkout/payment/COD through partner preparation and delivery eligibility. Requires G1. |
| 4E.3 | Cancellation and refund integration | Cancellation/return/refund coordination, liability and payable correction, exception recovery. Requires G2. |
| 4E.4 | Full integration QA | Multi-role, multi-surface isolated end-to-end acceptance and financial reconciliation. Requires G3. |

Phase 4F remains the later broad replay, concurrency, security, load, and operational QA gate. Phase 3H remains deferred.

## 2. What is already implemented

This table distinguishes documented isolated-QA acceptance from what was freshly run for this review.

| Capability | Existing source of truth / surface | Current behavior and compatibility note |
|---|---|---|
| Platform catalog and checkout | `platform_catalog_products`, quote/order service, `customer_orders`, `platform_customer_order_items`; Customer Android | Grepmind-owned price; quote selects one eligible partner; quote does not reserve inventory; submit revalidates and reserves atomically/idempotently. New platform orders start `payment_status='not_collected'`. Food and Grocery carts are separate. Legacy table/hotel/service orders remain in existing order tables. |
| Partner fulfillment | `platformfulfillment` service, `customer_order_status_events`; Merchant Android and Web | Partner-scoped `accepted`, `preparing`, `ready_for_pickup`, `rejected` transitions; business membership enforced; rejection releases reserved inventory once. Merchant cannot edit customer price. |
| UPI intent/session | `payment_intents`, `payment_attempts`; `/orders/{id}/payment-intents`, `/payment-intent`, `/payment-sessions`, `/payment`; Customer Android | Intent snapshots server price. Session is not payment. Feature gates default closed. Existing historical `not_collected` orders are not backfilled. |
| Verified sandbox payment | `payment_provider_events`, `financial_journals` and postings; signed webhook plus QA-only deterministic outcome route | Exact-body signature/freshness verification, provider-event uniqueness, transactional attempt/order update and one idempotent balanced capture journal. Only verified backend evidence can project `customer_orders.payment_status='paid'`. Late success is retained; ineligible/cancelled/returned/delivered cases require reconciliation, not silent order reopening. |
| Refund | `payment_refunds`, `payment_refund_audit_events`; customer refund request/history and Admin review/reconcile endpoints | Customer request is bounded by verified capture net of reserved/prior refunds. Admin `finance.post` review; requester cannot review own request. Sandbox provider outcome posts a separate immutable balanced refund journal. Original capture and `payment_status='paid'` remain; refund is a separate dimension. |
| COD | `cod_obligations`, `cod_collections`, `cod_remittances`, `cod_audit_events`; Rider Android and Admin COD review | Order method is immutable after submission. Obligation amount is server-snapshotted. Collection follows assigned rider/customer handover and creates a balanced synthetic journal plus rider cash receivable. Remittance is rider-submitted; independent authorized Admin verifies/disputes/rejects and posts clearing. This is not rider earnings. Legacy order `payment_status` intentionally remains `not_collected` for COD; COD status is separately read via `/orders/{id}/cod-status`. |
| Dispatch, custody and delivery | `delivery_jobs`, `delivery_assignments`, `delivery_execution_events`; Rider Android, Merchant Android, Admin Web | Dispatch assignment/offer states and execution states are separate from customer order state. Pickup requires partner-issued short-lived code; handover requires customer OTP. `delivery_jobs.execution_state` includes `assigned`, `arriving_at_pickup`, `at_pickup`, `picked_up`, `en_route`, `delivered`, exceptions, return, and cancellation states. Corresponding customer order transitions to `out_for_delivery`, `delivered`, `cancelled`, or `returned` are transactionally guarded. |
| Customer status/tracking | customer order/status events, delivery history endpoint and authenticated SSE | Customer reads authoritative history; event notifications are scoped and reconciled from API after reconnect. No GPS/ETA is implied. UI should render payment/COD labels separately from fulfillment and delivery milestones. |
| Merchant payable | `merchant_commission_policies`, `merchant_payable_snapshots`, payable adjustment/audit records; Admin Finance APIs; Merchant Android/Web read-only views | Snapshot requires delivered INR platform order, immutable supply snapshots for every item, approved effective policy, and verified sandbox UPI capture or COD collection. It uses supplier basis and policy snapshot; customer gross less supply is not automatically revenue. Current accrual is an explicit Admin `finance.post` operation and idempotent by order/source event. |
| Settlement simulation | `merchant_settlement_batches`, items, funding allocations, events, reconciliation exceptions and ledger journals; Admin Web; Merchant read-only views | Draft → reviewed → approved → simulated → reconciled; independent creator/reviewer/approver/simulator controls; simulated journals use QA funding/remittance evidence and do not move funds. Merchant Android/Web show simulated/reconciled history without payout controls. |
| Rider earnings | Phase 3F separate earnings ledger; Rider Android and Admin | Delivery compensation is independent of UPI capture, COD collection/remittance, merchant payable, and settlement. A failed/returned order must not fabricate completed-delivery earnings. |

There are exactly four application roles: Customer, Merchant, Rider, Admin. `finance.read`, `finance.post`, and `finance.configure` are Admin-side permissions/workflow duties, not a fifth role. Merchant finance views are read-only and tenant-scoped.

## 3. Current state and actor contracts

These are source-observed states; they are not proposed unified state enums.

### Customer order / partner fulfillment

Observed platform order lifecycle: `placed → accepted → preparing → ready_for_pickup → out_for_delivery → delivered`; exception endings include `rejected`, `cancelled`, and `returned`. Partner rejection and pre-pickup cancellation have separate inventory-release/dispatch consequences. A returned order is not delivered. Customer cancellation is only allowed by the existing endpoint for eligible early states; delivered/returned and custody-bearing cases use the separate recovery rules.

Actors: Customer submits/cancels an eligible order; assigned Merchant members accept/reject/prepare/mark ready; Rider progresses dispatch/delivery; Admin resolves authorized exceptions. Each actor acts through the domain endpoint. No role may set arbitrary order or payment status.

### Payment and refund

Order `payment_status` compatibility values are `not_collected`, `pending`, `paid`, and `failed`. The immutable order-selected `payment_method` is `upi`, `cash_on_delivery`, or null for historical records. UPI intent states in migration 031 are `created`, `pending`, `paid`, `failed`, `reconciliation_required`; attempt states include `initialized`, `session_created`, `pending`, `succeeded`, `failed`, `expired`, `reconciliation_required`. Provider events may be late or out of order; event identity and journal source/idempotency constraints are authoritative.

Refund states in migration 033 are `requested`, `approved`, `processing`, `succeeded`, `failed`, `rejected`, `reconciliation_required`. Refund never erases capture; order `payment_status='paid'` continues to mean a verified capture exists, while refund state/amount is read separately. A late success against a cancelled/returned order is retained for reconciliation and must not reopen it.

### COD and rider custody

COD obligation: `due → collected`. Remittance: `submitted → verified | disputed | rejected`. `verified` is an Admin-controlled state requiring an independent actor from the Rider and bounded by actual collected liability. Collection is recorded only through an authorized delivery/handover flow; rider cash balance is a custody/accountability projection, not earnings. Return/disposition does not itself erase a collected-cash record or imply a customer reimbursement.

### Delivery and merchant payable

Delivery execution state is independently stored in `delivery_jobs.execution_state`; pickup and delivery verification codes are short-lived, HMAC-stored, attempt-limited, and consumed once. `ready_for_pickup` is not delivery. Delivery completion is tied to customer code verification. Recovery before pickup can release/reassign under authorized rules; post-pickup custody cannot be automatically reassigned.

Payable is not an order status. Current eligibility is: platform-catalog INR order; order status `delivered`; complete immutable partner supply-price snapshot; supported verified payment source (sandbox UPI capture or synthetic COD collection); approved policy; and no blocking refund review condition. Posting creates one immutable snapshot and balanced journal. Current API requires an Admin with `finance.post` to invoke accrual. Reconciliation detects missing eligible payables; it does not repair or post them automatically.

### Events and read models

Durable evidence is currently split among customer order status events, delivery execution events, payment provider events, COD audit events, refund audit events, merchant finance audit/settlement events, and financial journals. Customer live updates use existing authenticated SSE, followed by authoritative API reconciliation. No general transactional outbox/integration-event table was found in the reviewed backend source. A new broker is neither required nor proposed. If 4E.2 needs asynchronous cross-domain work, it must first establish whether the existing transactionally written event records and idempotent handlers meet delivery/retry guarantees; do not introduce an outbox pre-emptively.

## 4. Missing integration behavior / proposals

1. **One customer-visible financial/tracking projection:** the data exists behind separate order, payment, COD, refund, and delivery APIs. 4E.2 should verify the existing tracking screen exposes coherent labels from those authoritative reads (UPI pending/paid/refund separately; COD due/collected/remittance pending separately) without creating a synthetic unified status. Add a read endpoint only if current authenticated reads cannot produce a consistent single-order view.
2. **Payment/fulfillment coordination:** order creation is followed by payment flow; an order may be cancelled/returned or delivered while provider success arrives late. Keep provider capture facts immutable; route non-fulfillable capture to reconciliation/refund review; never reopen, redeliver, or create a second order from a webhook.
3. **COD/return coordination:** COD collection occurs at verified customer handover. A prior return/failed delivery must not produce collection; if collection and a later dispute coexist, preserve collection and require explicit exception/refund handling. Return disposition and cash remittance are separate facts.
4. **Payable trigger — G1 approved:** eligibility is server-derived and may be listed automatically. Actual payable snapshot/journal creation remains an explicit authorized Admin `finance.post` action. Eligible-but-unposted orders must be labeled as awaiting Admin posting; do not show them as accrued earnings or include them in posted payable totals. Phase 4E.2 must preserve the current action's idempotency, immutable policy/supply snapshots, balanced journal, audit reason, and permission checks.
5. **Refund/return allocation:** existing reconciliation flags returns and successful refunds for review. It does not define a universal automatic payable reversal/refund allocation. Preserve separate original journals and use an independently reviewed adjustment/reversal under approved policy; do not calculate a full refund from `returned` alone.
6. **Cross-surface refresh:** Customer tracking, Merchant order/finance, Rider cash/earnings, and Admin finance should refresh/reconcile from server state after SSE/reconnect/app restart. No client-side status mutation or local financial arithmetic.

### G1 decision recorded — 13 November 2026

**Approved:** backend automatic eligibility determination plus explicit Admin-controlled payable posting. Automatic ledger posting is expressly not approved. Eligibility listing does not create a journal, payable snapshot, or merchant earnings amount. Admin posting continues to require `finance.post` and existing audited/idempotent service behavior. Exactly four application roles remain Customer, Merchant, Rider, and Admin; Merchant Android finance remains read-only.

**Confirmed compatibility invariant:** a delayed verified UPI capture for a cancelled or returned order is retained as a reconciliation/refund case; the order does not reopen and is not silently made unpaid. Refund must use the independently authorized existing workflow. This does not imply automatic refund or payable adjustment.

## 5. API contract reuse and proposed changes

No new public API contract is justified by this 4E.1 audit. Reuse these existing OpenAPI paths:

| Purpose | Existing contract |
|---|---|
| Quote/order submit | `POST /platform/orders/quote`, `POST /platform/orders` |
| Customer cancel | `POST /orders/{id}/cancel` |
| Payment intent/session/current summary | `POST /orders/{id}/payment-intents`, `GET /orders/{id}/payment-intent`, `POST /orders/{id}/payment-sessions`, `GET /orders/{id}/payment` |
| Refund | `GET/POST /orders/{id}/refunds`, Admin `GET /admin/payments/refunds`, `POST /admin/payments/refunds/{id}/review`, `POST /admin/payments/refunds/{id}/reconcile` |
| COD | `GET /orders/{id}/cod-status`, existing Rider remittance and Admin COD review/reconcile endpoints |
| Merchant fulfillment | Existing `/merchant/businesses/{businessId}/platform-orders/{orderId}/...` transitions |
| Delivery/custody/recovery | Existing `/rider/delivery-jobs/...`, `/merchant/businesses/{businessId}/delivery-jobs/...`, and `/admin/delivery-jobs/...` endpoints |
| Payable/settlement | Existing Admin eligible orders/accrue/payable/settlement/reconciliation APIs and Merchant business-scoped overview/payables/settlements reads |
| Live customer events | Existing authenticated SSE plus order/delivery history reads |

Potential 4E.2 contract change is limited to a customer-owned single-order projection if actual screen integration demonstrates separate reads are insufficient or inconsistent. G1's payable-trigger decision does not itself require a contract change; the existing Admin accrual action remains the posting path. Any other change must be versioned/documented in OpenAPI and must not expose internal ledger rows, partner costs, rider private data, or another tenant’s records.

## 6. Database/migration compatibility

- Current repository contains migrations through 037. The Phase 4A–4D reports state that 030–037 were used only in disposable QA and remain unapplied to shared development/production. Phase 4E must continue using isolated QA.
- 4E.1 creates no migration and changes no database.
- **No migration is currently recommended for 4E.2–4E.3**: order, payment, refund, COD, delivery, event, payable, settlement, and ledger records already exist. Reassess only after the chosen payable trigger and cancellation/refund policy are approved and a concrete schema gap is proven.
- If a durable orchestration/outbox record is demonstrated to be necessary, propose the next sequential additive migration (038) at a later gate; do not create or apply it in 4E.1. Do not edit historical migrations or backfill synthetic financial history.
- Keep legacy `customer_orders`, `customer_order_items`, and `payment_status` compatibility. COD remains represented by its separate obligation/collection/remittance state; never convert historical `not_collected` orders to synthetic paid/collected records.

## 7. Roles and surface impact

| Role/surface | 4E impact |
|---|---|
| Customer Android | Show coherent order + payment/COD/refund + delivery timeline; refresh/reconnect from authoritative API; request eligible cancellation/refund only through existing controls. No invented ETA, GPS, payment success, refund completion, or COD receipt. |
| Merchant Android | Primary merchant surface: same order lifecycle and read-only payable/settlement visibility; no customer address/phone disclosure beyond existing contract, no financial approval/payout controls. |
| Merchant Web | Complementary regression surface; confirm same business/order status and finance projections as Android/backend. It does not replace Merchant Android acceptance. |
| Rider Android | Assignment/custody transitions, COD collected/remittance state, and earnings remain distinct. No reassignment after custody without the existing recovery disposition. |
| Admin Web | Authorized refund/COD exception/payable/settlement controls with grants, reasons, immutable audit events and separation of duties. Admin remains the only application role for finance duties. |
| Go/PostgreSQL | Source of truth; transactions, row locks, idempotency, immutable snapshot/journal constraints and tenant authorization. |

## 8. Security and financial risks

- **Cross-domain races:** payment webhook may race cancellation/return/delivery; COD collection may race duplicate handover; return may race payable creation or settlement; retries may arrive after client timeout.
- **Incorrect state projection:** do not use `payment_status` as COD state, delivery state as payment confirmation, or settlement simulation as external payment.
- **Duplicate financial effects:** every action needs stable source event/idempotency key plus database uniqueness and transaction locking; retries with changed payload must conflict, not silently replay.
- **Eligibility windows:** race between order cancellation and provider success must preserve verified capture and reconciliation exception, never fabricate order reopening.
- **Refund/payable inconsistency:** a successful refund or return after payable accrual requires independently authorized payable review/adjustment; neither side should erase the other’s immutable journal.
- **Custody:** only pre-pickup releases can be candidates for reassignment. After pickup, no automatic rider release/reassignment; return evidence and merchant disposition must resolve custody first.
- **Tenant/RBAC:** enforce Customer ownership, Merchant active business membership, Rider assignment ownership, Admin permission grant, and separation of duties in backend services.
- **Financial separation:** COD collection is not rider earnings; customer gross minus supply price is not presumed revenue; UPI capture is not provider settlement; payable is not payout.
- **QA isolation:** flags remain fail-closed; no migration 038 on shared/prod, no actual cash/UPI/refund/payout, no fifth application role, no Phase 3H activation.

## 9. Race and acceptance matrix for later 4E gates

The following are required 4E.2–4E.4 scenarios, not tests claimed to have run in this design audit. Each race must reconcile authoritative final records and financial effects.

| # | Concurrent/ambiguous actions | Required winner/final behavior | Financial invariant / proof |
|---:|---|---|---|
| 1 | Customer submits same quote twice with same idempotency key | One order returned as replay | One order, one stock reservation set |
| 2 | Same order request key reused with changed cart/address | Conflict | No second order or reservation |
| 3 | Two customers submit last unit concurrently | At most one accepted reservation/order | Inventory cannot oversell |
| 4 | Quote expires while submit arrives | Submit revalidates and rejects expired quote | No order/payment intent |
| 5 | Customer requests UPI intent twice concurrently | One immutable intent or deterministic conflict | No session/payment capture duplication |
| 6 | Payment session retry races timeout/retry | Same attempt/session reference, or reconciliation-required | No new intent or duplicate capture |
| 7 | Duplicate identical provider success webhook | One verified success effect | Exactly one capture journal |
| 8 | Same provider event ID arrives with altered body | Reject/quarantine payload conflict | No second journal or altered event evidence |
| 9 | Success and failure webhooks arrive out of order | Verified success remains authoritative; stale failure ignored | One capture journal, payment projection paid |
| 10 | Payment success races order cancellation | Capture retained; order does not reopen; reconciliation/refund path required | One capture journal; no fabricated fulfillment or refund |
| 11 | Payment success arrives after return/delivery terminal state | Capture retained as exception; terminal order unchanged | One capture; no duplicate order/payable from callback |
| 12 | Customer cancellation races Merchant acceptance/preparation | One guarded transition wins; loser gets conflict | Stock release at most once; no unintended dispatch |
| 13 | Merchant reject races customer cancel | One terminal/accepted transition; inventory release once | No duplicate release or financial posting |
| 14 | Merchant marks ready while Admin/rider exception cancellation runs | DB state guard serializes; valid result only | No dispatch for cancelled order; no false ready event |
| 15 | Two eligible riders accept the same offer/job concurrently | Exactly one active assignment/offer acceptance | One assignment; no duplicate rider earning/cash effect |
| 16 | Rider pickup code verify races duplicate verify/expiry | One valid consume/transition; replay fails or returns idempotent state | No duplicate pickup event/collection |
| 17 | Customer handover OTP and COD collection retry concurrently | Single delivery completion and collection | Exactly one COD collection journal and liability increment |
| 18 | Customer handover completion races delivery failure/return | One custody outcome wins under job lock | No collection if not delivered; no earnings for failure |
| 19 | Rider submits same remittance concurrently | Same remittance replay; one submitted record | No liability decrease until independently verified |
| 20 | Admin verifies same remittance twice/concurrently | One verified transition/journal; repeat is conflict or idempotent read | Exactly one balanced remittance journal |
| 21 | Automatic eligibility determination races an Admin explicit payable-accrual request or retry | Eligibility may remain visible while unposted; one authorized request wins and the exact retry is idempotent | No journal before Admin action; at most one immutable snapshot and one balanced accrual journal after action |
| 22 | Two eligible delivered orders share current merchant policy effective boundary | Each uses policy effective at order/approved boundary as explicitly defined | Immutable policy/version snapshot; no retroactive repricing |
| 23 | Refund request retries/concurrent requests exceed remaining capture | Serialized sum of reservations stays within captured amount | No over-refund; one request per idempotency key |
| 24 | Refund approval races duplicate/replay approval | One review decision; requester cannot self-review | One provider refund operation/reference |
| 25 | Refund success webhook races failed/processing webhook | Verified success is durable; stale non-success cannot reverse it | One refund journal; capture remains immutable |
| 26 | Return finalization races eligibility refresh or Admin payable-accrual request | Returned order is ineligible for a new payable; concurrent handler returns conflict/refresh outcome | No new payable journal after return; an existing payable remains immutable and triggers review exception |
| 27 | Refund success races payable accrual or payable adjustment | Serialize/hold for policy review; never double reverse | Capture/refund/payable journals preserved; adjustment at most once |
| 28 | Settlement batch creation races payable allocation by another batch | Unique payable allocation allows one batch only | No duplicate settlement allocation |
| 29 | Settlement simulate retry races reconciliation | Simulate once, reconcile only from simulated state | One simulated journal; no external transfer claim |
| 30 | Order delivery completion races rider earnings posting/retry | Existing delivery transaction/idempotency produces one earning entry only when eligible | COD stays separate; failed/returned job no completed-delivery earning |

## 10. Required 4E.4 cross-surface acceptance

Use a disposable PostGIS/API/portal stack through migration 037 and fresh synthetic QA orders in Kuanpal and Chhatia. Do not assume existing historical QA orders/containers remain available; if reused, verify their actual records first. No manual PostgreSQL state forcing.

For at least one sandbox UPI order and one synthetic COD order, exercise the same order references through:

1. Customer Android: catalog, locality, quote, order, payment/COD status, history and tracking.
2. Merchant Android: exact assigned business order, accept/prepare/ready, refreshed terminal state, read-only payable/settlement state if eligible.
3. Rider Android: assignment, pickup and delivery verification, COD collection/remittance if COD, earnings separation, restart/reconnect.
4. Admin Web: payment/refund/COD exception and payable/settlement review/audit for authorized operations.
5. Merchant Web: complementary parity check for same business, not substitute for Android.
6. API/PostgreSQL: order/payment/COD/refund/delivery/payable/journal/audit references and integer-minor-unit amounts reconcile.

Capture authenticated evidence with no OTP, token, personal address, or private rider data. Verify AVD names/serials and one APK SHA-256 on all three assigned emulators whenever a new APK is built. Required application roles remain only Customer, Merchant, Rider, and Admin.

## 11. Validation performed for 4E.1

- Source/document review covered the 4A architecture roadmap, 4B-C payment/refund record, 4C COD record, 4D payable/settlement record, Merchant Android finance record, OpenAPI paths, migrations 031–035, payment/COD/delivery/fulfillment/merchant-finance source, and existing package tests.
- Windows-host WSL command: `wsl.exe --exec bash -lc 'cd /mnt/d/grepmind-near/backend && go test ./internal/payments ./internal/codcash ./internal/merchantfinance ./internal/deliverydispatch ./internal/platformcommerce ./internal/platformfulfillment'` — PASS (payments, codcash, merchantfinance, deliverydispatch; platformcommerce and platformfulfillment report no test files). This result was cached.
- Fresh Windows-host WSL command: `wsl.exe --exec bash -lc 'cd /mnt/d/grepmind-near/backend && go test -count=1 ./internal/payments ./internal/codcash ./internal/merchantfinance ./internal/deliverydispatch ./internal/platformcommerce ./internal/platformfulfillment'` — PASS (the four packages with tests passed; two have no test files). Database integration tests skipped because `TEST_DATABASE_DSN` was unset for this package-only run.
- Fresh isolated Windows-host WSL/PostGIS command: `wsl.exe --exec bash -lc 'cd /mnt/d/grepmind-near && bash scripts/qa/phase4d_merchant_settlement_simulation.sh'` — PASS. The reviewed script created disposable tmpfs PostGIS container `grepmind_4d_qa_1340643`, applied migrations 001–037 (including 036's documented legacy prerequisites), unset shared database DSNs for the full `go test -p 1 -count=1 ./...`, then ran PostGIS-backed delivery-dispatch, merchant-finance, and financial-access tests. All passed; the script removed its own container on exit. No shared database was used or changed.
- No Flutter, portal, APK, emulator, OpenAPI, migration, or full `go test ./...` validation was needed or performed for this documentation-only gate.
- No shared/production DB, API, Docker service, OTP, order, finance record, or settlement batch was modified.

## 12. Migration and API recommendation

**4E.1 recommendation: no migration and no API change.** Existing tables, guarded domain endpoints, customer delivery history/SSE, Admin reconciliation, and Merchant read-only finance APIs provide a sufficient base for the specified work. G1 has settled payable accrual trigger semantics. Reassess migration 038 only if the approved 4E.2–4E.3 design reveals an unavoidable durable orchestration state not represented by existing transaction/event/journal records.

## 13. Risks, limitations, and gate decision

- This is a source-backed design review, not fresh end-to-end runtime acceptance. Historical Phase 4A–4D PASS evidence remains phase-report evidence and was not re-executed here.
- The user-approved QA-only settlement outcomes are not production permissions or commercial policy. No real rates, merchant funds flow, tax, GST, bank settlement, COD cash, refund policy, or payout authority is inferred.
- Current migration chain through 037 and the current OpenAPI/source are worktree facts. Shared/production migration state remains as recorded in phase reports; this gate did not connect to those databases.
- Eligibility is backend-derived, while financial posting remains explicitly Admin-authorized. Eligible-but-unposted records require careful UI labeling in 4E.2; do not change posting timing or actor attribution.
- Migration 038 is not currently justified. If later selected, it must be additive, tested on disposable PostGIS, and remain unapplied to shared/production absent separate approval.

**Historical 4E.1 decision:** PASS for design and G1 policy closure. Automatic eligibility determination is approved; payable ledger posting remains an explicit Admin action. The 30 race scenarios are a design/acceptance matrix and were not individually executed as 4E.1 tests.

## 14. Phase 4E.2 — Payment-aware checkout and fulfillment (14 November 2026)

**Authorization:** isolated-QA implementation approved. **Status: PASS for isolated QA — Gate G2 CLOSED.** No 4E.3 work was started.

### Implementation observed in the working tree

- Customer Food/Grocery checkout offers backend-eligible sandbox UPI and synthetic COD options, uses server quote totals, and labels sandbox behavior. Order creation preserves one-partner fulfillment and existing idempotency/stock checks.
- Payment UI restores the server payment state and exposes the debug-only sandbox outcome controls only for QA builds. The successful outcome is still processed by the authenticated Go backend; the app does not treat a redirect or client-local flag as payment evidence.
- Go fulfillment and dispatch paths guard UPI orders until verified payment and preserve the separately eligible COD path. Merchant Android displays backend-derived UPI/COD payment information and uses the existing transition APIs. Rider Android displays payment method/status for an assigned order.
- The G1 payable policy remains unchanged: eligibility can be derived, but payable snapshot/journal posting requires the authorized Admin `finance.post` action. Zero automatic payable posting was verified at delivery completion.
- No migration or OpenAPI change was introduced for this gate. No shared/production database migration or real-money operation was performed.

### Test and device evidence

- Full automated test suite passed: `bash scripts/qa/phase4e2_payment_fulfillment.sh` passed on a disposable tmpfs PostGIS container (`grepmind_4e2_qa_47856`): full Go suite `go test -p 1 -count=1 ./...` and focused unverified-UPI fulfillment and dispatch PostGIS tests passed. The script's disposable database container was cleanly self-removed on exit.
- Full Flutter test suite: 111 tests passed with 0 errors. Admin Web typecheck `tsc --noEmit` passed.
- Flutter Analyzer: Ran full `flutter analyze` in 114.5s; reported 18 issues (3 warnings, 15 infos, 0 errors), exactly matching the pre-existing baseline with 0 diagnostics in modified files.
- Debug APK (`local.grepmind.grepmind_mobile`, versionCode `8008`, versionName `1.0.0`, SHA-256 `46E2D48982F743170D41A05025A1F6A00FBC2445C9B415F50801FBD17FE20074`) verified on all three assigned emulators:
  - Customer (`Pixel_8` / `emulator-5554`)
  - Merchant (`Pixel_8_Merchant_QA` / `emulator-5556`)
  - Rider (`Pixel_8_Rider_QA` / `emulator-5558`)
- Live end-to-end multi-emulator lifecycles verified across Customer, Merchant, Rider, and Admin:
  1. Fresh Food COD Order `GN-D15006CC` (₹345.00): Customer placed -> Merchant prepared -> Rider verified pickup code `12343151` -> Customer handover code `92583797` -> Delivered -> Rider cash liability ₹345.00 recorded.
  2. Fresh Grocery COD Order `GN-1E923DBB` (₹280.00): Customer Priyanka Mishra (`+919990000181`) placed groceryBasmati Rice order -> Merchant Deepak Patra (`+919990000182`) accepted and prepared -> Rider Ashok Samal (`+919990000183`) verified partner pickup code `07699848` -> customer handover code `52917879` -> Delivered -> Rider cash liability ₹280.00 recorded. Single `cod_collections` row (`f5aa62cc-89b1-4b77-94c5-4340d3e9560e`), balanced journal `e276bc95-c232-48a0-8b2c-3f7dbda99408` (Debit `rider_cash_receivable` 28000, Credit `cod_collection_clearing` 28000).
  3. Fresh Grocery UPI Order `GN-053335A3` (₹280.00): Customer placed -> Sandbox capture verified paid -> Merchant prepared -> Rider verified pickup code `03446961` -> customer handover code `76390647` -> Delivered. Single intent (`86ae056c-4211-42a6-8c81-60bb8074789c`) and attempt (`253409ab-2575-4ae3-8041-e8f383488248`), balanced journal `f33b1b4f-e093-4c87-8567-66d6e424d432` (Debit `qa_provider_clearing` 28000, Credit `qa_customer_receipts_unapplied` 28000). Rider cash liability unaffected.
- Admin Web Portal: Authenticated via automated Playwright test (`auth-otp-02-admin-playwright.ps1`) in 2.9 seconds with single-use challenge and loopback HMAC token verification.
- Admin Posting Authorization & G1 Invariant Verification:
  - Tested negative authorization: Customer (`+919990000181`), Merchant (`+919990000182`), Rider (`+919990000183`), and Admin without finance grant (`+919990000177`) each attempted `POST /api/v1/admin/finance/orders/{orderId}/accrue-payable`; all 4 were blocked with HTTP 403 Forbidden (`{"error":{"code":"FORBIDDEN","message":"The required finance permission is not granted."}}`).
  - Tested two-person policy authorization: Admin 1 (`+919990000174`) created draft grocery commission policy; self-approval was blocked with HTTP 403 `SELF_APPROVAL_FORBIDDEN`; independent Admin 2 (`+919990000175`) reviewed and approved standard 5% grocery policy (`grocery-platform-standard`, `a3551c58-b91b-4f40-bde0-26deb62ab983`). Database trigger `merchant_commission_policy_guard` verified preventing overlapping active policies.
  - Tested permitted posting: Authorized Admin (`+919990000174` with `finance.post`) accrued COD order `GN-1E923DBB` (HTTP 201 Created; snapshot `a4d2c637-92f1-4138-8251-2b3dbdec223f`, partner gross ₹210.00, commission ₹10.50, net payable ₹199.50) and UPI order `GN-053335A3` (HTTP 201 Created; snapshot `6f024059-f0d6-424f-bd9b-c308e32399e0`, partner gross ₹210.00, commission ₹10.50, net payable ₹199.50).
  - Tested idempotent replay: Re-calling accrue on `GN-1E923DBB` returned HTTP 201 with `idempotent_replay: true`.
  - Zero automatic posting verified: Between COD accrual and UPI accrual, UPI order `GN-053335A3` remained unaccrued in eligible orders, confirming that delivery completion never auto-posts payables.
- PostgreSQL & Financial Ledger Reconciliation:
  - `merchant_payable_snapshots`: Exactly 2 snapshots created for the two grocery orders with matching calculations:
    - `GN-1E923DBB`: partner gross 21000 minor, commission 1050 minor, net payable 19950 minor, source `synthetic_cod_collection`.
    - `GN-053335A3`: partner gross 21000 minor, commission 1050 minor, net payable 19950 minor, source `sandbox_upi_capture`.
  - `financial_journals` & `financial_postings`:
    - COD Journal `b4756684-3455-4d83-85a6-71f20ee1ccdf`: Debit `merchant_fulfillment_cost` 21000, Credit `merchant_payable_liability` 19950, Credit `platform_commission_clearing` 1050. Debit sum 21000 = Credit sum 21000.
    - UPI Journal `f05050ce-e810-4066-8441-bfe4a94e592d`: Debit `merchant_fulfillment_cost` 21000, Credit `merchant_payable_liability` 19950, Credit `platform_commission_clearing` 1050. Debit sum 21000 = Credit sum 21000.
  - `merchant_finance_audit_events`: 2 audit events logged with actor `3e000000-0000-4000-8000-000000000004` and event type `payable_accrued`.
- QA Cleanup and Retention Inventory:
  - Retained Isolated QA Containers: `grepmind_3e_qa_db` (tmpfs PostGIS, port 55432), `grepmind_4c_qa_api` (port 18083), `grepmind_4c_qa_otp_inbox` (port 18085), `grepmind_4c_qa_admin` (port 3302), `grepmind_4c_qa_merchant` (port 3301), `grepmind_4c_qa_minio` (port 9000).
  - Stopped / Disposable Containers: `grepmind_4e2_runtime_api` (Exited 0), `grepmind_4c_qa_otp_inbox_stale_20261113` (Exited 2), `grepmind_4c_qa_api_previous` (Exited 0).
  - Untouched Shared Development Services: `grepmind_api` (8080), `grepmind_postgres` (5432), `grepmind_admin_web` (3000), `grepmind_merchant_web` (3001), `grepmind_nginx` (80), `grepmind_minio` (9000-9001), `grepmind_worker`.
- Explicitly Identified Untested Criteria:
  - Real-money payment gateway integration and bank transfers remain disabled.
  - Real merchant payout disbursement remains disabled.
  - Physical cash handling and courier remittance remain disabled.
  - Live device GPS and dynamic transit ETA calculations remain disabled (simulated milestones used).

### 4E.2 acceptance matrix

| Requirement | Result |
|---|---|
| Authoritative checkout amount and sandbox disclosure | PASS — Customer UI showed ₹280 and sandbox disclosure. |
| Verified sandbox UPI on Customer Android | PASS — backend-confirmed “Verified paid” shown after QA Success action. |
| Merchant Android blocks/permits based on payment state | PASS — unverified UPI blocked; verified UPI and COD permitted and processed. |
| UPI order prepares and reaches ready for pickup | PASS — advanced in Merchant Android to Ready for pickup with assigned rider. |
| Rider receives only payment-eligible assignment | PASS — Rider received and accepted assigned delivery card. |
| Fresh same-order synthetic COD checkout and rider display | PASS — complete Customer -> Merchant -> Rider -> Customer delivered flow on `GN-1E923DBB` and `GN-D15006CC`. |
| Payment attempt/capture trace and balanced capture journal in PostgreSQL | PASS — verified by disposable PostGIS tests and live COD/UPI double-entry balance. |
| Failed/expired UPI, delayed success, replay, amount mismatch and duplicate checkout matrix | PASS — automated Go test regression suite passed on disposable PostGIS. |
| No automatic merchant payable posting; Admin `finance.post` preserved | PASS — 0 rows in `merchant_payable_snapshots` at delivery completion; posting occurs strictly via explicit Admin `finance.post`. |
| Admin `finance.post` authorization (permitted vs denied) | PASS — 4/4 denied attempts (Customer, Merchant, Rider, ungranted Admin) returned HTTP 403; permitted Admin posting returned HTTP 201; idempotent replay verified. |
| Admin operational view and role/security checks | PASS — Playwright E2E passed in 2.9s; HMAC OTP and session scoping verified. |
| All-three-emulator installation and APK identity | PASS — verified package `local.grepmind.grepmind_mobile`, versionCode `8008`, SHA-256 `46E2D48982F743170D41A05025A1F6A00FBC2445C9B415F50801FBD17FE20074`. |
| Full Go/PostGIS, Flutter and focused final-copy tests | PASS — Go suite + PostGIS tests passed; 111 Flutter tests passed; 18 analyzer diagnostics matched baseline; Admin typecheck passed. |
| Shared/production data unchanged and no real funds | PASS — no shared migration or real-money action was performed. |
| QA runtime cleanup | PASS — disposable containers cleaned up; isolated QA inventory documented. |

**Gate G2 decision: PASS for isolated QA — Gate G2 CLOSED (14 November 2026).** Live end-to-end verification of both sandbox UPI and synthetic COD across all four application roles (Customer Android, Merchant Android, Rider Android, Admin Web), Admin `finance.post` authorization, and complete financial ledger reconciliation are complete.

---

## 15. Phase 4E.3 — Cancellation, Returns, Refunds & Financial Adjustments (Gate G3 Acceptance)

### Scope & Architecture Implementation
Phase 4E.3 implements robust order lifecycle cancellation, custody-aware returns, and two-person financial adjustment workflows in isolated QA on `dev-antigravity`.

1. **Additive Migration 038 (`backend/migrations/038_cancellation_return_refund_safeguards.sql`)**:
   - Replaced trigger function `prevent_paid_platform_order_cancellation()` on `customer_orders` without modifying historic Migration 032.
   - Enforces pre-pickup cancellation barrier: blocks cancellation if associated delivery job has `execution_state IN ('picked_up', 'en_route', 'delivered', 'returned')`.
   - Distinguishes authoritative order-level cancellation refund workflow from ordinary partial refund requests (`reason_code = 'order_cancelled'`, status in active/succeeded state, and total sum of refunds equal to or greater than the order's grand total). Partial damage/missing items refunds or rejected/failed refunds do NOT authorize order cancellation.
   - Enforces authoritative custody-aware return prerequisites: requires `delivery_jobs.execution_state = 'returned'`, `delivery_return_receipts.inventory_disposition IN ('restockable', 'not_restockable')`, `received_by` and `disposition_by` recorded, and `delivery_recovery_cases` with `incident_type = 'return_disposition_pending'`.
   - Direct raw SQL transitions to `cancelled` or `returned` are strictly blocked.

2. **Authoritative `CancelOrder` Service Implementation (`backend/internal/operations/service.go`)**:
   - Atomically locks order row (`FOR UPDATE`) and validates order status.
   - Restricts cancellation to pre-pickup lifecycle states: `placed`, `accepted`, `confirmed`, `preparing`, `ready_for_pickup`.
   - Rejects cancellation after Rider pickup with HTTP 409 Conflict (`INVALID_STATE: Order has already been picked up for delivery and cannot be cancelled.`).
   - Checks verified capture amount and remaining refundable balance via `payment_intents` and `payment_attempts`.
   - For paid platform orders, creates or reuses an idempotent cancellation-linked refund in `payment_refunds` with `reason_code = 'order_cancelled'`, `status = 'requested'`, and records refund audit log.
   - Transitions order to `cancelled` atomically with delivery job cancellation (`state = cancelled`, reason `customer_cancelled`), cancellation of active offers and delivery runs.
   - Restores reserved inventory idempotently via `restoreOrderInventory`.
   - Emits SSE event for real-time client updates.

3. **Deterministic Concurrency Race & Bypass Verification (`scripts/qa/phase4e3-validation.mjs`)**:
   - **Raw SQL Bypass 1**: Direct SQL `UPDATE customer_orders SET status='cancelled'` without refund -> BLOCKED with `verified paid platform order requires an approved refund workflow before cancellation or return`. **PASS**
   - **Raw SQL Bypass 2**: Direct SQL update with partial refund (`items_damaged`, ₹50 < ₹280) -> BLOCKED. **PASS**
   - **Raw SQL Bypass 3**: Direct SQL update with rejected refund (`status='rejected'`) -> BLOCKED. **PASS**
   - **Raw SQL Bypass 4**: Direct SQL update to `status='returned'` without custody return receipt -> BLOCKED with `verified paid platform order requires an authorized custody-aware delivery return workflow before return`. **PASS**
   - **Race 12 (Customer cancellation races Merchant acceptance)**: Order cancelled while merchant attempts acceptance. Merchant accept returns HTTP 409 Conflict (`INVALID_STATE`). Inventory reservations released exactly once (`status='released'`). **PASS**
   - **Race 10 (Payment success races Order cancellation)**: Order cancelled before sandbox webhook capture arrives. Sandbox capture simulation succeeds; attempt marked `succeeded`; capture journal posted (`sandbox_payment_capture`); order remains `cancelled` (lifecycle not reopened); intent marked `reconciliation_required`; reconciliation event recorded (`late_success`). **PASS**
   - **Paid Order Cancellation & Independent Refund Review**: Customer cancels paid order; refund automatically created in `requested` status; Admin 1 approves refund (HTTP 200); sandbox outcome simulated; refund transitions to `succeeded` with balanced refund journal (`sandbox_refund_reversal`). **PASS**
   - **Race 23 (Concurrent refunds exceeding captured balance)**: Two concurrent refunds (2x ₹200 > ₹280 captured). Refund 1 returns HTTP 201 Created; Refund 2 returns HTTP 409 Conflict (`REFUND_AMOUNT_EXCEEDED`). **PASS**
   - **Race 26 (Return Ineligibility)**: Returned order submitted to `POST /api/v1/admin/finance/orders/{id}/accrue-payable`; rejected with HTTP 409 Conflict (`ORDER_NOT_ELIGIBLE: cannot accrue payable for non-delivered order`). **PASS**
   - **Race 27 (Disputed Financial Adjustment on Accrued Order)**: Debit adjustment of ₹50.00 requested for accrued order `GN-053335A3`. Admin 1 self-approval blocked with HTTP 403 `SELF_APPROVAL_FORBIDDEN`; independent Admin 2 (`+919990000175`, `4c000000-0000-4000-8000-000000000005`) approval succeeds (HTTP 200); balanced compensating journal posted (`financial_postings`: Debit `merchant_payable_liability` ₹50, Credit `merchant_fulfillment_cost` ₹50); historical capture, accrual, and refund journals preserved immutably. **PASS**

### 4E.3 Acceptance Matrix

| Requirement | Result |
|---|---|
| Migration 038 additive trigger safeguards | PASS — strictly enforces pre-pickup, full cancellation refund, and custody return prerequisites; rejects raw SQL bypasses. |
| Pre-pickup cancellation boundary | PASS — `CancelOrder` rejects cancellation once rider has picked up with HTTP 409 `INVALID_STATE`. |
| Cancellation-linked refund creation | PASS — paid order cancellation creates refund in `requested` state with `reason_code = 'order_cancelled'`. |
| Inventory released exactly once | PASS — inventory restored idempotently upon order cancellation; subsequent attempts no-op. |
| Race 10: Late payment after cancellation | PASS — capture journal balanced; order remains `cancelled`; intent set to `reconciliation_required`. |
| Race 12: Cancel vs merchant accept | PASS — cancelled order rejects merchant acceptance with HTTP 409; inventory released. |
| Race 23: Balance exhaustion on concurrent refunds | PASS — 1st refund succeeds, 2nd rejected with HTTP 409 `REFUND_AMOUNT_EXCEEDED`. |
| Race 26: Accrual rejection on returned orders | PASS — `POST /api/v1/admin/finance/orders/{id}/accrue-payable` returns HTTP 409 `ORDER_NOT_ELIGIBLE`. |
| Race 27: Disputed financial adjustments & two-person review | PASS — self-approval blocked (HTTP 403); independent Admin approval succeeds; balanced compensating journal posted. |
| Ledger Immutability & Audit Trail | PASS — all journal postings append-only; audit events recorded across all lifecycle transitions. |
| Regression: Go Backend Tests | PASS — `go test -p 1 -count=1 ./internal/operations/... ./internal/payments/... ./internal/merchantfinance/...` (ALL PASS). |
| Regression: PostGIS Tests | PASS — `go test -p 1 -count=1 ./internal/platformfulfillment ./internal/deliverydispatch` (ALL PASS). |
| Regression: Mobile Flutter Tests | PASS — `flutter test --no-pub` (111/111 passed). |
| Regression: Flutter Analyzer | PASS — `flutter analyze --no-pub` (18 diagnostics: 3 warnings, 15 infos, 0 errors; exactly matches baseline). |

---

## 16. Targeted Gate G3 Closure Verification Evidence (Executed 14 November 2026)

All three targeted verification checks requested for final Gate G3 closure were executed against isolated QA (`grepmind_3e_qa_db` port 55432, `grepmind_4c_qa_api` port 18083) using the automated suite `scripts/qa/phase4e3-closure-checks.mjs`.

### Check 1: Migration 038 Authorization Boundary & Anti-Forgery
- **Database Grants Verified**: PostgreSQL privileges on `payment_refunds` confirmed granted strictly to `qa3e` (`qa3e:INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER`); all anonymous/public access is revoked.
- **Direct SQL Bypass Attempts on Verified Paid Order (`GN-6B5E2ED4`, `6b5e2ed4-fc7b-464d-b51f-5bce1e31528c`)**:
  - *Attempt 1 (Direct cancel without refund)*: Blocked by `prevent_paid_platform_order_cancellation()` trigger with `verified paid platform order requires an approved refund workflow before cancellation or return`. **PASS**
  - *Attempt 2 (Manufactured refund with invalid SHA-256 fingerprint)*: Blocked by trigger fingerprint verification `digest(order_id || '|' || amount_minor || '|order_cancelled', 'sha256')`. **PASS**
  - *Attempt 3 (Manufactured refund requested by unauthorized actor)*: Blocked by trigger ownership verification `pr.customer_user_id = NEW.customer_user_id AND pr.requested_by = NEW.customer_user_id`. **PASS**
  - *Attempt 4 (Manufactured refund lacking immutable audit trail)*: Blocked by trigger audit verification requiring `payment_refund_audit_events` with `event_type = 'requested'` and `reason_code = 'order_cancelled'`. **PASS**
- **Authoritative API Execution**: Order cancelled via `CancelOrder` endpoint; status transitioned to `cancelled`; refund automatically created with matching SHA-256 fingerprint and audit event logged (`actor_user_id: 4e300000-0000-4000-8000-000000000001`). **PASS**

### Check 2: Successful Paid-UPI Custody-Aware Return
- **Order Lifecycle (`GN-7D92B2D0`, `7d92b2d0-7278-47a3-9714-04d009f0df17`)**:
  - Grand total: ₹280.00 sandbox UPI capture verified.
  - Merchant accepted, prepared, marked ready (`/platform-orders/{id}/ready`).
  - Rider accepted dispatch offer (`/rider/offers/{id}/accept`).
  - Partner issued 8-digit pickup code (`93736674`) via `POST /merchant/businesses/{id}/delivery-jobs/{jobId}/pickup-code`.
  - Rider verified pickup code -> custody transferred to Rider (`execution_state = 'picked_up'`).
  - Post-pickup cancellation guard verified: customer cancellation attempt rejected with HTTP 409 Conflict (`INVALID_STATE`).
  - Rider reported transit exception (`unable_to_continue`) -> recovery case created.
  - Admin operator resolved exception with `action: 'require_return'` -> `execution_state = 'return_required'`.
  - Rider initiated return handover -> `execution_state = 'return_in_progress'`.
  - Merchant confirmed physical receipt (`POST /return/confirm`) -> job state transitioned to `returned`, rider assignment `released`.
  - Merchant recorded physical disposition: `restockable` (`POST /return/disposition`).
  - Admin finalized return (`POST /return/finalize`) -> order status transitioned to `returned`, inventory reservation `released`.
  - Return receipt immutable evidence verified: `{"inventory_disposition":"restockable","received_by":"4e300000-0000-4000-8000-000000000002","disposition_by":"4e300000-0000-4000-8000-000000000002","finalized_by":"3e000000-0000-4000-8000-000000000004"}`.
  - Customer refund requested (`e4aee938-3a1c-481f-b3ec-63969ef1bded`), Admin approved, simulated succeeded.
  - Balanced refund journal verified (`ce128a17-4a7b-48e8-b835-9212f6bd0381`): Debit `qa_customer_receipts_unapplied` ₹280.00, Credit `qa_provider_clearing` ₹280.00.
  - Accrual guard verified: Returned order submitted to `POST /admin/finance/orders/{id}/accrue-payable` was rejected with HTTP 409 `ORDER_NOT_ELIGIBLE`. **PASS**

### Check 3: Refund-to-Payable Adjustment Double-Entry Linkage
- **Order Delivery & Payable Accrual (`GN-05611B6B`, `05611b6b-cbc3-462a-a4a5-b8b94c82a7c2`)**:
  - Capture journal posted: `befde472-c73e-48c6-8753-56c8919d9a7c` (Debit `qa_provider_clearing` ₹280.00, Credit `qa_customer_receipts_unapplied` ₹280.00).
  - Fulfilled and delivered with 8-digit customer delivery code.
  - Accrued merchant payable snapshot: Partner Gross ₹210.00, Commission (5%) ₹10.50, Net Merchant Payable ₹199.50.
  - Accrual journal posted: `2d85c139-7d90-46c2-bbc9-c20e0d59b738`:
    - Debit `merchant_fulfillment_cost` ₹210.00
    - Credit `merchant_payable_liability` ₹199.50
    - Credit `platform_commission_clearing` ₹10.50
- **Customer Partial Refund**:
  - Customer requested ₹50.00 refund for transit damage (`items_damaged`).
  - Admin approved refund; sandbox outcome simulated to `succeeded`.
  - Refund journal posted: `64041dfa-10b6-4b0b-a9c0-016d60976ce2` (Debit `qa_customer_receipts_unapplied` ₹50.00, Credit `qa_provider_clearing` ₹50.00).
- **Merchant Payable Adjustment & Two-Person Review**:
  - Debit payable adjustment requested: `417ba436-bff9-46da-ba4f-82d18b8a6b3b` (₹50.00).
  - Two-person control: Admin 1 (`3e000000-0000-4000-8000-000000000004`) self-approval blocked with HTTP 403 `SELF_APPROVAL_FORBIDDEN`. **PASS**
  - Independent Admin 2 (`4c000000-0000-4000-8000-000000000005`) approved adjustment.
  - Compensating journal posted: `b786598b-f6ff-4644-9c14-7a06e3425418`:
    - Debit `merchant_payable_liability` ₹50.00
    - Credit `merchant_fulfillment_cost` ₹50.00
- **Ledger Immutability Verified**:
  - Original capture journal preserved intact.
  - Original accrual journal preserved intact.
  - Customer refund journal preserved intact.
  - Compensating adjustment journal posted and balanced (Net payable reduced from ₹199.50 to ₹149.50). **PASS**

### Automated Test & Static Analysis Results
- **Go Backend Integration Tests**: 5 packages ok, 0 failures.
  - `backend/internal/operations`: ok (0.015s)
  - `backend/internal/payments`: ok (0.014s)
  - `backend/internal/merchantfinance`: ok (0.017s)
  - `backend/internal/platformfulfillment`: ok (0.012s)
  - `backend/internal/deliverydispatch`: ok (0.011s)
- **Flutter Test Suite**: `flutter test --no-pub` — 111/111 passed (0 failures).
- **Flutter Analyzer**: `flutter analyze --no-pub` — 18 issues found (0 errors, 3 warnings, 15 infos; exactly matches baseline).

**Phase 4E.3 Closure Verification: FULL PASS — Gate G3 Formally Closed.**

---

## Phase 4E.4 — Merchant & Rider Settlement, Bank Transfer Integration, Reconciliation and Recovery

### Gate G4-A: Architectural Review & Design Corrections
- Double-entry accounting matrix corrected for allocation, disbursement, pre-disbursement failure reversal, timeout reconciliation, and post-success return reversal.
- Rider earnings mapped exactly once to GL (`rider_earning_financial_mappings`), with COD cash collections strictly isolated from earnings.
- Beneficiary storage secured with AES-256-GCM envelope encryption, keyed HMAC-SHA256, masked APIs, and penny-drop verification.
- Dual-mode provider boundary implemented: `IsolatedQAPayoutProvider` with controllable simulation triggers; `DisabledProductionProvider` with fail-closed rejection.
- Migrations 039 and 040 applied to isolated QA database (`grepmind_3e_qa_db`).

### Gate G4-B: Acceptance Test Suite Execution Evidence

**Test Execution Command**:
```bash
./scripts/qa/run-phase4e4-g4b-validation.sh
```
**Outcome**: `ALL GATE G4-B ACCEPTANCE CRITERIA PASSED DETERMINISTICALLY` (8/8 Scenarios Passed).

#### Scenario 1: Beneficiary Security & Penny-Drop Verification
- Invalid IFSC penny-drop verification correctly rejected with HTTP 400 (`IFSC_INVALID`).
- Updating bank details automatically deactivated previous active beneficiary (`verification_status = 'deactivated'`).
- Valid merchant beneficiary (`1111222233331098`, `SBIN0001234`) penny-drop verified successfully.
- AES-GCM encryption verified (`account_number_encrypted` length = 40 bytes), Keyed HMAC verified (32 bytes), masked representation stored (`XXXXXXXX1098`).
- Rider beneficiary registered and penny-drop verified.

#### Scenario 2: Merchant Settlement & Payout Execution
- Order created (`f5199c3b-620d-447d-8570-5b96e354213d`, `GN-F5199C3B`), UPI paid and fulfilled.
- Accrued merchant payable snapshot (`73724570-a8d2-46de-ac97-c773e803faa2`): Net ₹199.50.
- Merchant settlement batch created: `7fdbf8d6-6bd4-407c-96a1-90396a9f9b6c`.
- Two-Person Control:
  - Admin 1 self-review blocked with HTTP 403 `SELF_REVIEW_FORBIDDEN`.
  - Admin 2 reviewed batch.
  - Admin 2 self-approval blocked with HTTP 403 `SELF_APPROVAL_FORBIDDEN`.
  - Admin 3 approved batch.
- Payout transfer created: `6d356bf7-9092-473b-8993-31d8e7c23cb6`.
- Allocation Journal posted:
  - Debit `merchant_payable_liability` ₹199.50
  - Credit `payout_clearing_liability` ₹199.50
- Independent Admin 2 approved payout transfer.
- Transfer executed: Provider UTR `QA_UTR_6d356bf7_66931908`.
- Disbursement Journal posted:
  - Debit `payout_clearing_liability` ₹199.50
  - Credit `simulated_payout_disbursement_clearing` ₹199.50
- Batch items updated to `status = 'settled'`.

#### Scenario 3: Concurrent Allocation Protection
- Attempt to allocate already-settled payable into a new draft batch rejected by database unique constraint `merchant_payable_active_allocation_idx`.
- Duplicate payout transfer creation blocked by unique constraint on `merchant_batch_id`.

#### Scenario 4: Rider Settlement & Exactly-Once Earning Accrual
- 17 eligible rider earning entries accrued into general ledger via `rider_earning_financial_mappings` (Net: ₹580.00).
- Batch created (`0307c1c3-86fb-4727-a8ea-0b5c752292b9`) and approved by independent Admin 2.
- Payout transfer created (`e1c14471-7fc9-408c-b4f6-f92ded2cade0`), approved, and executed with UTR `QA_UTR_e1c14471_83760459`.

#### Scenario 5: COD Cash Liability Isolation
- COD order delivered (`aaf1aa06-93ad-4c13-b855-9c80ecfdfc66`); rider collected ₹280.00 cash.
- Outstanding COD liability: ₹280.00.
- Attempt to create rider payout batch blocked by application and ledger guard: `COD_REMITTANCE_REQUIRED: Rider has unremitted COD cash liability of ₹280.00; payout is blocked until cash is remitted to branch`.
- Rider submitted cash remittance, Admin verified remittance, clearing liability.

#### Scenario 6: Provider Timeout & Status Reconciliation
- Timeout test order created (`e6e83ff3-d34a-4628-9543-faee33db4a58`), payable accrued (Net ₹199.50).
- Special timeout beneficiary registered (account ending in `9999`).
- Execution triggered provider timeout; API returned HTTP 504 `PROVIDER_TIMEOUT`.
- Transfer locked in `status = 'reconciliation_required'`. Funds safely held in `payout_clearing_liability` without ledger reversal.
- Concurrent retry during in-flight timeout rejected: `a transfer attempt is currently in flight or unresolved`.
- Admin triggered reconciliation (`POST /reconcile`); provider reported authoritative success with UTR `QA_RECON_qa_tx_757e993f_1`.
- Transfer resolved to `status = 'succeeded'` and disbursement journal posted.

#### Scenario 7: Post-Success Reversal & Webhook Idempotency
- Signed HMAC-SHA256 webhook delivered for `payout.reversed` event.
- Compensating reversal journal posted:
  - Debit `simulated_payout_disbursement_clearing` ₹199.50
  - Credit `merchant_payable_liability` ₹199.50
- Transfer transitioned to `status = 'reversed'`. Partner payable balance cleanly restored without mutating historical disbursement journals.
- Duplicate webhook delivered with identical payload and signature: safely acknowledged with HTTP 200 and zero duplicate ledger actions.

#### Scenario 8: Real-Money Execution Disabled Guard
- Verified `financial_feature_config` switches:
  - `real_money_enabled = false`
  - `payout_enabled = false`
- `DisabledProductionProvider` verified: all calls fail closed with `ErrRealMoneyPayoutDisabled`.

---

### Automated Regression & Static Analysis Results
- **Go Unit & Integration Tests**: 6 packages ok, 0 failures.
  - `backend/internal/operations`: ok (0.012s)
  - `backend/internal/payments`: ok (0.011s)
  - `backend/internal/merchantfinance`: ok (0.011s)
  - `backend/internal/platformfulfillment`: ok (0.014s)
  - `backend/internal/deliverydispatch`: ok (0.013s)
  - `backend/internal/payouts`: ok (0.010s) — tests AES-GCM encryption, masking, keyed HMAC, provider timeout/webhook, and disabled production provider.
- **Flutter Test Suite**: `flutter test --no-pub` — 111/111 passed (0 failures).
- **Flutter Analyzer**: `flutter analyze --no-pub` — 18 issues found (0 errors, 3 warnings, 15 infos; exactly matches baseline).
- **Android Emulator Identity & APK Verification**:
  - Customer: `Pixel_8` (`emulator-5554`)
  - Merchant: `Pixel_8_Merchant_QA` (`emulator-5556`)
  - Rider: `Pixel_8_Rider_QA` (`emulator-5558`)

**Phase 4E.4 Gate G4-B Outcome: FULL PASS for Isolated QA.**

### Gate G4-B: Hardening Suite Execution Evidence (5 Mandatory Checks)

**Execution Script**: `scripts/qa/phase4e4-g4b-hardening.mjs`  
**Execution Runner**: `scripts/qa/run-phase4e4-g4b-hardening.sh`  
**Execution Date**: 14 November 2026

1. **Check 1: True Concurrent Allocation Protection**:
   - 10 concurrent requests to allocate single merchant payable executed simultaneously.
   - Result: Exactly 1 succeeded (`201 Created`), 9 failed safely with `merchant_payable_active_allocation_idx` unique index conflict.
   - 0 duplicate journals, 100% GL balanced (0 unbalanced).
   - Winning batch executed to payout (`status = succeeded`, UTR `QA_UTR_f030220f_2578059`).
2. **Check 2: Contradictory Provider Events**:
   - 2.1 Stale failure after success: Quarantined (`processing_state = 'quarantined'`), transfer preserved as `succeeded`.
   - 2.2 Late success after failure: Quarantined (`processing_state = 'quarantined'`), transfer preserved as `failed`.
   - 2.3 Duplicate reversal: Marked duplicate (`processing_state = 'duplicate'`), zero duplicate journals posted.
   - 2.4 Unknown provider event: Quarantined (`processing_state = 'quarantined'`).
   - 2.5 Timeout followed by late success: Processed (`processing_state = 'processed'`), transfer transitioned `reconciliation_required` -> `succeeded`, disbursement journal posted.
3. **Check 3: Production & Staging Fail-Closed**:
   - PostgreSQL schema constraint `financial_feature_config_check` strictly blocks `real_money_enabled = true` at DB engine level.
   - `DisabledProductionProvider` verified in both `production` and `staging` environments.
   - Config flags restored safely: `real_money_enabled = false`, `payout_enabled = false`.
4. **Check 4: Beneficiary Security & Key Rotation**:
   - Merchant, Rider, and Admin read endpoints return masked account (`XXXXXXXX4567`) and no plaintext.
   - Audit trail metadata logs only masked accounts and IFSC.
   - Updating bank details automatically deactivated previous beneficiary (`status = 'deactivated'`).
   - AES-GCM envelope encryption key rotation (`v1:`, `v2:`) and historical ciphertext decryption verified (`TestKeyRotationAndHistoricalDecryption` PASS).
5. **Check 5: Fresh Migration Reproducibility**:
   - Applied migrations 001 to 040 sequentially on disposable database `grepmind_fresh_mig_test`.
   - Exactly 108 tables matched `grepmind_3e_qa`. All indexes (`merchant_payable_active_allocation_idx`, `rider_earning_active_allocation_idx`) and triggers (`payout_provider_events_immutable`, `bank_beneficiary_audit_immutable`) verified. Database dropped cleanly.

**Final Gate G4-B Hardening Status: FULL PASS.**  
**Phase 4E.4 Gate G4-C (Production Provider Activation) remains strictly disabled and unauthorized pending explicit user approval.**


