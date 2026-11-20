# Phase 5B.4B — Authorized QA Domain Workflow Adapters & Isolation Verification

**Status: PASS — Authorized workflow adapters, authoritative QA isolation verification, and mock validation test suite implemented and verified. No financial fixtures or live database mutations were executed. Phase 5B remains PARTIAL.**

## 1. Objective & Authorized Scope

Phase 5B.4B extends the Phase 5B.4A fixture orchestrator (`backend/internal/qafixtures/`, `backend/cmd/qa-fixture-orchestrator/main.go`) with:
1. Authoritative QA isolation verification that performs multi-layered fail-closed validation of runtime environment, database identity, persistent mounts, network bounds, feature flags, provider modes, and schema presence before any mutation could ever occur.
2. Authenticated domain workflow adapters around genuine application APIs and domain services across Merchant, Rider, Customer, and Admin roles.
3. A distinct synthetic identity plan for 8 isolated QA principals.
4. Full integration of the six canonical Phase 5B Merchant/Rider fixture scenarios to the adapter interfaces.
5. Mock-based test validation verifying RBAC, multi-tenant isolation, separation-of-duties, dual-code delivery handovers, COD remittance/overdraw protection, and idempotency.

**Explicit Phase Boundaries:**
- Implementation, mock-based unit tests, compilation, and non-mutating dry-run/refusal verification ONLY.
- **NO** live financial fixture generation.
- **NO** live order, delivery, settlement, or payout mutations against any database.
- **NO** direct table insertions, privileged SQL backdoors, or artificial test routes.
- **NO** commit or push to git.
- **NO** initiation of Phase 5B.4C or Phase 5C.

---

## 2. Stage 1 — Domain Workflows Audit

A comprehensive source audit across `backend/cmd/api/main.go`, `internal/platformcommerce/`, `internal/deliverydispatch/`, `internal/merchantfinance/`, `internal/riderearnings/`, `internal/payouts/`, `internal/financialaccess/`, and `internal/codcash/` confirmed the exact routes, methods, and authorization requirements for all 13 domain workflows:

| Workflow | Endpoint / Service Method | Auth / RBAC Requirements | Key Business Constraints |
|---|---|---|---|
| **1. QA Identity Provisioning & Auth** | `POST /api/v1/auth/otp/request`<br>`POST /api/v1/auth/otp/verify` | Synthetic allowlisted phone numbers; challenge-bound token validation | Expiring single-use OTPs; replay-protected; returns role-bound JWT |
| **2. Merchant Business Ownership** | `POST /api/v1/merchant/businesses`<br>`POST /api/v1/merchant/products` | Bearer Token (`requireUser`), owner auto-assigned | Zero cross-merchant leakage; items scoped strictly by `business_id` |
| **3. Rider Approval & Availability** | `PUT /api/v1/rider/availability`<br>`POST /api/v1/admin/riders/{id}/approve` | Rider JWT (`requireRider`); Admin JWT (`requireAdmin`) | Must be approved before dispatch eligibility; availability toggle |
| **4. Platform Catalog & Order Creation** | `POST /api/v1/platform/orders/quote`<br>`POST /api/v1/platform/orders` | Customer JWT (`requireUser`), valid snapshot | Server-side single-partner fulfillment; price totals verified on backend |
| **5. Merchant Acceptance & Prep** | `POST /api/v1/merchant/orders/{id}/accept`<br>`POST /api/v1/merchant/orders/{id}/prepare`<br>`POST /api/v1/merchant/orders/{id}/ready`<br>`POST /api/v1/merchant/orders/{id}/pickup-code` | Merchant JWT (`requireBusinessOwnerOrManager`) | Enforces order state machine: `placed` → `accepted` → `preparing` → `ready_for_pickup` |
| **6. Rider Dispatch, Pickup & Delivery** | `POST /api/v1/delivery-offers/{id}/accept`<br>`POST /api/v1/delivery-jobs/{id}/pickup/verify`<br>`POST /api/v1/customer/orders/{id}/delivery-code`<br>`POST /api/v1/delivery-jobs/{id}/delivery/confirm` | Rider JWT (`requireRider`) & Customer JWT (`requireUser`) | Dual-code handover verification: merchant verifies pickup code, customer provides delivery code |
| **7. COD Collection & Remittance** | Handover delivery confirmation (`is_cod=true`)<br>`POST /api/v1/rider/cash-remittances`<br>`POST /api/v1/admin/finance/cash-remittances/{id}/verify` | Rider JWT (`requireRider`) & Admin Finance JWT (`requireAdmin` + `finance.post`) | Rider cash liability tracks collected cash; remittance requires explicit Admin finance verification |
| **8. Rider Earnings Accrual** | `riderearnings.RecordCompletionTx`<br>`POST /api/v1/admin/finance/rider-earnings/accrue` | System trigger on delivery completion; Admin (`finance.post`) | Accrual blocked if rider has outstanding unremitted COD liability |
| **9. Merchant Payable Accrual** | `POST /api/v1/admin/finance/orders/{id}/accrue-payable` | Admin JWT (`requireAdmin` + `finance.post`) | Eligible completed delivered order; idempotent accrual journal |
| **10. Commission Policy Approval** | `POST /api/v1/admin/finance/commission-policies`<br>`POST /api/v1/admin/finance/commission-policies/{id}/approve` | Primary superadmin author & distinct approver (`requireAdmin`) | Separation of duties: author cannot approve own policy |
| **11. Beneficiary Registration & Verification** | `POST /api/v1/merchant/businesses/{id}/bank-beneficiary`<br>`POST /api/v1/rider/bank-beneficiary`<br>`POST /api/v1/admin/finance/beneficiaries/{id}/verify` | Merchant owner / Rider self; Admin (`finance.review`) | Stored in `bank_beneficiaries` (migration 039); verified before settlement inclusion |
| **12. Settlement Lifecycle** | `POST /api/v1/admin/finance/settlements`<br>`POST /api/v1/admin/finance/settlements/{id}/review`<br>`POST /api/v1/admin/finance/settlements/{id}/approve`<br>`POST /api/v1/admin/finance/settlements/{id}/payout-transfer`<br>`POST /api/v1/admin/finance/payout-transfers/{id}/approve`<br>`POST /api/v1/admin/finance/payout-transfers/{id}/execute` | Admin Author, Admin Reviewer, Admin Approver (`requireAdmin` + dual control) | Multi-stage approval; author cannot review/approve; transfer execution simulation only in QA |
| **13. Protected QA OTP Authentication** | `scripts/qa/auth-otp-02-reader-diagnose.sh`<br>`POST /api/v1/auth/otp/verify` with challenge token | Synthetic allowlist only; isolated reader service | Rate limits, replay protection, and expiry enforced; no universal OTPs |

---

## 3. Stage 2 — Authoritative QA Isolation Verification

Implemented in `backend/internal/qafixtures/isolation.go`. The orchestrator rejects any execution unless all conditions pass simultaneously:

```
[Target Verification]
  ├── APP_ENV in ["qa", "test"] (rejects "production", "shared", "dev", "")
  ├── Database name matches explicit allowlist: ["grepmind_3e_qa", "grepmind_qa", "grepmind_test"]
  │     └── Rejects: "grepmind_near", "grepmind_prod", "grepmind_production", "grepmind_shared", "grepmind_development", "near_live"
  ├── Database host loopback-bound (127.0.0.1 / localhost)
  ├── Host container inspected:
  │     ├── Container name contains "qa" or "test"
  │     ├── Exclusively connected to isolated network ("grepmind_qa_network", "grepmind_3e_default", "bridge")
  │     └── NO persistent volume mounts (must be tmpfs, anonymous, or ephemeral QA bind mounts)
  └── Required schema verification:
        └── Checks existence of authoritative tables: `users`, `businesses`, `customer_orders`, `platform_orders`, `delivery_jobs`, `merchant_payable_ledgers`, `rider_earning_entries`, `cod_collections`, `bank_beneficiaries`, `payout_settlement_batches`, `payout_transfers`

[Safety & Provider Flags]
  ├── `REAL_MONEY_ENABLED == false` (fails closed if true)
  ├── `PAYOUT_ENABLED == false` (fails closed if true)
  ├── `SMS_PROVIDER in ["mock", "sandbox", "fake", "none"]` (rejects "fast2sms", "twilio", "live")
  ├── `PAYMENT_PROVIDER in ["mock", "sandbox", "fake", "none"]` (rejects live gateways)
  └── `PAYOUT_PROVIDER in ["mock", "sandbox", "fake", "none"]` (rejects live bank/payout APIs)

[Service Health & Fingerprint]
  ├── QA API healthy (`GET /healthz` returns 200 with `env=qa|test`)
  ├── QA OTP Inbox healthy (`GET /healthz` returns 200)
  └── Fingerprint matching: API database connection string matches verified DB container
```

A live `SQLDatabaseInspector` queries PostgreSQL metadata (`current_database()`, `inet_server_addr()`, `information_schema.tables`), while mock implementations support unit testing.

---

## 4. Stage 3 — Authenticated Workflow Adapters

Implemented in `backend/internal/qafixtures/adapters.go`. Built around narrow, typed interfaces that model real business operations without backdoor database modifications:

1. **`AuthWorkflowAdapter`**: Requests and verifies challenge-bound OTPs for synthetic identities; receives JWT bearer tokens.
2. **`MerchantWorkflowAdapter`**:
   - `EnsureBusiness(ownerToken, name, address)`: Provisions store; enforces ownership.
   - `AddProduct(ownerToken, bizID, name, priceCents)`: Adds catalog item.
   - `AcceptOrder`, `PrepareOrder`, `MarkReadyForPickup`: Advances order state machine.
   - `IssuePickupCode`: Issues merchant verification code for rider handover.
   - `RegisterMerchantBeneficiary`: Enrolls payout bank account.
   - `GetMerchantSettlements`: Fetches read-only settlement visibility with tenant scoping.
3. **`CustomerWorkflowAdapter`**:
   - `QuoteAndPlaceOrder(customerToken, bizID, items, paymentMethod)`: Calculates snapshot quotes and places order.
   - `ConfirmPayment(customerToken, orderID)`: Confirms sandbox payment intent.
   - `GetDeliveryCode(customerToken, orderID)`: Retrieves customer delivery verification code.
4. **`RiderWorkflowAdapter`**:
   - `SetAvailability(riderToken, isAvailable)`: Controls dispatch readiness.
   - `AcceptDeliveryOffer(riderToken, jobID)`: Accepts assignment.
   - `VerifyPickup(riderToken, jobID, pickupCode)`: Verifies handover at merchant.
   - `ConfirmDelivery(riderToken, jobID, deliveryCode, codAmountCollected)`: Verifies customer handover; records COD cash liability if COD.
   - `RemitCash(riderToken, amountCents)`: Submits cash remittance request.
   - `RegisterRiderBeneficiary`: Enrolls payout bank account.
   - `GetRiderSettlements`: Fetches rider settlement status scoped to rider ID.
5. **`AdminWorkflowAdapter`**:
   - `ApproveRider(adminToken, riderID)`: Activates rider profile.
   - `AccrueMerchantPayable(adminToken, orderID)`: Posts merchant payable with `finance.post`.
   - `VerifyCashRemittance(adminToken, remittanceID)`: Clears rider cash liability.
   - `AccrueRiderEarnings(adminToken, jobID)`: Posts rider earnings to ledger (blocked if unremitted COD exists).
   - `VerifyBeneficiary(adminToken, beneficiaryID)`: Approves bank account for payouts.
   - `CreateSettlementBatch`, `ReviewSettlementBatch`, `ApproveSettlementBatch`: Enforces separation-of-duties (author cannot review or approve).
   - `CreatePayoutTransfer`, `ApprovePayoutTransfer`, `ExecutePayoutTransferSimulation`: Enforces dual approval; executes simulation only.

`HTTPDomainWorkflowAdapters` implements these interfaces against live HTTP endpoints passing standard `Authorization: Bearer <token>` and `Idempotency-Key: <key>` headers.

---

## 5. Stage 4 — Synthetic Identity Plan

Implemented in `backend/internal/qafixtures/identities.go`. Allocates 8 distinct, synthetic QA actors in the `+9199999900xx` test range:

| Actor ID | Name | Role | Expected Scoping / Binding | Phone Number |
|---|---|---|---|---|
| `merchant_a` | Merchant A QA | `merchant` | Business A (`biz-merchant-a-qa`) | `+919999990001` |
| `merchant_b` | Merchant B QA | `merchant` | Business B (`biz-merchant-b-qa`) | `+919999990002` |
| `rider_a` | Rider A QA | `rider` | Approved Rider A | `+919999990011` |
| `rider_b` | Rider B QA | `rider` | Approved Rider B | `+919999990012` |
| `customer_qa` | Customer QA | `customer` | General customer ordering | `+919999990021` |
| `admin_author` | Admin Author QA | `admin` | Maker role (`finance.post`) | `+919999990031` |
| `admin_reviewer` | Admin Reviewer QA | `admin` | Checker / Reviewer role | `+919999990032` |
| `admin_approver` | Admin Approver QA | `admin` | Checker / Approver role | `+919999990033` |

`ValidateSyntheticIdentityPlan()` enforces:
- All phone numbers are strictly in the synthetic QA block (`+9199999900xx`).
- Merchant A and Merchant B have distinct identities and distinct businesses.
- Rider A and Rider B have distinct identities.
- Admin Author, Admin Reviewer, and Admin Approver are distinct identities to prevent separation-of-duties violations.

---

## 6. Stage 5 — Scenario Integration

Implemented in `backend/internal/qafixtures/scenarios.go`. Connects all six canonical scenarios to the workflow adapters:

1. **`merchant_a_payable_and_settlement`**:
   - Actor: `merchant_a`, `customer_qa`, `rider_a`, `admin_author`, `admin_reviewer`, `admin_approver`.
   - Workflow: Order placed → Merchant accepts/preps → Rider delivers → Admin accrues payable → Admin creates/reviews/approves settlement → Simulation executed.
   - Result: Accrued payable ledger, verified beneficiary, approved settlement, simulated transfer.
2. **`merchant_b_payable_and_settlement`**:
   - Actor: `merchant_b` (Business B). Identical workflow to prove multi-tenant isolation.
3. **`rider_a_earning_and_settlement`**:
   - Actor: `rider_a`. Delivery completed with digital payment → zero COD liability → earnings accrued → settlement approved and simulated.
4. **`rider_b_earning_and_settlement`**:
   - Actor: `rider_b`. Independent delivery and settlement flow.
5. **`rider_a_nonzero_cod_liability`**:
   - Actor: `rider_a`. COD order completed → cash liability tracked → remittance submitted but NOT verified by Finance → earnings settlement accrual blocked due to outstanding liability.
6. **`rider_b_independent_cod_liability`**:
   - Actor: `rider_b`. COD order completed → cash liability tracked → remittance submitted AND verified by Admin Finance → liability cleared → earnings accrual unblocked.

---

## 7. Stage 6 — Mock-Based Validation

A comprehensive test suite in `backend/internal/qafixtures/` validates isolation and workflow integrity without touching external systems:

### Test Suite Execution Output
```
=== RUN   TestMockDomainWorkflowAdapters_AuthAndFailure
--- PASS: TestMockDomainWorkflowAdapters_AuthAndFailure (0.00s)
=== RUN   TestMockDomainWorkflowAdapters_CrossMerchantIsolation
--- PASS: TestMockDomainWorkflowAdapters_CrossMerchantIsolation (0.00s)
=== RUN   TestMockDomainWorkflowAdapters_SeparationOfDuties
--- PASS: TestMockDomainWorkflowAdapters_SeparationOfDuties (0.00s)
=== RUN   TestMockDomainWorkflowAdapters_DualCodeHandover
--- PASS: TestMockDomainWorkflowAdapters_DualCodeHandover (0.00s)
=== RUN   TestMockDomainWorkflowAdapters_CODRemittanceAndOverdraw
--- PASS: TestMockDomainWorkflowAdapters_CODRemittanceAndOverdraw (0.00s)
=== RUN   TestMockDomainWorkflowAdapters_Idempotency
--- PASS: TestMockDomainWorkflowAdapters_Idempotency (0.00s)
=== RUN   TestValidateSyntheticIdentityPlan
--- PASS: TestValidateSyntheticIdentityPlan (0.00s)
=== RUN   TestScenarioRunner_DryRunIsNonMutating
--- PASS: TestScenarioRunner_DryRunIsNonMutating (0.00s)
=== RUN   TestVerifyAuthoritativeIsolation_Valid
--- PASS: TestVerifyAuthoritativeIsolation_Valid (0.00s)
=== RUN   TestVerifyAuthoritativeIsolation_RejectsProductionAndSharedDB
--- PASS: TestVerifyAuthoritativeIsolation_RejectsProductionAndSharedDB (0.00s)
=== RUN   TestVerifyAuthoritativeIsolation_RejectsPersistentMounts
--- PASS: TestVerifyAuthoritativeIsolation_RejectsPersistentMounts (0.00s)
=== RUN   TestVerifyAuthoritativeIsolation_RejectsMissingSchema
--- PASS: TestVerifyAuthoritativeIsolation_RejectsMissingSchema (0.00s)
=== RUN   TestVerifyAuthoritativeIsolation_RejectsLiveMoneyAndPayoutFlags
--- PASS: TestVerifyAuthoritativeIsolation_RejectsLiveMoneyAndPayoutFlags (0.00s)
=== RUN   TestVerifyAuthoritativeIsolation_RejectsLiveProviders
--- PASS: TestVerifyAuthoritativeIsolation_RejectsLiveProviders (0.00s)
=== RUN   TestVerifyAuthoritativeIsolation_RejectsUnhealthyOrNonQAServices
--- PASS: TestVerifyAuthoritativeIsolation_RejectsUnhealthyOrNonQAServices (0.00s)
=== RUN   TestVerifyAuthoritativeIsolation_InspectorErrorsFailClosed
--- PASS: TestVerifyAuthoritativeIsolation_InspectorErrorsFailClosed (0.00s)
=== RUN   TestBuildPlanIsDeterministicAndNonMutating
--- PASS: TestBuildPlanIsDeterministicAndNonMutating (0.00s)
=== RUN   TestValidateExecutionRequiresExplicitQAIsolation
--- PASS: TestValidateExecutionRequiresExplicitQAIsolation (0.00s)
=== RUN   TestExecutionEnvironmentGuardFailsClosedWithoutLiveEvidence
--- PASS: TestExecutionEnvironmentGuardFailsClosedWithoutLiveEvidence (0.00s)
=== RUN   TestValidateExecutionRejectsUnsafeTargetsAndFlags
--- PASS: TestValidateExecutionRejectsUnsafeTargetsAndFlags (0.00s)
=== RUN   TestActorSetRequiresDistinctTenantBoundApprovedSyntheticActors
--- PASS: TestActorSetRequiresDistinctTenantBoundApprovedSyntheticActors (0.00s)
=== RUN   TestMissingWorkflowPrerequisiteBlocksScenario
--- PASS: TestMissingWorkflowPrerequisiteBlocksScenario (0.00s)
=== RUN   TestSensitiveAssignmentsRedacted
--- PASS: TestSensitiveAssignmentsRedacted (0.00s)
PASS
ok  	grepmind-near/backend/internal/qafixtures	0.013s
```

### Coverage Highlights
- **Cross-Merchant Tenant Isolation**: Verified that `merchant_b` cannot manage products, accept orders, or view settlements for `business_a`.
- **Separation-of-Duties**: Verified that `admin_author` cannot review or approve their own settlement batches.
- **Dual-Code Handover**: Verified order cannot be picked up with wrong pickup code or confirmed delivered with wrong delivery code.
- **COD Liability & Overdraw**: Verified remittance cannot exceed outstanding cash liability, and earnings accrual fails closed if liability is nonzero.
- **Idempotency**: Repeated calls with matching `Idempotency-Key` return identical results without duplicate ledger entries.
- **Fail-Closed Safety**: Any production/shared database name, persistent volume, live provider, or missing schema immediately aborts isolation verification.

---

## 8. CLI & Non-Mutating Verification

The CLI (`backend/cmd/qa-fixture-orchestrator/main.go`) was verified under WSL:

1. **Compilation Check**:
   `go build -o /dev/null ./cmd/qa-fixture-orchestrator` → Exited 0 with no warnings.
2. **Deterministic Dry-Run**:
   `go run ./cmd/qa-fixture-orchestrator --dry-run` → Emits deterministic 6-scenario plan with `mutations_performed=false`.
3. **Isolation Verification Refusal**:
   `go run ./cmd/qa-fixture-orchestrator --verify-isolation` → Fails closed with exit code 2: `isolation violation: execution restricted to APP_ENV=qa or APP_ENV=test (got "")`.
4. **Execution Refusal Guard**:
   `APP_ENV=qa go run ./cmd/qa-fixture-orchestrator --execute --confirm-isolated-qa` → Fails closed with exit code 2: `execution is disabled until the CLI can verify the live database container, database identity, network isolation, feature flags, and provider mode`.

---

## 9. Gate Boundary & Next Steps

Phase 5B.4B is **COMPLETE and PASS** for its authorized scope:
- **What was completed**: Workflow adapters, authoritative isolation checks, synthetic identity plan, scenario integration, mock validation suite, and CLI compilation/dry-run verification.
- **What was NOT done**: No live databases were modified; no financial fixtures were created; no live orders or payments were processed; no live settlement records were inserted; no migrations were applied; no commits or pushes were made.
- **Phase 5B Status**: Remains **PARTIAL**.
- **Recommended Next Phase**: **Phase 5B.4C — Controlled QA Execution**, which must be explicitly authorized to run against verified isolated QA services (`grepmind_3e_qa_db` and `grepmind_4c_qa_api`) before final Android UI validation in Phase 5B.5.
