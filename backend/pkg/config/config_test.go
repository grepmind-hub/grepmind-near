package config

import (
	"strings"
	"testing"
	"time"
)

func TestValidateAuthRequiresExplicitProductionSecret(t *testing.T) {
	base := Config{Env: "production", JWTSecret: "replace-with-strong-secret-min-32-chars", JWTAccessTTL: time.Minute, JWTRefreshTTL: time.Hour, OTPTTL: time.Minute, OTPMaxAttempts: 5}
	if err := base.ValidateAuth(); err == nil {
		t.Fatal("production must reject the development JWT secret")
	}
	base.JWTSecret = strings.Repeat("x", 32)
	if err := base.ValidateAuth(); err != nil {
		t.Fatalf("production rejected an explicitly configured strong-length secret: %v", err)
	}
	base.Env = "local"
	base.JWTSecret = "replace-with-strong-secret-min-32-chars"
	if err := base.ValidateAuth(); err != nil {
		t.Fatalf("local development should allow its documented placeholder secret: %v", err)
	}
}

func TestEnvironmentDefaultsToNonLocal(t *testing.T) {
	t.Setenv("APP_ENV", "")
	if cfg := Load(); cfg.IsLocal() {
		t.Fatal("an omitted APP_ENV must not enable local OTP disclosure")
	}
}
