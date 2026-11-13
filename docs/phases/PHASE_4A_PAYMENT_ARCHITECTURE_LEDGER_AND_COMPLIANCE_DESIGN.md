# Phase 4A — Payment Architecture, Ledger & Compliance Design

**Status:** Design accepted; Phase 4A-Build passed isolated PostGIS acceptance; Phase 4B-A implemented, runtime acceptance pending
**Date:** 10 November 2026
**Original design scope:** Source audit and architecture design only. At that stage no migrations, payment integration, COD collection, or financial postings were implemented. Implementation evidence is recorded in the Phase 4A-Build section below; all real-money activity remains disabled.

## Executive decision

The repository has a server-authoritative commerce foundation and an append-only rider compensation ledger, but it does **not** yet implement customer payment collection, COD, merchant payables, refunds, or merchant settlement. Phase 4 should establish these as separate financial domains and connect them through immutable, balanced accounting journals. The Go modular monolith remains the authority; provider callbacks and browser/app return screens are inputs, never proof of payment by themselves.

The desired centralized UPI collection and merchant settlement model is a product decision, not evidence that Grepmind may hold or distribute third-party funds. Before live activation, counsel and a payment provider must confirm the seller-of-record, funds-flow, payment-aggregator/marketplace arrangement, escrow/settlement product, GST treatment, customer disclosures, refunds, and support obligations. Until then, development and QA use only sandbox providers and synthetic COD records.

## Repository audit — current behavior and evidence

| Area | Current source evidence | Verified conclusion |
|---|---|---|
| Checkout/order payment state | `backend/migrations/019_customer_addresses_checkout.sql` adds `customer_orders.payment_status` with `not_collected`, `pending`, `paid`, and `failed`. `backend/migrations/023_platform_cart_checkout.sql` adds platform catalog quote/order fields. | This is a small order-level state field, not a payment entity or accounting ledger. It cannot safely represent attempts, partial payments, late callbacks, refunds, cash liability, or settlement. |
| Platform quote and order | `backend/internal/platformcommerce/service.go` quote returns INR integer minor units; delivery fee/tax are explicitly `not_configured` and zero. Order submission persists `not_collected`, validates quote and inventory, and is idempotent. `api/openapi.yaml` documents no payment collection. | Customers can create unpaid orders. The server does not collect or verify payment. Do not infer that a placed/delivered order is paid. |
| Delivery completion | `backend/internal/deliverydispatch/execution.go` and `recovery.go` keep delivery/order lifecycle separate from payment. | Existing delivery and return state transitions do not collect COD or settle merchants. |
| Rider earnings | `backend/migrations/028_rider_earnings_ledger.sql` creates append-only rider compensation policy, earning, and audit tables. `backend/internal/riderearnings/service.go` records an idempotent completion effect in the delivery transaction. `backend/pkg/config/config.go` defaults posting off and restricts synthetic policy use to QA/test. | This is a rider compensation subledger only. It is not payment, COD, merchant payable, or payout functionality. Real rate policy and posting remain disabled. |
| Existing finance UI/API | Rider endpoints are registered in `backend/cmd/api/main.go`; Rider and primary-superadmin screens are `apps/mobile/lib/core/screens/rider_earnings_screen.dart` and `apps/admin-web/components/RiderEarningsView.tsx`. The UI explicitly says payouts/settlement are unavailable. | There is no customer payment UI, Merchant settlement UI, COD remittance UI, or finance operations module. |
| API/schema inventory | `api/openapi.yaml` has rider earnings contracts but no payment-intent/session, provider webhook, refund, COD, payable, settlement, or reconciliation endpoint. Latest repository migration is 029. | No payment provider or payment/COD/settlement schema is present in the audited API and migration set. No migration was added in 4A. |

The existing `customer_orders` / `customer_order_items` model and distinct order, delivery, payment, and rider-earning state dimensions must remain compatible. Phase 4 must not replace legacy food, reservation, hotel, or service order workflows.

## Domain boundaries

1. **Customer payment** records verified funds collected for an order. It has provider intent/attempt state and provider references.
2. **COD collection** records cash physically collected by a rider and the resulting rider cash liability. Cash collection is not rider income and must never be netted against earnings implicitly.
3. **Merchant payable** records the amount owed under approved merchant terms after the applicable fulfillment, delivery, refund, and return rules.
4. **Rider earnings** remains the separate compensation domain already implemented in Phase 3F. A payment or COD collection must not create rider earnings.
5. **Refund** records an authorized return of funds and its provider state; it does not erase the original payment or order history.
6. **Payout/settlement execution** means an external funds transfer confirmed by the provider/bank. A calculated payable or generated batch is not proof of a transfer. External payouts remain disabled during Phase 4 implementation and QA.

## Proposed state machines

### UPI payment

`created → pending → paid | failed | expired`

- Each retry is a new immutable payment attempt under the same order/payment intent; one order must not receive duplicate successful captures beyond the server-authorized due amount.
- A late provider success after local expiry is not discarded or shown as a failure. It enters reconciliation as a verified late success, then an authorized policy resolves the order (for example, fulfill if still eligible or refund). Never silently create a second order or duplicate ledger posting.
- Only server-verified provider status changes payment state. Deep-link/app return, client polling payload, screenshot, customer assertion, and unverified webhook are not proof.
- `paid` means the provider has verified/captured the customer's payment obligation. It does **not** mean the provider has settled the gross/net funds into Grepmind's bank or an approved settlement account. Track provider capture and provider-to-Grepmind settlement as separate facts, references, timestamps, amounts, and reconciliation states.
- An order can have no payment (existing `not_collected` path), one successful full payment, or a future explicitly designed partial-payment case. Partial payments are not enabled in the initial sandbox slice.
- A verified payment webhook may append the provider event and payment-state/journal effect only. It must not accept, prepare, dispatch, pick up, deliver, or otherwise bypass the order/delivery state machines or inventory/custody rules. A separate transactionally guarded order-eligibility flow decides what happens when funds arrive for an order that is cancelled, returned, or otherwise no longer fulfillable; otherwise the verified capture remains a reconciliation/refund exception.

### COD cash liability

`due → collected → remitted → reconciled`, with explicit `disputed` / `short` / `over` exception outcomes.

- COD eligibility is an explicit server decision before order acceptance, based on approved locality, vertical, merchant/customer policy, value limits, and operations configuration. No default eligibility is assumed.
- Cash due is snapshotted from the authoritative order total and may not be edited by Rider or client.
- Rider records collection only through an authorized delivery action with idempotency and auditable evidence. The system records a liability to Grepmind's approved collection process, not rider earnings.
- Remittance is recorded against an identified receiver/bank/cash-office process and reconciled by an authorized finance/admin role. A rider cannot self-approve their remittance.
- Phase 4C QA uses synthetic amounts and simulated receipt/remittance records only; no cash is exchanged.

### Refund and merchant payable

- Refund: `requested → approved → processing → succeeded | failed`; approval and provider execution are separately recorded. Partial/refund reason/scope must reference immutable order lines or amounts.
- Return, cancellation, or failed delivery is evidence for a refund decision, not itself a refund authorization. Refund eligibility and amount are computed from the order's paid amount, prior successful refunds, immutable item/charge snapshots, event history, and the approved commercial/refund policy. A returned unpaid order creates no customer refund; a paid returned order is not assumed to receive a full refund. COD return is a cash/collection exception and is not modeled as a provider refund unless a separate customer reimbursement is approved and recorded.
- Merchant payable: `accrued → eligible → batched → externally_confirmed`, with `held`, `adjusted`, and `reversed` states represented by separate events/entries rather than overwriting history.
- Return disposition, cancellation eligibility, paid/unpaid state, and applicable merchant terms determine payable and refund effects. No payable is made externally settled by a database state change alone.
- No commission, tax, delivery fee, refund allocation, or merchant share is hardcoded until the product/legal/accounting owners approve a versioned policy.
- Do not assume partner payable equals customer selling price less a commission. Grepmind controls customer catalog price and partners fulfill mapped items; payable basis depends on whether the signed arrangement is a supplier purchase/supply price, marketplace agency/commission, or another approved structure. Seller-of-record and the specific contractual model must be resolved before payable calculations are activated.

## Target accounting architecture

### Ledger rules

- Use immutable journals and debit/credit postings in integer minor units (`BIGINT`) with explicit ISO currency. Do not use floating point or `NUMERIC` as an arithmetic transport format in app/API code.
- Every posted journal balances per currency: total debits equal total credits. Enforce this in a transaction and with a deferred database constraint/validation mechanism; incomplete journals must not be visible as posted.
- Journal source, source event, and idempotency key are unique enough to prevent duplicate posting. Corrections use linked reversal/adjustment journals, never updates/deletes.
- Separate account classes/control accounts for provider clearing, customer funds/receipts, merchant payable, platform fee/revenue, tax liabilities, refunds, rider cash liability, and rider compensation. Final account mapping needs the accountant's chart-of-accounts approval.
- Reconciliation compares internal journals with provider settlement reports and cash-remittance evidence. It reports discrepancies and supports audited resolution; it does not silently repair balances.
- Keep named records and statuses distinct for (a) provider-confirmed capture, (b) provider settlement into the approved Grepmind account, (c) internal merchant payable, and (d) external merchant transfer confirmation. Avoid one overloaded `settled` flag. A provider settlement statement must reconcile gross capture, provider fees/adjustments, net settled amount, currency and bank reference; it is not a merchant payout record.
- COD's rider-facing `cash_due_to_platform` is an operational subledger/control balance. Accounting classification must be approved by the accountant; for example, books may represent cash held by a rider as a due-from-rider/cash-in-transit asset. Do not assume the phrase “rider cash liability” is itself the final general-ledger account classification. It remains strictly separate from rider compensation earnings.

### Illustrative balanced journal flow (symbolic amounts only)

These entries show separation and balancing, not a final chart of accounts or accounting/tax policy. Let `G` be gross customer amount, `N` provider net settlement, `F` verified provider fee/adjustment, and `M` a payable amount established by an approved partner contract. Each journal balances per currency; the actual account names and recognition timing require accountant/legal approval.

| Event | Illustrative debit | Illustrative credit | Must remain separate |
|---|---|---|---|
| Provider confirms UPI capture `G` | Provider receivable / clearing `G` | Customer funds in transit / unapplied receipts `G` | Does not mark provider payout settled, merchant payable paid, or order delivered. |
| Provider statement/bank confirms settlement | Bank/cash `N`; provider fee/adjustment expense or receivable `F` | Provider clearing `G` (where `G = N + F`; model other adjustments as explicit lines) | This is provider-to-Grepmind settlement, not merchant transfer. |
| Contractual partner payable `M` accrues | Approved fulfillment cost/partner expense `M` (or applicable contract-specific account) | Merchant/partner payable `M` | Recognition trigger and basis depend on seller-of-record and contract; do not infer commission. |
| COD collected by rider | Due-from-rider / cash-in-transit control `C` | Contract-specific collection clearing/payable/receivable counter-account `C` | Creates a rider cash custody balance, never rider earnings. The correct counterpart depends on who sold the goods and owns the receivable. |
| Rider remits COD `C` | Bank/cash office asset `C` | Due-from-rider / cash-in-transit control `C` | Clears custody only after an authorized receiver/remittance record; does not create earnings. |
| Approved customer refund `R` executes | Refund payable/customer reimbursement clearing `R` (with any approved payable reversal separated) | Provider/bank cash or clearing `R` | Preserve original capture, refund authorization and provider-confirmed refund as separate immutable events. |

Never create a journal from an unverified provider callback, customer app return, COD screen tap, or merchant-entered status alone. A journal and its postings are committed atomically; a rejected/failed transaction creates no partially posted journal. Reversal journals link to and preserve the original journal and cannot exceed the reversible amount under the approved policy.

### Proposed additive data model (design only)

These are logical entities, not approved table names or migrations:

| Entity | Purpose and key constraints |
|---|---|
| `financial_accounts` | Versioned chart/control accounts, currency and account class; no sensitive bank credentials. |
| `financial_journals` | Immutable business event, source identity, idempotency key, state, currency and actor/system origin. |
| `financial_postings` | Debit/credit amount in minor units, account, order/payment/COD/payable references. Balanced journal constraint. |
| `payments` | Order/customer, amount due, currency, payment method, lifecycle state and current reconciliation status. |
| `payment_attempts` | One provider attempt per retry with unique provider reference, expiry, amount snapshot and safe status history. |
| `payment_provider_events` | Verified/raw-body hash, provider event identity unique per provider, signature verification outcome and processing status; raw secrets/card/UPI credentials are not stored. |
| `provider_settlement_batches` / `provider_settlement_lines` | Provider statement/bank settlement period, gross, fees/adjustments, net, currency, transfer reference, file checksum and matched/unmatched status. Separate from merchant settlement batches. |
| `refunds` | Authorized requested amount/reason, approval, provider state/reference, idempotency and immutable history. |
| `cod_collections` / `cash_remittances` | Snapshotted amount due, collecting rider, collection evidence, receiver/remittance reference, discrepancy and reconciliation actors. |
| `merchant_payables` / `merchant_settlement_batches` / `merchant_settlement_items` | Versioned partner contract basis, order-level accrual, fees/refunds/adjustments, holds and payable balance. An externally confirmed merchant transfer is a separate later fact. No external transfer during Phase 4 QA. |
| `financial_reconciliation_runs` / `exceptions` | Source file/provider period, checksum, totals, matching status, unmatched rows, reasoned resolution and audit trail. |

The next additive migration after 029 is **030**, but its table boundaries and rollout order must be finalized in 4A review. Do not create or apply migration 030 as part of this design milestone. Historical migrations remain immutable; migrations 023–029 have not been applied to shared development/production according to the phase records.

### Historical compatibility requirements

- Do not rewrite migration 019, 023, or any other historical migration. Add only sequential migrations after 029; test from a clean disposable PostGIS DB and against a disposable copy with the supported migration chain before any shared rollout is proposed.
- Existing orders retain their current order/payment values. Existing `payment_status='not_collected'` means exactly that; do not backfill synthetic payment intents, captures, refunds, COD collections, provider settlements, or merchant payables for historical orders.
- Keep legacy `customer_orders` payment defaults and all existing order/delivery/reservation/hotel/service status flows valid. New payment/COD entities are opt-in and do not change delivery/order state unless a later approved orchestration transition explicitly does so.
- Leave the Phase 3F rider earning tables and entries unchanged. Do not copy rider earnings into the financial journal as if they were customer payments or COD. If a future accounting bridge is required, link a new journal effect to the immutable earning entry with a one-to-one idempotent source reference; never rewrite the earning row.
- Existing orders can lack platform quote snapshots and use legacy decimal amount columns. Financial journal amounts remain integer minor units; conversion must be exact and validated against currency scale and bounds. Do not use binary floating point, and do not silently reinterpret historical amounts.

## Go API and provider contracts (proposed)

Keep provider integration behind interfaces in the existing Go modular monolith. Example responsibilities (names are illustrative):

- `PaymentProvider.CreatePaymentSession(ctx, request)`: server amount/currency/order reference, provider idempotency key, bounded expiry; returns provider reference and customer launch data.
- `PaymentProvider.VerifyWebhook(ctx, headers, rawBody)`: signature/timestamp verification over exact raw bytes; returns a normalized event only after verification.
- `PaymentProvider.FetchPayment(ctx, providerReference)`: server-to-server reconciliation lookup for ambiguous or late outcomes.
- `PaymentProvider.CreateRefund(ctx, request)`: sandbox-only, idempotent refund execution.
- `SettlementReportImporter`: validates provider/bank report checksum, currency, total and row identity before reconciliation; no direct transfer capability in Phase 4.

Expected future HTTP surface (final path/version to be approved with OpenAPI):

- Customer-authenticated create/retry payment session and read payment state for an owned order.
- Provider-authenticated webhook endpoint with signature, freshness, replay, size and rate controls.
- Admin/finance-authorized payment/refund review, reconciliation exception view, COD remittance review, and payable/batch read or simulation endpoints.
- Merchant portal read-only payable/settlement statement views scoped by `business_id`; merchants cannot change platform fee, payout status, or ledger postings.
- Rider collection/remittance actions scoped to the authenticated assigned rider and exact delivery/order; rider cannot edit amount due, finalize their own reconciliation, or read another rider's cash ledger.

Never expose provider secrets, partner supply cost, another merchant's payable, customer payment instrument data, or full provider payloads to clients. Use a provider allowlist/configuration; no provider is selected or enabled in 4A.

## Security, reliability, and operational controls

- Provider webhook: TLS at the edge, exact raw-body signature verification, key rotation support, signed timestamp/freshness window, replay-safe provider event uniqueness, strict body size, endpoint-specific rate limits, minimal logs, and alerting on repeated verification failures.
- Client payment return: treat as a hint and query server/provider; never mark paid from Flutter/Admin/Merchant state, redirect query parameters, or browser callback.
- All mutations enforce authenticated owner, merchant membership/business isolation, assigned rider, or explicit finance/admin permission server-side. Root superadmin protections stay intact; high-risk adjustments require reason, idempotency, append-only audit and least privilege.
- Enforce legal state transitions in Go services and transactions with row locks/conditional updates. Ensure order cancellation/return versus successful payment/callback races have one consistent winner and compensating journal behavior.
- Use an outbox or the existing durable event mechanism for post-commit notifications. Do not publish `paid`, `refunded`, `collected`, or `settled` SSE/UI events before the transaction commits.
- Reconciliation must detect duplicate, missing, late, amount-mismatch, currency-mismatch and orphan provider records; Admin sees actionable exceptions rather than zero/paid defaults.
- Do not store UPI PINs, full card data, bank login secrets, or unnecessary payer credentials. Minimize financial personal data and define retention/deletion with counsel and the gateway.
- Feature flags default closed. Sandbox keys must be separate from production; real-money switches must fail closed unless a later explicit authorization, reviewed configuration, legal arrangement and operational checklist exist.

## UI responsibilities

| Surface | Phase 4 direction |
|---|---|
| Customer Flutter | UPI sandbox launch/pending/confirmed/failed/expired/retry states; server-reconciled order status and refund history. COD choice only when backend says eligible; clear amount due and collection confirmation. Never show success optimistically. |
| Rider Flutter | COD amount due and collect confirmation only for assigned COD delivery; remittance/discrepancy workflow in 4C. Earnings remain a separate tab/value. No payout button. |
| Merchant Portal | Order-level financial status and statement preview only after server records; payable calculation/holds and settlement batch visibility after 4D. No seller-side control of platform price or ledger. |
| Admin Portal | Payment/refund exception queue, webhook/reconciliation health, COD cash liability/remittance, payable and settlement controls, immutable audit trail, and filters by locality/date/provider/state. High-risk write controls require confirmation and reason. |

All screens need loading, empty, failure, retry and permission-denied states; an API failure must never render a zero balance or false “settled” state.

## Phased dependency and acceptance plan

| Subphase | Scope | Mandatory acceptance gate |
|---|---|---|
| **4A — Architecture/design** | Domain model, state machines, balanced ledger, provider interface, regulatory/accounting questions, API/data/UI plans, threat model. | Design review accepts seller/funds flow questions as explicit unresolved decisions; no code/schema/payment state mutation. This document is the design deliverable. Stop for approval before 4B. |
| **4A-Build — Financial foundation** | Minimal account chart primitives, append-only journals/postings/audit, DB-enforced balanced posting, idempotency/reversal, fail-closed finance configuration and finance authorization. | Disposable PostGIS through migration 030; full Go suite; DB tests prove unauthorized/unbalanced posts cannot commit, concurrent retries create one journal, reversal is append-only, defaults remain disabled, and historical order payment states remain unchanged. Does not implement UPI, COD, merchant payable operations, refunds, payouts, or order payment-state writes. |
| **4B — UPI sandbox** | Provider adapter, server-created intents, Flutter pending/retry flow, webhook verification, late-success reconciliation, sandbox refunds. | Fake provider contract tests, signature/replay/late-event tests, idempotency and order-ownership tests, balanced journal tests, disposable DB; UI displays only server-verified sandbox state. No live credentials or money. |
| **4C — Synthetic COD** | Eligibility policy, amount snapshot, rider collection liability, synthetic remittance/dispute controls. | Assignment/ownership isolation, duplicate collection protection, amount tamper rejection, remittance separation, cash-versus-earnings reconciliation; no physical cash. |
| **4D — Payables/finance ops** | Versioned commercial terms, payable calculations, fee/refund allocation, batch previews, statements and Admin review. | Deterministic sample reconciliation in each currency, append-only adjustments, role/biz isolation, no transfer API or external settlement claim. Requires finance/legal policy approval for rates. |
| **4E — Commerce integration** | Tie verified payments, COD, cancellation/return, dispatch/delivery, refunds and financial journals together. | Cross-surface same-order API/DB/UI reconciliation, race matrix, no paid-state fabrication, no double payable/refund/cash/earning posting. |
| **4F — Integrity/security/isolated QA** | Replay/concurrency/security/load/reconciliation, two-device and portal acceptance, runbooks. | Repeated isolated suites, balanced journals, all exceptions accounted, secure cleanup, explicit PASS/PARTIAL. Still no real money or payouts. |

Phase 3H release hardening and pilot readiness remains deferred as directed. Phase 4A does not activate real compensation, payments, COD, merchant transfers, or rider payouts.

## Decisions still required before live activation

1. Seller of record and contractual role of Grepmind versus each partner.
2. A gateway/marketplace settlement product and written confirmation of its supported funds flow, onboarding/KYC, refunds, disputes and settlement timing. No provider is selected in this design.
3. Legal/accounting advice on whether Grepmind's proposed collection/holding/transfer flow requires a regulated Payment Aggregator arrangement or must remain entirely within an authorized provider's funds flow.
4. GST invoicing and any e-commerce operator collection/reporting obligations for the actual principal/agent and consideration model; tax rates and treatment must not be guessed in code.
5. Approved merchant fee/commission and delivery-fee allocation, refund/chargeback loss allocation, reserve/hold rules and settlement calendar.
6. COD eligibility, cash custody, insurance/security, maximum amount, receipt, failed handover, short/over cash, remittance location and escalation SLA.
7. Refund authority/threshold, partial refund rules, customer support/dispute policy, reconciliation windows, financial retention and audit access.

These are professional-review and commercial-policy questions, not assumptions the code should make. RBI's 15 September 2025 Payment Aggregator Master Direction covers PA applicability and settlement/escrow requirements; CBIC materials describe e-commerce operator GST/TCS obligations with outcomes depending on the transaction model. Obtain current India-specific legal and tax advice before choosing a live funds flow: [RBI Master Direction on Regulation of Payment Aggregators (2025)](https://www.rbi.org.in/Scripts/NotificationUser.aspx/upload/notification/docs/Scripts/NotificationUser.aspx?Id=12896), [RBI PA/PG Guidelines](https://www.rbi.org.in/Scripts/NotificationUser.aspx?Id=11822&Mode=0), [CBIC e-commerce FAQs](https://cbic-gst.gov.in/hindi/sectoral-faq.html?initialSessionID=259-3264333-3442837&ld=SDINSOADirect).

## Phase 4A design completion record

- Read current checkout, order, rider earning, migration, API, and portal/mobile source paths listed above.
- Confirmed the current checkout remains unpaid and rider earning posting is separately disabled by default.
- No application source, OpenAPI contract, migration, runtime service, or database was changed for Phase 4A.
- No payment provider was selected, no credential was introduced, and no real or sandbox transaction was initiated.
- **Recommendation: 4A design ready for review; Phase 4B is not started and requires explicit approval.**

## Phase 4A-Build — Financial foundation implementation (10 November 2026)

**Result: PASS for isolated QA.** This is a separate implementation gate after the accepted design; it does not mark the subsequent payment, COD, or settlement phases complete.

### Schema and invariants

- Added additive migration `backend/migrations/030_financial_foundation.sql`; no historical migration was edited and migration 030 was applied only to a disposable tmpfs PostgreSQL 16/PostGIS database.
- The minimal schema contains `financial_accounts`, `financial_feature_config`, `financial_access_grants`, `financial_journals`, `financial_postings`, and `financial_audit_events`. No payment attempt, COD collection/remittance, merchant payable/settlement, refund, payout, provider credential, or order posting table was added.
- Journals are created as drafts and transition once to `posted` inside the caller's database transaction. A deferred PostgreSQL constraint trigger checks at commit that every posted journal has at least two postings across at least two enabled accounts, all in the journal/account currency, with positive debit and credit totals equal. A `BEFORE` trigger also requires an active authorized finance actor when the journal is posted. Posted journals/postings, financial accounts' identity, and audit records are immutable; corrections use one full equal-and-opposite reversal journal.
- Unique constraints cover idempotency keys, `(source_type, source_id, source_event)`, and one reversal per original journal. The Go service fingerprints posting requests, returns the existing journal for an identical retry, and rejects a reused source/key with changed content. Row locks plus unique constraints protect concurrent duplicate posts and reversals.
- Finance permissions are separate from the ordinary admin role. Non-root finance actions require an active admin with a separately approved grant; grant issuer, approver, and target are distinct, and grants/revocations are append-audited. Configuration changes require finance authorization, actor and reason. The root superadmin remains protected.
- All feature flags default off. Migration 030's database constraint keeps UPI, COD, merchant settlement, and real-money flags off; only the generic accounting-posting gate can be turned on through the authorized, audited service for isolated ledger validation. No application endpoint or portal exposes a posting/configuration workflow.

### Compatibility and scope boundaries

- Migration 030 documents `customer_orders.payment_status` as a compatibility state. The ledger package does not read or write it; existing `not_collected` orders are not backfilled or mutated. A verified-payment-derived projection remains future payment integration work and must preserve paid history when refunds are later represented.
- Phase 3F rider earnings remains its own append-only subledger. This migration does not copy, net, or transform rider earning entries.
- No OpenAPI or public API contract changed. No payment-provider interface was activated, and no UPI/COD/merchant-settlement/refund/payout operation was initiated.
- COD liability accounts and merchant payable accounts are not seeded or accrued in 4A-Build: their business events and classification belong to approved later subphases. The generic chart supports those future classifications without assuming rates, seller-of-record, or funds flow now.

### Verification evidence

- Command: `wsl bash -lc 'cd /mnt/d/grepmind-near && bash scripts/qa/phase4a_financial_foundation.sh'` — PASS. The script created an isolated PostGIS container with tmpfs storage, applied migrations 001–030 (including documented legacy bootstrap prerequisites), verified six Phase 4A foundation tables, ran `go test -count=1 ./...` with `TEST_DATABASE_DSN` pointed at that disposable database, and removed the container on exit.
- The PostgreSQL integration test verifies all feature flags default off; disabled posting is rejected; UPI/COD/settlement/real-money flags cannot be enabled; self-approval is rejected; an ordinary customer and direct SQL cannot post; an authorized raw SQL unbalanced journal fails at commit; exact repeated posts return one journal; changed payload reuse is rejected; eight concurrent identical submissions produce one journal ID; reversal creates opposite entries and preserves the original; second reversal and update/delete of a posted journal are denied; grant revocation removes access and is audited; a QA historical `not_collected` order remains unchanged.
- `gofmt` was run on the new Go package. Scoped `git diff --check` is recorded after final edits below. No emulator, portal, shared-development database, or production database was used.
- The first disposable attempt exposed a PostgreSQL startup-readiness race in the new QA script; the script was corrected to wait for the final startup. The first integration attempt exposed a nullable memo scan and a raw-test actor omission; both were corrected. The final full migration and Go test run passed.

### Remaining risks and next gate

- Phase 4A-Build has no finance HTTP endpoints or user-facing finance screens; payment intents, verified callbacks, COD collection, merchant payable calculation, refunds, payouts, provider settlement reconciliation, and account-grant management UI are intentionally not implemented.
- The actual payment-state projection from verified provider events is not implemented until a payment domain exists. The current order field remains the legacy compatibility state.
- Seller-of-record, legal funds flow, payment-provider arrangement, GST treatment, merchant commercial terms, refund policy, and COD custody remain unresolved prerequisites before live activity.
- Migration 030 is not applied to shared development or production. This PASS is isolated-QA only. Real-money switches and all later payment/cash/settlement operations remain disabled.
- **Stop: Phase 4B has not started and requires separate explicit approval.**
