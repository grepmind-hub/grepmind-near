package qafixtures

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"
)

// RequiredSchemaTables lists all tables required in the isolated QA database
// for Phase 5B settlement and payout visibility workflows.
var RequiredSchemaTables = []string{
	"users",
	"businesses",
	"business_members",
	"rider_profiles",
	"customer_orders",
	"delivery_jobs",
	"delivery_assignments",
	"cod_obligations",
	"cod_collections",
	"rider_earning_entries",
	"financial_journals",
	"financial_postings",
	"bank_beneficiaries",
	"merchant_settlement_batches",
	"rider_settlement_batches",
	"payout_transfers",
}

// EnvironmentEvidence captures runtime configuration flags.
type EnvironmentEvidence struct {
	AppEnv           string
	RealMoneyEnabled bool
	PayoutEnabled    bool
	PaymentProvider  string
	PayoutProvider   string
	SMSProvider      string
	OTPProvider      string
}

// DatabaseEvidence captures live database server identity.
type DatabaseEvidence struct {
	DatabaseName          string
	DatabaseHost          string
	DatabasePort          int
	ServerVersion         string
	IsDisposableTmpfs     bool
	HasPersistentMounts   bool
	ConnectionFingerprint string
}

// SchemaEvidence captures schema presence in the target database.
type SchemaEvidence struct {
	PresentTables []string
	MissingTables []string
}

// ServicesEvidence captures live status of supporting QA services.
type ServicesEvidence struct {
	APIHealthy      bool
	APIBaseURL      string
	APIEnvironment  string
	OTPInboxHealthy bool
	OTPInboxURL     string
}

// FullIsolationReport combines all inspected evidence into one verifiable report.
type FullIsolationReport struct {
	InspectedAt time.Time
	Environment EnvironmentEvidence
	Database    DatabaseEvidence
	Schema      SchemaEvidence
	Services    ServicesEvidence
}

// LiveIsolationInspector defines the read-only contract for querying runtime facts.
type LiveIsolationInspector interface {
	InspectEnvironment(ctx context.Context) (EnvironmentEvidence, error)
	InspectDatabase(ctx context.Context) (DatabaseEvidence, error)
	InspectSchema(ctx context.Context) (SchemaEvidence, error)
	InspectServices(ctx context.Context) (ServicesEvidence, error)
}

// VerifyAuthoritativeIsolation executes the full suite of isolation checks.
// It fails closed on any mismatch, production trace, or unavailable service.
func VerifyAuthoritativeIsolation(ctx context.Context, inspector LiveIsolationInspector) (*FullIsolationReport, error) {
	if inspector == nil {
		return nil, errors.New("isolation inspector is required")
	}

	envEv, err := inspector.InspectEnvironment(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to inspect environment: %w", err)
	}

	// 1. Environment validation
	envClean := strings.ToLower(strings.TrimSpace(envEv.AppEnv))
	if envClean != "qa" && envClean != "test" {
		return nil, fmt.Errorf("isolation violation: execution restricted to APP_ENV=qa or APP_ENV=test (got %q)", envEv.AppEnv)
	}
	if envEv.RealMoneyEnabled {
		return nil, errors.New("isolation violation: real money mode must be disabled (REAL_MONEY_ENABLED=false)")
	}
	if envEv.PayoutEnabled {
		return nil, errors.New("isolation violation: live payouts must be disabled (PAYOUT_ENABLED=false)")
	}

	payProvider := strings.ToLower(strings.TrimSpace(envEv.PaymentProvider))
	if payProvider != "sandbox" && payProvider != "fake" && payProvider != "qa" && payProvider != "none" && payProvider != "" {
		return nil, fmt.Errorf("isolation violation: live or unsupported payment provider %q", envEv.PaymentProvider)
	}

	payoutProvider := strings.ToLower(strings.TrimSpace(envEv.PayoutProvider))
	if payoutProvider != "sandbox" && payoutProvider != "fake" && payoutProvider != "qa" && payoutProvider != "none" && payoutProvider != "" {
		return nil, fmt.Errorf("isolation violation: live or unsupported payout provider %q", envEv.PayoutProvider)
	}

	smsProvider := strings.ToLower(strings.TrimSpace(envEv.SMSProvider))
	if smsProvider == "fast2sms" || strings.Contains(smsProvider, "live") || strings.Contains(smsProvider, "prod") {
		return nil, fmt.Errorf("isolation violation: live SMS provider %q must not be used in QA", envEv.SMSProvider)
	}

	// 2. Database validation
	dbEv, err := inspector.InspectDatabase(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to inspect database: %w", err)
	}
	if !isQAName(dbEv.DatabaseName) {
		return nil, fmt.Errorf("isolation violation: database %q is not a recognized disposable QA database", dbEv.DatabaseName)
	}
	if !dbEv.IsDisposableTmpfs || dbEv.HasPersistentMounts {
		return nil, errors.New("isolation violation: QA database must not have persistent mounts (tmpfs required)")
	}

	// 3. Schema validation
	schemaEv, err := inspector.InspectSchema(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to inspect schema: %w", err)
	}
	if len(schemaEv.MissingTables) > 0 {
		return nil, fmt.Errorf("isolation violation: database %q is missing required schema tables: %s", dbEv.DatabaseName, strings.Join(schemaEv.MissingTables, ", "))
	}

	// 4. Services validation
	servEv, err := inspector.InspectServices(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to inspect QA services: %w", err)
	}
	if !servEv.APIHealthy {
		return nil, fmt.Errorf("isolation violation: QA API at %s is not healthy or unreachable", servEv.APIBaseURL)
	}
	if !strings.EqualFold(servEv.APIEnvironment, "qa") && !strings.EqualFold(servEv.APIEnvironment, "test") {
		return nil, fmt.Errorf("isolation violation: QA API reports non-QA environment %q", servEv.APIEnvironment)
	}
	if !servEv.OTPInboxHealthy {
		return nil, fmt.Errorf("isolation violation: QA OTP inbox at %s is unreachable", servEv.OTPInboxURL)
	}

	return &FullIsolationReport{
		InspectedAt: time.Now().UTC(),
		Environment: envEv,
		Database:    dbEv,
		Schema:      schemaEv,
		Services:    servEv,
	}, nil
}

// SQLDatabaseInspector implements LiveIsolationInspector using a *sql.DB and standard HTTP client.
type SQLDatabaseInspector struct {
	DB          *sql.DB
	DBName      string
	DBHost      string
	DBPort      int
	TmpfsBacked bool
	Env         EnvironmentEvidence
	APIBaseURL  string
	OTPInboxURL string
	HTTPClient  *http.Client
}

func (s *SQLDatabaseInspector) InspectEnvironment(ctx context.Context) (EnvironmentEvidence, error) {
	return s.Env, nil
}

func (s *SQLDatabaseInspector) InspectDatabase(ctx context.Context) (DatabaseEvidence, error) {
	if s.DB == nil {
		return DatabaseEvidence{}, errors.New("database connection is nil")
	}
	var currentDB, version string
	err := s.DB.QueryRowContext(ctx, "SELECT current_database(), version()").Scan(&currentDB, &version)
	if err != nil {
		return DatabaseEvidence{}, fmt.Errorf("failed to query database identity: %w", err)
	}
	if s.DBName != "" && !strings.EqualFold(currentDB, s.DBName) {
		return DatabaseEvidence{}, fmt.Errorf("connected database name %q does not match configured target %q", currentDB, s.DBName)
	}
	return DatabaseEvidence{
		DatabaseName:          currentDB,
		DatabaseHost:          s.DBHost,
		DatabasePort:          s.DBPort,
		ServerVersion:         version,
		IsDisposableTmpfs:     s.TmpfsBacked,
		HasPersistentMounts:   !s.TmpfsBacked,
		ConnectionFingerprint: fmt.Sprintf("%s@%s:%d", currentDB, s.DBHost, s.DBPort),
	}, nil
}

func (s *SQLDatabaseInspector) InspectSchema(ctx context.Context) (SchemaEvidence, error) {
	if s.DB == nil {
		return SchemaEvidence{}, errors.New("database connection is nil")
	}
	rows, err := s.DB.QueryContext(ctx, "SELECT table_name FROM information_schema.tables WHERE table_schema='public'")
	if err != nil {
		return SchemaEvidence{}, fmt.Errorf("failed to query tables: %w", err)
	}
	defer rows.Close()

	presentMap := make(map[string]bool)
	var present []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return SchemaEvidence{}, err
		}
		presentMap[name] = true
		present = append(present, name)
	}

	if err := rows.Err(); err != nil {
		return SchemaEvidence{}, err
	}

	var missing []string
	for _, req := range RequiredSchemaTables {
		if !presentMap[req] {
			missing = append(missing, req)
		}
	}
	return SchemaEvidence{
		PresentTables: present,
		MissingTables: missing,
	}, nil
}

func (s *SQLDatabaseInspector) InspectServices(ctx context.Context) (ServicesEvidence, error) {
	client := s.HTTPClient
	if client == nil {
		client = &http.Client{Timeout: 3 * time.Second}
	}

	apiHealthy := false
	apiEnv := ""
	if s.APIBaseURL != "" {
		req, _ := http.NewRequestWithContext(ctx, "GET", strings.TrimRight(s.APIBaseURL, "/")+"/healthz", nil)
		if resp, err := client.Do(req); err == nil {
			apiHealthy = resp.StatusCode == http.StatusOK
			apiEnv = resp.Header.Get("X-App-Env")
			if apiEnv == "" {
				apiEnv = s.Env.AppEnv
			}
			resp.Body.Close()
		}
	}

	otpHealthy := false
	if s.OTPInboxURL != "" {
		req, _ := http.NewRequestWithContext(ctx, "GET", strings.TrimRight(s.OTPInboxURL, "/")+"/healthz", nil)
		if resp, err := client.Do(req); err == nil {
			otpHealthy = resp.StatusCode == http.StatusOK || resp.StatusCode == http.StatusNoContent
			resp.Body.Close()
		}
	}

	return ServicesEvidence{
		APIHealthy:      apiHealthy,
		APIBaseURL:      s.APIBaseURL,
		APIEnvironment:  apiEnv,
		OTPInboxHealthy: otpHealthy,
		OTPInboxURL:     s.OTPInboxURL,
	}, nil
}
