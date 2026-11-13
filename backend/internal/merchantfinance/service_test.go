package merchantfinance

import (
	"context"
	"net/http/httptest"
	"os"
	"testing"

	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/jmoiron/sqlx"
	"grepmind-near/backend/pkg/database"
)

func TestCommissionAmountIntegerPaise(t *testing.T) {
	tests := []struct {
		name        string
		basis, rate int64
		typ         string
		want        int64
		wantErr     bool
	}{
		{name: "percentage example", basis: 100000, rate: 1000, typ: "percentage_bps", want: 10000},
		{name: "half up rounds one paise", basis: 1, rate: 5000, typ: "percentage_bps", want: 1},
		{name: "below half rounds to zero", basis: 1, rate: 4999, typ: "percentage_bps", want: 0},
		{name: "fixed paise", basis: 1000, rate: 125, typ: "fixed_minor", want: 125},
		{name: "fixed above basis rejected", basis: 100, rate: 101, typ: "fixed_minor", wantErr: true},
		{name: "percentage above basis rejected", basis: 100, rate: 10001, typ: "percentage_bps", wantErr: true},
		{name: "negative input rejected", basis: -1, rate: 100, typ: "fixed_minor", wantErr: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := commissionAmount(tt.basis, tt.typ, tt.rate)
			if (err != nil) != tt.wantErr {
				t.Fatalf("commissionAmount() error=%v wantErr=%v", err, tt.wantErr)
			}
			if err == nil && got != tt.want {
				t.Fatalf("commissionAmount()=%d want %d", got, tt.want)
			}
		})
	}
}

func TestSettlementTransitionSQLUsesNonConflictingParameters(t *testing.T) {
	tests := map[string]string{
		"review":    "reviewed_by=$3,reviewed_at=now(),review_reason=$4",
		"approve":   "approved_by=$3,approved_at=now(),approval_reason=$4",
		"simulate":  "simulated_by=$3,simulated_at=now(),simulation_reason=$4,financial_journal_id=$5",
		"reconcile": "reconciled_at=now()",
	}
	for action, want := range tests {
		t.Run(action, func(t *testing.T) {
			got, ok := settlementTransitionUpdate(action)
			if !ok || got != want {
				t.Fatalf("settlementTransitionUpdate(%q)=(%q,%t), want (%q,true)", action, got, ok, want)
			}
			args := settlementTransitionArgs(action, "batch", "next", "actor", "reason", "journal")
			wantArgs := map[string]int{"review": 4, "approve": 4, "simulate": 5, "reconcile": 2}[action]
			if len(args) != wantArgs {
				t.Fatalf("settlementTransitionArgs(%q) returned %d args, want %d", action, len(args), wantArgs)
			}
		})
	}
	if _, ok := settlementTransitionUpdate("unexpected"); ok {
		t.Fatal("unsupported action unexpectedly returned a SQL update")
	}
	if args := settlementTransitionArgs("unexpected", "batch", "next", "actor", "reason", "journal"); args != nil {
		t.Fatalf("unsupported action returned args: %#v", args)
	}
}

func TestMerchantFinanceUnavailableOutsideQA(t *testing.T) {
	db := database.DB{}
	svc := NewService(&db, "production")
	r := httptest.NewRequest("GET", "/api/v1/admin/finance/payables", nil)
	w := httptest.NewRecorder()
	svc.ListPayables(w, r, "00000000-0000-4000-8000-000000000001")
	if w.Code != 404 {
		t.Fatalf("production finance simulation endpoint status=%d, want 404", w.Code)
	}
}

func TestMerchantSimulatedSettlementTotalIsBusinessScopedAndExcludesUnsimulatedPostGIS(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_DSN")
	if dsn == "" {
		t.Skip("TEST_DATABASE_DSN is not set; run scripts/qa/phase4d_merchant_settlement_simulation.sh")
	}
	db, err := sqlx.Connect("pgx", dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	tx, err := db.BeginTxx(context.Background(), nil)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback()
	if _, err := tx.Exec(`CREATE TEMP TABLE merchant_settlement_batches (business_id UUID NOT NULL, simulated_net_minor BIGINT NOT NULL, status TEXT NOT NULL)`); err != nil {
		t.Fatal(err)
	}
	if _, err := tx.Exec(`INSERT INTO merchant_settlement_batches VALUES
		('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',22000,'simulated'),
		('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',22000,'reconciled'),
		('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',99000,'approved'),
		('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',50000,'reconciled')`); err != nil {
		t.Fatal(err)
	}
	var total int64
	if err := tx.GetContext(context.Background(), &total, merchantSimulatedSettlementTotalQuery, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"); err != nil {
		t.Fatal(err)
	}
	if total != 44000 {
		t.Fatalf("merchant simulated settlement total=%d, want 44000 paise", total)
	}
}

func TestMerchantFinanceMigration035PostGIS(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_DSN")
	if dsn == "" {
		t.Skip("TEST_DATABASE_DSN is not set; run scripts/qa/phase4d_merchant_settlement_simulation.sh")
	}
	db, err := sqlx.Connect("pgx", dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	var columns, tables, accountCount, approvedPolicies int
	if err := db.GetContext(ctx, &columns, `SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='platform_customer_order_items' AND column_name IN ('partner_supply_price_minor','partner_supply_currency')`); err != nil {
		t.Fatal(err)
	}
	if columns != 2 {
		t.Fatalf("order-time supply snapshot columns=%d, want 2", columns)
	}
	if err := db.GetContext(ctx, &tables, `SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name IN ('merchant_commission_policies','merchant_finance_audit_events','merchant_payable_snapshots','merchant_payable_adjustments','merchant_settlement_qa_funding_pools','merchant_settlement_batches','merchant_settlement_batch_items','merchant_settlement_funding_allocations','merchant_settlement_events','merchant_reconciliation_exceptions')`); err != nil {
		t.Fatal(err)
	}
	if tables != 10 {
		t.Fatalf("Phase 4D tables=%d, want 10", tables)
	}
	if err := db.GetContext(ctx, &accountCount, `SELECT count(*) FROM financial_accounts WHERE account_code IN ('merchant_fulfillment_cost','merchant_payable_liability','platform_commission_clearing','simulated_merchant_settlement_clearing') AND currency='INR'`); err != nil {
		t.Fatal(err)
	}
	if accountCount != 4 {
		t.Fatalf("Phase 4D financial accounts=%d, want 4", accountCount)
	}
	var snapshotTriggerCount int
	if err := db.GetContext(ctx, &snapshotTriggerCount, `SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname='platform_customer_order_items' AND t.tgname='platform_order_partner_supply_snapshot_immutable' AND NOT t.tgisinternal`); err != nil {
		t.Fatal(err)
	}
	if snapshotTriggerCount != 1 {
		t.Fatalf("immutable order-time partner-supply trigger count=%d, want 1", snapshotTriggerCount)
	}
	if err := db.GetContext(ctx, &approvedPolicies, `SELECT count(*) FROM merchant_commission_policies WHERE status='approved'`); err != nil {
		t.Fatal(err)
	}
	if approvedPolicies != 0 {
		t.Fatalf("migration unexpectedly seeded %d approved commission policies", approvedPolicies)
	}
	var posting, sandbox, upi, cod, merchantSettlement, realMoney bool
	if err := db.QueryRowxContext(ctx, `SELECT financial_posting_enabled,sandbox_merchant_settlement_enabled,upi_enabled,cod_enabled,merchant_settlement_enabled,real_money_enabled FROM financial_feature_config WHERE singleton=true`).Scan(&posting, &sandbox, &upi, &cod, &merchantSettlement, &realMoney); err != nil {
		t.Fatal(err)
	}
	if posting || sandbox || upi || cod || merchantSettlement || realMoney {
		t.Fatalf("financial gates must default off; posting=%t simulation=%t upi=%t cod=%t settlement=%t live=%t", posting, sandbox, upi, cod, merchantSettlement, realMoney)
	}
}

func TestPayableSnapshotInsertSetsRequiredSourceEventPostGIS(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_DSN")
	if dsn == "" {
		t.Skip("TEST_DATABASE_DSN is not set; run scripts/qa/phase4d_merchant_settlement_simulation.sh")
	}
	db, err := sqlx.Connect("pgx", dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	tx, err := db.BeginTxx(context.Background(), nil)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback()
	_, err = tx.Exec(`CREATE TEMP TABLE merchant_payable_snapshots (
		id UUID PRIMARY KEY DEFAULT 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
		order_id UUID NOT NULL, business_id UUID NOT NULL, policy_id UUID NOT NULL,
		policy_version INTEGER NOT NULL, currency CHAR(3) NOT NULL,
		customer_gross_minor BIGINT NOT NULL, partner_gross_minor BIGINT NOT NULL,
		commission_basis_minor BIGINT NOT NULL, commission_minor BIGINT NOT NULL,
		net_payable_minor BIGINT NOT NULL, source_event_id TEXT NOT NULL,
		source_event TEXT NOT NULL CHECK (source_event='delivered_payment_verified'),
		payment_source TEXT NOT NULL, snapshot_hash BYTEA NOT NULL,
		financial_journal_id UUID NOT NULL UNIQUE, created_by UUID NOT NULL
	)`)
	if err != nil {
		t.Fatal(err)
	}
	payableID, err := insertPayableSnapshot(context.Background(), tx,
		"0a130595-310d-4cb2-ad4e-105694f74957",
		"3e000000-0000-4000-8000-000000000101",
		"f532ec05-8aa0-4825-9dca-9590e44711c7", 1,
		34500, 22000, 0, 22000, "sandbox_upi_capture", make([]byte, 32),
		"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "4c000000-0000-4000-8000-000000000005")
	if err != nil {
		t.Fatalf("insert payable snapshot: %v", err)
	}
	var sourceEvent string
	if err := tx.Get(&sourceEvent, `SELECT source_event FROM merchant_payable_snapshots WHERE id=$1`, payableID); err != nil {
		t.Fatal(err)
	}
	if sourceEvent != "delivered_payment_verified" {
		t.Fatalf("source_event=%q, want delivered_payment_verified", sourceEvent)
	}
}

func TestSettlementCreatedEventFundingModeJSONPostGIS(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_DSN")
	if dsn == "" {
		t.Skip("TEST_DATABASE_DSN is not set; run scripts/qa/phase4d_merchant_settlement_simulation.sh")
	}
	db, err := sqlx.Connect("pgx", dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	tx, err := db.BeginTxx(context.Background(), nil)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback()
	if _, err := tx.Exec(`CREATE TEMP TABLE merchant_settlement_events (
		batch_id UUID NOT NULL, actor_user_id UUID NOT NULL, event_type TEXT NOT NULL,
		reason TEXT NOT NULL, metadata JSONB NOT NULL
	)`); err != nil {
		t.Fatal(err)
	}
	if _, err := tx.Exec(insertSettlementCreatedEventQuery,
		"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
		"4c000000-0000-4000-8000-000000000005", int64(22000), "synthetic_qa_pool"); err != nil {
		t.Fatalf("insert settlement-created event: %v", err)
	}
	var fundingMode string
	var amount int64
	if err := tx.QueryRowx(`SELECT metadata->>'funding_mode', (metadata->>'simulated_net_minor')::bigint FROM merchant_settlement_events`).Scan(&fundingMode, &amount); err != nil {
		t.Fatal(err)
	}
	if fundingMode != "synthetic_qa_pool" || amount != 22000 {
		t.Fatalf("event metadata=(%q,%d), want (synthetic_qa_pool,22000)", fundingMode, amount)
	}
}

func TestCheckedAddInt64(t *testing.T) {
	max := int64(^uint64(0) >> 1)
	min := -max - 1
	tests := []struct {
		name       string
		a, b, want int64
		wantOK     bool
	}{
		{name: "positive", a: 100, b: 25, want: 125, wantOK: true},
		{name: "negative adjustment", a: 100, b: -25, want: 75, wantOK: true},
		{name: "positive overflow", a: max, b: 1},
		{name: "negative underflow", a: min, b: -1},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := checkedAddInt64(tt.a, tt.b)
			if got != tt.want || ok != tt.wantOK {
				t.Fatalf("checkedAddInt64(%d,%d)=(%d,%t), want (%d,%t)", tt.a, tt.b, got, ok, tt.want, tt.wantOK)
			}
		})
	}
}

func TestResolvePaymentMethodForLegacyOrders(t *testing.T) {
	tests := []struct {
		name, method, status string
		verifiedCapture      bool
		want                 string
	}{
		{name: "current UPI remains explicit", method: "upi", status: "paid", verifiedCapture: true, want: "upi"},
		{name: "legacy paid order needs verified sandbox capture", status: "paid", verifiedCapture: true, want: "upi"},
		{name: "legacy paid order without capture is not inferred", status: "paid", want: ""},
		{name: "legacy unpaid order is not inferred", status: "not_collected", verifiedCapture: true, want: ""},
		{name: "COD remains COD", method: "cash_on_delivery", status: "not_collected", want: "cash_on_delivery"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := resolvePaymentMethod(tt.method, tt.status, tt.verifiedCapture); got != tt.want {
				t.Fatalf("resolvePaymentMethod(%q, %q, %t)=%q, want %q", tt.method, tt.status, tt.verifiedCapture, got, tt.want)
			}
		})
	}
}

func TestNullableDBTextPreservesOptionalUUIDAsEmpty(t *testing.T) {
	if got := nullableDBText(nil); got != "" {
		t.Fatalf("nullableDBText(nil)=%q, want empty string", got)
	}
	if got := nullableDBText("3e000000-0000-4000-8000-000000000001"); got != "3e000000-0000-4000-8000-000000000001" {
		t.Fatalf("nullableDBText(uuid)=%q", got)
	}
}
