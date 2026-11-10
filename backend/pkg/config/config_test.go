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

func TestSyntheticEarningsAreLimitedToExplicitQATestEnvironments(t *testing.T) {
	t.Setenv("RIDER_EARNINGS_POSTING_ENABLED", "true")
	t.Setenv("RIDER_EARNINGS_ALLOW_SYNTHETIC", "true")
	t.Setenv("RIDER_EARNINGS_POLICY_APPROVED", "false")
	t.Setenv("APP_ENV", "production")
	if cfg := Load(); cfg.RiderEarningsPostingEnabled || cfg.RiderEarningsAllowSynthetic {
		t.Fatal("production must reject synthetic earnings activation")
	}
	t.Setenv("APP_ENV", "local")
	if cfg := Load(); cfg.RiderEarningsPostingEnabled || cfg.RiderEarningsAllowSynthetic {
		t.Fatal("shared local mode must not enable synthetic earnings")
	}
	t.Setenv("APP_ENV", "qa")
	if cfg := Load(); !cfg.RiderEarningsPostingEnabled || !cfg.RiderEarningsAllowSynthetic {
		t.Fatal("explicit QA mode should permit synthetic earning validation")
	}
}

func TestRealEarningsRequireBothPolicyApprovalAndPostingGate(t *testing.T) {
	t.Setenv("APP_ENV", "production")
	t.Setenv("RIDER_EARNINGS_ALLOW_SYNTHETIC", "false")
	t.Setenv("RIDER_EARNINGS_POLICY_APPROVED", "true")
	t.Setenv("RIDER_EARNINGS_POSTING_ENABLED", "false")
	if cfg := Load(); cfg.RiderEarningsPostingEnabled || cfg.RiderEarningsAllowSynthetic {
		t.Fatal("policy approval alone must not activate posting")
	}
	t.Setenv("RIDER_EARNINGS_POSTING_ENABLED", "true")
	if cfg := Load(); !cfg.RiderEarningsPostingEnabled || cfg.RiderEarningsAllowSynthetic {
		t.Fatal("real posting requires explicit policy approval and posting gate")
	}
}
