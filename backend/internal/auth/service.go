package auth

import (
	"context"
	"crypto/rand"
	"database/sql"
	"errors"
	"fmt"
	"math/big"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v4"
	"golang.org/x/crypto/bcrypt"

	"grepmind-near/backend/pkg/config"
	"grepmind-near/backend/pkg/database"
)

var (
	errOTPExpired     = errors.New("OTP expired")
	errOTPMaxAttempts = errors.New("OTP maximum attempts exceeded")
	errInvalidToken   = errors.New("invalid token")
)

type Service struct {
	db  *database.DB
	cfg *config.Config
	now func() time.Time
}

func NewService(db *database.DB, cfg *config.Config) *Service {
	return &Service{
		db:  db,
		cfg: cfg,
		now: time.Now,
	}
}

// ConfigSecret returns the JWT secret for middleware use.
func (s *Service) ConfigSecret() string {
	return s.cfg.JWTSecret
}

// DB returns the underlying database connection.
func (s *Service) DB() *database.DB {
	return s.db
}

// Now returns the current time.
func (s *Service) Now() time.Time {
	return s.now()
}

// ---------- Token helpers ----------

func (s *Service) issueTokens(ctx context.Context, userID string) (string, string, error) {
	now := s.now()
	accessClaims := jwt.RegisteredClaims{
		Subject:   userID,
		IssuedAt:  jwt.NewNumericDate(now),
		ExpiresAt: jwt.NewNumericDate(now.Add(s.cfg.JWTAccessTTL)),
		Issuer:    "grepmind-near",
	}
	accessToken, err := jwt.NewWithClaims(jwt.SigningMethodHS256, accessClaims).SignedString([]byte(s.cfg.JWTSecret))
	if err != nil {
		return "", "", err
	}

	refreshRaw := generateRandomHex(32)
	refreshHash := hashToken(refreshRaw)
	refreshExpires := now.Add(s.cfg.JWTRefreshTTL)
	_, err = s.db.ExecContext(ctx, `
		INSERT INTO sessions (user_id, refresh_token_hash, expires_at, user_agent, ip_address)
		VALUES ($1, $2, $3, $4, $5)
	`, userID, refreshHash, refreshExpires, "", "")
	if err != nil {
		return "", "", err
	}

	refreshClaims := jwt.RegisteredClaims{
		Subject:   userID,
		IssuedAt:  jwt.NewNumericDate(now),
		ExpiresAt: jwt.NewNumericDate(refreshExpires),
		Issuer:    "grepmind-near",
	}
	refreshToken, err := jwt.NewWithClaims(jwt.SigningMethodHS256, refreshClaims).SignedString([]byte(s.cfg.JWTSecret))
	if err != nil {
		return "", "", err
	}
	_ = refreshRaw
	return accessToken, refreshToken, nil
}

func (s *Service) validateRefreshToken(ctx context.Context, token string) (*jwt.RegisteredClaims, error) {
	claims := &jwt.RegisteredClaims{}
	_, err := jwt.ParseWithClaims(token, claims, func(t *jwt.Token) (interface{}, error) {
		return []byte(s.cfg.JWTSecret), nil
	})
	if err != nil {
		return nil, err
	}
	if !claims.VerifyExpiresAt(s.now(), true) {
		return nil, errInvalidToken
	}
	var exists bool
	var revoked sql.NullTime
	err = s.db.QueryRowxContext(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM sessions
			WHERE refresh_token_hash = $1 AND user_id = $2
		), revoked_at
		FROM sessions
		WHERE refresh_token_hash = $1
		LIMIT 1
	`, hashToken(token)).Scan(&exists, &revoked)
	if err != nil || !exists {
		return nil, errInvalidToken
	}
	if revoked.Valid {
		return nil, errInvalidToken
	}
	return claims, nil
}

// ---------- Utilities ----------

func generateOTP() string {
	n, _ := rand.Int(rand.Reader, big.NewInt(1000000))
	return fmt.Sprintf("%06d", n.Int64())
}

func hashToken(token string) string {
	sum, _ := bcrypt.GenerateFromPassword([]byte(token), bcrypt.DefaultCost)
	return string(sum)
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

func generateRandomHex(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return ""
	}
	var sb strings.Builder
	for _, v := range b {
		sb.WriteString(fmt.Sprintf("%02x", v))
	}
	return sb.String()
}

var _ = sql.NullString{}
var _ = sql.NullInt64{}
var _ = sql.NullTime{}
