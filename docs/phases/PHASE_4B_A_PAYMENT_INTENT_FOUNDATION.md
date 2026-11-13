# Phase 4B-A — Payment Intent & Provider Boundary

**Status:** PASS for isolated QA
**Scope:** Server-owned payment intent snapshots and a provider-neutral API boundary only.
**Money movement:** Disabled. No provider session, payment attempt, payment-state update, ledger posting, UPI, COD, refund, settlement or payout is performed.

## Architecture

- Migration 031 adds an audited `payment_intent_creation_enabled` gate and a separate `payment_attempt_creation_enabled` gate. Both default to false. The existing migration-030 constraint still keeps UPI, COD, merchant settlement and real-money switches off.
- `payment_intents` stores one immutable amount/currency snapshot per platform-catalog order, with customer ownership and idempotency constraints. A database trigger verifies the owner, eligible unpaid platform-order source/state, order total in minor units and currency at insert time. Clients cannot submit a price.
- `payment_attempts` defines the future provider-attempt shape and allowed attempt-state progression. A database trigger rejects attempt insertion while the separate attempt gate is off and binds each attempt's amount/currency to its immutable intent. Phase 4B-A creates no attempt rows.
- `PaymentProvider` defines create-session, webhook-verification and provider-lookup operations. `UnconfiguredProvider` fails closed; no real or fake gateway implementation or credentials are included.
- Authenticated customer APIs create an idempotent intent and read the exact order's intent. Ownership failures are hidden as not found. The create route returns 503 while intent creation is disabled. When enabled for isolated QA, the response explicitly reports no provider session and `payment_status=not_collected`.
- `customer_orders.payment_status` is neither read as mutable payment truth nor changed by this phase; eligibility checks require the existing value to remain `not_collected`. Financial journal posting and rider earnings remain separate.

## Contracts

- `POST /api/v1/orders/{id}/payment-intents` — customer bearer token plus UUID `Idempotency-Key`; server derives `amount_minor` and currency from the owned eligible platform order. Exact retry returns the same resource. Changed-key reuse, existing intent, invalid order and disabled feature produce documented errors.
- `GET /api/v1/orders/{id}/payment-intent` — returns only the current caller's intent for the exact order.
- The OpenAPI contract states that creating an intent does not launch a provider session, collect funds, change order payment status or mark an order paid.

## Database and compatibility

Migration 031 is additive after 030; historical migrations are unchanged. Migration 031 has not been applied to shared development or production. Existing historical `not_collected` orders are not backfilled. The payment-attempt insertion gate and provider-facing operations remain disabled.

## Validation evidence

- Added a disposable PostGIS runner applying migrations 001–031 and executing the full Go suite: `scripts/qa/phase4b_a_payment_intents.sh`.
- Added database-backed coverage for default-off behavior, server-derived price, owner isolation, idempotent and concurrent retries, changed-key conflicts, immutable intent amounts, zero attempt creation, and unchanged order payment status; added fail-closed provider unit coverage.
- `wsl bash -lc 'cd /mnt/d/grepmind-near/backend && gofmt -w internal/payments/*.go cmd/api/main.go && go test ./internal/payments ./cmd/api'` — PASS after resolving the unused test variable. The database test skipped in this non-DB run.
- `wsl bash -lc 'cd /mnt/d/grepmind-near && bash scripts/qa/phase4b_a_payment_intents.sh'` — PASS. The script applied migrations 001–031 to a disposable tmpfs PostGIS instance, ran `go test -count=1 ./...`, passed all packages including the DB-backed payment-intent cases, and removed its temporary container. The first DB run exposed an ambiguous PL/pgSQL `order_source` reference; the trigger now qualifies source columns through the customer-order table alias. The final full run passed.
- Windows-side `python -c "import yaml; yaml.safe_load(open('api/openapi.yaml', encoding='utf-8'))"` — PASS. Targeted `git diff --check` and whitespace scan of new/modified files — PASS (Git emitted line-ending normalization notices only).
- No shared/production database was changed. No emulator or portal test is in scope for this backend foundation gate. No commit or push was created.

## Acceptance decision

**PASS for isolated QA.** The final migration-chain, full Go and targeted ownership/idempotency/provider-boundary checks passed. Do not start Phase 4B-B (sandbox provider sessions/webhooks) without explicit approval.

## Remaining risks

- Intent creation is not enabled by default, and there is no operator-facing feature-flag management route.
- Provider attempts are schema-only and blocked by default. Signature verification, replay handling, late success, capture-state projection and financial journal integration belong to the later sandbox gate.
- No actual provider is selected. Seller-of-record, settlement arrangement, GST treatment and commercial terms remain live-activation prerequisites documented in Phase 4A.
