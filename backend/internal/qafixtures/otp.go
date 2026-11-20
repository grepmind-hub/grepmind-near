package qafixtures

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"
	"grepmind-near/backend/internal/qaotpinbox"
)

var (
	syntheticPhone = regexp.MustCompile(`^\+9199900001[0-9]{2}$`)
	otpCode        = regexp.MustCompile(`^[0-9]{6}$`)
)

type otpChallenge struct {
	ID        string `json:"challenge_id"`
	Phone     string `json:"phone_e164"`
	ExpiresAt string `json:"expires_at"`
}

// ScopeOTPReader uses the isolated inbox's single-use reader capability.
type ScopeOTPReader struct {
	endpoint string
	runID    string
	runnerID string
	secret   string
	client   *http.Client
}

func NewScopeOTPReader(origin, runID, runnerID, secret string) (*ScopeOTPReader, error) {
	u, err := url.Parse(origin)
	if err != nil || u.Scheme != "http" || (u.Hostname() != "127.0.0.1" && u.Hostname() != "localhost") ||
		u.User != nil || (u.Path != "" && u.Path != "/") || u.ForceQuery || u.RawQuery != "" || u.Fragment != "" {
		return nil, errors.New("QA OTP reader requires a loopback HTTP origin")
	}
	if runID == "" || runnerID == "" || secret == "" {
		return nil, errors.New("scoped QA OTP reader configuration is incomplete")
	}
	u.Path = "/v1/read"
	return &ScopeOTPReader{endpoint: u.String(), runID: runID, runnerID: runnerID, secret: secret, client: scopedHTTPClient()}, nil
}

func scopedHTTPClient() *http.Client {
	return &http.Client{
		Timeout:       10 * time.Second,
		Transport:     &http.Transport{},
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}
}

func (r *ScopeOTPReader) read(ctx context.Context, phone string, challenge otpChallenge) (string, error) {
	expires, expiryErr := time.Parse(time.RFC3339Nano, challenge.ExpiresAt)
	if _, err := uuid.Parse(challenge.ID); err != nil || expiryErr != nil || !expires.After(time.Now()) || challenge.Phone != phone {
		return "", errors.New("QA OTP challenge scope is invalid or expired")
	}
	scope := qaotpinbox.Scope{ChallengeID: challenge.ID, PhoneE164: phone, Purpose: "login", RunID: r.runID, ExpiresAt: challenge.ExpiresAt}
	body, err := json.Marshal(scope)
	if err != nil {
		return "", errors.New("could not encode QA OTP scope")
	}
	mac := hmac.New(sha256.New, []byte(r.secret))
	_, _ = mac.Write([]byte(strings.Join([]string{r.runnerID, scope.RunID, scope.ChallengeID, scope.PhoneE164, scope.Purpose, scope.ExpiresAt}, "\x00")))
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, r.endpoint, bytes.NewReader(body))
	if err != nil {
		return "", errors.New("could not create scoped QA OTP request")
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+hex.EncodeToString(mac.Sum(nil)))
	req.Header.Set("X-QA-Runner-ID", r.runnerID)
	res, err := r.client.Do(req)
	if err != nil {
		return "", errors.New("scoped QA OTP reader request failed")
	}
	defer res.Body.Close()
	var payload struct {
		Code string `json:"code"`
	}
	if res.StatusCode != http.StatusOK || json.NewDecoder(io.LimitReader(res.Body, 4096)).Decode(&payload) != nil || !otpCode.MatchString(payload.Code) {
		return "", errors.New("scoped QA OTP reader rejected the challenge or returned an invalid code")
	}
	return payload.Code, nil
}
