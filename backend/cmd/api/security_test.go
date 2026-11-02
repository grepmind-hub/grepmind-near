package main

import (
	"github.com/golang-jwt/jwt/v4"
	"grepmind-near/backend/internal/auth"
	"grepmind-near/backend/internal/notifications"
	"grepmind-near/backend/internal/operations"
	"grepmind-near/backend/pkg/config"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestAccessTokenClockBoundaries(t *testing.T) {
	const secret = "local-test-secret-only-not-production"
	svc := auth.NewService(nil, &config.Config{JWTSecret: secret})
	now := time.Now()
	for _, tc := range []struct {
		name            string
		issued, expires time.Time
		issuer, subject string
		method          jwt.SigningMethod
		valid           bool
	}{
		{"valid", now, now.Add(time.Hour), "grepmind-near", "test-user", jwt.SigningMethodHS256, true},
		{"small issuance skew", now.Add(2 * time.Second), now.Add(time.Hour), "grepmind-near", "test-user", jwt.SigningMethodHS256, true},
		{"future issuance", now.Add(time.Minute), now.Add(time.Hour), "grepmind-near", "test-user", jwt.SigningMethodHS256, false},
		{"expired", now.Add(-time.Hour), now.Add(-time.Second), "grepmind-near", "test-user", jwt.SigningMethodHS256, false},
		{"wrong issuer", now, now.Add(time.Hour), "other", "test-user", jwt.SigningMethodHS256, false},
		{"empty subject", now, now.Add(time.Hour), "grepmind-near", "", jwt.SigningMethodHS256, false},
		{"wrong algorithm", now, now.Add(time.Hour), "grepmind-near", "test-user", jwt.SigningMethodHS384, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			token, err := jwt.NewWithClaims(tc.method, jwt.RegisteredClaims{Subject: tc.subject, Issuer: tc.issuer, IssuedAt: jwt.NewNumericDate(tc.issued), ExpiresAt: jwt.NewNumericDate(tc.expires)}).SignedString([]byte(secret))
			if err != nil {
				t.Fatal(err)
			}
			_, err = jwtParse(token, svc)
			if (err == nil) != tc.valid {
				t.Fatalf("valid=%v error=%v", tc.valid, err)
			}
		})
	}
}

func TestSensitiveRoutesRejectAnonymousRequests(t *testing.T) {
	router := setupRouter(auth.NewService(nil, nil), nil, nil, nil, notifications.NewHub(nil), operations.NewService(nil))
	for _, test := range []struct{ method, path string }{
		{"GET", "/api/v1/events?business_id=00000000-0000-0000-0000-000000000001"},
		{"GET", "/api/v1/notifications"},
		{"POST", "/api/v1/notifications/00000000-0000-0000-0000-000000000001/read"},
		{"POST", "/api/v1/notifications/broadcast-test"},
		{"GET", "/api/v1/requests/00000000-0000-0000-0000-000000000001"},
		{"POST", "/api/v1/businesses/00000000-0000-0000-0000-000000000001/requests"},
		{"POST", "/api/v1/requests/00000000-0000-0000-0000-000000000001/cancel"},
		{"POST", "/api/v1/businesses/00000000-0000-0000-0000-000000000001/orders"},
		{"GET", "/api/v1/customer/orders"},
		{"GET", "/api/v1/orders/00000000-0000-0000-0000-000000000001"},
		{"POST", "/api/v1/orders/00000000-0000-0000-0000-000000000001/cancel"},
		{"PATCH", "/api/v1/merchant/orders/00000000-0000-0000-0000-000000000001/status"},
		{"GET", "/api/v1/admin/unserved-locations"},
		{"GET", "/api/v1/merchant/catalog-categories"},
		{"POST", "/api/v1/merchant/catalog-categories"},
		{"PATCH", "/api/v1/merchant/catalog-categories/00000000-0000-0000-0000-000000000001"},
		{"DELETE", "/api/v1/merchant/catalog-categories/00000000-0000-0000-0000-000000000001"},
	} {
		t.Run(test.method+test.path, func(t *testing.T) {
			response := httptest.NewRecorder()
			router.ServeHTTP(response, httptest.NewRequest(test.method, test.path, nil))
			if response.Code != http.StatusUnauthorized {
				t.Fatalf("expected 401, got %d", response.Code)
			}
		})
	}
}
