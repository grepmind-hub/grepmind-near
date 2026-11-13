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

## 14. Phase 4E.2 — Payment-aware checkout and fulfillment (13 November 2026)

**Authorization:** isolated-QA implementation approved. **Status: PARTIAL.** No 4E.3 work was started.

### Implementation observed in the working tree

- Customer Food/Grocery checkout offers backend-eligible sandbox UPI and synthetic COD options, uses server quote totals, and labels sandbox behavior. Order creation preserves one-partner fulfillment and existing idempotency/stock checks.
- Payment UI restores the server payment state and exposes the debug-only sandbox outcome controls only for QA builds. The successful outcome is still processed by the authenticated Go backend; the app does not treat a redirect or client-local flag as payment evidence.
- Go fulfillment and dispatch paths guard UPI orders until verified payment and preserve the separately eligible COD path. Merchant Android displays backend-derived UPI/COD payment information and uses the existing transition APIs. Rider Android displays payment method/status for an assigned order.
- The G1 payable policy remains unchanged: eligibility can be derived, but payable snapshot/journal posting requires the authorized Admin `finance.post` action. No automatic payable posting was introduced.
- No migration or OpenAPI change was introduced for this gate. No shared/production database migration or real-money operation was performed.

### Test and device evidence

- Earlier in this 4E.2 execution, `bash scripts/qa/phase4e2_payment_fulfillment.sh` passed on a disposable tmpfs PostGIS database: full Go suite `go test -p 1 -count=1 ./...` and the focused unverified-UPI fulfillment and dispatch PostGIS tests passed. The script's disposable database container was self-cleaned. This is historical evidence from the earlier run, not a fresh rerun in the final device check.
- Earlier Flutter validation: 112 tests passed. Full analyzer completed with 18 baseline diagnostics (3 warnings, 15 infos), zero errors, exit code 1. After the final product-detail copy change, focused `flutter test test/platform_catalog_test.dart` passed (4 tests). No Go code changed after the earlier backend test run.
- Debug APK versionCode 4010, SHA-256 `46E2D48982F743170D41A05025A1F6A00FBC2445C9B415F50801FBD17FE20074`, was installed as the identical build on the three designated emulators. The visible emulator titles confirmed `Pixel_8`/`emulator-5560`, `Pixel_8_Merchant_QA`/`emulator-5558`, and `Pixel_8_Rider_QA`/`emulator-5556`.
- Customer Android created QA order `GN-B7B47B4C` for Kuanpal Food, one QA Chicken Biryani at ₹345. The Customer payment screen first showed pending after session creation. The debug QA Success action was then submitted in the app; the screen changed to **Verified paid**. Merchant Android independently displayed “Payment verified by Grepmind backend,” accepted the order, advanced it through Preparing to Ready for pickup, and showed “Delivery progress: assigned.” Rider Android refreshed to an assigned-delivery card for the same order and displayed UPI verified by Grepmind. This is live UI evidence for the UPI payment/fulfillment/dispatch-eligibility path; it does not prove pickup or delivery, which are outside 4E.2.
- No fresh COD order was completed during this acceptance attempt. Historical delivered COD order `GN-E2F76199` is not treated as a 4E.2 COD checkout result.

### Unverified gates and runtime blocker

- PostgreSQL/API reconciliation after the sandbox Success action is pending. The last read-only database result before that UI action showed the new order in `placed`, payment `pending`, and its attempt `session_created`; no post-success database/journal query was available. Therefore capture-journal count, payment-event trace, no-automatic-payable invariant, and preserved Phase 4D settlement records were not freshly reconciled.
- Customer COD checkout/obligation, Merchant COD eligibility, and Rider COD visibility were not verified with a new same-order journey.
- Admin operational/finance view was not authenticated or checked in this run. Existing `finance.post` permission and no-automatic-accrual were not revalidated at runtime.
- After the Windows-host shell attempted `wsl.exe --exec bash -lc ...`, it returned `Wsl/Service/E_ACCESSDENIED`. Direct Windows `docker` was unavailable (`docker` is not recognized). Consequently no further API/container/database inspection, full test rerun, or QA API container cleanup could be completed in this final acceptance turn. No terminal UI workaround was used.
- Merchant and Rider surfaces showed the same UPI-verified, assigned state, but authenticated user identity/role and database ownership could not be freshly reconciled from the blocked runtime. Sensitive address/contact details from checkout evidence were not retained in the phase report; address-bearing QA screenshots created during this run were removed.

### 4E.2 acceptance matrix

| Requirement | Result |
|---|---|
| Authoritative checkout amount and sandbox disclosure | PASS — Customer UI showed ₹345 and sandbox disclosure. |
| Verified sandbox UPI on Customer Android | PASS — backend-confirmed “Verified paid” shown after QA Success action. |
| Merchant Android blocks/permits based on payment state | PARTIAL — eligible UPI order was permitted and processed; negative ineligible runtime attempt not repeated here. |
| UPI order prepares and reaches ready for pickup | PASS — same order advanced in Merchant Android. |
| Rider receives only payment-eligible assignment | PASS for displayed journey — Rider saw same assigned UPI-verified delivery; no post-assignment transition tested. |
| Fresh same-order synthetic COD checkout and rider display | NOT VERIFIED. |
| Payment attempt/capture trace and exactly one balanced capture journal in PostgreSQL | NOT VERIFIED after UI success. |
| Failed/expired UPI, delayed success, replay, amount mismatch and duplicate checkout matrix | Automated regression evidence exists for relevant covered cases; full 4E.2 race matrix not executed. |
| No automatic merchant payable posting; Admin `finance.post` preserved | NOT VERIFIED against current runtime/database. |
| Admin operational view and role/security checks | NOT VERIFIED in this turn. |
| All-three-emulator installation and APK identity | PASS — same v4010/hash installed and launched; live UPI flow used Customer, Merchant and Rider screens. |
| Full Go/PostGIS, Flutter and focused final-copy tests | PASS historically as recorded above; focused 4-test catalog run was the only fresh test after the final UI-copy change. |
| Shared/production data unchanged and no real funds | PASS — no shared migration or real-money action was performed. |
| QA runtime cleanup | NOT VERIFIED; the isolated runtime API created for this acceptance may remain running. |

**Gate G2 decision: PARTIAL.** The live UPI path proves backend-confirmed payment state is respected by Merchant preparation and Rider dispatch visibility. Mandatory COD, post-success PostgreSQL/journal reconciliation, Admin runtime controls, payable non-posting verification, full fresh regression, and isolated runtime cleanup remain outstanding. Do not report Phase 4E.2 as PASS.

**STOPPED AT PHASE 4E.2 GATE — AWAITING EXPLICIT USER APPROVAL FOR PHASE 4E.3.**
