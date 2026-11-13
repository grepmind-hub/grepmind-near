# Phase 4B-B — Sandbox Provider, Verified Webhooks & Ledger Integration

**Result: PASS for isolated QA (10 November 2026).** This records backend behavior against a disposable tmpfs PostgreSQL/PostGIS database only. It does not authorize production use, shared-database migration, live UPI, COD, refunds, merchant settlement, payouts, or Flutter checkout.

## Scope delivered

- Added additive migration `backend/migrations/032_sandbox_payment_provider.sql`. It adds fail-closed sandbox configuration, provider event and reconciliation history, ledger-account mappings, constrained sandbox attempt transitions, and the guard preventing a verified paid platform order from being cancelled/returned before a refund workflow exists.
- Added a deterministic in-memory `grepmind_sandbox` provider. It is available only in explicit `qa`/`test` configuration with sandbox enablement and webhook secret/key ID. Otherwise the provider is unconfigured. Webhooks authenticate the exact raw body using HMAC-SHA256, bounded timestamp freshness, key ID, and constant-time comparison. The provider has no network client or live gateway integration.
- Added session creation/replay, webhook processing, and finance-authorized server-to-server reconciliation. Amount and currency come from immutable server records. No raw webhook body or signature secret is persisted.
- Verified successful captures create a single balanced INR journal through the narrow sandbox ledger entry point. Capture, provider event, payment attempt/intent, order payment projection, and reconciliation exception remain linked. Order fulfillment state is never changed by a payment callback.
- Preserved historic `not_collected` orders without backfill. Rider earnings remain separate. Payment status is only projected from verified sandbox events; a session is not payment evidence.
- Added OpenAPI contracts and a disposable acceptance runner that applies migrations 001–032 in a tmpfs PostGIS container and removes the container on exit.

## API contracts added

- `POST /api/v1/orders/{id}/payment-sessions` — customer-owned, bodyless, server-priced, idempotent sandbox session.
- `POST /api/v1/payments/webhooks/{provider}` — unauthenticated provider callback, authenticated by exact-body signature. Only `grepmind_sandbox` is allowlisted.
- `POST /api/v1/admin/payments/attempts/{id}/reconcile` — finance-authorized reconciliation using provider-fetched status; callers cannot submit a payment result.

The 4B-A `POST /orders/{id}/payment-intents` and `GET /orders/{id}/payment-intent` contracts remain in place. Live provider flows remain disabled.

## Validation actually executed

From the Windows host using the requested Ubuntu WSL route:

```text
wsl bash -lc 'cd /mnt/d/grepmind-near && bash scripts/qa/phase4b_b_sandbox_provider_webhooks.sh'
```

Result: **PASS**. The runner applied migrations 001–032 to a new disposable tmpfs PostGIS container, then ran `go test -count=1 ./...`; every Go package passed. The integration coverage exercised invalid signatures without state mutation, concurrent duplicate success webhooks, exact duplicate acknowledgement and changed-payload event conflict, balanced single posting, payment/order projection consistency, canceled-order late success without reopening fulfillment, amount mismatch and late success reconciliation, finance authorization, webhook/reconciliation concurrency, success/expiry concurrency, multiple-capture exception handling, and ambiguous provider-timeout retry without creating a second attempt. Provider HMAC tests cover raw-body tampering, stale signatures, key rotation overlap, and fail-closed environment selection.

The first full run found an ambiguous-timeout retry bug: a nullable `provider_reference` was scanned directly into a Go string. The retry lookup now uses `COALESCE`; the complete migration and Go suite was rerun after the fix and passed. The runner reported removal of its disposable container.

OpenAPI YAML parsing passed with PyYAML on api/openapi.yaml; targeted git diff --check passed under Windows Git and WSL Git configured with core.whitespace=cr-at-eol for repository CRLF files; no Flutter or portal test was run because this phase is backend-only.

## Boundaries and remaining risks

- Migration 032 was applied only to the disposable test database. Migrations 030–032 remain unapplied to shared development and production.
- Sandbox provider state is intentionally in-memory and deterministic; it is not a durable or production gateway adapter. A process restart can lose fake-provider state, so this implementation is not an operational payment provider.
- Full commercial, legal, tax, seller-of-record, gateway marketplace/settlement, refund, COD and payout decisions remain unresolved or deferred. No real-money feature is enabled.
- No Flutter checkout, browser payment UI, provider sandbox credentials, real refunds, COD, merchant payables, or settlement execution were added.
- No commit or push was created. Existing unrelated worktree changes were preserved.

## Acceptance

**PASS for isolated backend QA.** Verified fake-provider success posts exactly one balanced journal; repeated/concurrent webhooks do not duplicate captures; late success is retained and reconciled without reopening a cancelled order; payment projection agrees with verified records; and all live-money flags remain disabled. Phase 4B-C remains not started and requires explicit approval.
