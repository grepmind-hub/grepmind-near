# Phase 4B-C — Flutter Sandbox Checkout & Refunds

**Date:** 11 November 2026

**Status:** PASS — isolated QA acceptance completed 11 November 2026. Authenticated same-order sandbox payment, process-restart recovery, finance-reviewed refund, Pixel 8 UI, API and PostgreSQL evidence were reconciled. No live money movement was enabled.

## Executive summary

Phase 4B-C connects customer order tracking to the existing server-authoritative payment intent and fake sandbox provider, and adds finance-reviewed synthetic refunds. It does not initiate real UPI, move real funds, collect COD, create merchant settlements, or pay riders. The payment projection remains `paid` after a refund; refund state and accounting are separate records.

A new additive migration 033 defines refund requests and immutable refund audit history, links refund webhook evidence, and allows only fail-closed synthetic refund journals. Existing migrations 001–032 were not edited. Migration 033 was applied only to disposable isolated QA databases; it remains unapplied to shared development and production.

The Windows-host WSL entry point succeeded through the authorized host execution path. The disposable migration runner and full Go suite passed, the full Flutter test suite passed, the debug APK built and launched on Pixel 8 `emulator-5554`, and the full analyzer returned the existing 18-diagnostic baseline. The final isolated QA run exercised an authenticated customer's same-order payment → app restart → finance-approved sandbox refund flow on device and reconciled it with finance API and PostgreSQL records. Therefore Phase 4B-C is **PASS for isolated QA**.

## Baseline and worktree

- Branch: `development-02` (per the active project checkout).
- The worktree was already substantially modified/untracked before this phase, including the prior Phase 4A/4B implementation, QA scripts, docs, portal test artifacts, and unrelated mobile/emulator files. Those files were preserved. No commit or push was created.
- Relevant Phase 4 baseline: migrations 030–032, financial ledger package, payment intents, deterministic in-memory sandbox provider, existing order tracking and checkout workflows.

## Implementation changes

### Backend and database

- Added `backend/migrations/033_sandbox_refunds.sql` for finance-reviewed refund requests, idempotency, capture linkage, provider event linkage, immutable audit evidence, valid state transitions, and synthetic refund journal guardrails.
- Extended the existing provider interface with create/fetch refund methods; the in-memory fake accepts a refund only against an existing succeeded synthetic capture and returns the same synthetic reference on idempotent retry.
- Added owned payment/refund summary, refund request/history, finance review/list/reconciliation endpoints, and signed sandbox refund event processing. Customer refund requests reserve against verified capture balance; concurrent customer submissions are serialized before the balance check. Failed refunds remain reserved until provider reconciliation resolves a possible delayed success.
- Refund approval requires `finance.post` and a different principal from the requester. Reconciliation also requires `finance.post`. Provider ambiguity retains an approved request so Finance can retry the same idempotent fake-provider operation instead of stranding a record without a provider reference.
- A verified sandbox refund posts one balanced journal: debit customer-receipt liability, credit sandbox provider-clearing asset. The capture journal and order `payment_status=paid` remain unchanged. No rider earning, delivery, or merchant payable is touched.
- QA outcome routes are registered only under `APP_ENV=qa|test`, and require the authenticated user ID to be in `PAYMENT_SANDBOX_QA_USER_IDS`. They are absent in other environment route tables.
- Corrected explicit PostgreSQL parameter typing in refund audit metadata and finance authorization error mapping. Replaced transaction-stable `now()` with `clock_timestamp()` for payment-attempt transitions so concurrent webhook updates satisfy the monotonic timestamp guard.
- Updated OpenAPI contracts and added `scripts/qa/phase4b_c_checkout_refunds.sh`, which provisions only a uniquely named disposable tmpfs PostGIS container, binds its random host port to loopback, caps migration application at 033, runs Go tests and removes only that container. Previous Phase 4 QA runners are capped at their original migration versions.

### Flutter

- Added an account-scoped Riverpod/Dio payment workflow provider keyed by order and user, stable idempotency keys for ambiguous requests, bounded reconciliation polling, server-derived amount/eligibility, and refund request/reconciliation actions.
- Added a premium Material 3 payment card to the existing order tracking view. It discloses sandbox-only behavior, displays backend status and amount, shows retry/reconciliation states, requires a second confirmation before requesting a finance refund review, and labels refund status without promising a bank credit.
- QA payment/refund outcome controls are debug-build-only in Flutter and still require backend QA identity allowlisting. They call backend simulation routes; clients cannot directly set financial state.
- Added widget/notifier tests for sandbox disclosure, duplicate submission protection, ambiguous session retry idempotency, and refund confirmation/server-specified amount.

## API and authorization

OpenAPI includes customer-owned payment summary and refund request/history, finance-authorized review/list/reconciliation, and QA-only payment/refund simulation routes. Customer resources are scoped by `customer_user_id`; finance operations use explicit `finance.post` / `finance.read` grants and separation of duties. The webhook uses the existing sandbox provider signature verifier over the exact request body; no raw body, secrets, or OTPs are persisted.

## Financial state and journal behavior

- Payment state remains authoritative from verified provider evidence; session creation, UI taps, app timers and local state do not mark an order paid.
- Refund states: `requested → approved → processing → succeeded | failed`, with rejection and reconciliation states where needed. A delayed verified success can resolve a failed/reconciliation state without altering capture history.
- Pending, approved, processing, failed and succeeded refund amounts reserve captured balance. A failed refund remains reserved until reconciliation prevents a late-success callback from exceeding the original capture.
- Refund confirmation is separate from actual gateway settlement or bank credit. No `refunded` legacy payment status is introduced.

## Validation actually executed

| Check | Result |
|---|---|
| OpenAPI YAML parse with Python PyYAML | PASS — parsed 179 paths |
| `bash scripts/qa/phase4b_c_checkout_refunds.sh` | PASS — migrations 001–033 applied in a uniquely named disposable tmpfs PostGIS container; full `go test -count=1 ./...` passed; runner removed its container |
| `gofmt` on changed Go files | PASS |
| `flutter test --no-pub --reporter compact` | PASS — 99 tests |
| Focused payment/order Flutter tests | PASS — 5 tests |
| `dart analyze lib/core/providers/payment_workflow_provider.dart lib/core/screens/order_payment_card.dart test/payment_workflow_test.dart` | PASS — no issues in changed Dart files |
| `flutter analyze --no-pub` | Completed, exit 1 — 18 existing diagnostics (3 warnings, 15 infos), matching the recorded baseline |
| `flutter build apk --debug --no-pub` | PASS — `assembleDebug` completed |
| `./scripts/mobile_emulator.ps1 -Action BuildRun -DeviceId emulator-5554 -ApiBaseUrl http://10.0.2.2:80 -AdbServerPort 5037` | PASS — Pixel 8 `emulator-5554`, install succeeded and main activity launched; login screen visually verified |
| Windows ADB device check | PASS in authorized host context — `emulator-5554` and `emulator-5558` listed; restricted process could not start ADB |
| Screenshot | Captured at `docs/phases/evidence/phase4bc-pixel8-launch.png`; shows login screen, not authenticated payment/refund UI |
| Scoped `git diff --check` and whitespace scan | PASS (Git emitted line-ending normalization warnings only) |
| Same-order authenticated sandbox payment/refund on emulator | PASS — QA customer placed and paid order `GN-58CEDC89` (order `58cedc89-cbb3-4b4c-a26a-6cdfa9dc535f`, ₹125.00), requested refund `71bd55ee-c017-41de-aff9-e1e7279f32a1`, and saw the verified refund after app force-stop/relaunch; see evidence below |
| Finance API review | PASS — authorized finance identity listed the pending refund and approved it; review returned HTTP 200 and caused the sandbox provider refund workflow to enter processing |
| Customer refund completion | PASS — customer used the QA-only success control; the same order showed `Verified paid` and refund history `Verified sandbox refund` after process restart |
| Exact order/payment references | PASS — payment intent `4353a301-3fc6-49fc-99cf-c48872f3a968`; attempt `e61cf453-8756-44bf-b92c-f7ce70ca6170`; provider reference `qa_a31b305c9b975c762093048e` |
| Financial journals | PASS — capture journal `e7b476b9-24a1-441d-8099-9fd031ef87d0` and refund journal `f441488c-cd7b-48c4-b90c-528546eae34c`, each posted in INR with debit total equal to credit total at 12,500 paise |
| QA cleanup | PASS — removed only `grepmind_4bc_e2e_api`, `grepmind_4bc_e2e_otp_proxy`, `grepmind_4bc_e2e_db`, `grepmind_4bc_e2e_net` and the QA-only `/tmp/phase4bc_e2e_nginx.conf`; verified no named QA container/network remained. The disposable DB used tmpfs/no volume; shared containers remained running. |

WSL was reachable from the Windows host through the authorized execution path. A normal restricted invocation still returned `Wsl/Service/E_ACCESSDENIED`. Windows ADB startup similarly failed in the restricted path on ports 5037 and 5039; starting ADB through the authorized host path succeeded. No WSL or Android SDK configuration was changed.

Installed APK SHA-256: `42d44ba3d58a58022491aa43ed37efd0a42144e4b8001a75065828e2b6a02255`. Installed package: `local.grepmind.grepmind_mobile`, version `1.0.0` (`versionCode=1`).

## Security and safety status

- No real gateway adapter or live credentials were added.
- UPI, COD, merchant settlement and real-money switches remain constrained off.
- No shared or production database was migrated or modified.
- No real payment, refund, payout, dispatch, rider earnings, or delivery state was changed.
- The fake provider remains in-memory. Restart recovery must reconcile to its available state and must not fabricate success.

## Limitations and remaining risks

1. Full Flutter analysis exits 1 due the same 18 baseline diagnostics (3 warnings, 15 infos); changed Phase 4B-C Dart files pass focused analysis.
2. Admin finance UI is not implemented. The authorized finance API review and refund audit records were validated instead, as allowed by the acceptance scope. A dedicated finance dashboard remains separate future work.
3. The order details view reported temporary order-history unavailability during the payment/refund run. Payment/refund state and restart recovery still reconciled correctly; this remains a separate order-history service follow-up.
4. Failed refunds intentionally reserve the remaining capture amount until reconciliation; operational handling for irrecoverable provider failures needs later review.
5. The fake provider is in-memory and not suitable for durable production use; this acceptance verified app-process restart while the isolated API/provider remained available.
6. Legal seller-of-record, provider marketplace settlement, tax treatment, actual refund policy and live funds flow remain unresolved and must be reviewed before real transactions.

## Final isolated QA acceptance evidence

- The same Pixel 8 customer created and paid QA order `GN-58CEDC89` for ₹125.00, requested the full sandbox refund, and after app force-stop/relaunch reopened that same order from My Orders. The UI restored `Verified paid` and showed `Refund history — ₹125.00 · Verified sandbox refund`.
- Screenshots: `docs/phases/evidence/phase4bc-ordercreated.png`, `phase4bc-paymentcard.png`, `phase4bc-paid.png`, `phase4bc-refundsubmitted.png`, `phase4bc-refreshedstate.png`, `phase4bc-refundcomplete.png`, `phase4bc-processrestart3.png`, `phase4bc-afterrestart-orders2.png`, `phase4bc-afterrestart-payment-refund.png`, `phase4bc-afterrestart-refund-status.png`, and `phase4bc-qa-session-cleared.png` (returned to the login screen after logout).
- PostgreSQL had the same order at `payment_status=paid`, succeeded payment intent/attempt and succeeded refund for 12,500 INR minor units. The capture and refund journals were each posted and balanced. Refund audit recorded customer request, finance approval, provider start, and provider success. The original capture journal remained intact.
- No COD collection, rider earning, merchant settlement/payout, delivery custody transition, or real-money movement was part of this workflow. The payment projection remains `paid`; the separate refund record reports successful synthetic refund, preserving original capture history.
- The order details view also displayed “Order history is temporarily unavailable” for its delivery timeline while the payment/refund card loaded and reconciled. This is a separate order-history service limitation and did not block the payment/refund acceptance.
- Finance UI is absent; finance API authorization/review and audit records were tested. Migration 033 and the QA fixtures were used only in the disposable isolated database; shared development and production remain unchanged.

## Recommendation

**Phase 4B-C: PASS for isolated QA.** The authenticated same-order customer UI flow, restart recovery, finance review API, payment/refund records and balanced journals were verified across Pixel 8, API and PostgreSQL. Real UPI, COD, real refunds, settlements/payouts remain disabled. Do not start Phase 4C without separate explicit approval.
