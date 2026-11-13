package auth

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestFast2SMSUsesServerGeneratedOTPAndCurrentTemplateContract(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != "/dev/otp/send" {
			t.Errorf("request=%s %s", r.Method, r.URL.Path)
		}
		if got := r.Header.Get("Authorization"); got != "test-server-api-key" {
			t.Errorf("authorization header not set to server API key")
		}
		if got := r.Header.Get("Content-Type"); got != "application/json" {
			t.Errorf("content type=%q", got)
		}
		var payload fast2SMSSendRequest
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Errorf("decode provider request: %v", err)
		}
		if payload.Mobile != "9876543210" || payload.OTPTemplateID != "approved-template" || payload.OTP != "012345" || payload.OTPLength != 6 || payload.OTPExpiry != 2 || payload.VariablesValues != "{otp}|Grepmind" || payload.UserDefined1 != "9d43b8e0-0000-4000-8000-000000000001" {
			t.Errorf("provider payload did not preserve configured template and generated challenge: %+v", payload)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"return":true,"status_code":200,"request_id":"provider-reference"}`))
	}))
	defer server.Close()

	provider := newFast2SMSOTPProviderForTest(server.URL+"/dev/otp/send", "test-server-api-key", "approved-template", server.Client())
	provider.variables = "{otp}|Grepmind"
	delivery := OTPDelivery{
		ChallengeID: "9d43b8e0-0000-4000-8000-000000000001",
		PhoneE164:   "+919876543210",
		Purpose:     "login",
		Code:        "012345",
		CreatedAt:   time.Now(),
		ExpiresAt:   time.Now().Add(61 * time.Second),
	}
	if err := provider.SendOTP(context.Background(), delivery); err != nil {
		t.Fatalf("SendOTP() error = %v", err)
	}
}

func TestFast2SMSProviderFailuresAreGenericAndNeverRetried(t *testing.T) {
	cases := []struct {
		name      string
		handler   http.HandlerFunc
		client    *http.Client
		wantCalls int
	}{
		{
			name: "provider rejects",
			handler: func(w http.ResponseWriter, _ *http.Request) {
				w.WriteHeader(http.StatusTooManyRequests)
				_, _ = w.Write([]byte(`{"return":false,"error":"do not expose provider body"}`))
			},
			client: &http.Client{Timeout: time.Second}, wantCalls: 1,
		},
		{
			name: "malformed acceptance",
			handler: func(w http.ResponseWriter, _ *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				_, _ = w.Write([]byte(`{"return":false,"error":"do not expose provider body"}`))
			},
			client: &http.Client{Timeout: time.Second}, wantCalls: 1,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			calls := 0
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				calls++
				tc.handler(w, r)
			}))
			defer server.Close()
			provider := newFast2SMSOTPProviderForTest(server.URL, "key", "template", tc.client)
			err := provider.SendOTP(context.Background(), validFast2SMSDelivery())
			if err == nil || strings.Contains(err.Error(), "provider body") || strings.Contains(err.Error(), "012345") {
				t.Fatalf("expected generic delivery error, got %v", err)
			}
			if calls != tc.wantCalls {
				t.Fatalf("provider request count=%d, want %d", calls, tc.wantCalls)
			}
		})
	}

	t.Run("timeout ambiguous POST is not retried", func(t *testing.T) {
		calls := 0
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			calls++
			// Hold the response beyond the client deadline, then return so the
			// test server can always shut down cleanly on platforms where client
			// cancellation is not propagated to an in-flight handler immediately.
			timer := time.NewTimer(100 * time.Millisecond)
			defer timer.Stop()
			<-timer.C
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(`{"return":true,"status_code":200}`))
		}))
		defer server.Close()
		provider := newFast2SMSOTPProviderForTest(server.URL, "key", "template", &http.Client{Timeout: 10 * time.Millisecond})
		if err := provider.SendOTP(context.Background(), validFast2SMSDelivery()); err == nil {
			t.Fatal("timeout should fail closed")
		}
		if calls != 1 {
			t.Fatalf("ambiguous provider POST count=%d, want exactly one", calls)
		}
	})
}

func TestFast2SMSRejectsUnsupportedOrMalformedDelivery(t *testing.T) {
	provider := newFast2SMSOTPProviderForTest("https://example.invalid", "key", "template", &http.Client{Timeout: time.Second})
	for _, tc := range []struct {
		name string
		edit func(*OTPDelivery)
	}{
		{name: "non India phone", edit: func(d *OTPDelivery) { d.PhoneE164 = "+14155550100" }},
		{name: "invalid Indian phone", edit: func(d *OTPDelivery) { d.PhoneE164 = "+910123456789" }},
		{name: "non login purpose", edit: func(d *OTPDelivery) { d.Purpose = "registration" }},
		{name: "invalid code", edit: func(d *OTPDelivery) { d.Code = "12345x" }},
		{name: "expired challenge", edit: func(d *OTPDelivery) { d.ExpiresAt = d.CreatedAt }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			delivery := validFast2SMSDelivery()
			tc.edit(&delivery)
			err := provider.SendOTP(context.Background(), delivery)
			if err == nil || err.Error() != "OTP delivery unavailable" {
				t.Fatalf("expected generic validation error, got %v", err)
			}
		})
	}
}

func TestFast2SMSDoesNotForwardProviderSecretAcrossRedirect(t *testing.T) {
	var redirected bool
	target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		redirected = true
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"return":true,"status_code":200}`))
	}))
	defer target.Close()
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Location", target.URL)
		w.WriteHeader(http.StatusTemporaryRedirect)
	}))
	defer origin.Close()
	provider := newFast2SMSOTPProviderForTest(origin.URL, "server-only-secret", "template", &http.Client{Timeout: time.Second})
	if err := provider.SendOTP(context.Background(), validFast2SMSDelivery()); err == nil {
		t.Fatal("redirect response must fail closed")
	}
	if redirected {
		t.Fatal("provider client must not follow redirects with its API credential")
	}
}

func validFast2SMSDelivery() OTPDelivery {
	now := time.Now()
	return OTPDelivery{
		ChallengeID: "9d43b8e0-0000-4000-8000-000000000001",
		PhoneE164:   "+919876543210",
		Purpose:     "login",
		Code:        "012345",
		CreatedAt:   now,
		ExpiresAt:   now.Add(time.Minute),
	}
}
