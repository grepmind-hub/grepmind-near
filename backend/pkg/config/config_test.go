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

func TestSyntheticCODRequiresExplicitQATestEnvironment(t *testing.T) {
	t.Setenv("APP_ENV", "production")
	t.Setenv("SANDBOX_COD_ENABLED", "true")
	if Load().SandboxCODEnabled {
		t.Fatal("production must never enable synthetic COD")
	}
	t.Setenv("APP_ENV", "local")
	if Load().SandboxCODEnabled {
		t.Fatal("local shared development must not enable synthetic COD")
	}
	t.Setenv("APP_ENV", "qa")
	if !Load().SandboxCODEnabled {
		t.Fatal("explicit QA synthetic COD gate should be available")
	}
	t.Setenv("SANDBOX_COD_ENABLED", "false")
	if Load().SandboxCODEnabled {
		t.Fatal("synthetic COD must remain disabled unless explicitly requested")
	}
}

func TestQAOTPDeliveryRequiresExplicitQAConfiguration(t *testing.T) {
	t.Setenv("JWT_SECRET", strings.Repeat("x", 32))
	t.Setenv("OTP_PROVIDER", "qa_http")
	t.Setenv("QA_OTP_DELIVERY_ENABLED", "true")
	t.Setenv("QA_OTP_ALLOWLIST", "+919000000001,+919000000002")
	t.Setenv("QA_OTP_DELIVERY_URL", "http://qa-otp-inbox:8090")
	t.Setenv("QA_OTP_WRITER_TOKEN", strings.Repeat("w", 40))
	t.Setenv("QA_OTP_RUN_ID", "auth-otp-test-run")
	t.Setenv("APP_ENV", "production")
	if cfg := Load(); cfg.QAOTPDeliveryEnabled || len(cfg.QAOTPAllowlist) != 0 || cfg.ValidateAuth() == nil {
		t.Fatal("production must not enable QA OTP delivery")
	}
	t.Setenv("APP_ENV", "local")
	if cfg := Load(); cfg.QAOTPDeliveryEnabled || len(cfg.QAOTPAllowlist) != 0 {
		t.Fatal("shared development must not enable QA OTP delivery")
	}
	t.Setenv("APP_ENV", "qa")
	if cfg := Load(); !cfg.QAOTPDeliveryEnabled || len(cfg.QAOTPAllowlist) != 2 {
		t.Fatal("explicit QA config should enable delivery only for configured test identities")
	}
	t.Setenv("QA_OTP_DELIVERY_ENABLED", "false")
	if cfg := Load(); cfg.QAOTPDeliveryEnabled || len(cfg.QAOTPAllowlist) != 0 {
		t.Fatal("QA delivery must be disabled by default")
	}
}

func TestQAOTPDeliveryConfigurationMustBeCompleteAndValid(t *testing.T) {
	cfg := Config{Env: "qa", OTPProvider: "qa_http", QAOTPDeliveryEnabled: true, QAOTPDeliveryURL: "http://qa-otp-inbox:8090", QAOTPWriterToken: strings.Repeat("w", 40), QAOTPAllowlist: []string{"not-a-phone"}, JWTSecret: strings.Repeat("x", 32), JWTAccessTTL: time.Minute, JWTRefreshTTL: time.Hour, OTPTTL: time.Minute, OTPMaxAttempts: 5}
	if err := cfg.ValidateAuth(); err == nil {
		t.Fatal("invalid QA OTP allowlist entry must be rejected")
	}
	cfg.QAOTPAllowlist = nil
	if err := cfg.ValidateAuth(); err == nil {
		t.Fatal("empty QA OTP allowlist must be rejected")
	}
	cfg.Env = "production"
	cfg.QAOTPAllowlist = []string{"+919000000001"}
	if err := cfg.ValidateAuth(); err == nil {
		t.Fatal("QA OTP delivery must not validate outside APP_ENV=qa")
	}
	cfg.Env = "qa"
	cfg.QAOTPAllowlist = []string{"+919000000001"}
	cfg.QAOTPRunID = ""
	if err := cfg.ValidateAuth(); err == nil {
		t.Fatal("QA OTP delivery must require a run identifier")
	}
	cfg.QAOTPRunID = "short"
	if err := cfg.ValidateAuth(); err == nil {
		t.Fatal("QA OTP delivery must reject predictable short run identifiers")
	}
	cfg.QAOTPRunID = "auth-otp-test-run"
	cfg.QAOTPWriterToken = "short"
	if err := cfg.ValidateAuth(); err == nil {
		t.Fatal("QA OTP delivery must require a high-entropy writer credential")
	}
}

func TestFast2SMSConfigurationUsesServerSecretsAndFailsClosed(t *testing.T) {
	t.Setenv("APP_ENV", "production")
	t.Setenv("JWT_SECRET", strings.Repeat("j", 40))
	t.Setenv("OTP_PROVIDER", "stub")
	t.Setenv("SMS_PROVIDER", "fast2sms")
	t.Setenv("FAST2SMS_API_KEY", "")
	t.Setenv("FAST2SMS_OTP_TEMPLATE_ID", "")
	if cfg := Load(); cfg.OTPProvider != "fast2sms" || cfg.ValidateAuth() == nil {
		t.Fatal("Fast2SMS must be selected explicitly and fail closed without credentials/template")
	}

	t.Setenv("FAST2SMS_API_KEY", "server-only-test-key")
	t.Setenv("FAST2SMS_OTP_TEMPLATE_ID", "approved-otp-template")
	t.Setenv("FAST2SMS_REQUEST_TIMEOUT", "5s")
	if cfg := Load(); cfg.ValidateAuth() != nil {
		t.Fatalf("complete production configuration rejected: %v", cfg.ValidateAuth())
	}

	t.Setenv("APP_ENV", "qa")
	if cfg := Load(); cfg.ValidateAuth() == nil {
		t.Fatal("Fast2SMS must not activate in isolated QA")
	}

	t.Setenv("APP_ENV", "production")
	t.Setenv("FAST2SMS_REQUEST_TIMEOUT", "21s")
	if cfg := Load(); cfg.ValidateAuth() == nil {
		t.Fatal("provider timeout above the bounded maximum must be rejected")
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
