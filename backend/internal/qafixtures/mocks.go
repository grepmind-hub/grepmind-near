package qafixtures

import (
	"context"
	"errors"
	"sync"
)

// MockDomainWorkflowAdapters implements all adapter interfaces in-memory for testing.
type MockDomainWorkflowAdapters struct {
	mu sync.Mutex

	// Mock state
	Users            map[string]string // phone -> token
	Businesses       map[string]string // bizID -> ownerToken
	BusinessNames    map[string]string // bizID -> name
	Products         map[string][]string
	Orders           map[string]map[string]any // orderID -> details
	DeliveryJobs     map[string]map[string]any
	PickupCodes      map[string]string // jobID -> code
	DeliveryCodes    map[string]string // orderID -> code
	CashLiability    map[string]int64  // riderToken -> minor
	EarningsRecorded map[string]int64  // riderToken -> minor
	Settlements      map[string][]map[string]any
	Transfers        map[string]map[string]any
	AccessGrants     map[string]map[string]any // grantID -> details
	IdempotencyStore map[string]bool

	// Injection points for testing failures
	FailAuth          bool
	FailPickupCode    bool
	FailDeliveryCode  bool
	FailFinancePost   bool
	FailSelfApproval  bool
	FailRemittance    bool
	CrossTenantAccess bool
}

func NewMockDomainWorkflowAdapters() *MockDomainWorkflowAdapters {
	return &MockDomainWorkflowAdapters{
		Users:            make(map[string]string),
		Businesses:       make(map[string]string),
		BusinessNames:    make(map[string]string),
		Products:         make(map[string][]string),
		Orders:           make(map[string]map[string]any),
		DeliveryJobs:     make(map[string]map[string]any),
		PickupCodes:      make(map[string]string),
		DeliveryCodes:    make(map[string]string),
		CashLiability:    make(map[string]int64),
		EarningsRecorded: make(map[string]int64),
		Settlements:      make(map[string][]map[string]any),
		Transfers:        make(map[string]map[string]any),
		AccessGrants:     make(map[string]map[string]any),
		IdempotencyStore: make(map[string]bool),
	}
}

// 1. Auth Mock
func (m *MockDomainWorkflowAdapters) Login(ctx context.Context, phone string) (string, error) {
	challenge, err := m.RequestOTP(ctx, phone)
	if err != nil {
		return "", err
	}
	code, err := m.ResolveQAOTP(ctx, challenge)
	if err != nil {
		return "", err
	}
	return m.VerifyOTP(ctx, phone, code, challenge)
}

func (m *MockDomainWorkflowAdapters) RequestOTP(ctx context.Context, phone string) (string, error) {
	if m.FailAuth {
		return "", errors.New("auth provider unavailable")
	}
	return "mock-challenge-" + phone, nil
}

func (m *MockDomainWorkflowAdapters) ResolveQAOTP(ctx context.Context, challengeID string) (string, error) {
	if m.FailAuth {
		return "", errors.New("failed to read OTP")
	}
	return "123456", nil
}

func (m *MockDomainWorkflowAdapters) VerifyOTP(ctx context.Context, phone, otp, challengeID string) (string, error) {
	if m.FailAuth || otp != "123456" {
		return "", errors.New("invalid OTP code")
	}
	token := "token-for-" + phone
	m.mu.Lock()
	m.Users[phone] = token
	m.mu.Unlock()
	return token, nil
}

// 2. Merchant Mock
func (m *MockDomainWorkflowAdapters) EnsureBusiness(ctx context.Context, token, name, category, localityID string) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	bizID := "biz-" + name
	m.Businesses[bizID] = token
	m.BusinessNames[bizID] = name
	return bizID, nil
}

func (m *MockDomainWorkflowAdapters) AddProduct(ctx context.Context, token, businessID, name string, price float64) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	ownerToken, ok := m.Businesses[businessID]
	if !ok || (!m.CrossTenantAccess && ownerToken != token) {
		return "", errors.New("FORBIDDEN: business not owned by caller")
	}
	prodID := "prod-" + name
	m.Products[businessID] = append(m.Products[businessID], prodID)
	return prodID, nil
}

func (m *MockDomainWorkflowAdapters) AcceptOrder(ctx context.Context, token, businessID, orderID, idempotency string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if owner := m.Businesses[businessID]; owner != token && !m.CrossTenantAccess {
		return errors.New("FORBIDDEN: business mismatch")
	}
	return nil
}

func (m *MockDomainWorkflowAdapters) PrepareOrder(ctx context.Context, token, businessID, orderID, idempotency string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if owner := m.Businesses[businessID]; owner != token && !m.CrossTenantAccess {
		return errors.New("FORBIDDEN: business mismatch")
	}
	m.DeliveryJobs["job-"+orderID] = map[string]any{"order_id": orderID, "business_id": businessID, "state": "prepared"}
	return nil
}

func (m *MockDomainWorkflowAdapters) ReadyOrder(ctx context.Context, token, businessID, orderID, idempotency string) error {
	return nil
}

func (m *MockDomainWorkflowAdapters) IssuePickupCode(ctx context.Context, token, businessID, jobID string) (string, error) {
	if m.FailPickupCode {
		return "", errors.New("cannot issue pickup code: order not ready")
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if owner := m.Businesses[businessID]; owner != token && !m.CrossTenantAccess {
		return "", errors.New("FORBIDDEN: business mismatch")
	}
	code := "88881111"
	m.PickupCodes[jobID] = code
	return code, nil
}

func (m *MockDomainWorkflowAdapters) RegisterMerchantBeneficiary(ctx context.Context, token, businessID, accountNum, ifsc, holder string) (string, error) {
	return "bene-m-" + businessID, nil
}

func (m *MockDomainWorkflowAdapters) GetMerchantSettlements(ctx context.Context, token, businessID string) ([]MerchantSettlementView, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if owner := m.Businesses[businessID]; owner != token && !m.CrossTenantAccess {
		return nil, errors.New("FORBIDDEN: cross-merchant access denied")
	}
	var res []MerchantSettlementView
	for _, raw := range m.Settlements[businessID] {
		res = append(res, MerchantSettlementView{
			ID:         raw["id"].(string),
			Status:     raw["status"].(string),
			TotalGross: raw["gross"].(int64),
			TotalNet:   raw["net"].(int64),
		})
	}
	return res, nil
}

// 3. Customer Mock
func (m *MockDomainWorkflowAdapters) EnsureDeliveryAddress(ctx context.Context, token, localityID, line1 string) (string, error) {
	return "addr-101", nil
}

func (m *MockDomainWorkflowAdapters) RequestQuote(ctx context.Context, token, vertical, addressID, variantID string) (string, int64, error) {
	return "quote-1", 25000, nil
}

func (m *MockDomainWorkflowAdapters) PlaceOrder(ctx context.Context, token, quoteID, paymentMethod, idempotency string) (string, string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if idempotency != "" && m.IdempotencyStore[idempotency] {
		return "order-idempotent-1", "GN-IDEM-01", nil
	}
	if idempotency != "" {
		m.IdempotencyStore[idempotency] = true
	}
	orderID := "order-" + quoteID
	m.Orders[orderID] = map[string]any{"payment_method": paymentMethod, "status": "created"}
	return orderID, "GN-MOCK-01", nil
}

func (m *MockDomainWorkflowAdapters) SimulatePaymentSuccess(ctx context.Context, token, orderID, idempotency string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if ord, ok := m.Orders[orderID]; ok {
		ord["status"] = "paid"
	}
	return nil
}

func (m *MockDomainWorkflowAdapters) IssueDeliveryCode(ctx context.Context, token, orderID string) (string, error) {
	if m.FailDeliveryCode {
		return "", errors.New("cannot issue delivery code")
	}
	code := "99992222"
	m.mu.Lock()
	m.DeliveryCodes[orderID] = code
	m.mu.Unlock()
	return code, nil
}

// 4. Rider Mock
func (m *MockDomainWorkflowAdapters) EnsureApprovedRider(ctx context.Context, token, vehicleType string) (string, error) {
	return "rider-id-" + token, nil
}

func (m *MockDomainWorkflowAdapters) SetAvailability(ctx context.Context, token string, isOnline bool) error {
	return nil
}

func (m *MockDomainWorkflowAdapters) AcceptOffer(ctx context.Context, token, offerID, idempotency string) error {
	return nil
}

func (m *MockDomainWorkflowAdapters) TransitionJobState(ctx context.Context, token, jobID, state, idempotency string) error {
	return nil
}

func (m *MockDomainWorkflowAdapters) VerifyPickup(ctx context.Context, token, jobID, code string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	expected := m.PickupCodes[jobID]
	if expected != "" && expected != code {
		return errors.New("VALIDATION_ERROR: pickup code mismatch")
	}
	return nil
}

func (m *MockDomainWorkflowAdapters) ConfirmDelivery(ctx context.Context, token, jobID, code string, confirmCOD bool) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if confirmCOD {
		m.CashLiability[token] += 18000
	}
	m.EarningsRecorded[token] += 4500
	return nil
}

func (m *MockDomainWorkflowAdapters) SubmitRemittance(ctx context.Context, token string, amountMinor int64, notes, idempotency string) (string, error) {
	if m.FailRemittance {
		return "", errors.New("REMITTANCE_EXCEEDS_LIABILITY")
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	curr := m.CashLiability[token]
	if amountMinor > curr {
		return "", errors.New("REMITTANCE_EXCEEDS_LIABILITY: amount exceeds current liability")
	}
	m.CashLiability[token] -= amountMinor
	return "remit-101", nil
}

func (m *MockDomainWorkflowAdapters) RegisterRiderBeneficiary(ctx context.Context, token, accountNum, ifsc, holder string) (string, error) {
	return "bene-r-" + token, nil
}

func (m *MockDomainWorkflowAdapters) GetRiderSettlements(ctx context.Context, token string) ([]RiderSettlementView, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	var res []RiderSettlementView
	for _, raw := range m.Settlements[token] {
		res = append(res, RiderSettlementView{
			ID:         raw["id"].(string),
			Status:     raw["status"].(string),
			TotalMinor: raw["net"].(int64),
		})
	}
	return res, nil
}

func (m *MockDomainWorkflowAdapters) GetEarnings(ctx context.Context, token string) (int64, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.EarningsRecorded[token], nil
}

func (m *MockDomainWorkflowAdapters) GetCashAccountability(ctx context.Context, token string) (int64, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.CashLiability[token], nil
}

// 5. Admin Mock
func (m *MockDomainWorkflowAdapters) ReviewRiderApplication(ctx context.Context, token, applicationID, action string) error {
	return nil
}

func (m *MockDomainWorkflowAdapters) TriggerDispatchRun(ctx context.Context, token, localityID, idempotency string) error {
	return nil
}

func (m *MockDomainWorkflowAdapters) ReviewCashRemittance(ctx context.Context, token, remittanceID, action, notes string) error {
	return nil
}

func (m *MockDomainWorkflowAdapters) RequestFinancePostAccess(ctx context.Context, token, targetUserID, reason string) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	reqID := "grant-req-1"
	m.AccessGrants[reqID] = map[string]any{"requester": token, "target": targetUserID, "status": "pending"}
	return reqID, nil
}

func (m *MockDomainWorkflowAdapters) DecideFinancePostAccess(ctx context.Context, token, requestID, decision, reason string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	grant, ok := m.AccessGrants[requestID]
	if !ok {
		return errors.New("grant request not found")
	}
	if grant["requester"] == token && !m.FailSelfApproval {
		return errors.New("FORBIDDEN: self-approval of finance.post is blocked")
	}
	grant["status"] = decision
	return nil
}

func (m *MockDomainWorkflowAdapters) AccrueMerchantPayable(ctx context.Context, token, orderID string) error {
	if m.FailFinancePost {
		return errors.New("FORBIDDEN: caller lacks finance.post permission")
	}
	return nil
}

func (m *MockDomainWorkflowAdapters) CreateCommissionPolicy(ctx context.Context, token, category string, rateBps int) (string, error) {
	return "pol-1", nil
}

func (m *MockDomainWorkflowAdapters) DecideCommissionPolicy(ctx context.Context, token, policyID, decision string) error {
	return nil
}

func (m *MockDomainWorkflowAdapters) CreateMerchantSettlement(ctx context.Context, token, businessID, periodStart, periodEnd, idempotency string) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	batchID := "batch-m-" + businessID
	m.Settlements[businessID] = append(m.Settlements[businessID], map[string]any{
		"id": batchID, "status": "draft", "gross": int64(25000), "net": int64(23750), "creator": token,
	})
	return batchID, nil
}

func (m *MockDomainWorkflowAdapters) ReviewMerchantSettlement(ctx context.Context, token, batchID string) error {
	return nil
}

func (m *MockDomainWorkflowAdapters) ApproveMerchantSettlement(ctx context.Context, token, batchID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, list := range m.Settlements {
		for _, s := range list {
			if s["id"] == batchID {
				if s["creator"] == token && !m.FailSelfApproval {
					return errors.New("FORBIDDEN: separation of duties violation: creator cannot approve settlement")
				}
				s["status"] = "approved"
				return nil
			}
		}
	}
	return nil
}

func (m *MockDomainWorkflowAdapters) CreateRiderSettlement(ctx context.Context, token, riderID, periodStart, periodEnd string) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	batchID := "batch-r-" + riderID
	m.Settlements[riderID] = append(m.Settlements[riderID], map[string]any{
		"id": batchID, "status": "draft", "net": int64(4500), "creator": token,
	})
	return batchID, nil
}

func (m *MockDomainWorkflowAdapters) ApproveRiderSettlement(ctx context.Context, token, batchID, reason string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, list := range m.Settlements {
		for _, s := range list {
			if s["id"] == batchID {
				if s["creator"] == token && !m.FailSelfApproval {
					return errors.New("FORBIDDEN: separation of duties violation: creator cannot approve rider settlement")
				}
				s["status"] = "approved"
				return nil
			}
		}
	}
	return nil
}

func (m *MockDomainWorkflowAdapters) VerifyBeneficiary(ctx context.Context, token, beneficiaryID string) error {
	return nil
}

func (m *MockDomainWorkflowAdapters) CreatePayoutTransfer(ctx context.Context, token, kind, batchID, idempotency string) (string, error) {
	return "xfer-101", nil
}

func (m *MockDomainWorkflowAdapters) ApprovePayoutTransfer(ctx context.Context, token, transferID, reason, idempotency string) error {
	return nil
}

func (m *MockDomainWorkflowAdapters) ExecutePayoutTransfer(ctx context.Context, token, transferID, idempotency string) (string, error) {
	return "QA_UTR_MOCK_101", nil
}

// AsDomainWorkflowAdapters converts the mock instance to DomainWorkflowAdapters.
func (m *MockDomainWorkflowAdapters) AsDomainWorkflowAdapters() *DomainWorkflowAdapters {
	return &DomainWorkflowAdapters{
		Auth:     m,
		Merchant: m,
		Customer: m,
		Rider:    m,
		Admin:    m,
	}
}

// MockIsolationInspector implements LiveIsolationInspector for tests.
type MockIsolationInspector struct {
	Env      EnvironmentEvidence
	Database DatabaseEvidence
	Schema   SchemaEvidence
	Services ServicesEvidence

	FailEnv      bool
	FailDatabase bool
	FailSchema   bool
	FailServices bool
}

func (m *MockIsolationInspector) InspectEnvironment(ctx context.Context) (EnvironmentEvidence, error) {
	if m.FailEnv {
		return EnvironmentEvidence{}, errors.New("injected env inspection failure")
	}
	return m.Env, nil
}

func (m *MockIsolationInspector) InspectDatabase(ctx context.Context) (DatabaseEvidence, error) {
	if m.FailDatabase {
		return DatabaseEvidence{}, errors.New("injected database inspection failure")
	}
	return m.Database, nil
}

func (m *MockIsolationInspector) InspectSchema(ctx context.Context) (SchemaEvidence, error) {
	if m.FailSchema {
		return SchemaEvidence{}, errors.New("injected schema inspection failure")
	}
	return m.Schema, nil
}

func (m *MockIsolationInspector) InspectServices(ctx context.Context) (ServicesEvidence, error) {
	if m.FailServices {
		return ServicesEvidence{}, errors.New("injected services inspection failure")
	}
	return m.Services, nil
}

func ValidMockIsolationInspector() *MockIsolationInspector {
	return &MockIsolationInspector{
		Env: EnvironmentEvidence{
			AppEnv:           "qa",
			RealMoneyEnabled: false,
			PayoutEnabled:    false,
			PaymentProvider:  "sandbox",
			PayoutProvider:   "sandbox",
			SMSProvider:      "qa_http",
			OTPProvider:      "qa_http",
		},
		Database: DatabaseEvidence{
			DatabaseName:          "grepmind_3e_qa",
			DatabaseHost:          "grepmind_3e_qa_db",
			DatabasePort:          5432,
			ServerVersion:         "PostgreSQL 16.2",
			IsDisposableTmpfs:     true,
			HasPersistentMounts:   false,
			ConnectionFingerprint: "grepmind_3e_qa@grepmind_3e_qa_db:5432",
		},
		Schema: SchemaEvidence{
			PresentTables: RequiredSchemaTables,
			MissingTables: nil,
		},
		Services: ServicesEvidence{
			APIHealthy:      true,
			APIBaseURL:      "http://127.0.0.1:18083",
			APIEnvironment:  "qa",
			OTPInboxHealthy: true,
			OTPInboxURL:     "http://127.0.0.1:18085",
		},
	}
}
