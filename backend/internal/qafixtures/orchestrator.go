package qafixtures

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"regexp"
	"strings"
)

// Scenario describes one populated state needed by Phase 5B. The current
// orchestrator is intentionally a planner: no financial workflow adapter is
// registered until a separate gate authorizes and implements one.
type Scenario struct {
	Name          string   `json:"name"`
	Idempotency   string   `json:"idempotency_key"`
	Prerequisites []string `json:"prerequisites"`
	Status        string   `json:"status"`
	Blockers      []string `json:"blockers,omitempty"`
}

type Plan struct {
	RunID     string     `json:"run_id"`
	Mode      string     `json:"mode"`
	Mutations bool       `json:"mutations_performed"`
	Scenarios []Scenario `json:"scenarios"`
}

var requiredScenarios = []struct {
	name  string
	needs []string
}{
	{"merchant_a_payable_and_settlement", []string{"synthetic merchant A with distinct business", "eligible order completed through normal payment and delivery workflows", "Admin finance.post payable accrual", "verified beneficiary and independent settlement review/approval"}},
	{"merchant_b_payable_and_settlement", []string{"synthetic merchant B with distinct business", "eligible order completed through normal payment and delivery workflows", "Admin finance.post payable accrual", "verified beneficiary and independent settlement review/approval"}},
	{"rider_a_earning_and_settlement", []string{"approved synthetic rider A", "OTP-verified delivery with approved earnings policy", "Admin-controlled rider settlement workflow", "no outstanding COD liability"}},
	{"rider_b_earning_and_settlement", []string{"approved synthetic rider B distinct from rider A", "OTP-verified delivery with approved earnings policy", "Admin-controlled rider settlement workflow", "no outstanding COD liability"}},
	{"rider_a_nonzero_cod_liability", []string{"synthetic COD enabled in isolated QA", "assigned rider completes authorized customer handover", "backend records COD collection through delivery workflow"}},
	{"rider_b_independent_cod_liability", []string{"approved synthetic rider B distinct from rider A", "independent COD order and collection or verified zero balance", "backend-derived liability reconciliation"}},
}

// BuildPlan is pure and repeatable. Its identifiers are deterministic and do
// not contain account credentials or financial values.
func BuildPlan(runID string) (Plan, error) {
	runID = strings.TrimSpace(runID)
	if len(runID) < 8 || len(runID) > 80 {
		return Plan{}, errors.New("run ID must contain 8-80 characters")
	}
	for _, r := range runID {
		if !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '-' || r == '_') {
			return Plan{}, errors.New("run ID contains unsupported characters")
		}
	}
	plan := Plan{RunID: runID, Mode: "dry-run", Mutations: false}
	for _, def := range requiredScenarios {
		plan.Scenarios = append(plan.Scenarios, Scenario{
			Name: def.name, Idempotency: IdempotencyKey(runID, def.name),
			Prerequisites: append([]string(nil), def.needs...), Status: "blocked",
			Blockers: []string{"no approved narrow domain-workflow fixture adapter is implemented; no records were created"},
		})
	}
	return plan, nil
}

// IdempotencyKey gives a stable run/scenario key for a future authorized
// executor. The raw run ID is not embedded in the returned key.
func IdempotencyKey(runID, scenario string) string {
	sum := sha256.Sum256([]byte("grepmind-near/phase5b-fixture/v1\x00" + runID + "\x00" + scenario))
	return hex.EncodeToString(sum[:])
}

// IsolationEvidence must be obtained from the actual runtime, not supplied by
// a caller-controlled CLI assertion, before a future mutating adapter runs.
type IsolationEvidence struct {
	AppEnv              string
	DatabaseName        string
	DatabaseContainer   string
	ContainerRunning    bool
	ContainerImage      string
	PersistentMounts    int
	AttachedNetworks    []string
	ExpectedQANetwork   string
	DatabaseNameMatches bool
	RealMoneyEnabled    bool
	PayoutEnabled       bool
	ProviderMode        string
	SyntheticActorsOnly bool
}

func ValidateExecution(e IsolationEvidence, execute, confirm bool) error {
	if !execute || !confirm {
		return errors.New("execution requires both --execute and --confirm-isolated-qa")
	}
	if !strings.EqualFold(e.AppEnv, "qa") && !strings.EqualFold(e.AppEnv, "test") {
		return errors.New("execution is restricted to APP_ENV=qa or APP_ENV=test")
	}
	if !isQAName(e.DatabaseName) || !isQAName(e.DatabaseContainer) || !e.DatabaseNameMatches {
		return errors.New("database identity is not verified as an isolated QA/test target")
	}
	if !e.ContainerRunning || !strings.Contains(strings.ToLower(e.ContainerImage), "postgres") || e.PersistentMounts != 0 {
		return errors.New("database container is not a running disposable PostgreSQL container without persistent mounts")
	}
	if !isQANetwork(e.ExpectedQANetwork) || len(e.AttachedNetworks) != 1 || e.AttachedNetworks[0] != e.ExpectedQANetwork {
		return errors.New("database container network isolation is not verified")
	}
	if e.RealMoneyEnabled || e.PayoutEnabled {
		return errors.New("real-money and payout feature flags must both be disabled")
	}
	provider := strings.ToLower(strings.TrimSpace(e.ProviderMode))
	if provider != "fake" && provider != "sandbox" && provider != "qa" && provider != "none" {
		return errors.New("live or unknown external provider is not permitted")
	}
	if !e.SyntheticActorsOnly {
		return errors.New("only synthetic QA actors are permitted")
	}
	return nil
}

// ValidateExecutionFromEnvironment is intentionally an unconditional fail-safe
// for the current CLI. Runtime identity/flags are not yet queried by an
// execution adapter, so APP_ENV and a confirmation flag alone cannot authorize
// mutation.
func ValidateExecutionFromEnvironment(appEnv string, confirm bool) error {
	if !confirm {
		return errors.New("execution requires --confirm-isolated-qa")
	}
	if !strings.EqualFold(appEnv, "qa") && !strings.EqualFold(appEnv, "test") {
		return errors.New("execution is restricted to APP_ENV=qa or APP_ENV=test")
	}
	return errors.New("execution is disabled until the CLI can verify the live database container, database identity, network isolation, feature flags, and provider mode")
}

func isQAName(name string) bool {
	n := strings.ToLower(strings.TrimSpace(name))
	if strings.Contains(n, "prod") || strings.Contains(n, "production") || strings.Contains(n, "shared") || strings.Contains(n, "development") {
		return false
	}
	return strings.HasSuffix(n, "_qa") || strings.HasSuffix(n, "_test") || strings.Contains(n, "_qa_") || strings.Contains(n, "_test_")
}

func isQANetwork(name string) bool {
	n := strings.ToLower(strings.TrimSpace(name))
	return isQAName(n) && (strings.HasSuffix(n, "_net") || strings.HasSuffix(n, "_network"))
}

// ActorSet validates that the identities a future run references are distinct
// synthetic principals with the required approvals and tenant bindings.
type ActorSet struct {
	MerchantAID, MerchantABusinessID string
	MerchantBID, MerchantBBusinessID string
	RiderAID, RiderBID               string
	CustomerID, AdminID              string
	AllSynthetic                     bool
	RiderAApproved, RiderBApproved   bool
}

func (a ActorSet) Validate() error {
	if !a.AllSynthetic {
		return errors.New("all referenced principals must be synthetic QA identities")
	}
	ids := []string{a.MerchantAID, a.MerchantBID, a.RiderAID, a.RiderBID, a.CustomerID, a.AdminID}
	for _, id := range ids {
		if strings.TrimSpace(id) == "" {
			return errors.New("all required actor IDs must be present")
		}
	}
	seen := map[string]bool{}
	for _, id := range ids {
		if seen[id] {
			return errors.New("merchant, rider, customer, and admin actors must be distinct")
		}
		seen[id] = true
	}
	if strings.TrimSpace(a.MerchantABusinessID) == "" || strings.TrimSpace(a.MerchantBBusinessID) == "" || a.MerchantABusinessID == a.MerchantBBusinessID {
		return errors.New("merchant actors must own distinct businesses")
	}
	if !a.RiderAApproved || !a.RiderBApproved {
		return errors.New("both rider actors must have independently verified approval")
	}
	return nil
}

// Redact prevents accidental propagation of credentials if a caller adds
// runtime diagnostics around the planner. The CLI currently emits no runtime
// environment or API response bodies.
func Redact(s string) string {
	return sensitiveAssignment.ReplaceAllString(s, "$1=[REDACTED]")
}

var sensitiveAssignment = regexp.MustCompile(`(?i)\b(OTP|TOKEN|SECRET|PASSWORD|ACCOUNT_NUMBER|BANK_ACCOUNT)=([^\s,;}]+)`)

func ValidateScenarioPrerequisites(have map[string]bool, required []string) error {
	missing := make([]string, 0)
	for _, item := range required {
		if !have[item] {
			missing = append(missing, item)
		}
	}
	if len(missing) != 0 {
		return fmt.Errorf("scenario blocked; missing approved prerequisites: %s", strings.Join(missing, "; "))
	}
	return nil
}
