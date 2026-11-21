package config

import (
	"errors"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	Env      string
	Port     string
	BaseURL  string
	LogLevel string

	DBHost     string
	DBPort     string
	DBUser     string
	DBPassword string
	DBName     string
	DBSSLMode  string
	DSN        string

	JWTSecret     string
	JWTAccessTTL  time.Duration
	JWTRefreshTTL time.Duration

	OTPTTL                 time.Duration
	OTPResendCooldown      time.Duration
	OTPMaxAttempts         int
	OTPProvider            string
	OTPFrom                string
	Fast2SMSAPIKey         string
	Fast2SMSOTPTemplateID  string
	Fast2SMSOTPVariables   string
	Fast2SMSRequestTimeout time.Duration
	QAOTPDeliveryRequested bool
	QAOTPDeliveryEnabled   bool
	QAOTPDeliveryURL       string
	QAOTPWriterToken       string
	QAOTPAllowlist         []string
	QAOTPRunID             string

	UnsupportedOTPProviderRequested bool

	S3Endpoint      string
	S3Region        string
	S3Bucket        string
	S3PrivateBucket string
	S3AccessKey     string
	S3SecretKey     string
	S3UseSSL        bool

	FCMProjectID string

	FCMServiceAccountPath string
	FCMHTTPTimeout        time.Duration
	FCMMaxRetries         int
	FCMTestOTPEnabled     bool
	FCMTestOTPChannel     string

	GoogleOAuthClientID string

	RiderDispatchEnabled        bool
	RiderOfferTimeout           time.Duration
	RiderAvailabilityLease      time.Duration
	RiderEarningsPostingEnabled bool
	RiderEarningsAllowSynthetic bool
	RiderEarningsPolicyApproved bool
	SandboxCODEnabled           bool

	RateLimitAuth string
	RateLimitAPI  string

	AdminDefaultEmail    string
	AdminDefaultPassword string
}

func Load() *Config {
	appEnv := getenv("APP_ENV", "production")
	syntheticRequested := strings.EqualFold(getenv("RIDER_EARNINGS_ALLOW_SYNTHETIC", "false"), "true")
	syntheticAllowed := syntheticRequested && (strings.EqualFold(appEnv, "qa") || strings.EqualFold(appEnv, "test"))
	policyApproved := strings.EqualFold(getenv("RIDER_EARNINGS_POLICY_APPROVED", "false"), "true")
	postingRequested := strings.EqualFold(getenv("RIDER_EARNINGS_POSTING_ENABLED", "false"), "true")
	sandboxCODRequested := strings.EqualFold(getenv("SANDBOX_COD_ENABLED", "false"), "true")
	sandboxCODAllowed := sandboxCODRequested && (strings.EqualFold(appEnv, "qa") || strings.EqualFold(appEnv, "test"))
	qaOTPRequested := strings.EqualFold(getenv("QA_OTP_DELIVERY_ENABLED", "false"), "true")
	// SMS_PROVIDER is the documented name for new deployments; preserve the
	// older OTP_PROVIDER variable as a compatibility fallback.
	otpProvider := getenv("SMS_PROVIDER", getenv("OTP_PROVIDER", getenv("OTP_DELIVERY_PROVIDER", "stub")))
	unsupportedOTPProviderRequested := false
	for _, name := range []string{"SMS_PROVIDER", "OTP_PROVIDER", "OTP_DELIVERY_PROVIDER"} {
		value := strings.TrimSpace(os.Getenv(name))
		if strings.EqualFold(value, "fcm_test") || strings.EqualFold(value, "mock") {
			unsupportedOTPProviderRequested = true
		}
	}
	qaOTPAllowed := qaOTPRequested && strings.EqualFold(appEnv, "qa") && strings.EqualFold(otpProvider, "qa_http")
	var qaOTPAllowlist []string
	if qaOTPAllowed {
		for _, phone := range strings.Split(getenv("QA_OTP_ALLOWLIST", ""), ",") {
			phone = strings.TrimSpace(phone)
			if phone != "" {
				qaOTPAllowlist = append(qaOTPAllowlist, phone)
			}
		}
	}
	return &Config{
		// Fail closed when the environment is not explicitly marked local. The
		// local Docker Compose stack sets APP_ENV=local by default.
		Env:      appEnv,
		Port:     getenv("APP_PORT", "8080"),
		BaseURL:  getenv("APP_BASE_URL", "http://localhost:8080"),
		LogLevel: getenv("LOG_LEVEL", "info"),

		DBHost:     getenv("DB_HOST", "localhost"),
		DBPort:     getenv("DB_PORT", "5432"),
		DBUser:     getenv("DB_USER", "grepmind"),
		DBPassword: getenv("DB_PASSWORD", "grepmind_dev"),
		DBName:     getenv("DB_NAME", "grepmind_near"),
		DBSSLMode:  getenv("DB_SSLMODE", "disable"),

		JWTSecret:     getenv("JWT_SECRET", "replace-with-strong-secret-min-32-chars"),
		JWTAccessTTL:  parseDuration(getenv("JWT_ACCESS_TTL", "15m")),
		JWTRefreshTTL: parseDuration(getenv("JWT_REFRESH_TTL", "720h")),

		OTPTTL:                 parseDuration(getenv("OTP_TTL", "10m")),
		OTPResendCooldown:      parseDuration(getenv("OTP_RESEND_COOLDOWN", "60s")),
		OTPMaxAttempts:         parseInt(getenv("OTP_MAX_ATTEMPTS", "5")),
		OTPProvider:            otpProvider,
		OTPFrom:                getenv("OTP_FROM", "Grepmind Near"),
		Fast2SMSAPIKey:         getenv("FAST2SMS_API_KEY", ""),
		Fast2SMSOTPTemplateID:  getenv("FAST2SMS_OTP_TEMPLATE_ID", ""),
		Fast2SMSOTPVariables:   getenv("FAST2SMS_OTP_VARIABLES", ""),
		Fast2SMSRequestTimeout: parseDuration(getenv("FAST2SMS_REQUEST_TIMEOUT", "5s")),
		QAOTPDeliveryRequested: qaOTPRequested,
		QAOTPDeliveryEnabled:   qaOTPAllowed,
		QAOTPDeliveryURL:       getenv("QA_OTP_DELIVERY_URL", ""),
		QAOTPWriterToken:       getenv("QA_OTP_WRITER_TOKEN", ""),
		QAOTPAllowlist:         qaOTPAllowlist,
		QAOTPRunID:             getenv("QA_OTP_RUN_ID", ""),

		UnsupportedOTPProviderRequested: unsupportedOTPProviderRequested,

		S3Endpoint:      getenv("S3_ENDPOINT", "http://localhost:9000"),
		S3Region:        getenv("S3_REGION", "us-east-1"),
		S3Bucket:        getenv("S3_BUCKET", "grepmind-near"),
		S3PrivateBucket: getenv("S3_PRIVATE_BUCKET", "grepmind-near-private"),
		S3AccessKey:     getenv("S3_ACCESS_KEY", "minioadmin"),
		S3SecretKey:     getenv("S3_SECRET_KEY", "minioadmin"),
		S3UseSSL:        getenv("S3_USE_SSL", "false") == "true",

		FCMProjectID: getenv("FCM_PROJECT_ID", "grepmind-near-dev"),

		FCMServiceAccountPath: getenv("FCM_SERVICE_ACCOUNT_PATH", ""),
		FCMHTTPTimeout:        parseDuration(getenv("FCM_HTTP_TIMEOUT", "10s")),
		FCMMaxRetries:         parseInt(getenv("FCM_MAX_RETRIES", "3")),
		FCMTestOTPEnabled:     strings.EqualFold(getenv("FCM_TEST_OTP_ENABLED", "false"), "true"),
		FCMTestOTPChannel:     getenv("FCM_TEST_OTP_CHANNEL", "verification"),

		GoogleOAuthClientID: getenv("GOOGLE_OAUTH_CLIENT_ID", ""),

		// Dispatch is an explicit feature gate. It remains disabled in shared
		// development/production unless an isolated QA operator opts in.
		RiderDispatchEnabled:   strings.EqualFold(getenv("RIDER_DISPATCH_ENABLED", "false"), "true"),
		RiderOfferTimeout:      parseDuration(getenv("RIDER_OFFER_TIMEOUT", "60s")),
		RiderAvailabilityLease: parseDuration(getenv("RIDER_AVAILABILITY_LEASE", "90s")),
		// Compensation is fail-closed until Grepmind approves a commercial policy.
		// Synthetic policies are accepted only in explicitly isolated QA stacks.
		RiderEarningsPostingEnabled: postingRequested && (syntheticAllowed || policyApproved),
		RiderEarningsAllowSynthetic: syntheticAllowed,
		RiderEarningsPolicyApproved: policyApproved,
		// Synthetic COD is available only in explicitly isolated QA/test API processes.
		// APP_ENV=local and production always fail closed.
		SandboxCODEnabled: sandboxCODAllowed,

		RateLimitAuth: getenv("RATE_LIMIT_AUTH", "5/min"),
		RateLimitAPI:  getenv("RATE_LIMIT_API", "100/min"),

		AdminDefaultEmail:    getenv("ADMIN_DEFAULT_EMAIL", "admin@grepmind.local"),
		AdminDefaultPassword: getenv("ADMIN_DEFAULT_PASSWORD", "replace-me"),
	}
}

func (c *Config) DBDSN() string {
	return "host=" + c.DBHost +
		" port=" + c.DBPort +
		" user=" + c.DBUser +
		" password=" + c.DBPassword +
		" dbname=" + c.DBName +
		" sslmode=" + c.DBSSLMode
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func parseDuration(s string) time.Duration {
	d, err := time.ParseDuration(s)
	if err != nil {
		return time.Second
	}
	return d
}

func parseInt(s string) int {
	n, err := strconv.Atoi(s)
	if err != nil {
		return 0
	}
	return n
}

func (c *Config) IsLocal() bool {
	return strings.EqualFold(c.Env, "local")
}

// ValidateAuth rejects unsafe production authentication configuration before
// the API starts listening. Development defaults remain available in local.
func (c *Config) ValidateAuth() error {
	if c == nil {
		return errors.New("configuration is required")
	}
	if c.JWTAccessTTL <= 0 || c.JWTRefreshTTL <= 0 || c.OTPTTL <= 0 || c.OTPMaxAttempts <= 0 {
		return errors.New("authentication expiries and attempt limits must be positive")
	}
	if !c.IsLocal() && (len(strings.TrimSpace(c.JWTSecret)) < 32 || c.JWTSecret == "replace-with-strong-secret-min-32-chars") {
		return errors.New("JWT_SECRET must be explicitly configured with at least 32 characters outside local mode")
	}
	// These proposed providers are not implemented yet. Never silently start
	// with a no-op provider, including in production or a misconfigured QA run.
	if c.UnsupportedOTPProviderRequested || strings.EqualFold(strings.TrimSpace(c.OTPProvider), "fcm_test") || strings.EqualFold(strings.TrimSpace(c.OTPProvider), "mock") {
		return errors.New("requested OTP delivery provider is not implemented and cannot be enabled")
	}
	if c.QAOTPDeliveryEnabled {
		if !strings.EqualFold(c.Env, "qa") || !strings.EqualFold(c.OTPProvider, "qa_http") {
			return errors.New("QA OTP delivery is only valid with APP_ENV=qa and OTP_PROVIDER=qa_http")
		}
		if strings.TrimSpace(c.QAOTPDeliveryURL) == "" || len(c.QAOTPWriterToken) < 32 || strings.TrimSpace(c.QAOTPRunID) == "" {
			return errors.New("QA OTP delivery requires a private inbox endpoint, writer credential, and run ID")
		}
		if len(c.QAOTPRunID) < 16 || len(c.QAOTPRunID) > 80 {
			return errors.New("QA OTP run ID is invalid")
		}
		for _, r := range c.QAOTPRunID {
			if !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '-' || r == '_') {
				return errors.New("QA OTP run ID is invalid")
			}
		}
	}
	if c.QAOTPDeliveryRequested && (!strings.EqualFold(c.Env, "qa") || !strings.EqualFold(c.OTPProvider, "qa_http")) {
		return errors.New("QA OTP delivery cannot be enabled outside an isolated QA environment")
	}
	if (strings.EqualFold(c.OTPProvider, "qa_file") || strings.EqualFold(c.OTPProvider, "qa_http")) && (!strings.EqualFold(c.Env, "qa") || !c.QAOTPDeliveryEnabled) {
		return errors.New("QA OTP provider requires explicit isolated QA delivery enablement")
	}
	if strings.EqualFold(c.OTPProvider, "fast2sms") {
		if !strings.EqualFold(c.Env, "production") {
			return errors.New("Fast2SMS delivery is restricted to production; use the isolated QA provider for tests")
		}
		if strings.TrimSpace(c.Fast2SMSAPIKey) == "" || strings.TrimSpace(c.Fast2SMSOTPTemplateID) == "" {
			return errors.New("Fast2SMS requires a server-side API key and approved OTP template ID")
		}
		if c.Fast2SMSRequestTimeout <= 0 || c.Fast2SMSRequestTimeout > 20*time.Second {
			return errors.New("Fast2SMS request timeout must be greater than zero and at most 20 seconds")
		}
		if strings.ContainsAny(c.Fast2SMSOTPVariables, "\r\n") || len(c.Fast2SMSOTPVariables) > 512 {
			return errors.New("Fast2SMS OTP template variables are invalid")
		}
	}
	if c.FCMTestOTPEnabled {
		// FCM test OTP delivers login codes to a registered installation instead
		// of an SMS provider, so it must never run outside the isolated QA stack.
		if !strings.EqualFold(c.Env, "qa") {
			return errors.New("FCM test OTP is restricted to APP_ENV=qa")
		}
		if strings.TrimSpace(c.QAOTPRunID) == "" || len(c.QAOTPRunID) < 16 {
			return errors.New("FCM test OTP requires a QA run identifier")
		}
		if strings.TrimSpace(c.FCMServiceAccountPath) == "" || strings.TrimSpace(c.FCMProjectID) == "" {
			return errors.New("FCM test OTP requires an FCM service account and project")
		}
	}
	// Google Sign-In requires an explicit OAuth client ID; never use the default
	// web client from google-services.json.
	if strings.TrimSpace(c.GoogleOAuthClientID) == "" && strings.EqualFold(c.Env, "production") {
		return errors.New("GOOGLE_OAUTH_CLIENT_ID is required in production")
	}
	return nil
}
