package payouts

import (
	"context"
	"net/http"
	"os"
	"strings"
	"testing"
)

func TestBeneficiaryEncryptionAndMasking(t *testing.T) {
	plainAcc := "1234567890123456"

	encrypted, err := encryptAccountNumber(plainAcc)
	if err != nil {
		t.Fatalf("Failed to encrypt account number: %v", err)
	}

	decrypted, err := decryptAccountNumber(encrypted)
	if err != nil {
		t.Fatalf("Failed to decrypt account number: %v", err)
	}

	if decrypted != plainAcc {
		t.Errorf("Decrypted mismatch: got %s, want %s", decrypted, plainAcc)
	}

	masked := maskAccountNumber(plainAcc)
	expectedMask := "XXXXXXXXXXXX3456"
	if masked != expectedMask {
		t.Errorf("Masked mismatch: got %s, want %s", masked, expectedMask)
	}

	hmacVal := hashAccountNumber(plainAcc)
	if len(hmacVal) != 32 {
		t.Errorf("Expected 32-byte HMAC hash, got %d bytes", len(hmacVal))
	}
}

func TestKeyRotationAndHistoricalDecryption(t *testing.T) {
	// Step 1: Encrypt under V1 key
	os.Unsetenv("PAYOUT_BENEFICIARY_ENCRYPTION_KEY_V2")
	plainAcc := "9876543210987654"

	v1Ciphertext, err := encryptAccountNumber(plainAcc)
	if err != nil {
		t.Fatalf("V1 encryption failed: %v", err)
	}
	if !strings.HasPrefix(string(v1Ciphertext), "v1:") {
		t.Errorf("Expected v1: prefix, got %s", string(v1Ciphertext[:3]))
	}

	// Step 2: Rotate key to V2
	os.Setenv("PAYOUT_BENEFICIARY_ENCRYPTION_KEY_V2", "grepmind_qa_bene_aes_v2_key_32b_")
	defer os.Unsetenv("PAYOUT_BENEFICIARY_ENCRYPTION_KEY_V2")

	// Step 3: New encryptions must use V2
	v2Ciphertext, err := encryptAccountNumber("1111222233334444")
	if err != nil {
		t.Fatalf("V2 encryption failed: %v", err)
	}
	if !strings.HasPrefix(string(v2Ciphertext), "v2:") {
		t.Errorf("Expected v2: prefix, got %s", string(v2Ciphertext[:3]))
	}

	// Step 4: Historical V1 ciphertext must decrypt seamlessly under rotated configuration
	historicalDecrypted, err := decryptAccountNumber(v1Ciphertext)
	if err != nil {
		t.Fatalf("Historical V1 decryption failed after rotation: %v", err)
	}
	if historicalDecrypted != plainAcc {
		t.Errorf("Historical decrypted mismatch: got %s, want %s", historicalDecrypted, plainAcc)
	}

	// Step 5: V2 ciphertext decrypts cleanly
	v2Decrypted, err := decryptAccountNumber(v2Ciphertext)
	if err != nil {
		t.Fatalf("V2 decryption failed: %v", err)
	}
	if v2Decrypted != "1111222233334444" {
		t.Errorf("V2 decrypted mismatch: got %s, want 1111222233334444", v2Decrypted)
	}
}

func TestDisabledProductionProvider(t *testing.T) {
	dp := &DisabledProductionProvider{}

	_, err := dp.ValidateBeneficiary(context.Background(), BeneficiaryValidationRequest{})
	if err != ErrRealMoneyPayoutDisabled {
		t.Errorf("Expected ErrRealMoneyPayoutDisabled, got %v", err)
	}

	_, err = dp.InitiateTransfer(context.Background(), TransferRequest{})
	if err != ErrRealMoneyPayoutDisabled {
		t.Errorf("Expected ErrRealMoneyPayoutDisabled, got %v", err)
	}

	_, err = dp.FetchTransfer(context.Background(), "tx_123")
	if err != ErrRealMoneyPayoutDisabled {
		t.Errorf("Expected ErrRealMoneyPayoutDisabled, got %v", err)
	}
}

func TestQAProviderWebhookVerification(t *testing.T) {
	secret := []byte("qa_isolated_payout_webhook_secret_key_32_bytes_min!")
	qp := NewIsolatedQAPayoutProvider(secret)
	ctx := context.Background()

	rawBody := []byte(`{"provider":"grepmind_qa_payout","event_id":"evt_1","status":"reversed"}`)
	sig := qp.SignWebhook(rawBody)

	headers := http.Header{}
	headers.Set("X-Grepmind-Payout-Signature", sig)

	evt, err := qp.VerifyWebhook(ctx, headers, rawBody)
	if err != nil {
		t.Fatalf("Valid webhook signature failed verification: %v", err)
	}
	if evt.Status != "reversed" {
		t.Errorf("Expected status 'reversed', got %s", evt.Status)
	}

	// Invalid signature
	headers.Set("X-Grepmind-Payout-Signature", "deadbeef0000111122223333444455556666777788889999aaaabbbbccccdddd")
	_, err = qp.VerifyWebhook(ctx, headers, rawBody)
	if err == nil {
		t.Error("Expected error for invalid signature, got nil")
	}
}

func TestFailClosedInProductionAndStaging(t *testing.T) {
	environments := []string{"production", "staging"}

	for _, env := range environments {
		t.Run("Env_"+env, func(t *testing.T) {
			dp := NewDisabledProductionProvider("fail-closed test")

			// 1. Verify disabled provider rejects beneficiary validation
			_, err := dp.ValidateBeneficiary(context.Background(), BeneficiaryValidationRequest{
				BeneficiaryID: "bene_1",
				AccountNumber: "1234567890",
				IFSC:          "SBIN0001234",
				AccountHolder: "Test Partner",
			})
			if err != ErrRealMoneyPayoutDisabled {
				t.Fatalf("[%s] Expected ErrRealMoneyPayoutDisabled from ValidateBeneficiary, got %v", env, err)
			}

			// 2. Verify disabled provider rejects transfer initiation
			_, err = dp.InitiateTransfer(context.Background(), TransferRequest{
				TransferID:    "tx_1",
				AccountNumber: "1234567890",
				AmountMinor:   50000,
			})
			if err != ErrRealMoneyPayoutDisabled {
				t.Fatalf("[%s] Expected ErrRealMoneyPayoutDisabled from InitiateTransfer, got %v", env, err)
			}

			// 3. Verify disabled provider rejects reconciliation fetching
			_, err = dp.FetchTransfer(context.Background(), "provider_tx_1")
			if err != ErrRealMoneyPayoutDisabled {
				t.Fatalf("[%s] Expected ErrRealMoneyPayoutDisabled from FetchTransfer, got %v", env, err)
			}

			// 4. Verify disabled provider rejects webhooks
			_, err = dp.VerifyWebhook(context.Background(), http.Header{}, []byte(`{}`))
			if err != ErrRealMoneyPayoutDisabled {
				t.Fatalf("[%s] Expected ErrRealMoneyPayoutDisabled from VerifyWebhook, got %v", env, err)
			}
		})
	}
}
