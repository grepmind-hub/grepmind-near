package auth

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
	"grepmind-near/backend/pkg/config"
	"grepmind-near/backend/pkg/database"
)

func TestRefreshRejectsExpiredToken(t *testing.T) {
	svc, userID := newSessionIntegrationService(t)
	now := time.Now()
	sessionID := uuid.NewString()
	token, err := generateOpaqueRefreshToken()
	if err != nil {
		t.Fatal(err)
	}
	_, err = svc.db.ExecContext(context.Background(), `INSERT INTO sessions (id,user_id,refresh_token_hash,expires_at) VALUES ($1,$2,$3,$4)`, sessionID, userID, hashToken(token), now.Add(-time.Minute))
	if err != nil {
		t.Fatal(err)
	}
	if response := refreshRequest(svc, token); response.Code != http.StatusUnauthorized {
		t.Fatalf("expired refresh token status=%d body=%s", response.Code, response.Body.String())
	}
}

func TestRevokedSessionRejectsRefreshAndAccess(t *testing.T) {
	svc, userID := newSessionIntegrationService(t)
	access, refresh, err := svc.issueTokens(context.Background(), userID, "test", "127.0.0.1")
	if err != nil {
		t.Fatal(err)
	}
	if _, err = svc.db.ExecContext(context.Background(), `UPDATE sessions SET revoked_at=$1 WHERE refresh_token_hash=$2`, time.Now(), hashToken(refresh)); err != nil {
		t.Fatal(err)
	}
	if response := refreshRequest(svc, refresh); response.Code != http.StatusUnauthorized {
		t.Fatalf("revoked refresh token status=%d", response.Code)
	}
	if _, err := svc.ValidateAccessToken(context.Background(), access); err == nil {
		t.Fatal("access token for revoked session must be rejected")
	}
}

func TestLogoutRevokesBoundSession(t *testing.T) {
	svc, userID := newSessionIntegrationService(t)
	access, refresh, err := svc.issueTokens(context.Background(), userID, "test", "127.0.0.1")
	if err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest(http.MethodPost, "/api/v1/auth/logout", nil)
	request.Header.Set("Authorization", "Bearer "+access)
	response := httptest.NewRecorder()
	svc.Logout(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("logout status=%d body=%s", response.Code, response.Body.String())
	}
	if _, err = svc.ValidateAccessToken(context.Background(), access); err == nil {
		t.Fatal("access token must stop working after logout")
	}
	if response := refreshRequest(svc, refresh); response.Code != http.StatusUnauthorized {
		t.Fatalf("refresh after logout status=%d, want 401", response.Code)
	}
}

func TestRefreshTokenReuseRejected(t *testing.T) {
	svc, userID := newSessionIntegrationService(t)
	_, refresh, err := svc.issueTokens(context.Background(), userID, "test", "127.0.0.1")
	if err != nil {
		t.Fatal(err)
	}
	first := refreshRequest(svc, refresh)
	if first.Code != http.StatusOK {
		t.Fatalf("first refresh status=%d body=%s", first.Code, first.Body.String())
	}
	if second := refreshRequest(svc, refresh); second.Code != http.StatusUnauthorized {
		t.Fatalf("reused refresh token status=%d, want 401", second.Code)
	}
	var active int
	if err = svc.db.GetContext(context.Background(), &active, `SELECT count(*) FROM sessions WHERE user_id=$1 AND revoked_at IS NULL`, userID); err != nil {
		t.Fatal(err)
	}
	if active != 1 {
		t.Fatalf("expected one active rotated session, got %d", active)
	}
}

func TestConcurrentRefreshOnlyRotatesOnce(t *testing.T) {
	svc, userID := newSessionIntegrationService(t)
	_, refresh, err := svc.issueTokens(context.Background(), userID, "test", "127.0.0.1")
	if err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	statuses := make(chan int, 2)
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			statuses <- refreshRequest(svc, refresh).Code
		}()
	}
	wg.Wait()
	close(statuses)
	successes, rejected := 0, 0
	for status := range statuses {
		switch status {
		case http.StatusOK:
			successes++
		case http.StatusUnauthorized:
			rejected++
		default:
			t.Fatalf("unexpected concurrent refresh status %d", status)
		}
	}
	if successes != 1 || rejected != 1 {
		t.Fatalf("expected one successful rotation and one rejection, got success=%d rejected=%d", successes, rejected)
	}
	var active int
	if err = svc.db.GetContext(context.Background(), &active, `SELECT count(*) FROM sessions WHERE user_id=$1 AND revoked_at IS NULL`, userID); err != nil {
		t.Fatal(err)
	}
	if active != 1 {
		t.Fatalf("expected one active session after concurrent refresh, got %d", active)
	}
}

func TestConcurrentOTPRequestsEnforcePersistentPhoneLimit(t *testing.T) {
	svc, _ := newSessionIntegrationService(t)
	cfg := &config.Config{
		Env: "local", OTPProvider: "stub", JWTSecret: "integration-test-secret-with-over-32-characters",
		JWTAccessTTL: time.Minute, JWTRefreshTTL: time.Hour, OTPTTL: 10 * time.Minute,
		OTPResendCooldown: 0, OTPMaxAttempts: 5,
	}
	const attempts = 6
	statuses := make(chan int, attempts)
	var wg sync.WaitGroup
	for i := 0; i < attempts; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			request := httptest.NewRequest(http.MethodPost, "/api/v1/auth/otp/request", strings.NewReader(`{"phone_e164":"+919876543210"}`))
			request.RemoteAddr = "127.0.0.1:12345"
			response := httptest.NewRecorder()
			NewService(svc.db, cfg).RequestOTP(response, request)
			statuses <- response.Code
		}()
	}
	wg.Wait()
	close(statuses)
	accepted, limited := 0, 0
	for status := range statuses {
		switch status {
		case http.StatusAccepted:
			accepted++
		case http.StatusTooManyRequests:
			limited++
		default:
			t.Fatalf("unexpected OTP request status %d", status)
		}
	}
	if accepted != 5 || limited != 1 {
		t.Fatalf("expected five OTPs and one rate limit, got accepted=%d limited=%d", accepted, limited)
	}
	var stored int
	if err := svc.db.GetContext(context.Background(), &stored, `SELECT count(*) FROM otp_codes WHERE phone_e164=$1`, "+919876543210"); err != nil {
		t.Fatal(err)
	}
	if stored != 5 {
		t.Fatalf("expected exactly five stored OTPs, got %d", stored)
	}
}

func refreshRequest(svc *Service, token string) *httptest.ResponseRecorder {
	body, _ := json.Marshal(map[string]string{"refresh_token": token})
	request := httptest.NewRequest(http.MethodPost, "/api/v1/auth/refresh", bytes.NewReader(body))
	request.RemoteAddr = "127.0.0.1:12345"
	response := httptest.NewRecorder()
	svc.Refresh(response, request)
	return response
}

func newSessionIntegrationService(t *testing.T) (*Service, string) {
	t.Helper()
	dsn := os.Getenv("GREPMIND_TEST_DATABASE_URL")
	if dsn == "" {
		dsn = os.Getenv("TEST_DATABASE_URL")
	}
	if dsn == "" {
		t.Skip("set GREPMIND_TEST_DATABASE_URL to run PostgreSQL session lifecycle integration tests")
	}
	adminDB, err := sqlx.Open("pgx", dsn)
	if err != nil {
		t.Fatalf("open test database: %v", err)
	}
	if err = adminDB.Ping(); err != nil {
		adminDB.Close()
		t.Fatalf("connect test database: %v", err)
	}
	schema := "auth_test_" + strings.ReplaceAll(uuid.NewString(), "-", "")
	if _, err = adminDB.Exec(`CREATE SCHEMA ` + schema); err != nil {
		adminDB.Close()
		t.Fatalf("create isolated test schema: %v", err)
	}
	testDSN := dsn
	if parsed, parseErr := url.Parse(dsn); parseErr == nil && parsed.Scheme != "" {
		query := parsed.Query()
		query.Set("search_path", schema)
		parsed.RawQuery = query.Encode()
		testDSN = parsed.String()
	} else {
		testDSN += " search_path=" + schema
	}
	raw, err := sqlx.Open("pgx", testDSN)
	if err != nil {
		_, _ = adminDB.Exec(`DROP SCHEMA ` + schema + ` CASCADE`)
		adminDB.Close()
		t.Fatalf("open isolated test schema connection: %v", err)
	}
	raw.SetMaxOpenConns(5)
	raw.SetMaxIdleConns(5)
	if err = raw.Ping(); err != nil {
		raw.Close()
		_, _ = adminDB.Exec(`DROP SCHEMA ` + schema + ` CASCADE`)
		adminDB.Close()
		t.Fatalf("connect isolated test schema: %v", err)
	}
	t.Cleanup(func() {
		_ = raw.Close()
		_, _ = adminDB.Exec(`DROP SCHEMA ` + schema + ` CASCADE`)
		_ = adminDB.Close()
	})
	for _, statement := range []string{
		`CREATE TABLE users (id UUID PRIMARY KEY, phone_e164 TEXT UNIQUE NOT NULL)`,
		`CREATE TABLE sessions (id UUID PRIMARY KEY, user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, refresh_token_hash TEXT NOT NULL, expires_at TIMESTAMPTZ NOT NULL, revoked_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), user_agent TEXT, ip_address TEXT)`,
		`CREATE TABLE otp_codes (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), phone_e164 TEXT NOT NULL, code_hash TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, max_attempts INTEGER NOT NULL DEFAULT 5, expires_at TIMESTAMPTZ NOT NULL, verified_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now())`,
	} {
		if _, err = raw.Exec(statement); err != nil {
			t.Fatalf("create auth fixture table: %v", err)
		}
	}
	userID := uuid.NewString()
	if _, err = raw.Exec(`INSERT INTO users(id, phone_e164) VALUES ($1,$2)`, userID, "+919876543210"); err != nil {
		t.Fatalf("create auth fixture user: %v", err)
	}
	cfg := &config.Config{Env: "test", JWTSecret: "integration-test-secret-with-over-32-characters", JWTAccessTTL: time.Minute, JWTRefreshTTL: time.Hour}
	return NewService(&database.DB{DB: raw}, cfg), userID
}
