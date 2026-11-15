package payouts

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"
)

const QAProviderName = "grepmind_qa_payout"

type IsolatedQAPayoutProvider struct {
	secret    []byte
	mu        sync.RWMutex
	transfers map[string]TransferResult
	benes     map[string]BeneficiaryValidationResult
}

func NewIsolatedQAPayoutProvider(secret []byte) *IsolatedQAPayoutProvider {
	if len(secret) < 32 {
		secret = []byte("qa_isolated_payout_webhook_secret_key_32_bytes_min!")
	}
	return &IsolatedQAPayoutProvider{
		secret:    secret,
		transfers: make(map[string]TransferResult),
		benes:     make(map[string]BeneficiaryValidationResult),
	}
}

func (p *IsolatedQAPayoutProvider) Name() string {
	return QAProviderName
}

func (p *IsolatedQAPayoutProvider) ValidateBeneficiary(_ context.Context, req BeneficiaryValidationRequest) (BeneficiaryValidationResult, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	// Deterministic failure triggers for negative QA testing
	if strings.HasPrefix(req.IFSC, "FAIL") || strings.HasSuffix(req.AccountNumber, "0000") {
		res := BeneficiaryValidationResult{
			ProviderBeneficiaryID: "qa_bene_" + req.BeneficiaryID[:8],
			Status:                "rejected",
			FailureReason:         "Account does not exist or bank rejected penny drop verification.",
			Evidence: map[string]any{
				"penny_drop_status": "failed",
				"provider_code":     "ACCOUNT_NOT_FOUND",
			},
		}
		p.benes[req.BeneficiaryID] = res
		return res, nil
	}

	res := BeneficiaryValidationResult{
		ProviderBeneficiaryID: "qa_bene_" + req.BeneficiaryID[:8],
		Status:                "verified",
		RegisteredName:        req.AccountHolder,
		Evidence: map[string]any{
			"penny_drop_status": "succeeded",
			"penny_drop_utr":    fmt.Sprintf("QA_PENNY_%d", time.Now().UnixNano()%1000000000),
			"registered_name":   req.AccountHolder,
			"verified_at":       time.Now().UTC().Format(time.RFC3339),
		},
	}
	p.benes[req.BeneficiaryID] = res
	return res, nil
}

func (p *IsolatedQAPayoutProvider) InitiateTransfer(_ context.Context, req TransferRequest) (TransferResult, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	providerTransferID := fmt.Sprintf("qa_tx_%s_%d", req.TransferID[:8], req.AttemptNumber)

	// Scenario 1: Immediate failure simulation
	if strings.Contains(req.Narration, "FAIL") || strings.HasPrefix(req.IFSC, "FAIL") || strings.HasSuffix(req.AccountNumber, "0000") || strings.HasSuffix(req.AccountNumber, "8888") {
		res := TransferResult{
			ProviderTransferID: providerTransferID,
			Status:             "failed",
			ErrorCode:          "BENEFICIARY_BANK_REJECTED",
			ErrorMessage:       "Beneficiary bank declined payment credit: account invalid or blocked.",
			InitiatedAt:        time.Now().UTC(),
		}
		p.transfers[providerTransferID] = res
		return res, nil
	}

	// Scenario 2: Network timeout / Ambiguous in-flight simulation
	if strings.Contains(req.Narration, "TIMEOUT") || strings.HasSuffix(req.AccountNumber, "9999") {
		// Recorded in provider memory as processing, but caller experiences timeout
		res := TransferResult{
			ProviderTransferID: providerTransferID,
			Status:             "processing",
			InitiatedAt:        time.Now().UTC(),
		}
		p.transfers[providerTransferID] = res
		return res, ErrProviderTimeout
	}

	// Scenario 3: Standard immediate success
	utr := fmt.Sprintf("QA_UTR_%s_%d", req.TransferID[:8], time.Now().UnixNano()%100000000)
	res := TransferResult{
		ProviderTransferID: providerTransferID,
		Status:             "succeeded",
		UTR:                utr,
		InitiatedAt:        time.Now().UTC(),
	}
	p.transfers[providerTransferID] = res
	return res, nil
}

func (p *IsolatedQAPayoutProvider) FetchTransfer(_ context.Context, providerTransferID string) (TransferResult, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	res, ok := p.transfers[providerTransferID]
	if !ok {
		return TransferResult{
			ProviderTransferID: providerTransferID,
			Status:             "failed",
			ErrorCode:          "TRANSACTION_NOT_FOUND",
			ErrorMessage:       "Transfer was not recorded at payout provider.",
		}, nil
	}

	// If it was processing/timeout, reconcile to succeeded with valid UTR
	if res.Status == "processing" {
		res.Status = "succeeded"
		res.UTR = fmt.Sprintf("QA_RECON_%s", providerTransferID)
		p.transfers[providerTransferID] = res
	}

	return res, nil
}

func (p *IsolatedQAPayoutProvider) VerifyWebhook(_ context.Context, headers http.Header, rawBody []byte) (VerifiedPayoutEvent, error) {
	sig := headers.Get("X-Grepmind-Payout-Signature")
	if sig == "" {
		return VerifiedPayoutEvent{}, fmt.Errorf("missing payout signature header")
	}

	mac := hmac.New(sha256.New, p.secret)
	mac.Write(rawBody)
	expectedSig := hex.EncodeToString(mac.Sum(nil))

	if !hmac.Equal([]byte(sig), []byte(expectedSig)) {
		return VerifiedPayoutEvent{}, fmt.Errorf("invalid payout webhook signature")
	}

	var event VerifiedPayoutEvent
	if err := json.Unmarshal(rawBody, &event); err != nil {
		return VerifiedPayoutEvent{}, fmt.Errorf("invalid payout webhook body: %w", err)
	}

	return event, nil
}

func (p *IsolatedQAPayoutProvider) SignWebhook(payload []byte) string {
	mac := hmac.New(sha256.New, p.secret)
	mac.Write(payload)
	return hex.EncodeToString(mac.Sum(nil))
}
