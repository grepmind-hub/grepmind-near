package auth

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v4"
	"grepmind-near/backend/pkg/config"
)

func TestRefreshTokenHashIsDeterministicAndOneWaySized(t *testing.T) {
	first := hashToken("signed-refresh-token")
	if first != hashToken("signed-refresh-token") {
		t.Fatal("same refresh token must map to the same database lookup digest")
	}
	if len(first) != 64 {
		t.Fatalf("SHA-256 hex digest must be 64 characters, got %d", len(first))
	}
	if first == "signed-refresh-token" {
		t.Fatal("stored refresh digest must not contain the token")
	}
}

func TestParseSessionTokenRejectsExpiredAndWrongAlgorithm(t *testing.T) {
	secret := "unit-test-secret-with-more-than-32-characters"
	svc := NewService(nil, &config.Config{JWTSecret: secret})
	now := time.Now()
	for _, tc := range []struct {
		name   string
		method jwt.SigningMethod
		exp    time.Time
		valid  bool
	}{
		{name: "expired", method: jwt.SigningMethodHS256, exp: now.Add(-time.Minute)},
		{name: "valid", method: jwt.SigningMethodHS256, exp: now.Add(time.Minute), valid: true},
		{name: "wrong algorithm", method: jwt.SigningMethodHS384, exp: now.Add(time.Minute)},
	} {
		t.Run(tc.name, func(t *testing.T) {
			token, err := jwt.NewWithClaims(tc.method, sessionClaims{SessionID: "00000000-0000-4000-8000-000000000001", RegisteredClaims: jwt.RegisteredClaims{
				Subject: "user-1", Issuer: "grepmind-near", IssuedAt: jwt.NewNumericDate(now), ExpiresAt: jwt.NewNumericDate(tc.exp),
			}}).SignedString([]byte(secret))
			if err != nil {
				t.Fatal(err)
			}
			_, err = svc.parseSessionToken(token)
			if (err == nil) != tc.valid {
				t.Fatalf("valid=%v error=%v", tc.valid, err)
			}
		})
	}
}

func TestOTPRequestResponseNeverContainsCode(t *testing.T) {
	response := otpRequestResponseData("+919876543210", "9d43b8e0-0000-4000-8000-000000000001", time.Now().Add(time.Minute))
	if _, exists := response["otp_code"]; exists {
		t.Fatal("OTP request response must never disclose the code")
	}
	if response["challenge_id"] == nil {
		t.Fatal("OTP response should identify the non-secret challenge")
	}
}

func TestOTPExpiryUsesPostgresMicrosecondPrecision(t *testing.T) {
	now := time.Date(2026, time.November, 12, 19, 10, 14, 542236789, time.FixedZone("test", 2*60*60))
	expiresAt := otpExpiry(now, time.Minute)
	if expiresAt.Location() != time.UTC {
		t.Fatalf("expiry location=%v, want UTC", expiresAt.Location())
	}
	if got := expiresAt.Nanosecond(); got%int(time.Microsecond) != 0 {
		t.Fatalf("expiry nanoseconds=%d, want microsecond-aligned", got)
	}
	if want := now.Add(time.Minute).UTC().Truncate(time.Microsecond); !expiresAt.Equal(want) {
		t.Fatalf("expiry=%s, want %s", expiresAt, want)
	}
}

func TestProductionOTPRequestFailsClosedWithoutProvider(t *testing.T) {
	svc := NewService(nil, &config.Config{Env: "production", OTPProvider: "stub"})
	request := httptest.NewRequest(http.MethodPost, "/api/v1/auth/otp/request", strings.NewReader(`{"phone_e164":"+919876543210"}`))
	response := httptest.NewRecorder()
	svc.RequestOTP(response, request)
	if response.Code != http.StatusServiceUnavailable {
		t.Fatalf("status=%d, want 503", response.Code)
	}
	if strings.Contains(response.Body.String(), "otp_code") {
		t.Fatalf("production response disclosed an OTP: %s", response.Body.String())
	}
}

func TestQAHTTPOTPProviderUsesAuthenticatedPrivateDelivery(t *testing.T) {
	var received bool
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/internal/v1/deliver" || r.Header.Get("Authorization") != "Bearer writer-token-that-is-long-enough-for-tests" {
			t.Fatalf("unexpected QA delivery request")
		}
		received = true
		w.WriteHeader(http.StatusCreated)
	}))
	defer server.Close()
	provider, err := newQAHTTPOTPProvider(server.URL, "writer-token-that-is-long-enough-for-tests")
	if err != nil {
		t.Fatal(err)
	}
	delivery := OTPDelivery{ChallengeID: "9d43b8e0-0000-4000-8000-000000000001", PhoneE164: "+919000000001", Purpose: "login", Code: "012345", CreatedAt: time.Now(), ExpiresAt: time.Now().Add(time.Minute), RunID: "qa-test-run-00000001"}
	if err := provider.SendOTP(context.Background(), delivery); err != nil {
		t.Fatal("private QA delivery failed")
	}
	if !received {
		t.Fatal("QA inbox did not receive the challenge")
	}
	if _, err := newQAHTTPOTPProvider("https://user:pass@example.test", "writer-token-that-is-long-enough-for-tests"); err == nil {
		t.Fatal("userinfo URL must be rejected")
	}
}

func TestRemoteIPUsesRealAddressOnlyBehindPrivateProxy(t *testing.T) {
	request := httptest.NewRequest(http.MethodPost, "/", nil)
	request.RemoteAddr = "172.18.0.3:8080"
	request.Header.Set("X-Real-IP", "203.0.113.42")
	if got := remoteIP(request); got != "203.0.113.42" {
		t.Fatalf("trusted private proxy address=%q", got)
	}
	request.RemoteAddr = "198.51.100.9:8080"
	request.Header.Set("X-Real-IP", "203.0.113.42")
	if got := remoteIP(request); got != "198.51.100.9" {
		t.Fatalf("untrusted peer must not control its rate-limit address, got %q", got)
	}
}

func TestOTPRateLimiterAppliesLimitsUnderConcurrency(t *testing.T) {
	limiter := newOTPRateLimiter()
	now := time.Now()
	var mu sync.Mutex
	allowed := 0
	var wg sync.WaitGroup
	for i := 0; i < 50; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if limiter.allow("phone", "+919876543210", now, 5, time.Minute) {
				mu.Lock()
				allowed++
				mu.Unlock()
			}
		}()
	}
	wg.Wait()
	if allowed != 5 {
		t.Fatalf("expected exactly five requests within window, got %d", allowed)
	}
	if !limiter.allow("phone", "+919876543210", now.Add(time.Minute), 5, time.Minute) {
		t.Fatal("rate limit should reset after the fixed window")
	}
}
