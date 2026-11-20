# Phase 5B.4A — Safe QA Fixture Orchestrator

**Status: IMPLEMENTED — non-mutating planner validated; fixture generation is not enabled. Phase 5B remains PARTIAL.**

## Scope and source audit

This gate adds a dry-run planner and fail-closed safety contract for a future isolated-QA fixture workflow. It does not create users, orders, payables, journals, COD events, earnings, beneficiaries, settlements, or payout transfers. No migration or financial business logic changed.

The source audit confirmed that:

- Merchant payable accrual is an Admin `finance.post` operation over a genuinely eligible completed order. Settlement creation, review, approval, simulation, and reconciliation remain separate audited actions with separation-of-duties checks.
- Rider cash liability is derived from COD collection less Finance-verified remittance. Collection requires the assigned rider's authorized delivery handover; it is not rider earnings.
- Rider earnings originate from a completed delivery through `riderearnings.RecordCompletionTx`; settlement accrual reads those entries and blocks while COD liability is outstanding. Administrative compensation-policy setup is restricted to primary-superadmin controls.
- Merchant beneficiary data uses `bank_beneficiaries` (migration 039), not `payout_beneficiaries`. Merchant and Rider settlements are represented in migrations 035/039/040.
- Existing G4-B QA scripts are broad acceptance suites; source inspection found direct rider earning/policy SQL setup. They are not used as fixture generators.

Relevant source: `backend/internal/merchantfinance/service.go`, `backend/internal/codcash/service.go`, `backend/internal/riderearnings/service.go`, `backend/internal/payouts/rider_settlement.go`, `backend/internal/payouts/beneficiaries.go`, and migrations 035, 039, and 040.

## Implementation

- `backend/internal/qafixtures` produces six deterministic scenario plans: Merchant A/B payable and settlement, Rider A/B earning and settlement, Rider A nonzero COD liability, and Rider B independent COD liability/zero balance.
- Each scenario has a stable SHA-256 idempotency key derived from a non-secret run ID and scenario name. Repeating a dry run produces the same plan.
- All scenarios currently report `blocked`: there is no narrow approved workflow adapter that provisions distinct synthetic actors and generates the required events using the normal authenticated domain workflows. The plan enumerates prerequisites; it does not imply those records exist.
- The package defines fail-closed execution checks for QA/test environment, disposable database/container identity, no persistent mounts, exclusive QA network, matching DB identity, disabled real-money/payout flags, fake/sandbox provider, synthetic-only actors, distinct merchant businesses, and independently approved riders.
- The CLI defaults to dry run. Its execution mode is deliberately disabled because the current CLI does not independently inspect live Docker/database evidence and no approved domain workflow adapters exist. `--execute` plus `--confirm-isolated-qa` cannot override that limitation.
- Tests use in-memory evidence only. No runtime database query, Docker operation, fixture generation, or financial mutation was performed as part of this gate.

## Run commands

From `D:\grepmind-near\backend` in the user's interactive WSL shell:

```sh
APP_ENV=qa go run ./cmd/qa-fixture-orchestrator --dry-run --run-id phase5b-review-001
```

This command only prints the plan. Do not run the execution form until a later gate implements live isolation verification and approved workflow adapters. The currently refused form is:

```sh
APP_ENV=qa go run ./cmd/qa-fixture-orchestrator --execute --confirm-isolated-qa --run-id phase5b-review-001
```

It must exit nonzero with an explicit “execution is disabled” reason; no data is changed. A usable future execution command cannot be authorized or claimed yet because the safe provisioning/order/delivery/approval adapter does not exist. No API credentials, OTPs, bank details, or actor secrets belong on the command line.

## Synthetic identity and lifecycle plan

A future authorized run needs two distinct synthetic Merchant users/businesses, two distinct Admin-approved synthetic Riders, and distinct Customer/Admin principals as needed. Authentication must use the protected QA OTP mechanism. The Merchant scenario must create a new order and complete payment plus delivery through normal APIs/UI, then use Admin `finance.post` and independent settlement review/approval/simulation controls. The Rider scenario must produce earnings only through an approved delivery completion and use existing settlement controls. COD liability must arise from a real synthetic COD delivery handover; remittance can clear it only through the existing verified workflow. No seed-only financial records are acceptable.

## Preconditions, reset, and evidence for a later execution gate

Before any future mutation, the executor must establish `APP_ENV=qa|test`, inspect the actual database container and expected QA-only network, verify there are no persistent mounts, query `current_database()` and financial safety flags read-only, verify no live provider, and confirm synthetic actor ownership/approval. Any unknown or mismatched evidence must stop before mutation. Both `real_money_enabled` and `payout_enabled` must remain false.

Reset/rollback is limited to discarding the disposable QA database/container after capturing redacted evidence. Do not reverse immutable financial history or delete records from shared/production systems. Expected evidence includes run ID, actor role references (not credentials), distinct business/rider bindings, order/delivery references, payable/earning/COD/remittance IDs, approval/audit references, journal balance checks, authenticated cross-account denials, API/UI amounts, and refresh/restart persistence.

## Validation and blockers

- The planner and guard tests cover production/shared/mismatched targets, missing confirmation, real-money/payout flags, live providers, non-synthetic actors, duplicate merchant/rider identities, missing approvals/prerequisites, stable idempotency, and sensitive-value redaction.
- Via the user's interactive Windows-host VS Code WSL terminal, `gofmt -w internal/qafixtures/*.go cmd/qa-fixture-orchestrator/main.go` completed, and `go test -count=1 ./internal/qafixtures ./cmd/qa-fixture-orchestrator` passed (exit 0; planner package passed, CLI package has no separate test files). `APP_ENV=qa go run ./cmd/qa-fixture-orchestrator --dry-run --run-id phase5b-review-001` completed and emitted six blocked scenarios with `mutations_performed=false`. `--execute --confirm-isolated-qa` under QA refused execution because live container/database/network/flag/provider evidence is not queried by the CLI; the production-mode attempt refused with `execution is restricted to APP_ENV=qa or APP_ENV=test`. The `go run` guard attempts exited 1, as expected for the application's explicit refusal. Full project Go tests were not run.
- Existing accepted Phase 5B.1/5B.2 environment evidence is historical; this gate did not refresh live database, actor counts, OTP readiness, or AVD mappings.
- Missing capability: safe orchestration that provisions independent synthetic principals and drives authenticated business/order/delivery/finance workflows without embedding or printing credentials. Until designed and authorized, Stage B fixture generation and populated cross-account UI acceptance remain blocked.

**Recommendation: BLOCKED before Phase 5B.4B fixture execution.** A separate approval is needed to design/implement the authenticated workflow adapter and then separately authorize its execution. Phase 5C is not started.
