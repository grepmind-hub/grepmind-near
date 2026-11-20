package qafixtures

import (
	"context"
	"errors"
	"fmt"
)

// ScenarioDefinition provides comprehensive metadata and step sequences for a fixture scenario.
type ScenarioDefinition struct {
	Name                    string   `json:"name"`
	Description             string   `json:"description"`
	PrimaryActorKey         string   `json:"primary_actor_key"`
	ParticipatingActorKeys  []string `json:"participating_actor_keys"`
	Prerequisites           []string `json:"prerequisites"`
	WorkflowSteps           []string `json:"workflow_steps"`
	ExpectedRecordsCreated  []string `json:"expected_records_created"`
	ExpectedEvidenceOutputs []string `json:"expected_evidence_outputs"`
	SafeFailureBehavior     string   `json:"safe_failure_behavior"`
}

// DetailedScenarioRegistry maps the six canonical Phase 5B scenarios to their authoritative specifications.
var DetailedScenarioRegistry = []ScenarioDefinition{
	{
		Name:                   "merchant_a_payable_and_settlement",
		Description:            "End-to-end UPI commerce order, delivery completion, Admin finance.post payable accrual, and multi-person settlement approval for Merchant A",
		PrimaryActorKey:        "merchant_a",
		ParticipatingActorKeys: []string{"customer_qa", "rider_a", "admin_author", "admin_reviewer", "admin_approver"},
		Prerequisites: []string{
			"synthetic merchant A with distinct business",
			"eligible order completed through normal payment and delivery workflows",
			"Admin finance.post payable accrual",
			"verified beneficiary and independent settlement review/approval",
		},
		WorkflowSteps: []string{
			"Customer QA places food order with UPI payment",
			"Sandbox payment capture outcome simulates 'succeeded'",
			"Merchant A accepts, prepares, and marks order ready",
			"Rider A accepts dispatch offer, verifies pickup code, and confirms delivery with customer code",
			"Admin Author requests finance.post grant; Admin Reviewer decides and grants approval",
			"Admin Author executes finance.post payable accrual for the completed order",
			"Admin Author creates merchant settlement batch",
			"Admin Reviewer performs independent settlement review",
			"Admin Approver executes independent settlement approval under separation of duties",
			"Admin Author creates, approves, and executes simulated sandbox payout transfer",
		},
		ExpectedRecordsCreated: []string{
			"customer_orders (status=delivered, payment_status=paid)",
			"delivery_jobs (execution_state=delivered)",
			"financial_journals (purpose=merchant_payable_accrual, debit=credit)",
			"merchant_settlement_batches (status=reconciled/approved)",
			"payout_transfers (status=executed/reconciled)",
		},
		ExpectedEvidenceOutputs: []string{
			"Merchant Android Earnings & Payouts shows verified payable transitioning to approved settlement",
			"Merchant Web Portal displays matching simulated settlement history",
			"Double-entry balance check returns sum(debit) == sum(credit)",
		},
		SafeFailureBehavior: "Fails closed before payable accrual if order delivery handshake is incomplete. Rejects self-approval by Admin Author.",
	},
	{
		Name:                   "merchant_b_payable_and_settlement",
		Description:            "Independent UPI order, delivery completion, payable accrual, and settlement for Merchant B, proving cross-merchant tenant isolation",
		PrimaryActorKey:        "merchant_b",
		ParticipatingActorKeys: []string{"customer_qa", "rider_b", "admin_author", "admin_reviewer", "admin_approver"},
		Prerequisites: []string{
			"synthetic merchant B with distinct business",
			"eligible order completed through normal payment and delivery workflows",
			"Admin finance.post payable accrual",
			"verified beneficiary and independent settlement review/approval",
		},
		WorkflowSteps: []string{
			"Customer QA places grocery order from Merchant B with UPI payment",
			"Sandbox payment capture outcome simulates 'succeeded'",
			"Merchant B accepts, prepares, and marks order ready",
			"Rider B accepts dispatch offer, verifies pickup code, and confirms delivery with customer code",
			"Admin Author executes finance.post payable accrual specifically for Merchant B's order",
			"Admin Author creates merchant settlement batch for Merchant B business ID",
			"Admin Reviewer reviews Merchant B settlement batch",
			"Admin Approver approves Merchant B settlement batch",
		},
		ExpectedRecordsCreated: []string{
			"customer_orders (business_id=merchant_b, status=delivered)",
			"merchant_settlement_batches (business_id=merchant_b, status=approved)",
			"financial_journals (scoped strictly to Merchant B account)",
		},
		ExpectedEvidenceOutputs: []string{
			"Merchant B Android displays only Merchant B's earnings/settlements",
			"Merchant A token cannot query Merchant B's settlement endpoint (HTTP 403)",
			"Cross-tenant data leakage is 0%",
		},
		SafeFailureBehavior: "Immediate HTTP 403 Forbidden if Merchant A attempts to access Merchant B business ID.",
	},
	{
		Name:                   "rider_a_earning_and_settlement",
		Description:            "Rider delivery completion generates verified earnings entry and settlement batch without direct table inserts",
		PrimaryActorKey:        "rider_a",
		ParticipatingActorKeys: []string{"merchant_a", "customer_qa", "admin_author", "admin_approver"},
		Prerequisites: []string{
			"approved synthetic rider A",
			"OTP-verified delivery with approved earnings policy",
			"Admin-controlled rider settlement workflow",
			"no outstanding COD liability",
		},
		WorkflowSteps: []string{
			"Rider A goes online and accepts eligible delivery job",
			"Rider A completes delivery handover via dual verification code",
			"Delivery completion triggers riderearnings.RecordCompletionTx under approved locality policy",
			"Admin Author verifies zero unremitted COD liability for Rider A",
			"Admin Author creates rider settlement batch for Rider A",
			"Admin Approver independently approves Rider A settlement batch",
		},
		ExpectedRecordsCreated: []string{
			"rider_earnings_entries (rider_user_id=rider_a, status=recorded)",
			"rider_settlement_batches (rider_user_id=rider_a, status=approved)",
		},
		ExpectedEvidenceOutputs: []string{
			"Rider A Android Earnings screen displays recorded compensation and approved settlement",
			"Rider B token receives empty list or HTTP 403 when requesting Rider A settlements",
		},
		SafeFailureBehavior: "Settlement batch creation is blocked if unremitted COD liability exists for the rider.",
	},
	{
		Name:                   "rider_b_earning_and_settlement",
		Description:            "Independent delivery earnings and settlement for Rider B, confirming rider-to-rider data isolation",
		PrimaryActorKey:        "rider_b",
		ParticipatingActorKeys: []string{"merchant_b", "customer_qa", "admin_author", "admin_approver"},
		Prerequisites: []string{
			"approved synthetic rider B distinct from rider A",
			"OTP-verified delivery with approved earnings policy",
			"Admin-controlled rider settlement workflow",
			"no outstanding COD liability",
		},
		WorkflowSteps: []string{
			"Rider B completes separate delivery job",
			"RecordCompletionTx generates earning entry for Rider B",
			"Admin Author creates rider settlement batch for Rider B",
			"Admin Approver independently approves Rider B settlement batch",
		},
		ExpectedRecordsCreated: []string{
			"rider_earnings_entries (rider_user_id=rider_b)",
			"rider_settlement_batches (rider_user_id=rider_b, status=approved)",
		},
		ExpectedEvidenceOutputs: []string{
			"Rider B Android displays only Rider B earnings",
			"Zero cross-rider contamination",
		},
		SafeFailureBehavior: "Fails closed if Rider B has unapproved profile status or unremitted cash liability.",
	},
	{
		Name:                   "rider_a_nonzero_cod_liability",
		Description:            "COD grocery order delivery creates verified cash collection and records unremitted liability",
		PrimaryActorKey:        "rider_a",
		ParticipatingActorKeys: []string{"merchant_a", "customer_qa"},
		Prerequisites: []string{
			"synthetic COD enabled in isolated QA",
			"assigned rider completes authorized customer handover",
			"backend records COD collection through delivery workflow",
		},
		WorkflowSteps: []string{
			"Customer QA orders grocery items with cash_on_delivery",
			"Merchant A packs and hands over to Rider A",
			"Customer QA generates delivery code",
			"Rider A inputs delivery code with confirm_cod_collection=true",
			"codcash.RecordCollectionTx records collection in cod_collections and updates cod_obligations",
		},
		ExpectedRecordsCreated: []string{
			"cod_collections (rider_user_id=rider_a, amount_minor > 0)",
			"cod_obligations (rider_cash_receivable balance debited)",
		},
		ExpectedEvidenceOutputs: []string{
			"Rider A Android Cash Accountability screen shows nonzero pending liability",
			"Rider A cannot be settled until liability is remitted and verified",
		},
		SafeFailureBehavior: "Fails closed if handover code is missing, incorrect, or delivery was not pre-assigned.",
	},
	{
		Name:                   "rider_b_independent_cod_liability",
		Description:            "Rider B completes separate COD delivery followed by verified cash remittance, demonstrating ledger discharge",
		PrimaryActorKey:        "rider_b",
		ParticipatingActorKeys: []string{"merchant_b", "customer_qa", "admin_author"},
		Prerequisites: []string{
			"approved synthetic rider B distinct from rider A",
			"independent COD order and collection or verified zero balance",
			"backend-derived liability reconciliation",
		},
		WorkflowSteps: []string{
			"Rider B collects COD cash on separate delivery",
			"Rider B submits remittance via /api/v1/rider/cash-remittances",
			"Admin Author reviews and verifies safe deposit via /api/v1/admin/cod/remittances/{id}/review",
			"Rider B pending liability reconciles to zero",
		},
		ExpectedRecordsCreated: []string{
			"rider_cash_remittances (status=verified)",
			"cod_collections (reconciled)",
		},
		ExpectedEvidenceOutputs: []string{
			"Rider B Android Cash Accountability shows ₹0.00 unremitted liability",
			"Rider A cash liability remains unaffected",
		},
		SafeFailureBehavior: "Remittance rejection if submitted amount exceeds recorded unremitted liability.",
	},
}

// ScenarioRunner binds the scenario metadata to adapter execution.
type ScenarioRunner struct {
	Adapters *DomainWorkflowAdapters
	RunID    string
}

// DryRunPlan returns the complete execution roadmap for all 6 scenarios without mutating state.
func (r *ScenarioRunner) DryRunPlan() ([]Scenario, error) {
	if r.RunID == "" {
		return nil, errors.New("run ID is required")
	}

	scenarios := make([]Scenario, len(DetailedScenarioRegistry))
	for i, def := range DetailedScenarioRegistry {
		key := IdempotencyKey(r.RunID, def.Name)
		scenarios[i] = Scenario{
			Name:          def.Name,
			Idempotency:   key,
			Prerequisites: def.Prerequisites,
			Status:        "ready_for_adapter_execution",
			Blockers:      nil,
		}
	}
	return scenarios, nil
}

// ExecuteScenario validates preconditions and routes to the appropriate adapter workflow.
// In Phase 5B.4B, live execution is deliberately gated behind isolation verification and adapters.
func (r *ScenarioRunner) ExecuteScenario(ctx context.Context, scenarioName string, dryRun bool) error {
	if dryRun {
		return nil // Non-mutating dry run
	}

	if r.Adapters == nil {
		return errors.New("cannot execute scenario: domain workflow adapters not configured")
	}

	// Verify the scenario is recognized
	var target *ScenarioDefinition
	for _, def := range DetailedScenarioRegistry {
		if def.Name == scenarioName {
			target = &def
			break
		}
	}
	if target == nil {
		return fmt.Errorf("unknown scenario %q", scenarioName)
	}

	return fmt.Errorf("scenario %q execution requires explicit Phase 5B.4C authorization gate", scenarioName)
}
