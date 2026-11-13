package payments

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

const sandboxProviderName = "grepmind_sandbox"

var ErrInvalidWebhook = errors.New("provider webhook verification failed")

// SandboxProvider is deterministic and in-memory. It has no network client,
// payment rail, or live-provider credentials. Use only in isolated QA/tests.
type SandboxProvider struct {
	secret   []byte
	keyID    string
	keys     map[string][]byte
	maxAge   time.Duration
	mu       sync.RWMutex
	payments map[string]ProviderPayment
	refunds  map[string]ProviderRefund
}

func NewSandboxProvider(secret []byte, keyID string, maxAge time.Duration) (*SandboxProvider, error) {
	if len(secret) < 32 || strings.TrimSpace(keyID) == "" || maxAge < 30*time.Second || maxAge > 15*time.Minute {
		return nil, errors.New("sandbox provider requires a 32-byte secret, key ID, and bounded freshness window")
	}
	return &SandboxProvider{secret: append([]byte(nil), secret...), keyID: keyID, keys: map[string][]byte{keyID: append([]byte(nil), secret...)}, maxAge: maxAge, payments: make(map[string]ProviderPayment), refunds: make(map[string]ProviderRefund)}, nil
}

// ProviderForEnvironment only exposes the in-memory fake in explicit qa/test
// deployments. Local, staging, and production processes stay fail-closed.
func ProviderForEnvironment(environment string) PaymentProvider {
	if environment != "qa" && environment != "test" {
		return UnconfiguredProvider{}
	}
	if os.Getenv("PAYMENT_SANDBOX_ENABLED") != "true" {
		return UnconfiguredProvider{}
	}
	secret := []byte(os.Getenv("PAYMENT_SANDBOX_WEBHOOK_SECRET"))
	keyID := os.Getenv("PAYMENT_SANDBOX_WEBHOOK_KEY_ID")
	provider, err := NewSandboxProvider(secret, keyID, 5*time.Minute)
	if err != nil {
		return UnconfiguredProvider{}
	}
	previousID, previousSecret := os.Getenv("PAYMENT_SANDBOX_WEBHOOK_PREVIOUS_KEY_ID"), []byte(os.Getenv("PAYMENT_SANDBOX_WEBHOOK_PREVIOUS_SECRET"))
	if previousID != "" && len(previousSecret) >= 32 {
		_ = provider.AddVerificationKey(previousID, previousSecret, false)
	}
	return provider
}

func (p *SandboxProvider) Name() string { return sandboxProviderName }

// AddVerificationKey supports overlap during key rotation. Existing keys stay
// valid until the operator removes the old provider process/configuration.
func (p *SandboxProvider) AddVerificationKey(keyID string, secret []byte, makeCurrent bool) error {
	if strings.TrimSpace(keyID) == "" || len(secret) < 32 {
		return errors.New("sandbox verification key is invalid")
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	p.keys[keyID] = append([]byte(nil), secret...)
	if makeCurrent {
		p.keyID = keyID
		p.secret = append([]byte(nil), secret...)
	}
	return nil
}

func (p *SandboxProvider) CreateSession(_ context.Context, request CreateSessionRequest) (ProviderSession, error) {
	if request.AmountMinor <= 0 || request.Currency != "INR" || request.IdempotencyKey == "" || request.IntentID == "" {
		return ProviderSession{}, ErrInvalidProviderRequest
	}
	// Stable opaque reference makes provider retries deterministic.
	reference := "qa_" + shortHash(request.IdempotencyKey+":"+request.IntentID)
	p.mu.Lock()
	if _, ok := p.payments[reference]; !ok {
		p.payments[reference] = ProviderPayment{Reference: reference, Status: "pending", AmountMinor: request.AmountMinor, Currency: request.Currency}
	}
	p.mu.Unlock()
	return ProviderSession{Reference: reference, LaunchURL: "sandbox://payment/" + reference, ExpiresAt: request.ExpiresAt.UTC()}, nil
}

func (p *SandboxProvider) VerifyWebhook(_ context.Context, headers http.Header, rawBody []byte) (VerifiedProviderEvent, error) {
	if len(rawBody) == 0 || len(rawBody) > 16*1024 || len(headers.Get("X-Grepmind-Sandbox-Signature")) > 512 {
		return VerifiedProviderEvent{}, ErrInvalidWebhook
	}
	parts := strings.Split(headers.Get("X-Grepmind-Sandbox-Signature"), ",")
	var timestamp, signature, keyID string
	for _, part := range parts {
		k, v, ok := strings.Cut(strings.TrimSpace(part), "=")
		if !ok {
			continue
		}
		switch k {
		case "t":
			timestamp = v
		case "v1":
			signature = v
		case "kid":
			keyID = v
		}
	}
	seconds, err := strconv.ParseInt(timestamp, 10, 64)
	p.mu.RLock()
	key, ok := p.keys[keyID]
	key = append([]byte(nil), key...)
	p.mu.RUnlock()
	if err != nil || !ok || signature == "" {
		return VerifiedProviderEvent{}, ErrInvalidWebhook
	}
	eventTime := time.Unix(seconds, 0)
	if age := time.Since(eventTime); age > p.maxAge || age < -p.maxAge {
		return VerifiedProviderEvent{}, ErrInvalidWebhook
	}
	mac := hmac.New(sha256.New, key)
	_, _ = fmt.Fprintf(mac, "%d.", seconds)
	_, _ = mac.Write(rawBody)
	want, decodeErr := hex.DecodeString(signature)
	if decodeErr != nil || !hmac.Equal(want, mac.Sum(nil)) {
		return VerifiedProviderEvent{}, ErrInvalidWebhook
	}
	var event VerifiedProviderEvent
	decoder := json.NewDecoder(bytes.NewReader(rawBody))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&event); err != nil {
		return VerifiedProviderEvent{}, ErrInvalidWebhook
	}
	if err := decoder.Decode(new(any)); err != io.EOF {
		return VerifiedProviderEvent{}, ErrInvalidWebhook
	}
	if event.Provider != p.Name() || event.EventID == "" || event.ProviderReference == "" || event.AmountMinor <= 0 || event.Currency != "INR" || !validProviderStatus(event.Status) || event.EventAt.IsZero() || event.EventAt.After(time.Now().Add(p.maxAge)) {
		return VerifiedProviderEvent{}, ErrInvalidWebhook
	}
	if event.ObjectType == "" {
		event.ObjectType = "payment"
	}
	if event.ObjectType != "payment" && event.ObjectType != "refund" {
		return VerifiedProviderEvent{}, ErrInvalidWebhook
	}
	if event.ObjectType == "refund" && event.Status != "pending" && event.Status != "succeeded" && event.Status != "failed" {
		return VerifiedProviderEvent{}, ErrInvalidWebhook
	}
	return event, nil
}

func (p *SandboxProvider) FetchPayment(_ context.Context, reference string) (ProviderPayment, error) {
	p.mu.RLock()
	defer p.mu.RUnlock()
	payment, ok := p.payments[reference]
	if !ok {
		return ProviderPayment{}, sql.ErrNoRows
	}
	return payment, nil
}

func (p *SandboxProvider) CreateRefund(_ context.Context, request CreateRefundRequest) (ProviderRefund, error) {
	if request.AmountMinor <= 0 || request.Currency != "INR" || request.IdempotencyKey == "" || request.RefundID == "" || request.PaymentReference == "" {
		return ProviderRefund{}, ErrInvalidProviderRequest
	}
	ref := "qrf_" + shortHash(request.IdempotencyKey+":"+request.RefundID)
	p.mu.Lock()
	defer p.mu.Unlock()
	if existing, ok := p.refunds[ref]; ok {
		return existing, nil
	}
	captured, ok := p.payments[request.PaymentReference]
	if !ok || captured.Status != "succeeded" || captured.Currency != request.Currency || request.AmountMinor > captured.AmountMinor {
		return ProviderRefund{}, sql.ErrNoRows
	}
	out := ProviderRefund{Reference: ref, PaymentReference: request.PaymentReference, Status: "pending", AmountMinor: request.AmountMinor, Currency: request.Currency}
	p.refunds[ref] = out
	return out, nil
}

func (p *SandboxProvider) FetchRefund(_ context.Context, reference string) (ProviderRefund, error) {
	p.mu.RLock()
	defer p.mu.RUnlock()
	value, ok := p.refunds[reference]
	if !ok {
		return ProviderRefund{}, sql.ErrNoRows
	}
	return value, nil
}

// SetRefund is an in-process test control. HTTP simulation is separately
// restricted to explicitly allowlisted QA identities.
func (p *SandboxProvider) SetRefund(refund ProviderRefund) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.refunds[refund.Reference] = refund
}

// SetPayment is an explicit test/QA control, not an HTTP operation.
func (p *SandboxProvider) SetPayment(payment ProviderPayment) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.payments[payment.Reference] = payment
}

func (p *SandboxProvider) Sign(rawBody []byte, at time.Time) string {
	p.mu.RLock()
	secret := append([]byte(nil), p.secret...)
	keyID := p.keyID
	p.mu.RUnlock()
	mac := hmac.New(sha256.New, secret)
	_, _ = fmt.Fprintf(mac, "%d.", at.Unix())
	_, _ = mac.Write(rawBody)
	return fmt.Sprintf("t=%d,kid=%s,v1=%s", at.Unix(), keyID, hex.EncodeToString(mac.Sum(nil)))
}

func validProviderStatus(s string) bool {
	switch s {
	case "pending", "succeeded", "failed", "expired":
		return true
	default:
		return false
	}
}

func shortHash(value string) string {
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:12])
}
