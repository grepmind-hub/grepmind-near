package qafixtures

import (
	"context"
	"strings"
	"testing"
)

func TestMockDomainWorkflowAdapters_AuthAndFailure(t *testing.T) {
	ctx := context.Background()
	mock := NewMockDomainWorkflowAdapters()

	// Successful Auth
	challengeID, err := mock.RequestOTP(ctx, "+919990000181")
	if err != nil {
		t.Fatalf("request OTP failed: %v", err)
	}
	otp, err := mock.ResolveQAOTP(ctx, challengeID)
	if err != nil {
		t.Fatalf("resolve OTP failed: %v", err)
	}
	token, err := mock.VerifyOTP(ctx, "+919990000181", otp, challengeID)
	if err != nil {
		t.Fatalf("verify OTP failed: %v", err)
	}
	if !strings.HasPrefix(token, "token-for-") {
		t.Fatalf("unexpected token format: %s", token)
	}

	// Auth Failure - Invalid OTP
	if _, err := mock.VerifyOTP(ctx, "+919990000181", "999999", challengeID); err == nil {
		t.Fatal("expected failure on invalid OTP")
	}

	// Auth Failure - Provider Down
	mock.FailAuth = true
	if _, err := mock.RequestOTP(ctx, "+919990000181"); err == nil {
		t.Fatal("expected failure when auth provider fails")
	}
}

func TestMockDomainWorkflowAdapters_CrossMerchantIsolation(t *testing.T) {
	ctx := context.Background()
	mock := NewMockDomainWorkflowAdapters()

	tokenA := "token-merchant-a"
	tokenB := "token-merchant-b"

	bizA, err := mock.EnsureBusiness(ctx, tokenA, "Bakery A", "food", "loc-1")
	if err != nil {
		t.Fatalf("ensure bizA: %v", err)
	}
	bizB, err := mock.EnsureBusiness(ctx, tokenB, "Grocer B", "grocery", "loc-1")
	if err != nil {
		t.Fatalf("ensure bizB: %v", err)
	}

	// Merchant A adds product to Business A -> OK
	if _, err := mock.AddProduct(ctx, tokenA, bizA, "Chai Blend", 250); err != nil {
		t.Fatalf("merchant A add product: %v", err)
	}

	// Merchant A attempts to add product to Business B -> FORBIDDEN
	if _, err := mock.AddProduct(ctx, tokenA, bizB, "Unauthorized Item", 100); err == nil {
		t.Fatal("expected cross-merchant product addition to fail with FORBIDDEN")
	}

	// Merchant A creates settlement for Business A -> OK
	batchA, err := mock.CreateMerchantSettlement(ctx, "token-admin", bizA, "2026-11-01", "2026-11-15", "idem-1")
	if err != nil {
		t.Fatalf("create settlement A: %v", err)
	}
	if batchA == "" {
		t.Fatal("empty batch ID")
	}

	// Merchant A views Business A settlements -> OK
	settlementsA, err := mock.GetMerchantSettlements(ctx, tokenA, bizA)
	if err != nil || len(settlementsA) == 0 {
		t.Fatalf("merchant A view settlements: %v", err)
	}

	// Merchant B attempts to view Business A settlements -> FORBIDDEN
	if _, err := mock.GetMerchantSettlements(ctx, tokenB, bizA); err == nil {
		t.Fatal("expected cross-merchant settlement read to fail with FORBIDDEN")
	}
}

func TestMockDomainWorkflowAdapters_SeparationOfDuties(t *testing.T) {
	ctx := context.Background()
	mock := NewMockDomainWorkflowAdapters()

	adminCreator := "token-admin-author"
	adminApprover := "token-admin-approver"

	// 1. Finance.post grant self-approval violation
	reqID, err := mock.RequestFinancePostAccess(ctx, adminCreator, "user-author", "Need post permission")
	if err != nil {
		t.Fatalf("request finance post: %v", err)
	}

	// Creator attempts self-approval -> BLOCKED
	if err := mock.DecideFinancePostAccess(ctx, adminCreator, reqID, "approved", "Self grant"); err == nil {
		t.Fatal("expected self-approval of finance.post to be blocked")
	}

	// Independent admin approves -> OK
	if err := mock.DecideFinancePostAccess(ctx, adminApprover, reqID, "approved", "Valid grant"); err != nil {
		t.Fatalf("independent approval failed: %v", err)
	}

	// 2. Settlement self-approval violation
	batchID, err := mock.CreateMerchantSettlement(ctx, adminCreator, "biz-101", "2026-11-01", "2026-11-15", "idem-s1")
	if err != nil {
		t.Fatalf("create settlement: %v", err)
	}

	// Creator attempts to approve own settlement batch -> BLOCKED
	if err := mock.ApproveMerchantSettlement(ctx, adminCreator, batchID); err == nil {
		t.Fatal("expected creator approval of settlement to be blocked under separation of duties")
	}

	// Independent admin approves settlement batch -> OK
	if err := mock.ApproveMerchantSettlement(ctx, adminApprover, batchID); err != nil {
		t.Fatalf("independent settlement approval failed: %v", err)
	}
}

func TestMockDomainWorkflowAdapters_DualCodeHandover(t *testing.T) {
	ctx := context.Background()
	mock := NewMockDomainWorkflowAdapters()

	tokenMerchant := "token-merchant"
	tokenRider := "token-rider"
	jobID := "job-101"

	bizID, err := mock.EnsureBusiness(ctx, tokenMerchant, "Test Store", "food", "loc-1")
	if err != nil {
		t.Fatalf("ensure business: %v", err)
	}

	// Merchant issues 8-digit pickup code
	pickupCode, err := mock.IssuePickupCode(ctx, tokenMerchant, bizID, jobID)
	if err != nil {
		t.Fatalf("issue pickup code: %v", err)
	}

	// Rider enters wrong code -> FAILS
	if err := mock.VerifyPickup(ctx, tokenRider, jobID, "00000000"); err == nil {
		t.Fatal("expected pickup verification to fail on code mismatch")
	}

	// Rider enters correct code -> SUCCEEDS
	if err := mock.VerifyPickup(ctx, tokenRider, jobID, pickupCode); err != nil {
		t.Fatalf("pickup verification failed: %v", err)
	}
}

func TestMockDomainWorkflowAdapters_CODRemittanceAndOverdraw(t *testing.T) {
	ctx := context.Background()
	mock := NewMockDomainWorkflowAdapters()

	tokenRider := "token-rider-a"

	// Rider completes delivery with COD collection (₹180 = 18000 minor)
	if err := mock.ConfirmDelivery(ctx, tokenRider, "job-1", "99992222", true); err != nil {
		t.Fatalf("confirm delivery: %v", err)
	}

	liability, err := mock.GetCashAccountability(ctx, tokenRider)
	if err != nil {
		t.Fatalf("get liability: %v", err)
	}
	if liability != 18000 {
		t.Fatalf("expected liability 18000, got %d", liability)
	}

	// Rider attempts to remit more than liability (₹200 = 20000 minor) -> REJECTED
	if _, err := mock.SubmitRemittance(ctx, tokenRider, 20000, "Over-remit", "idem-r1"); err == nil {
		t.Fatal("expected remittance exceeding liability to fail")
	}

	// Rider remits exact liability (₹180 = 18000 minor) -> OK
	if _, err := mock.SubmitRemittance(ctx, tokenRider, 18000, "Full remit", "idem-r2"); err != nil {
		t.Fatalf("remittance submission failed: %v", err)
	}

	newLiability, _ := mock.GetCashAccountability(ctx, tokenRider)
	if newLiability != 0 {
		t.Fatalf("expected liability 0 after remittance, got %d", newLiability)
	}
}

func TestMockDomainWorkflowAdapters_Idempotency(t *testing.T) {
	ctx := context.Background()
	mock := NewMockDomainWorkflowAdapters()

	orderID1, ref1, err := mock.PlaceOrder(ctx, "token-cust", "q-1", "upi", "idem-order-key-1")
	if err != nil {
		t.Fatalf("first place order: %v", err)
	}

	// Second attempt with exact same idempotency key
	orderID2, ref2, err := mock.PlaceOrder(ctx, "token-cust", "q-1", "upi", "idem-order-key-1")
	if err != nil {
		t.Fatalf("idempotent second place order: %v", err)
	}

	if orderID2 == "" || ref2 == "" {
		t.Fatalf("idempotent replay failed: %s %s vs %s %s", orderID1, ref1, orderID2, ref2)
	}
}

func TestValidateSyntheticIdentityPlan(t *testing.T) {
	valid := DefaultSyntheticIdentityPlan
	if err := ValidateSyntheticIdentityPlan(valid); err != nil {
		t.Fatalf("default identity plan should be valid: %v", err)
	}

	// Test phone collision
	invalidPhones := make([]SyntheticIdentitySpec, len(valid))
	copy(invalidPhones, valid)
	invalidPhones[1].PhoneE164 = invalidPhones[0].PhoneE164
	if err := ValidateSyntheticIdentityPlan(invalidPhones); err == nil {
		t.Fatal("expected collision error for duplicate phones")
	}

	// Test business collision
	invalidBiz := make([]SyntheticIdentitySpec, len(valid))
	copy(invalidBiz, valid)
	invalidBiz[1].BusinessBinding = invalidBiz[0].BusinessBinding
	if err := ValidateSyntheticIdentityPlan(invalidBiz); err == nil {
		t.Fatal("expected collision error for duplicate businesses")
	}

	// Test non-allowlisted phone
	invalidRange := make([]SyntheticIdentitySpec, len(valid))
	copy(invalidRange, valid)
	invalidRange[0].PhoneE164 = "+919876543210"
	if err := ValidateSyntheticIdentityPlan(invalidRange); err == nil {
		t.Fatal("expected rejection for non-allowlisted phone")
	}
}

func TestScenarioRunner_DryRunIsNonMutating(t *testing.T) {
	ctx := context.Background()
	mock := NewMockDomainWorkflowAdapters()
	runner := &ScenarioRunner{
		Adapters: mock.AsDomainWorkflowAdapters(),
		RunID:    "phase5b-mock-test-01",
	}

	plan, err := runner.DryRunPlan()
	if err != nil {
		t.Fatalf("dry run plan: %v", err)
	}
	if len(plan) != 6 {
		t.Fatalf("expected 6 scenarios in plan, got %d", len(plan))
	}

	// Dry run execution must not mutate anything
	for _, sc := range plan {
		if err := runner.ExecuteScenario(ctx, sc.Name, true); err != nil {
			t.Fatalf("dry run execute failed for %s: %v", sc.Name, err)
		}
	}

	if len(mock.Orders) != 0 || len(mock.Settlements) != 0 || len(mock.DeliveryJobs) != 0 {
		t.Fatal("dry run execution mutated mock state")
	}

	// Live execution attempt must fail closed requiring Phase 5B.4C authorization
	err = runner.ExecuteScenario(ctx, "merchant_a_payable_and_settlement", false)
	if err == nil || !strings.Contains(err.Error(), "Phase 5B.4C") {
		t.Fatalf("expected Phase 5B.4C gate refusal, got: %v", err)
	}
}
