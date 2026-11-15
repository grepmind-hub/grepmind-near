package payouts

import (
	"context"
	"net/http"
)

type DisabledProductionProvider struct {
	reason string
}

func NewDisabledProductionProvider(reason string) *DisabledProductionProvider {
	if reason == "" {
		reason = "production payout transfers are disabled by operational fail-closed policy"
	}
	return &DisabledProductionProvider{reason: reason}
}

func (d *DisabledProductionProvider) Name() string {
	return "disabled_production"
}

func (d *DisabledProductionProvider) ValidateBeneficiary(_ context.Context, _ BeneficiaryValidationRequest) (BeneficiaryValidationResult, error) {
	return BeneficiaryValidationResult{}, ErrRealMoneyPayoutDisabled
}

func (d *DisabledProductionProvider) InitiateTransfer(_ context.Context, _ TransferRequest) (TransferResult, error) {
	return TransferResult{}, ErrRealMoneyPayoutDisabled
}

func (d *DisabledProductionProvider) FetchTransfer(_ context.Context, _ string) (TransferResult, error) {
	return TransferResult{}, ErrRealMoneyPayoutDisabled
}

func (d *DisabledProductionProvider) VerifyWebhook(_ context.Context, _ http.Header, _ []byte) (VerifiedPayoutEvent, error) {
	return VerifiedPayoutEvent{}, ErrRealMoneyPayoutDisabled
}
