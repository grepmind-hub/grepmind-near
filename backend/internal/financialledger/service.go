package financialledger

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"math"
	"sort"
	"strings"

	"github.com/jmoiron/sqlx"
)

var (
	ErrPostingDisabled      = errors.New("financial posting is disabled")
	ErrUnauthorized         = errors.New("finance permission denied")
	ErrInvalidJournal       = errors.New("invalid financial journal")
	ErrIdempotencyConflict  = errors.New("financial idempotency key or source was reused with different content")
	ErrJournalNotReversible = errors.New("journal is missing, already reversed, or not posted")
)

type Line struct {
	AccountID string
	Side      string
	Amount    int64
	Memo      string
}

type Journal struct {
	ID       string
	Currency string
}

type PostInput struct {
	Currency       string
	SourceType     string
	SourceID       string
	SourceEvent    string
	IdempotencyKey string
	Description    string
	ActorUserID    string
	Reason         string
	Lines          []Line
}

// AuthorizeReadTx allows active Platform Admins to inspect stored finance records.
// Operations that contact providers or write financial state use AuthorizeTx.
func AuthorizeReadTx(ctx context.Context, tx *sqlx.Tx, actorID string) error {
	var allowed bool
	err := tx.GetContext(ctx, &allowed, `SELECT EXISTS (
		SELECT 1 FROM users u WHERE u.id=$1 AND u.status='active'
		AND (u.phone_e164='+910000000000' OR EXISTS (
			SELECT 1 FROM user_roles r WHERE r.user_id=u.id AND r.role='admin'
		))
	)`, actorID)
	if err != nil || !allowed {
		return ErrUnauthorized
	}
	return nil
}

// AuthorizeTx is deliberately independent from ordinary admin membership.
// The protected root account is the only unconditional principal; all other
// access requires a separately approved, active financial permission grant.
func AuthorizeTx(ctx context.Context, tx *sqlx.Tx, actorID, permission string) error {
	var allowed bool
	err := tx.GetContext(ctx, &allowed, `SELECT EXISTS (
		SELECT 1 FROM users u WHERE u.id=$1 AND u.status='active' AND u.phone_e164='+910000000000'
		UNION ALL
		SELECT 1 FROM users u JOIN user_roles r ON r.user_id=u.id AND r.role='admin'
		JOIN financial_access_grants g ON g.user_id=u.id AND g.permission=$2 AND g.revoked_at IS NULL
		WHERE u.id=$1 AND u.status='active'
	)`, actorID, permission)
	if err != nil || !allowed {
		return ErrUnauthorized
	}
	return nil
}

func PostJournalTx(ctx context.Context, tx *sqlx.Tx, in PostInput) (Journal, error) {
	return postJournalTx(ctx, tx, in, "finance.post", "")
}

// PostSandboxPaymentJournalTx is a narrowly scoped system posting path. It is
// valid only for an exact synthetic capture source while the audited sandbox
// and ledger gates are enabled and every live-money feature remains disabled.
func PostSandboxPaymentJournalTx(ctx context.Context, tx *sqlx.Tx, in PostInput) (Journal, error) {
	validCapture := in.SourceType == "sandbox_payment_capture" && in.SourceEvent == "verified_capture"
	validRefund := in.SourceType == "sandbox_payment_refund" && in.SourceEvent == "verified_refund"
	if in.ActorUserID != "" || (!validCapture && !validRefund) || in.Currency != "INR" {
		return Journal{}, ErrInvalidJournal
	}
	var allowed bool
	if err := tx.GetContext(ctx, &allowed, `SELECT financial_posting_enabled AND sandbox_payment_enabled AND NOT upi_enabled AND NOT cod_enabled AND NOT merchant_settlement_enabled AND NOT real_money_enabled FROM financial_feature_config WHERE singleton=true`); err != nil {
		return Journal{}, err
	}
	if !allowed {
		return Journal{}, ErrPostingDisabled
	}
	return postJournalCore(ctx, tx, in, "", "", true)
}

// PostSandboxCODJournalTx permits only synthetic COD collection and verified
// remittance journals while their separate QA gate is enabled. Real COD,
// UPI, settlement, and real-money switches must remain disabled.
func PostSandboxCODJournalTx(ctx context.Context, tx *sqlx.Tx, in PostInput) (Journal, error) {
	validCollection := in.SourceType == "sandbox_cod_collection" && in.SourceEvent == "collected"
	validRemittance := in.SourceType == "sandbox_cod_remittance" && in.SourceEvent == "verified"
	if in.ActorUserID != "" || (!validCollection && !validRemittance) || in.Currency != "INR" {
		return Journal{}, ErrInvalidJournal
	}
	var allowed bool
	if err := tx.GetContext(ctx, &allowed, `SELECT financial_posting_enabled AND sandbox_cod_enabled AND NOT upi_enabled AND NOT cod_enabled AND NOT merchant_settlement_enabled AND NOT real_money_enabled FROM financial_feature_config WHERE singleton=true`); err != nil {
		return Journal{}, err
	}
	if !allowed {
		return Journal{}, ErrPostingDisabled
	}
	return postJournalCore(ctx, tx, in, "", "", true)
}

// SetPostingEnabledTx is the only configuration mutation exposed by this
// foundation. Payment, COD, merchant settlement, and real-money switches are
// database-constrained off until later approved phases.
func SetPostingEnabledTx(ctx context.Context, tx *sqlx.Tx, actorID string, enabled bool, reason string) error {
	if len(strings.TrimSpace(reason)) < 10 || len(reason) > 500 {
		return ErrInvalidJournal
	}
	if err := AuthorizeTx(ctx, tx, actorID, "finance.configure"); err != nil {
		return err
	}
	_, err := tx.ExecContext(ctx, `UPDATE financial_feature_config SET financial_posting_enabled=$1,updated_by=$2,change_reason=$3,updated_at=now() WHERE singleton=true`, enabled, actorID, strings.TrimSpace(reason))
	return err
}

func postJournalTx(ctx context.Context, tx *sqlx.Tx, in PostInput, permission, reversesID string) (Journal, error) {
	return postJournalCore(ctx, tx, in, permission, reversesID, false)
}

func postJournalCore(ctx context.Context, tx *sqlx.Tx, in PostInput, permission, reversesID string, sandboxPayment bool) (Journal, error) {
	if err := validate(in); err != nil {
		return Journal{}, err
	}
	if !sandboxPayment {
		if err := AuthorizeTx(ctx, tx, in.ActorUserID, permission); err != nil {
			return Journal{}, err
		}
	}
	var enabled bool
	if err := tx.GetContext(ctx, &enabled, `SELECT financial_posting_enabled FROM financial_feature_config WHERE singleton=true`); err != nil {
		return Journal{}, err
	}
	if !enabled {
		return Journal{}, ErrPostingDisabled
	}
	fingerprint := fingerprint(in, reversesID)

	if existing, found, err := findExistingJournal(ctx, tx, in, fingerprint); err != nil {
		return Journal{}, err
	} else if found {
		return existing, nil
	}

	var id string
	err := tx.QueryRowxContext(ctx, `INSERT INTO financial_journals
		(currency,source_type,source_id,source_event,idempotency_key,request_fingerprint,description,reason,reverses_journal_id,actor_user_id)
		VALUES($1,$2,$3,$4,$5,$6,$7,NULLIF($8,''),NULLIF($9,'')::uuid,NULLIF($10,'')::uuid)
		ON CONFLICT DO NOTHING RETURNING id::text`,
		in.Currency, in.SourceType, in.SourceID, in.SourceEvent, in.IdempotencyKey, fingerprint, in.Description, in.Reason, reversesID, in.ActorUserID).Scan(&id)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			// A concurrent transaction may have won the unique source/idempotency race.
			found, ok, lookupErr := findExistingJournal(ctx, tx, in, fingerprint)
			if lookupErr != nil {
				return Journal{}, lookupErr
			}
			if !ok {
				return Journal{}, ErrIdempotencyConflict
			}
			return found, nil
		}
		return Journal{}, err
	}
	for _, line := range in.Lines {
		if _, err := tx.ExecContext(ctx, `INSERT INTO financial_postings(journal_id,account_id,currency,side,amount_minor,memo) VALUES($1,$2,$3,$4,$5,NULLIF($6,''))`, id, line.AccountID, in.Currency, line.Side, line.Amount, line.Memo); err != nil {
			return Journal{}, err
		}
	}
	if _, err := tx.ExecContext(ctx, `UPDATE financial_journals SET status='posted',posted_at=now() WHERE id=$1 AND status='draft'`, id); err != nil {
		return Journal{}, err
	}
	return Journal{ID: id, Currency: in.Currency}, nil
}

func findExistingJournal(ctx context.Context, tx *sqlx.Tx, in PostInput, expectedFingerprint []byte) (Journal, bool, error) {
	rows, err := tx.QueryxContext(ctx, `SELECT id::text,currency,status,idempotency_key,source_type,source_id,source_event,request_fingerprint
		FROM financial_journals WHERE idempotency_key=$1 OR (source_type=$2 AND source_id=$3 AND source_event=$4) FOR UPDATE`,
		in.IdempotencyKey, in.SourceType, in.SourceID, in.SourceEvent)
	if err != nil {
		return Journal{}, false, err
	}
	defer rows.Close()
	var found Journal
	var status, key, sourceType, sourceID, sourceEvent string
	var savedFingerprint []byte
	count := 0
	for rows.Next() {
		count++
		if count > 1 {
			continue
		}
		if err := rows.Scan(&found.ID, &found.Currency, &status, &key, &sourceType, &sourceID, &sourceEvent, &savedFingerprint); err != nil {
			return Journal{}, false, err
		}
	}
	if err := rows.Err(); err != nil {
		return Journal{}, false, err
	}
	if count == 0 {
		return Journal{}, false, nil
	}
	if count != 1 || found.Currency != in.Currency || status != "posted" || key != in.IdempotencyKey ||
		sourceType != in.SourceType || sourceID != in.SourceID || sourceEvent != in.SourceEvent || !equalBytes(savedFingerprint, expectedFingerprint) {
		return Journal{}, false, ErrIdempotencyConflict
	}
	return found, true, nil
}

// ReverseJournalTx creates an equal and opposite journal; it never edits the
// posted source journal. Partial refunds/adjustments are intentionally outside
// this foundation and require a later, explicitly designed operation.
func ReverseJournalTx(ctx context.Context, tx *sqlx.Tx, originalID, idempotencyKey, actorID, reason string) (Journal, error) {
	if strings.TrimSpace(reason) == "" {
		return Journal{}, ErrInvalidJournal
	}
	var original PostInput
	var status string
	err := tx.QueryRowxContext(ctx, `SELECT currency,source_type,source_id,source_event,idempotency_key,description,COALESCE(actor_user_id::text,'') ,status FROM financial_journals WHERE id=$1 FOR UPDATE`, originalID).
		Scan(&original.Currency, &original.SourceType, &original.SourceID, &original.SourceEvent, &original.IdempotencyKey, &original.Description, &original.ActorUserID, &status)
	if err != nil || status != "posted" {
		return Journal{}, ErrJournalNotReversible
	}
	if err := AuthorizeTx(ctx, tx, actorID, "finance.reverse"); err != nil {
		return Journal{}, err
	}
	var already bool
	if err := tx.GetContext(ctx, &already, `SELECT EXISTS(SELECT 1 FROM financial_journals WHERE reverses_journal_id=$1)`, originalID); err != nil {
		return Journal{}, err
	}
	if already {
		return Journal{}, ErrJournalNotReversible
	}
	rows, err := tx.QueryxContext(ctx, `SELECT account_id::text,CASE side WHEN 'debit' THEN 'credit' ELSE 'debit' END,amount_minor,COALESCE(memo,'') FROM financial_postings WHERE journal_id=$1 ORDER BY id`, originalID)
	if err != nil {
		return Journal{}, err
	}
	defer rows.Close()
	for rows.Next() {
		var l Line
		if err := rows.Scan(&l.AccountID, &l.Side, &l.Amount, &l.Memo); err != nil {
			return Journal{}, err
		}
		original.Lines = append(original.Lines, l)
	}
	if err := rows.Err(); err != nil {
		return Journal{}, err
	}
	original.SourceType = "journal_reversal"
	original.SourceID = originalID
	original.SourceEvent = "full_reversal"
	original.IdempotencyKey = idempotencyKey
	original.Description = "Reversal of journal " + originalID
	original.ActorUserID = actorID
	original.Reason = reason
	return postJournalTx(ctx, tx, original, "finance.reverse", originalID)
}

func validate(in PostInput) error {
	if len(in.Lines) < 2 || len(in.Lines) > 100 || len(in.Currency) != 3 || in.Currency != strings.ToUpper(in.Currency) ||
		strings.TrimSpace(in.SourceType) == "" || strings.TrimSpace(in.SourceID) == "" || strings.TrimSpace(in.SourceEvent) == "" ||
		strings.TrimSpace(in.IdempotencyKey) == "" || strings.TrimSpace(in.Description) == "" {
		return ErrInvalidJournal
	}
	var debit, credit int64
	for _, l := range in.Lines {
		if l.Amount <= 0 || (l.Side != "debit" && l.Side != "credit") || strings.TrimSpace(l.AccountID) == "" {
			return ErrInvalidJournal
		}
		if l.Side == "debit" {
			if debit > math.MaxInt64-l.Amount {
				return ErrInvalidJournal
			}
			debit += l.Amount
		} else {
			if credit > math.MaxInt64-l.Amount {
				return ErrInvalidJournal
			}
			credit += l.Amount
		}
	}
	if debit <= 0 || debit != credit {
		return ErrInvalidJournal
	}
	return nil
}

func fingerprint(in PostInput, reversesID string) []byte {
	lines := append([]Line(nil), in.Lines...)
	sort.Slice(lines, func(i, j int) bool {
		a, b := lines[i], lines[j]
		return fmt.Sprintf("%s|%s|%d|%s", a.AccountID, a.Side, a.Amount, a.Memo) < fmt.Sprintf("%s|%s|%d|%s", b.AccountID, b.Side, b.Amount, b.Memo)
	})
	var b strings.Builder
	fmt.Fprintf(&b, "%s|%s|%s|%s|%s|%s|%s|", in.Currency, in.SourceType, in.SourceID, in.SourceEvent, in.Description, in.Reason, reversesID)
	for _, l := range lines {
		fmt.Fprintf(&b, "%s|%s|%d|%s;", l.AccountID, l.Side, l.Amount, l.Memo)
	}
	sum := sha256.Sum256([]byte(b.String()))
	return sum[:]
}
func equalBytes(a, b []byte) bool { return hex.EncodeToString(a) == hex.EncodeToString(b) }
