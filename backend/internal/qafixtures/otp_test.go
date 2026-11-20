package qafixtures

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"grepmind-near/backend/internal/qaotpinbox"
)

func TestScopedOTPLoginConsumesChallenge(t *testing.T) {
	const phone = "+919990000181"
	const challengeID = "97f78b7b-a53b-4c51-9bb1-e374ab25d07f"
	const code = "578421"
	now := time.Now().UTC()
	cfg := qaotpinbox.Config{
		Directory: t.TempDir(), ExpectedUID: os.Getuid(),
		RunID: "phase5b-test-run", RunnerID: "test-runner",
		RunnerSecret: strings.Repeat("r", 32), WriterSecret: strings.Repeat("w", 32),
		Allowlist: []string{phone},
	}
	if err := os.Chmod(cfg.Directory, 0700); err != nil {
		t.Fatal(err)
	}
	inbox, err := qaotpinbox.New(cfg)
	if err != nil {
		t.Fatal(err)
	}
	record := qaotpinbox.Record{
		ChallengeID: challengeID, PhoneE164: phone, Purpose: "login", Code: code,
		CreatedAt: now, ExpiresAt: now.Add(time.Minute), RunID: cfg.RunID,
	}
	body, err := json.Marshal(record)
	if err != nil {
		t.Fatal(err)
	}
	delivery := httptest.NewRequest(http.MethodPost, "/internal/v1/deliver", bytes.NewReader(body))
	delivery.Header.Set("Authorization", "Bearer "+cfg.WriterSecret)
	delivery.Header.Set("Content-Type", "application/json")
	written := httptest.NewRecorder()
	inbox.Handler().ServeHTTP(written, delivery)
	if written.Code != http.StatusCreated {
		t.Fatalf("inbox delivery returned %d", written.Code)
	}

	readerServer := httptest.NewServer(inbox.Handler())
	defer readerServer.Close()
	reader, err := NewScopeOTPReader(readerServer.URL, cfg.RunID, cfg.RunnerID, cfg.RunnerSecret)
	if err != nil {
		t.Fatal(err)
	}
	challenge := otpChallenge{ID: challengeID, Phone: phone, ExpiresAt: record.ExpiresAt.Format(time.RFC3339Nano)}
	api := http.NewServeMux()
	api.HandleFunc("POST /api/v1/auth/otp/request", func(w http.ResponseWriter, req *http.Request) {
		w.WriteHeader(http.StatusAccepted)
		_ = json.NewEncoder(w).Encode(map[string]any{"data": challenge})
	})
	api.HandleFunc("POST /api/v1/auth/otp/verify", func(w http.ResponseWriter, req *http.Request) {
		var payload map[string]string
		if json.NewDecoder(req.Body).Decode(&payload) != nil || payload["challenge_id"] != challengeID || payload["phone_e164"] != phone || payload["otp_code"] != code {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		_, _ = w.Write([]byte(`{"data":{"access_token":"test-session"}}`))
	})
	apiServer := httptest.NewServer(api)
	defer apiServer.Close()

	adapter := NewHTTPDomainWorkflowAdapters(apiServer.URL, reader)
	token, err := adapter.Login(context.Background(), phone)
	if err != nil || token != "test-session" {
		t.Fatalf("scoped login failed: %v", err)
	}
	if _, err := reader.read(context.Background(), phone, challenge); err == nil {
		t.Fatal("replayed scope was accepted")
	}
}
