package main

import (
	"grepmind-near/backend/internal/auth"
	"grepmind-near/backend/internal/notifications"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestSensitiveRoutesRejectAnonymousRequests(t *testing.T) {
	router := setupRouter(auth.NewService(nil, nil), nil, nil, nil, notifications.NewHub(nil))
	for _, test := range []struct{ method, path string }{
		{"GET", "/api/v1/events?business_id=00000000-0000-0000-0000-000000000001"},
		{"GET", "/api/v1/notifications"},
		{"POST", "/api/v1/notifications/00000000-0000-0000-0000-000000000001/read"},
		{"POST", "/api/v1/notifications/broadcast-test"},
		{"GET", "/api/v1/requests/00000000-0000-0000-0000-000000000001"},
		{"POST", "/api/v1/businesses/00000000-0000-0000-0000-000000000001/requests"},
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
