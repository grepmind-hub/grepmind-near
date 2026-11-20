package qafixtures

import (
	"strings"
	"testing"
)

func TestBuildPlanIsDeterministicAndNonMutating(t *testing.T) {
	a, err := BuildPlan("phase5b-run-001")
	if err != nil {
		t.Fatal(err)
	}
	b, err := BuildPlan("phase5b-run-001")
	if err != nil {
		t.Fatal(err)
	}
	if a.Mode != "dry-run" || a.Mutations || len(a.Scenarios) != 6 {
		t.Fatalf("unexpected plan header: %+v", a)
	}
	for i := range a.Scenarios {
		if a.Scenarios[i].Idempotency != b.Scenarios[i].Idempotency || a.Scenarios[i].Status != "blocked" {
			t.Fatalf("scenario plan is not stable/fail-closed: %+v / %+v", a.Scenarios[i], b.Scenarios[i])
		}
	}
}

func TestValidateExecutionRequiresExplicitQAIsolation(t *testing.T) {
	base := IsolationEvidence{AppEnv: "qa", DatabaseName: "grepmind_fixture_qa", DatabaseContainer: "grepmind_fixture_qa_db", ContainerRunning: true, ContainerImage: "postgres:16", AttachedNetworks: []string{"grepmind_fixture_qa_net"}, ExpectedQANetwork: "grepmind_fixture_qa_net", DatabaseNameMatches: true, ProviderMode: "fake", SyntheticActorsOnly: true}
	if err := ValidateExecution(base, false, true); err == nil {
		t.Fatal("execute flag should be required")
	}
	if err := ValidateExecution(base, true, false); err == nil {
		t.Fatal("confirmation flag should be required")
	}
	if err := ValidateExecution(base, true, true); err != nil {
		t.Fatal(err)
	}
}

func TestExecutionEnvironmentGuardFailsClosedWithoutLiveEvidence(t *testing.T) {
	if err := ValidateExecutionFromEnvironment("qa", false); err == nil {
		t.Fatal("missing isolated-QA confirmation was accepted")
	}
	if err := ValidateExecutionFromEnvironment("production", true); err == nil {
		t.Fatal("production execution was accepted")
	}
	if err := ValidateExecutionFromEnvironment("qa", true); err == nil || !strings.Contains(err.Error(), "live database") {
		t.Fatalf("CLI should refuse until live isolation evidence is wired: %v", err)
	}
}

func TestValidateExecutionRejectsUnsafeTargetsAndFlags(t *testing.T) {
	base := IsolationEvidence{AppEnv: "qa", DatabaseName: "grepmind_fixture_qa", DatabaseContainer: "grepmind_fixture_qa_db", ContainerRunning: true, ContainerImage: "postgres:16", AttachedNetworks: []string{"grepmind_fixture_qa_net"}, ExpectedQANetwork: "grepmind_fixture_qa_net", DatabaseNameMatches: true, ProviderMode: "fake", SyntheticActorsOnly: true}
	tests := []struct {
		name   string
		change func(*IsolationEvidence)
	}{
		{"production env", func(e *IsolationEvidence) { e.AppEnv = "production" }},
		{"shared database", func(e *IsolationEvidence) { e.DatabaseName = "grepmind_shared" }},
		{"identity mismatch", func(e *IsolationEvidence) { e.DatabaseNameMatches = false }},
		{"persistent mount", func(e *IsolationEvidence) { e.PersistentMounts = 1 }},
		{"network leak", func(e *IsolationEvidence) { e.AttachedNetworks = append(e.AttachedNetworks, "bridge") }},
		{"real money", func(e *IsolationEvidence) { e.RealMoneyEnabled = true }},
		{"payout enabled", func(e *IsolationEvidence) { e.PayoutEnabled = true }},
		{"live provider", func(e *IsolationEvidence) { e.ProviderMode = "fast2sms" }},
		{"non-synthetic actors", func(e *IsolationEvidence) { e.SyntheticActorsOnly = false }},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			e := base
			tt.change(&e)
			if err := ValidateExecution(e, true, true); err == nil {
				t.Fatal("unsafe execution was accepted")
			}
		})
	}
}

func TestActorSetRequiresDistinctTenantBoundApprovedSyntheticActors(t *testing.T) {
	valid := ActorSet{MerchantAID: "m-a", MerchantABusinessID: "b-a", MerchantBID: "m-b", MerchantBBusinessID: "b-b", RiderAID: "r-a", RiderBID: "r-b", CustomerID: "c", AdminID: "a", AllSynthetic: true, RiderAApproved: true, RiderBApproved: true}
	if err := valid.Validate(); err != nil {
		t.Fatal(err)
	}
	invalid := valid
	invalid.MerchantBBusinessID = invalid.MerchantABusinessID
	if err := invalid.Validate(); err == nil {
		t.Fatal("shared merchant business was accepted")
	}
	invalid = valid
	invalid.RiderBID = invalid.RiderAID
	if err := invalid.Validate(); err == nil {
		t.Fatal("duplicate rider was accepted")
	}
	invalid = valid
	invalid.RiderBApproved = false
	if err := invalid.Validate(); err == nil {
		t.Fatal("unapproved rider was accepted")
	}
	invalid = valid
	invalid.AllSynthetic = false
	if err := invalid.Validate(); err == nil {
		t.Fatal("non-synthetic actor was accepted")
	}
}

func TestMissingWorkflowPrerequisiteBlocksScenario(t *testing.T) {
	err := ValidateScenarioPrerequisites(map[string]bool{"approved rider": true}, []string{"approved rider", "authorized COD delivery workflow"})
	if err == nil || !strings.Contains(err.Error(), "authorized COD delivery workflow") {
		t.Fatalf("unexpected result: %v", err)
	}
}

func TestSensitiveAssignmentsRedacted(t *testing.T) {
	got := Redact("OTP=123456 token=abc SECRET=hidden ACCOUNT_NUMBER=123456789")
	for _, secret := range []string{"123456", "abc", "hidden", "123456789"} {
		if strings.Contains(got, secret) {
			t.Fatalf("sensitive value leaked: %s", got)
		}
	}
}
