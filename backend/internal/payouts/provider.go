package payouts

import (
	"context"
	"errors"
	"net/http"
	"time"
)

var (
	ErrProviderUnavailable    = errors.New("payout provider is not configured")
	ErrInvalidProviderRequest = errors.New("invalid payout provider request")
	ErrBeneficiaryUnverified  = errors.New("bank beneficiary is not verified")
	ErrAttemptInFlight        = errors.New("a transfer attempt is currently in flight or unresolved")
	ErrRealMoneyPayoutDisabled = errors.New("real-money payouts are disabled by operational fail-closed policy")
	ErrProviderTimeout        = errors.New("provider response timed out; transfer outcome is pending reconciliation")
)

type PayoutProvider interface {
	Name() string
	ValidateBeneficiary(ctx context.Context, req BeneficiaryValidationRequest) (BeneficiaryValidationResult, error)
	InitiateTransfer(ctx context.Context, req TransferRequest) (TransferResult, error)
	FetchTransfer(ctx context.Context, providerTransferID string) (TransferResult, error)
	VerifyWebhook(ctx context.Context, headers http.Header, rawBody []byte) (VerifiedPayoutEvent, error)
}

type BeneficiaryValidationRequest struct {
	BeneficiaryID string
	AccountHolder string
	AccountNumber string
	IFSC          string
	Phone         string
}

type BeneficiaryValidationResult struct {
	ProviderBeneficiaryID string
	Status                string // "verified", "rejected"
	RegisteredName        string
	FailureReason         string
	Evidence              map[string]any
}

type TransferRequest struct {
	TransferID     string // Grepmind internal UUID
	AttemptNumber  int
	IdempotencyKey string
	BeneficiaryID  string
	ProviderBeneID string
	AccountNumber  string
	IFSC           string
	AccountHolder  string
	AmountMinor    int64
	Currency       string
	Purpose        string
	Narration      string
}

type TransferResult struct {
	ProviderTransferID string    `json:"provider_transfer_id"`
	Status             string    `json:"status"` // "succeeded", "processing", "failed", "timeout"
	UTR                string    `json:"utr"`
	ErrorCode          string    `json:"error_code,omitempty"`
	ErrorMessage       string    `json:"error_message,omitempty"`
	InitiatedAt        time.Time `json:"initiated_at"`
}

type VerifiedPayoutEvent struct {
	Provider           string    `json:"provider"`
	EventID            string    `json:"event_id"`
	ProviderTransferID string    `json:"provider_transfer_id"`
	TransferID         string    `json:"transfer_id"`
	EventType          string    `json:"event_type"` // "payout.processed", "payout.failed", "payout.reversed"
	Status             string    `json:"status"`     // "succeeded", "failed", "reversed"
	AmountMinor        int64     `json:"amount_minor"`
	UTR                string    `json:"utr"`
	FailureReason      string    `json:"failure_reason,omitempty"`
	EventAt            time.Time `json:"event_at"`
}
