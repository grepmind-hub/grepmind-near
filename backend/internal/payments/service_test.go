package payments

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestUnconfiguredProviderFailsClosed(t *testing.T) {
	p := UnconfiguredProvider{}
	if p.Name() != "unconfigured" {
		t.Fatalf("provider name = %q", p.Name())
	}
	if _, err := p.CreateSession(context.Background(), CreateSessionRequest{}); !errors.Is(err, ErrProviderUnavailable) {
		t.Fatalf("CreateSession error = %v", err)
	}
	if _, err := p.VerifyWebhook(context.Background(), http.Header{}, nil); !errors.Is(err, ErrProviderUnavailable) {
		t.Fatalf("VerifyWebhook error = %v", err)
	}
	if _, err := p.FetchPayment(context.Background(), ""); !errors.Is(err, ErrProviderUnavailable) {
		t.Fatalf("FetchPayment error = %v", err)
	}
}

func TestSandboxProviderSignsExactBodyAndEnforcesFreshness(t *testing.T) {
	secret := []byte(strings.Repeat("s", 32))
	provider, err := NewSandboxProvider(secret, "qa-key-1", 5*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	event := VerifiedProviderEvent{Provider: sandboxProviderName, EventID: "evt-1", ProviderReference: "ref-1", Status: "succeeded", AmountMinor: 350, Currency: "INR", EventAt: time.Now().UTC()}
	body, err := json.Marshal(event)
	if err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest(http.MethodPost, "/", strings.NewReader(string(body)))
	req.Header.Set("X-Grepmind-Sandbox-Signature", provider.Sign(body, time.Now()))
	verified, err := provider.VerifyWebhook(context.Background(), req.Header, body)
	if err != nil || verified.EventID != event.EventID {
		t.Fatalf("valid signature rejected: event=%+v err=%v", verified, err)
	}
	mutated := append(append([]byte(nil), body...), byte(' '))
	if _, err = provider.VerifyWebhook(context.Background(), req.Header, mutated); !errors.Is(err, ErrInvalidWebhook) {
		t.Fatalf("signature accepted modified raw body: %v", err)
	}
	stale := http.Header{}
	stale.Set("X-Grepmind-Sandbox-Signature", provider.Sign(body, time.Now().Add(-10*time.Minute)))
	if _, err = provider.VerifyWebhook(context.Background(), stale, body); !errors.Is(err, ErrInvalidWebhook) {
		t.Fatalf("stale signature accepted: %v", err)
	}
	if err := provider.AddVerificationKey("qa-key-2", []byte(strings.Repeat("n", 32)), true); err != nil {
		t.Fatal(err)
	}
	rotated := http.Header{}
	rotated.Set("X-Grepmind-Sandbox-Signature", provider.Sign(body, time.Now()))
	if _, err := provider.VerifyWebhook(context.Background(), rotated, body); err != nil {
		t.Fatalf("rotated key rejected: %v", err)
	}
	if _, err := provider.VerifyWebhook(context.Background(), req.Header, body); err != nil {
		t.Fatalf("previous key rejected during rotation overlap: %v", err)
	}
}

func TestSandboxProviderIsUnavailableOutsideExplicitQATest(t *testing.T) {
	t.Setenv("PAYMENT_SANDBOX_ENABLED", "true")
	t.Setenv("PAYMENT_SANDBOX_WEBHOOK_SECRET", strings.Repeat("x", 32))
	t.Setenv("PAYMENT_SANDBOX_WEBHOOK_KEY_ID", "test-key")
	if got := ProviderForEnvironment("production").Name(); got != "unconfigured" {
		t.Fatalf("production provider=%q", got)
	}
	if got := ProviderForEnvironment("local").Name(); got != "unconfigured" {
		t.Fatalf("local provider=%q", got)
	}
	if got := ProviderForEnvironment("qa").Name(); got != sandboxProviderName {
		t.Fatalf("QA provider=%q", got)
	}
}

func TestSandboxProviderRefundIsCapturedAndIdempotent(t *testing.T) {
	provider, err := NewSandboxProvider([]byte(strings.Repeat("s", 32)), "qa-refunds", 5*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	provider.SetPayment(ProviderPayment{Reference: "qa-payment-1", Status: "pending", AmountMinor: 1000, Currency: "INR"})
	request := CreateRefundRequest{RefundID: "refund-1", PaymentReference: "qa-payment-1", IdempotencyKey: "refund-key-1", AmountMinor: 500, Currency: "INR"}
	if _, err := provider.CreateRefund(context.Background(), request); err == nil {
		t.Fatal("refund was created before a successful synthetic capture")
	}
	provider.SetPayment(ProviderPayment{Reference: "qa-payment-1", Status: "succeeded", AmountMinor: 1000, Currency: "INR"})
	first, err := provider.CreateRefund(context.Background(), request)
	if err != nil {
		t.Fatal(err)
	}
	second, err := provider.CreateRefund(context.Background(), request)
	if err != nil {
		t.Fatal(err)
	}
	if first.Reference == "" || first.Reference != second.Reference || first.Status != "pending" {
		t.Fatalf("refund retry was not stable: first=%+v second=%+v", first, second)
	}
	request.AmountMinor = 1001
	request.RefundID = "refund-too-large"
	request.IdempotencyKey = "refund-key-too-large"
	if _, err := provider.CreateRefund(context.Background(), request); err == nil {
		t.Fatal("refund larger than capture was accepted")
	}

	event := VerifiedProviderEvent{ObjectType: "refund", Provider: sandboxProviderName, EventID: "refund-event-1", ProviderReference: first.Reference, Status: "succeeded", AmountMinor: first.AmountMinor, Currency: first.Currency, EventAt: time.Now().UTC()}
	body, err := json.Marshal(event)
	if err != nil {
		t.Fatal(err)
	}
	headers := http.Header{}
	headers.Set("X-Grepmind-Sandbox-Signature", provider.Sign(body, time.Now()))
	verified, err := provider.VerifyWebhook(context.Background(), headers, body)
	if err != nil || verified.ObjectType != "refund" || verified.ProviderReference != first.Reference {
		t.Fatalf("signed refund event rejected: verified=%+v err=%v", verified, err)
	}
}
