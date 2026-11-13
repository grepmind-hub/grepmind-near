package auth

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// qaHTTPOTPProvider sends OTPs to the isolated, root-owned QA inbox sidecar.
// The public API process never mounts or reads the inbox filesystem.
type qaHTTPOTPProvider struct {
	endpoint string
	token    string
	client   *http.Client
}

func newQAHTTPOTPProvider(endpoint, token string) (*qaHTTPOTPProvider, error) {
	endpoint = strings.TrimRight(strings.TrimSpace(endpoint), "/")
	parsed, err := url.Parse(endpoint)
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Host == "" || parsed.User != nil || parsed.RawQuery != "" || parsed.Fragment != "" || len(token) < 32 {
		return nil, errors.New("QA OTP delivery configuration is incomplete")
	}
	return &qaHTTPOTPProvider{endpoint: endpoint + "/internal/v1/deliver", token: token, client: &http.Client{Timeout: 3 * time.Second}}, nil
}

func (p *qaHTTPOTPProvider) SendOTP(ctx context.Context, delivery OTPDelivery) error {
	if p == nil || ctx.Err() != nil {
		return errors.New("QA OTP delivery unavailable")
	}
	body, err := json.Marshal(map[string]any{
		"challenge_id": delivery.ChallengeID,
		"phone_e164":   delivery.PhoneE164,
		"purpose":      delivery.Purpose,
		"code":         delivery.Code,
		"created_at":   delivery.CreatedAt,
		"expires_at":   delivery.ExpiresAt,
		"run_id":       delivery.RunID,
	})
	if err != nil {
		return errors.New("QA OTP delivery unavailable")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, p.endpoint, bytes.NewReader(body))
	if err != nil {
		return errors.New("QA OTP delivery unavailable")
	}
	req.Header.Set("Authorization", "Bearer "+p.token)
	req.Header.Set("Content-Type", "application/json")
	resp, err := p.client.Do(req)
	if err != nil {
		return errors.New("QA OTP delivery unavailable")
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated {
		return errors.New("QA OTP delivery unavailable")
	}
	return nil
}
