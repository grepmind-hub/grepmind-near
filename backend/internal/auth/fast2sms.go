package auth

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"strings"
	"time"

	"grepmind-near/backend/pkg/config"
	"grepmind-near/backend/pkg/logger"
)

const fast2SMSSendOTPEndpoint = "https://www.fast2sms.com/dev/otp/send"

// fast2SMSOTPProvider sends the backend-generated code through Fast2SMS's
// current Smart OTP template endpoint. Provider-side verification is not used:
// Grepmind remains the sole authority for challenge verification.
type fast2SMSOTPProvider struct {
	endpoint   string
	apiKey     string
	templateID string
	variables  string
	client     *http.Client
}

func newFast2SMSOTPProvider(cfg *config.Config) (*fast2SMSOTPProvider, error) {
	if cfg == nil || strings.TrimSpace(cfg.Fast2SMSAPIKey) == "" || strings.TrimSpace(cfg.Fast2SMSOTPTemplateID) == "" {
		return nil, errors.New("Fast2SMS OTP configuration is incomplete")
	}
	if cfg.Fast2SMSRequestTimeout <= 0 || cfg.Fast2SMSRequestTimeout > 20*time.Second {
		return nil, errors.New("Fast2SMS OTP timeout is invalid")
	}
	return &fast2SMSOTPProvider{
		endpoint:   fast2SMSSendOTPEndpoint,
		apiKey:     strings.TrimSpace(cfg.Fast2SMSAPIKey),
		templateID: strings.TrimSpace(cfg.Fast2SMSOTPTemplateID),
		variables:  cfg.Fast2SMSOTPVariables,
		client:     fast2SMSHTTPClient(cfg.Fast2SMSRequestTimeout),
	}, nil
}

func newFast2SMSOTPProviderForTest(endpoint, apiKey, templateID string, client *http.Client) *fast2SMSOTPProvider {
	if client == nil {
		client = fast2SMSHTTPClient(time.Second)
	} else {
		// The Authorization header contains a provider secret. Do not follow
		// redirects, which could forward credentials to an unintended host.
		client.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	}
	return &fast2SMSOTPProvider{endpoint: endpoint, apiKey: apiKey, templateID: templateID, client: client}
}

func fast2SMSHTTPClient(timeout time.Duration) *http.Client {
	return &http.Client{
		Timeout:       timeout,
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}
}

type fast2SMSSendRequest struct {
	Mobile          string `json:"mobile"`
	OTPTemplateID   string `json:"otp_id"`
	OTPExpiry       int    `json:"otp_expiry"`
	OTPLength       int    `json:"otp_length"`
	OTP             string `json:"otp"`
	VariablesValues string `json:"variables_values,omitempty"`
	UserDefined1    string `json:"udf1,omitempty"`
}

type fast2SMSSendResponse struct {
	Return     bool   `json:"return"`
	StatusCode int    `json:"status_code"`
	RequestID  string `json:"request_id"`
}

func (p *fast2SMSOTPProvider) SendOTP(ctx context.Context, delivery OTPDelivery) error {
	if p == nil || p.client == nil || ctx == nil || ctx.Err() != nil {
		return errors.New("OTP delivery unavailable")
	}
	mobile, err := fast2SMSMobile(delivery.PhoneE164)
	if err != nil || delivery.Purpose != "login" || !sixDigits(delivery.Code) || strings.TrimSpace(delivery.ChallengeID) == "" {
		p.logResult("rejected_input", 0)
		return errors.New("OTP delivery unavailable")
	}
	expiry := delivery.ExpiresAt.Sub(delivery.CreatedAt)
	if expiry <= 0 {
		p.logResult("rejected_input", 0)
		return errors.New("OTP delivery unavailable")
	}
	expiryMinutes := int(math.Ceil(expiry.Minutes()))
	if expiryMinutes < 1 || expiryMinutes > 10080 {
		p.logResult("rejected_input", 0)
		return errors.New("OTP delivery unavailable")
	}

	body, err := json.Marshal(fast2SMSSendRequest{
		Mobile: mobile, OTPTemplateID: p.templateID, OTPExpiry: expiryMinutes,
		OTPLength: len(delivery.Code), OTP: delivery.Code, VariablesValues: p.variables,
		UserDefined1: delivery.ChallengeID,
	})
	if err != nil {
		p.logResult("request_error", 0)
		return errors.New("OTP delivery unavailable")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, p.endpoint, bytes.NewReader(body))
	if err != nil {
		p.logResult("request_error", 0)
		return errors.New("OTP delivery unavailable")
	}
	req.Header.Set("Authorization", p.apiKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
	resp, err := p.client.Do(req)
	if err != nil {
		// Do not retry an ambiguous POST: the provider may have accepted the SMS
		// before a network timeout, and retrying could send duplicate codes.
		p.logResult("transport_error", 0)
		return errors.New("OTP delivery unavailable")
	}
	defer resp.Body.Close()
	if resp.StatusCode < http.StatusOK || resp.StatusCode >= http.StatusMultipleChoices {
		p.logResult("provider_rejected", resp.StatusCode)
		return errors.New("OTP delivery unavailable")
	}
	var result fast2SMSSendResponse
	if err := json.NewDecoder(io.LimitReader(resp.Body, 64*1024)).Decode(&result); err != nil || !result.Return || (result.StatusCode != 0 && result.StatusCode != http.StatusOK) {
		p.logResult("provider_rejected", resp.StatusCode)
		return errors.New("OTP delivery unavailable")
	}
	p.logResult("accepted", resp.StatusCode)
	return nil
}

func (p *fast2SMSOTPProvider) logResult(outcome string, status int) {
	event := logger.Log.Info().Str("otp_provider", "fast2sms").Str("outcome", outcome)
	if status != 0 {
		event = event.Int("http_status", status)
	}
	event.Msg("OTP delivery attempt")
}

func fast2SMSMobile(phone string) (string, error) {
	if !strings.HasPrefix(phone, "+91") || len(phone) != 13 {
		return "", fmt.Errorf("unsupported mobile number")
	}
	mobile := phone[3:]
	for _, digit := range mobile {
		if digit < '0' || digit > '9' {
			return "", fmt.Errorf("invalid mobile number")
		}
	}
	if mobile[0] < '6' || mobile[0] > '9' {
		return "", fmt.Errorf("invalid Indian mobile number")
	}
	return mobile, nil
}
