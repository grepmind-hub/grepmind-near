package financialledger

import (
	"context"
	"crypto/sha256"
	"errors"
	"os"
	"sync"
	"testing"

	"github.com/google/uuid"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/jmoiron/sqlx"
)

func TestFinancialFoundationPostGISAcceptance(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_DSN")
	if dsn == "" {
		t.Skip("TEST_DATABASE_DSN is not set; run scripts/qa/phase4a_financial_foundation.sh for disposable PostGIS acceptance")
	}
	db, err := sqlx.Connect("pgx", dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	var migrations int
	if err := db.Get(&migrations, `SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name IN ('financial_accounts','financial_journals','financial_postings','financial_feature_config','financial_access_grants','financial_audit_events')`); err != nil {
		t.Fatal(err)
	}
	if migrations != 6 {
		t.Fatalf("migration 030 schema incomplete: found %d foundation tables", migrations)
	}
	var upi, cod, settlement, realMoney, posting bool
	if err := db.QueryRowx(`SELECT upi_enabled,cod_enabled,merchant_settlement_enabled,real_money_enabled,financial_posting_enabled FROM financial_feature_config WHERE singleton=true`).Scan(&upi, &cod, &settlement, &realMoney, &posting); err != nil {
		t.Fatal(err)
	}
	if upi || cod || settlement || realMoney || posting {
		t.Fatal("financial/payment feature switches must default disabled")
	}

	var rootID string
	if err := db.Get(&rootID, `SELECT id::text FROM users WHERE phone_e164='+910000000000' AND status='active'`); err != nil {
		t.Fatal(err)
	}
	issuerID := uuid.NewString()
	approverID := uuid.NewString()
	adminID := uuid.NewString()
	customerID := uuid.NewString()
	for _, u := range []struct{ id, phone string }{{issuerID, "+9191" + uuid.NewString()[:8]}, {approverID, "+9192" + uuid.NewString()[:8]}, {adminID, "+9193" + uuid.NewString()[:8]}, {customerID, "+9194" + uuid.NewString()[:8]}} {
		if _, err := db.Exec(`INSERT INTO users(id,phone_e164,status) VALUES($1,$2,'active') ON CONFLICT(phone_e164) DO NOTHING`, u.id, u.phone); err != nil {
			t.Fatal(err)
		}
	}
	for _, id := range []string{issuerID, approverID, adminID} {
		if _, err := db.Exec(`INSERT INTO user_roles(user_id,role) VALUES($1,'admin') ON CONFLICT DO NOTHING`, id); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := db.Exec(`INSERT INTO financial_access_grants(user_id,permission,granted_by,approved_by,reason) VALUES($1,'finance.post',$2,$3,'Approved isolated ledger posting test')`, adminID, rootID, approverID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO financial_access_grants(user_id,permission,granted_by,approved_by,reason) VALUES($1,'finance.configure',$2,$3,'Approved isolated ledger configuration test')`, adminID, rootID, approverID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO financial_access_grants(user_id,permission,granted_by,approved_by,reason) VALUES($1,'finance.reverse',$2,$3,'Approved isolated ledger reversal test')`, adminID, rootID, approverID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO financial_access_grants(user_id,permission,granted_by,approved_by,reason) VALUES($1,'finance.read',$2,$2,'Self approval must be rejected')`, adminID, rootID); err == nil {
		t.Fatal("financial grant allowed issuer and approver to be the same user")
	}
	assetID, liabilityID := uuid.NewString(), uuid.NewString()
	for _, a := range []struct{ id, code, class, side string }{{assetID, "qa-cash-" + assetID[:8], "asset", "debit"}, {liabilityID, "qa-clearing-" + liabilityID[:8], "liability", "credit"}} {
		if _, err := db.Exec(`INSERT INTO financial_accounts(id,account_code,display_name,account_class,currency,normal_side) VALUES($1,$2,$3,$4,'INR',$5)`, a.id, a.code, a.code, a.class, a.side); err != nil {
			t.Fatal(err)
		}
	}
	legacyOrderID := uuid.NewString()
	legacyBusinessID := uuid.NewString()
	if _, err := db.Exec(`INSERT INTO businesses(id,owner_user_id,name,slug,category_slug,address_text,locality,city,postal_code,location,status,verification_status) VALUES($1,$2,'QA finance compatibility fixture',$3,'restaurant','QA address','QA locality','Cuttack','753001',ST_SetSRID(ST_MakePoint(85.9,20.5),4326)::geography,'approved','verified')`, legacyBusinessID, rootID, "qa-finance-"+legacyBusinessID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,reference_code,payment_status) VALUES($1,$2,$3,'food_delivery',$4,'not_collected')`, legacyOrderID, customerID, legacyBusinessID, "QA-4A-"+legacyOrderID); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRowx(`SELECT financial_posting_enabled FROM financial_feature_config WHERE singleton=true`).Scan(&posting); err != nil {
		t.Fatal(err)
	}
	if posting {
		t.Fatal("posting should remain disabled before explicit QA-only setup")
	}
	in := PostInput{Currency: "INR", SourceType: "qa_test", SourceID: uuid.NewString(), SourceEvent: "foundation_post", IdempotencyKey: "qa-ledger-" + uuid.NewString(), Description: "Synthetic accounting foundation acceptance", ActorUserID: adminID, Reason: "Disposable QA ledger test", Lines: []Line{{AccountID: assetID, Side: "debit", Amount: 125}, {AccountID: liabilityID, Side: "credit", Amount: 125}}}
	disabledTx, err := db.BeginTxx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := PostJournalTx(ctx, disabledTx, in); !errors.Is(err, ErrPostingDisabled) {
		_ = disabledTx.Rollback()
		t.Fatalf("posting must fail closed before authorized QA configuration, got %v", err)
	}
	_ = disabledTx.Rollback()
	disabledDB, err := db.BeginTxx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	disabledID := uuid.NewString()
	disabledHash := sha256.Sum256([]byte("db-disabled-posting-test"))
	if _, err := disabledDB.Exec(`INSERT INTO financial_journals(id,currency,source_type,source_id,source_event,idempotency_key,request_fingerprint,description,actor_user_id) VALUES($1,'INR','qa','disabled-post','test',$2,$3,'Disabled boundary test',$4)`, disabledID, "disabled-"+disabledID, disabledHash[:], adminID); err != nil {
		_ = disabledDB.Rollback()
		t.Fatal(err)
	}
	if _, err := disabledDB.Exec(`UPDATE financial_journals SET status='posted',posted_at=now() WHERE id=$1`, disabledID); err == nil {
		_ = disabledDB.Rollback()
		t.Fatal("database allowed posting while financial posting was disabled")
	}
	_ = disabledDB.Rollback()
	for _, feature := range []string{"upi_enabled", "cod_enabled", "merchant_settlement_enabled", "real_money_enabled"} {
		if _, err := db.Exec(`UPDATE financial_feature_config SET ` + feature + `=true WHERE singleton=true`); err == nil {
			t.Fatalf("migration 030 must keep %s disabled", feature)
		}
	}
	configureTx, err := db.BeginTxx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	if err := SetPostingEnabledTx(ctx, configureTx, adminID, true, "Enable isolated synthetic ledger QA"); err != nil {
		_ = configureTx.Rollback()
		t.Fatal(err)
	}
	if err := configureTx.Commit(); err != nil {
		t.Fatal(err)
	}

	// PostgreSQL deferred constraint trigger rejects an unbalanced journal at
	// transaction commit, even when application balance validation is bypassed.
	badTx, err := db.BeginTxx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	badID := uuid.NewString()
	fingerprint := sha256.Sum256([]byte("db-boundary-balance-test"))
	_, err = badTx.Exec(`INSERT INTO financial_journals(id,currency,source_type,source_id,source_event,idempotency_key,request_fingerprint,description,actor_user_id) VALUES($1,'INR','qa','unbalanced','test',$2,$3,'Unbalanced boundary test',$4)`, badID, "bad-"+badID, fingerprint[:], adminID)
	if err != nil {
		t.Fatal(err)
	}
	_, err = badTx.Exec(`INSERT INTO financial_postings(journal_id,account_id,currency,side,amount_minor) VALUES($1,$2,'INR','debit',100)`, badID, assetID)
	if err != nil {
		t.Fatal(err)
	}
	_, err = badTx.Exec(`UPDATE financial_journals SET status='posted',posted_at=now() WHERE id=$1`, badID)
	if err != nil {
		t.Fatal(err)
	}
	if err = badTx.Commit(); err == nil {
		t.Fatal("unbalanced posted journal committed")
	}
	unauthorizedDB, err := db.BeginTxx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	unauthorizedID := uuid.NewString()
	_, err = unauthorizedDB.Exec(`INSERT INTO financial_journals(id,currency,source_type,source_id,source_event,idempotency_key,request_fingerprint,description,actor_user_id) VALUES($1,'INR','qa','unauthorized-post','test',$2,$3,'Unauthorized direct DB post',$4)`, unauthorizedID, "unauthorized-"+unauthorizedID, fingerprint[:], customerID)
	if err != nil {
		t.Fatal(err)
	}
	_, err = unauthorizedDB.Exec(`UPDATE financial_journals SET status='posted',posted_at=now() WHERE id=$1`, unauthorizedID)
	if err == nil {
		_ = unauthorizedDB.Rollback()
		t.Fatal("database allowed unauthorized direct journal post")
	}
	_ = unauthorizedDB.Rollback()

	unauthorized, err := db.BeginTxx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := PostJournalTx(ctx, unauthorized, PostInput{Currency: "INR", SourceType: "qa", SourceID: "unauthorized", SourceEvent: "test", IdempotencyKey: "unauth-key-123", Description: "Unauthorized", ActorUserID: customerID, Lines: in.Lines}); !errors.Is(err, ErrUnauthorized) {
		t.Fatalf("expected finance authorization denial, got %v", err)
	}
	_ = unauthorized.Rollback()
	journal, err := db.BeginTxx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	first, err := PostJournalTx(ctx, journal, in)
	if err != nil {
		_ = journal.Rollback()
		t.Fatal(err)
	}
	duplicate, err := PostJournalTx(ctx, journal, in)
	if err != nil {
		_ = journal.Rollback()
		t.Fatal(err)
	}
	if first.ID != duplicate.ID {
		_ = journal.Rollback()
		t.Fatal("same transaction duplicate returned another journal")
	}
	if err := journal.Commit(); err != nil {
		t.Fatal(err)
	}

	// Same source and payload over separate requests returns the posted entry.
	retry, err := db.BeginTxx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	retried, err := PostJournalTx(ctx, retry, in)
	if err != nil {
		_ = retry.Rollback()
		t.Fatal(err)
	}
	if retried.ID != first.ID {
		_ = retry.Rollback()
		t.Fatal("retry did not return existing journal")
	}
	if err := retry.Commit(); err != nil {
		t.Fatal(err)
	}
	conflicting := in
	conflicting.Lines = []Line{{AccountID: assetID, Side: "debit", Amount: 126}, {AccountID: liabilityID, Side: "credit", Amount: 126}}
	conflictTx, err := db.BeginTxx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := PostJournalTx(ctx, conflictTx, conflicting); !errors.Is(err, ErrIdempotencyConflict) {
		_ = conflictTx.Rollback()
		t.Fatalf("changed payload reused an existing source without conflict: %v", err)
	}
	_ = conflictTx.Rollback()

	// Eight simultaneous identical submissions must produce one journal and
	// return the same journal ID to each caller.
	concurrent := in
	concurrent.SourceID = uuid.NewString()
	concurrent.IdempotencyKey = "qa-race-" + uuid.NewString()
	const workers = 8
	start := make(chan struct{})
	ids := make(chan string, workers)
	errs := make(chan error, workers)
	var wg sync.WaitGroup
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start
			tx, e := db.BeginTxx(ctx, nil)
			if e != nil {
				errs <- e
				return
			}
			j, e := PostJournalTx(ctx, tx, concurrent)
			if e != nil {
				_ = tx.Rollback()
				errs <- e
				return
			}
			if e = tx.Commit(); e != nil {
				errs <- e
				return
			}
			ids <- j.ID
		}()
	}
	close(start)
	wg.Wait()
	close(ids)
	close(errs)
	for e := range errs {
		t.Errorf("concurrent idempotent submission: %v", e)
	}
	var canonical string
	for id := range ids {
		if canonical == "" {
			canonical = id
		} else if canonical != id {
			t.Errorf("race returned multiple journal IDs: %s and %s", canonical, id)
		}
	}
	if canonical == "" {
		t.Fatal("concurrent submission did not post a journal")
	}
	var journalCount int
	if err := db.Get(&journalCount, `SELECT count(*) FROM financial_journals WHERE source_type=$1 AND source_id=$2 AND source_event=$3`, concurrent.SourceType, concurrent.SourceID, concurrent.SourceEvent); err != nil {
		t.Fatal(err)
	}
	if journalCount != 1 {
		t.Fatalf("concurrent source created %d journals; want 1", journalCount)
	}

	// A reversal appends opposite postings. The original journal remains posted
	// and immutable; a second reversal is rejected.
	reverseTx, err := db.BeginTxx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	reversed, err := ReverseJournalTx(ctx, reverseTx, first.ID, "qa-reversal-"+uuid.NewString(), adminID, "Synthetic reversal for acceptance test")
	if err != nil {
		_ = reverseTx.Rollback()
		t.Fatal(err)
	}
	if err := reverseTx.Commit(); err != nil {
		t.Fatal(err)
	}
	var originalStatus string
	if err := db.Get(&originalStatus, `SELECT status FROM financial_journals WHERE id=$1`, first.ID); err != nil {
		t.Fatal(err)
	}
	if originalStatus != "posted" {
		t.Fatalf("original journal changed to %s", originalStatus)
	}
	if _, err := db.Exec(`UPDATE financial_journals SET description='tampered' WHERE id=$1`, first.ID); err == nil {
		t.Fatal("posted journal update was allowed")
	}
	if _, err := db.Exec(`DELETE FROM financial_journals WHERE id=$1`, first.ID); err == nil {
		t.Fatal("posted journal deletion was allowed")
	}
	if _, err := db.Exec(`UPDATE financial_postings SET amount_minor=amount_minor+1 WHERE journal_id=$1`, first.ID); err == nil {
		t.Fatal("posted journal posting mutation was allowed")
	}
	secondReverse, err := db.BeginTxx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := ReverseJournalTx(ctx, secondReverse, first.ID, "qa-reversal-again-"+uuid.NewString(), adminID, "Duplicate reversal acceptance test"); !errors.Is(err, ErrJournalNotReversible) {
		_ = secondReverse.Rollback()
		t.Fatalf("second reversal not rejected: %v", err)
	}
	_ = secondReverse.Rollback()
	var totalDebit, totalCredit int64
	if err := db.QueryRowx(`SELECT sum(amount_minor) FILTER(WHERE side='debit'),sum(amount_minor) FILTER(WHERE side='credit') FROM financial_postings WHERE journal_id IN ($1,$2)`, first.ID, reversed.ID).Scan(&totalDebit, &totalCredit); err != nil {
		t.Fatal(err)
	}
	if totalDebit != 250 || totalCredit != 250 {
		t.Fatalf("original/reversal totals do not balance: debit=%d credit=%d", totalDebit, totalCredit)
	}

	var historicalPaymentStatus string
	if err := db.Get(&historicalPaymentStatus, `SELECT payment_status FROM customer_orders WHERE id=$1`, legacyOrderID); err != nil {
		t.Fatal(err)
	}
	if historicalPaymentStatus != "not_collected" {
		t.Fatalf("historical not_collected order payment state changed to %s", historicalPaymentStatus)
	}
	var auditCount int
	if err := db.Get(&auditCount, `SELECT count(*) FROM financial_audit_events WHERE journal_id IN ($1,$2)`, first.ID, reversed.ID); err != nil {
		t.Fatal(err)
	}
	if auditCount != 2 {
		t.Fatalf("expected posted+reversal audit records, found %d", auditCount)
	}
	if _, err := db.Exec(`UPDATE financial_audit_events SET reason='tampered' WHERE journal_id=$1`, first.ID); err == nil {
		t.Fatal("financial audit mutation was allowed")
	}
	if _, err := db.Exec(`DELETE FROM financial_audit_events WHERE journal_id=$1`, first.ID); err == nil {
		t.Fatal("financial audit deletion was allowed")
	}
	if _, err := db.Exec(`UPDATE financial_access_grants SET revoked_at=now(),revoked_by=$2,revocation_reason='QA revocation authorization check' WHERE user_id=$1 AND permission='finance.post'`, adminID, rootID); err != nil {
		t.Fatal(err)
	}
	accessCheck, err := db.BeginTxx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	if err := AuthorizeTx(ctx, accessCheck, adminID, "finance.post"); !errors.Is(err, ErrUnauthorized) {
		_ = accessCheck.Rollback()
		t.Fatalf("revoked financial grant still authorized access: %v", err)
	}
	_ = accessCheck.Rollback()
	var grantAudit int
	if err := db.Get(&grantAudit, `SELECT count(*) FROM financial_audit_events WHERE event_type IN ('access_granted','access_revoked')`); err != nil {
		t.Fatal(err)
	}
	if grantAudit != 4 {
		t.Fatalf("expected three grants plus a revocation in financial audit, got %d", grantAudit)
	}
}
