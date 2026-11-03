package auth

import (
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

func TestOTPDisclosureIsLocalOnly(t *testing.T) {
	local := otpRequestResponseData("+919876543210", "123456", true)
	if local["otp_code"] != "123456" {
		t.Fatal("local development response should retain the stub OTP")
	}
	production := otpRequestResponseData("+919876543210", "123456", false)
	if _, exists := production["otp_code"]; exists {
		t.Fatal("non-local response must never contain the OTP")
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
