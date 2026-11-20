package qafixtures

import (
	"context"
	"strings"
	"testing"
)

func TestVerifyAuthoritativeIsolation_Valid(t *testing.T) {
	ctx := context.Background()
	insp := ValidMockIsolationInspector()

	report, err := VerifyAuthoritativeIsolation(ctx, insp)
	if err != nil {
		t.Fatalf("expected valid isolation to pass, got: %v", err)
	}
	if report == nil {
		t.Fatal("expected non-nil isolation report")
	}
	if report.Database.DatabaseName != "grepmind_3e_qa" {
		t.Fatalf("unexpected DB name: %s", report.Database.DatabaseName)
	}
}

func TestVerifyAuthoritativeIsolation_RejectsProductionAndSharedDB(t *testing.T) {
	ctx := context.Background()

	badDBs := []string{
		"grepmind_near",
		"grepmind_prod",
		"grepmind_production",
		"grepmind_shared",
		"grepmind_development",
		"near_live",
	}

	for _, dbName := range badDBs {
		t.Run("db_"+dbName, func(t *testing.T) {
			insp := ValidMockIsolationInspector()
			insp.Database.DatabaseName = dbName

			_, err := VerifyAuthoritativeIsolation(ctx, insp)
			if err == nil {
				t.Fatalf("expected rejection for database %q", dbName)
			}
			if !strings.Contains(err.Error(), "isolation violation") {
				t.Fatalf("expected isolation violation error, got: %v", err)
			}
		})
	}
}

func TestVerifyAuthoritativeIsolation_RejectsPersistentMounts(t *testing.T) {
	ctx := context.Background()
	insp := ValidMockIsolationInspector()
	insp.Database.HasPersistentMounts = true

	_, err := VerifyAuthoritativeIsolation(ctx, insp)
	if err == nil {
		t.Fatal("expected rejection for database with persistent mounts")
	}
	if !strings.Contains(err.Error(), "persistent mounts") {
		t.Fatalf("expected persistent mounts violation, got: %v", err)
	}
}

func TestVerifyAuthoritativeIsolation_RejectsMissingSchema(t *testing.T) {
	ctx := context.Background()
	insp := ValidMockIsolationInspector()
	insp.Schema.MissingTables = []string{"bank_beneficiaries", "rider_settlement_batches"}

	_, err := VerifyAuthoritativeIsolation(ctx, insp)
	if err == nil {
		t.Fatal("expected rejection for missing required schema tables")
	}
	if !strings.Contains(err.Error(), "missing required schema tables") {
		t.Fatalf("expected missing schema error, got: %v", err)
	}
}

func TestVerifyAuthoritativeIsolation_RejectsLiveMoneyAndPayoutFlags(t *testing.T) {
	ctx := context.Background()

	t.Run("real_money_enabled", func(t *testing.T) {
		insp := ValidMockIsolationInspector()
		insp.Env.RealMoneyEnabled = true
		if _, err := VerifyAuthoritativeIsolation(ctx, insp); err == nil {
			t.Fatal("expected rejection when real money is enabled")
		}
	})

	t.Run("payout_enabled", func(t *testing.T) {
		insp := ValidMockIsolationInspector()
		insp.Env.PayoutEnabled = true
		if _, err := VerifyAuthoritativeIsolation(ctx, insp); err == nil {
			t.Fatal("expected rejection when live payout is enabled")
		}
	})
}

func TestVerifyAuthoritativeIsolation_RejectsLiveProviders(t *testing.T) {
	ctx := context.Background()

	t.Run("live_sms_fast2sms", func(t *testing.T) {
		insp := ValidMockIsolationInspector()
		insp.Env.SMSProvider = "fast2sms"
		if _, err := VerifyAuthoritativeIsolation(ctx, insp); err == nil {
			t.Fatal("expected rejection for fast2sms live SMS provider")
		}
	})

	t.Run("live_payment_provider", func(t *testing.T) {
		insp := ValidMockIsolationInspector()
		insp.Env.PaymentProvider = "stripe_live"
		if _, err := VerifyAuthoritativeIsolation(ctx, insp); err == nil {
			t.Fatal("expected rejection for live payment provider")
		}
	})

	t.Run("live_payout_provider", func(t *testing.T) {
		insp := ValidMockIsolationInspector()
		insp.Env.PayoutProvider = "razorpayx_live"
		if _, err := VerifyAuthoritativeIsolation(ctx, insp); err == nil {
			t.Fatal("expected rejection for live payout provider")
		}
	})
}

func TestVerifyAuthoritativeIsolation_RejectsUnhealthyOrNonQAServices(t *testing.T) {
	ctx := context.Background()

	t.Run("api_unhealthy", func(t *testing.T) {
		insp := ValidMockIsolationInspector()
		insp.Services.APIHealthy = false
		if _, err := VerifyAuthoritativeIsolation(ctx, insp); err == nil {
			t.Fatal("expected rejection when QA API is unhealthy")
		}
	})

	t.Run("api_production_env", func(t *testing.T) {
		insp := ValidMockIsolationInspector()
		insp.Services.APIEnvironment = "production"
		if _, err := VerifyAuthoritativeIsolation(ctx, insp); err == nil {
			t.Fatal("expected rejection when QA API reports production env")
		}
	})

	t.Run("otp_inbox_unhealthy", func(t *testing.T) {
		insp := ValidMockIsolationInspector()
		insp.Services.OTPInboxHealthy = false
		if _, err := VerifyAuthoritativeIsolation(ctx, insp); err == nil {
			t.Fatal("expected rejection when QA OTP inbox is unreachable")
		}
	})
}

func TestVerifyAuthoritativeIsolation_InspectorErrorsFailClosed(t *testing.T) {
	ctx := context.Background()

	t.Run("env_error", func(t *testing.T) {
		insp := ValidMockIsolationInspector()
		insp.FailEnv = true
		if _, err := VerifyAuthoritativeIsolation(ctx, insp); err == nil {
			t.Fatal("expected fail-closed on env error")
		}
	})

	t.Run("db_error", func(t *testing.T) {
		insp := ValidMockIsolationInspector()
		insp.FailDatabase = true
		if _, err := VerifyAuthoritativeIsolation(ctx, insp); err == nil {
			t.Fatal("expected fail-closed on db error")
		}
	})

	t.Run("schema_error", func(t *testing.T) {
		insp := ValidMockIsolationInspector()
		insp.FailSchema = true
		if _, err := VerifyAuthoritativeIsolation(ctx, insp); err == nil {
			t.Fatal("expected fail-closed on schema error")
		}
	})

	t.Run("services_error", func(t *testing.T) {
		insp := ValidMockIsolationInspector()
		insp.FailServices = true
		if _, err := VerifyAuthoritativeIsolation(ctx, insp); err == nil {
			t.Fatal("expected fail-closed on services error")
		}
	})
}
