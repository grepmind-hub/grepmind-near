package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"math/big"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v4"
	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"

	"grepmind-near/backend/pkg/config"
	"grepmind-near/backend/pkg/database"
)

var (
	errInvalidToken      = errors.New("invalid token")
	errOTPRequestLimited = errors.New("OTP request rate limited")
)

type sessionClaims struct {
	SessionID string `json:"sid,omitempty"`
	jwt.RegisteredClaims
}

// OTPDeliveryProvider is the boundary for a future SMS gateway. The local
// implementation intentionally does not send externally; production remains
// unavailable until a provider is explicitly configured and implemented.
type OTPDeliveryProvider interface {
	SendOTP(context.Context, string, string) error
}

type localOTPProvider struct{}

func (localOTPProvider) SendOTP(context.Context, string, string) error { return nil }

type Service struct {
	db          *database.DB
	cfg         *config.Config
	now         func() time.Time
	otpProvider OTPDeliveryProvider
	otpLimits   *otpRateLimiter
}

func NewService(db *database.DB, cfg *config.Config) *Service {
	var provider OTPDeliveryProvider
	if cfg != nil && cfg.IsLocal() && (cfg.OTPProvider == "" || strings.EqualFold(cfg.OTPProvider, "stub")) {
		provider = localOTPProvider{}
	}
	return NewServiceWithOTPProvider(db, cfg, provider)
}

// NewServiceWithOTPProvider allows staging to inject a reviewed delivery
// adapter without tying authentication to a specific paid SMS vendor.
func NewServiceWithOTPProvider(db *database.DB, cfg *config.Config, provider OTPDeliveryProvider) *Service {
	return &Service{db: db, cfg: cfg, now: time.Now, otpProvider: provider, otpLimits: newOTPRateLimiter()}
}

// ConfigSecret returns the JWT secret for middleware use.
func (s *Service) ConfigSecret() string { return s.cfg.JWTSecret }

// DB returns the underlying database connection.
func (s *Service) DB() *database.DB { return s.db }

// Now returns the current time.
func (s *Service) Now() time.Time { return s.now() }

// ValidateAccessToken checks JWT claims and, for application sessions, verifies
// that the backing session has not expired or been revoked.
func (s *Service) ValidateAccessToken(ctx context.Context, token string) (*jwt.RegisteredClaims, error) {
	claims, err := s.parseSessionToken(token)
	if err != nil || claims.SessionID == "" {
		if err != nil {
			return nil, err
		}
		// Legacy/admin tokens do not have a session id and keep their existing
		// validation path. New customer and merchant tokens are always bound.
		return &claims.RegisteredClaims, nil
	}
	if s.db == nil {
		return nil, errInvalidToken
	}
	var active bool
	err = s.db.GetContext(ctx, &active, `
		SELECT EXISTS (
			SELECT 1 FROM sessions
			WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL AND expires_at > $3
		)
	`, claims.SessionID, claims.Subject, s.now())
	if err != nil || !active {
		return nil, errInvalidToken
	}
	return &claims.RegisteredClaims, nil
}

func (s *Service) parseSessionToken(token string) (*sessionClaims, error) {
	claims := &sessionClaims{}
	parsed, err := jwt.ParseWithClaims(token, claims, func(t *jwt.Token) (interface{}, error) {
		return []byte(s.cfg.JWTSecret), nil
	}, jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}), jwt.WithoutClaimsValidation())
	if err != nil || parsed == nil || !parsed.Valid {
		return nil, errInvalidToken
	}
	now := s.now()
	if claims.Subject == "" || claims.Issuer != "grepmind-near" || claims.ExpiresAt == nil ||
		!claims.VerifyExpiresAt(now, true) || !claims.VerifyNotBefore(now, false) ||
		claims.IssuedAt == nil || !claims.VerifyIssuedAt(now.Add(5*time.Second), true) {
		return nil, errInvalidToken
	}
	return claims, nil
}

// issueTokens creates a new database session and both tokens atomically.
func (s *Service) issueTokens(ctx context.Context, userID, userAgent, ipAddress string) (string, string, error) {
	if s.db == nil {
		return "", "", errors.New("session database unavailable")
	}
	tx, err := s.db.BeginTxx(ctx, nil)
	if err != nil {
		return "", "", err
	}
	defer tx.Rollback()
	access, refresh, err := s.issueTokensTx(ctx, tx, userID, userAgent, ipAddress)
	if err != nil {
		return "", "", err
	}
	if err = tx.Commit(); err != nil {
		return "", "", err
	}
	return access, refresh, nil
}

func (s *Service) issueTokensTx(ctx context.Context, tx *sqlx.Tx, userID, userAgent, ipAddress string) (string, string, error) {
	now := s.now()
	sessionID := uuid.NewString()
	accessClaims := sessionClaims{
		SessionID: sessionID,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject: userID, IssuedAt: jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(s.cfg.JWTAccessTTL)), Issuer: "grepmind-near",
		},
	}
	accessToken, err := jwt.NewWithClaims(jwt.SigningMethodHS256, accessClaims).SignedString([]byte(s.cfg.JWTSecret))
	if err != nil {
		return "", "", err
	}
	refreshToken, err := generateOpaqueRefreshToken()
	if err != nil {
		return "", "", err
	}
	refreshExpires := now.Add(s.cfg.JWTRefreshTTL)
	_, err = tx.ExecContext(ctx, `
		INSERT INTO sessions (id, user_id, refresh_token_hash, expires_at, user_agent, ip_address)
		VALUES ($1, $2, $3, $4, $5, $6)
	`, sessionID, userID, hashToken(refreshToken), refreshExpires, limitStoredValue(userAgent, 512), limitStoredValue(ipAddress, 64))
	if err != nil {
		return "", "", err
	}
	return accessToken, refreshToken, nil
}

// rotateRefreshToken locks the current session row, verifies its digest and
// state, revokes it, and inserts the replacement in the same transaction.
func (s *Service) rotateRefreshToken(ctx context.Context, token, userAgent, ipAddress string) (string, string, error) {
	if token == "" || len(token) > 128 || s.db == nil {
		return "", "", errInvalidToken
	}
	tx, err := s.db.BeginTxx(ctx, nil)
	if err != nil {
		return "", "", err
	}
	defer tx.Rollback()
	var sessionID, userID string
	var revokedAt sql.NullTime
	var expiresAt time.Time
	err = tx.QueryRowxContext(ctx, `
		SELECT id::text, user_id::text, revoked_at, expires_at
		FROM sessions WHERE refresh_token_hash = $1 FOR UPDATE
	`, hashToken(token)).Scan(&sessionID, &userID, &revokedAt, &expiresAt)
	if errors.Is(err, sql.ErrNoRows) {
		return "", "", errInvalidToken
	}
	if err != nil {
		return "", "", err
	}
	if revokedAt.Valid || !expiresAt.After(s.now()) {
		return "", "", errInvalidToken
	}
	result, err := tx.ExecContext(ctx, `UPDATE sessions SET revoked_at = $1 WHERE id = $2 AND revoked_at IS NULL`, s.now(), sessionID)
	if err != nil {
		return "", "", err
	}
	changed, err := result.RowsAffected()
	if err != nil || changed != 1 {
		return "", "", errInvalidToken
	}
	access, refresh, err := s.issueTokensTx(ctx, tx, userID, userAgent, ipAddress)
	if err != nil {
		return "", "", err
	}
	if err = tx.Commit(); err != nil {
		return "", "", err
	}
	return access, refresh, nil
}

func (s *Service) revokeAccessToken(ctx context.Context, token string) error {
	claims, err := s.parseSessionToken(token)
	if err != nil {
		return err
	}
	if claims.SessionID == "" || s.db == nil {
		return nil
	}
	_, err = s.db.ExecContext(ctx, `UPDATE sessions SET revoked_at = $1 WHERE id = $2 AND user_id = $3 AND revoked_at IS NULL`, s.now(), claims.SessionID, claims.Subject)
	return err
}

// ---------- Utilities ----------

func generateOTP() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(1000000))
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%06d", n.Int64()), nil
}

// hashToken is intentionally deterministic for indexed lookup while the input
// is a high-entropy opaque refresh secret. Password-style bcrypt is not
// suitable for equality lookups because each invocation produces a different digest.
func hashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

func normalizePhone(raw string) (string, error) {
	phone := strings.TrimSpace(raw)
	if !strings.HasPrefix(phone, "+") {
		return "", errors.New("phone must be in E.164 format (e.g. +919876543210)")
	}
	digits := strings.TrimPrefix(phone, "+")
	if len(digits) < 10 || len(digits) > 15 {
		return "", errors.New("phone number length is invalid")
	}
	for _, ch := range digits {
		if ch < '0' || ch > '9' {
			return "", errors.New("phone number contains invalid characters")
		}
	}
	return phone, nil
}

func generateOpaqueRefreshToken() (string, error) {
	secret := make([]byte, 32)
	if _, err := rand.Read(secret); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(secret), nil
}

func limitStoredValue(value string, max int) string {
	if len(value) > max {
		return value[:max]
	}
	return value
}
