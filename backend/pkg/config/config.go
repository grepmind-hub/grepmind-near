package config

import (
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

	OTPTTL            time.Duration
	OTPResendCooldown time.Duration
	OTPMaxAttempts    int
	OTPProvider       string
	OTPFrom           string

	S3Endpoint  string
	S3Region    string
	S3Bucket    string
	S3AccessKey string
	S3SecretKey string
	S3UseSSL    bool

	FCMProjectID string

	RateLimitAuth string
	RateLimitAPI  string

	AdminDefaultEmail    string
	AdminDefaultPassword string
}

func Load() *Config {
	return &Config{
		Env:      getenv("APP_ENV", "local"),
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

		OTPTTL:            parseDuration(getenv("OTP_TTL", "10m")),
		OTPResendCooldown: parseDuration(getenv("OTP_RESEND_COOLDOWN", "60s")),
		OTPMaxAttempts:    parseInt(getenv("OTP_MAX_ATTEMPTS", "5")),
		OTPProvider:       getenv("OTP_PROVIDER", "stub"),
		OTPFrom:           getenv("OTP_FROM", "Grepmind Near"),

		S3Endpoint:  getenv("S3_ENDPOINT", "http://localhost:9000"),
		S3Region:    getenv("S3_REGION", "us-east-1"),
		S3Bucket:    getenv("S3_BUCKET", "grepmind-near"),
		S3AccessKey: getenv("S3_ACCESS_KEY", "minioadmin"),
		S3SecretKey: getenv("S3_SECRET_KEY", "minioadmin"),
		S3UseSSL:    getenv("S3_USE_SSL", "false") == "true",

		FCMProjectID: getenv("FCM_PROJECT_ID", "grepmind-near-dev"),

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
