package riderearnings

import (
	"net/http/httptest"
	"testing"
)

func TestDateRangeRejectsInvalidAndUnboundedRequests(t *testing.T) {
	for _, query := range []string{"?from=not-a-date", "?from=2024-01-01T00:00:00Z&to=2025-01-02T00:00:00Z", "?from=2025-02-01T00:00:00Z&to=2025-01-01T00:00:00Z"} {
		t.Run(query, func(t *testing.T) {
			r := httptest.NewRequest("GET", "/api/v1/rider/earnings/summary"+query, nil)
			w := httptest.NewRecorder()
			if _, _, ok := dateRange(w, r); ok || w.Code != 400 {
				t.Fatalf("dateRange(%q) = ok %v, status %d", query, ok, w.Code)
			}
		})
	}
}

func TestPageBoundsAreEnforced(t *testing.T) {
	for _, query := range []string{"?limit=0", "?limit=101", "?offset=-1", "?offset=10001", "?limit=large"} {
		r := httptest.NewRequest("GET", "/api/v1/rider/earnings"+query, nil)
		w := httptest.NewRecorder()
		if _, _, ok := page(w, r); ok || w.Code != 400 {
			t.Fatalf("page(%q) = ok %v, status %d", query, ok, w.Code)
		}
	}
	for _, query := range []string{"", "?limit=100&offset=10000"} {
		r := httptest.NewRequest("GET", "/api/v1/rider/earnings"+query, nil)
		w := httptest.NewRecorder()
		if _, _, ok := page(w, r); !ok {
			t.Fatalf("page(%q) rejected a valid bound", query)
		}
	}
}

func TestValidCurrencyRequiresThreeUppercaseAsciiLetters(t *testing.T) {
	for _, tc := range []struct {
		value string
		valid bool
	}{{"INR", true}, {"USD", true}, {"", false}, {"inr", false}, {"US1", false}, {"EURO", false}} {
		if got := validCurrency(tc.value); got != tc.valid {
			t.Errorf("validCurrency(%q)=%v, want %v", tc.value, got, tc.valid)
		}
	}
}
