package moderation

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v4"
)

func TestWriteJSONEnvelope(t *testing.T) {
	rec := httptest.NewRecorder()
	payload := envelope{
		"data": map[string]string{"status": "ok"},
		"meta": map[string]string{"request_id": "test-req"},
	}

	writeJSON(rec, http.StatusOK, payload)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
		t.Fatalf("expected application/json content type, got %s", ct)
	}

	var res struct {
		Data map[string]string `json:"data"`
		Meta map[string]string `json:"meta"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &res); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if res.Data["status"] != "ok" {
		t.Errorf("expected status 'ok', got '%s'", res.Data["status"])
	}
	if res.Meta["request_id"] != "test-req" {
		t.Errorf("expected request_id 'test-req', got '%s'", res.Meta["request_id"])
	}
}

func TestWriteErrorFormat(t *testing.T) {
	rec := httptest.NewRecorder()
	writeError(rec, http.StatusForbidden, "FORBIDDEN", "Admin permissions required.")

	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected status 403, got %d", rec.Code)
	}

	var res struct {
		Error struct {
			Code      string `json:"code"`
			Message   string `json:"message"`
			RequestID string `json:"request_id"`
		} `json:"error"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &res); err != nil {
		t.Fatalf("failed to unmarshal error response: %v", err)
	}
	if res.Error.Code != "FORBIDDEN" {
		t.Errorf("expected code FORBIDDEN, got %s", res.Error.Code)
	}
	if res.Error.Message != "Admin permissions required." {
		t.Errorf("expected message 'Admin permissions required.', got %s", res.Error.Message)
	}
}

func TestAdminModelsSerialization(t *testing.T) {
	stats := Stats{
		PendingVerifications: 2,
		ReportedListings:     5,
		PendingOffers:        1,
		ActiveListings:       10,
	}
	data, err := json.Marshal(stats)
	if err != nil {
		t.Fatalf("failed to marshal Stats: %v", err)
	}

	var decoded Stats
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("failed to unmarshal Stats: %v", err)
	}
	if decoded.PendingVerifications != 2 || decoded.ReportedListings != 5 {
		t.Errorf("unexpected decoded values: %+v", decoded)
	}

	reason := "Spam report"
	rep := AdminReport{
		ID:               "rep-123",
		ReporterPhone:    "+919876543210",
		TargetType:       "business",
		TargetID:         "biz-456",
		Reason:           reason,
		Status:           "open",
		CreatedAt:        time.Now().Format(time.RFC3339),
	}
	repData, err := json.Marshal(rep)
	if err != nil {
		t.Fatalf("failed to marshal AdminReport: %v", err)
	}
	var decodedRep AdminReport
	if err := json.Unmarshal(repData, &decodedRep); err != nil {
		t.Fatalf("failed to unmarshal AdminReport: %v", err)
	}
	if decodedRep.ID != "rep-123" || decodedRep.TargetType != "business" {
		t.Errorf("unexpected decoded report: %+v", decodedRep)
	}
}

func TestAdminJWTTokenClaims(t *testing.T) {
	jwtSecret := []byte("test-super-secret-key-1234567890")
	userID := "user-admin-uuid"
	phone := "+910000000000"

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub":   userID,
		"phone": phone,
		"role":  "admin",
		"exp":   time.Now().Add(24 * time.Hour).Unix(),
	})
	tokenStr, err := token.SignedString(jwtSecret)
	if err != nil {
		t.Fatalf("failed to sign token: %v", err)
	}

	parsed, err := jwt.Parse(tokenStr, func(t *jwt.Token) (interface{}, error) {
		return jwtSecret, nil
	})
	if err != nil || !parsed.Valid {
		t.Fatalf("failed to parse valid token: %v", err)
	}

	claims, ok := parsed.Claims.(jwt.MapClaims)
	if !ok {
		t.Fatalf("expected MapClaims, got %T", parsed.Claims)
	}
	if claims["sub"] != userID {
		t.Errorf("expected sub '%s', got '%v'", userID, claims["sub"])
	}
	if claims["role"] != "admin" {
		t.Errorf("expected role 'admin', got '%v'", claims["role"])
	}
}
