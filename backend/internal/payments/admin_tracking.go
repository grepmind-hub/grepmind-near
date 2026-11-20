package payments

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"
	"grepmind-near/backend/internal/financialledger"
)

const (
	adminAttemptLimit        = 25
	adminRefundLimit         = 25
	adminReconciliationLimit = 50
)

var orderReferencePattern = regexp.MustCompile(`^[A-Z0-9][A-Z0-9-]{0,63}$`)

type trackedOrder struct {
	ID            string  `db:"id" json:"id"`
	ReferenceCode string  `db:"reference_code" json:"reference_code"`
	Status        string  `db:"status" json:"status"`
	PaymentStatus string  `db:"payment_status" json:"payment_status"`
	PaymentMethod *string `db:"payment_method" json:"payment_method"`
	AmountMinor   int64   `db:"amount_minor" json:"amount_minor"`
	Currency      string  `db:"currency" json:"currency"`
}

type trackedAttempt struct {
	ID            string    `db:"id" json:"id"`
	AttemptNumber int       `db:"attempt_number" json:"attempt_number"`
	Provider      string    `db:"provider" json:"provider"`
	Status        string    `db:"status" json:"status"`
	AmountMinor   int64     `db:"amount_minor" json:"amount_minor"`
	Currency      string    `db:"currency" json:"currency"`
	CapturePosted bool      `db:"capture_posted" json:"capture_posted"`
	UpdatedAt     time.Time `db:"updated_at" json:"updated_at"`
}

type trackedRefund struct {
	ID            string    `db:"id" json:"id"`
	AttemptID     string    `db:"attempt_id" json:"attempt_id"`
	AttemptNumber int       `db:"attempt_number" json:"attempt_number"`
	Provider      string    `db:"provider" json:"provider"`
	AmountMinor   int64     `db:"amount_minor" json:"amount_minor"`
	Currency      string    `db:"currency" json:"currency"`
	Status        string    `db:"status" json:"status"`
	CreatedAt     time.Time `db:"created_at" json:"created_at"`
}

type trackedReconciliation struct {
	ID             string    `db:"id" json:"id"`
	AttemptID      string    `db:"attempt_id" json:"attempt_id"`
	AttemptNumber  int       `db:"attempt_number" json:"attempt_number"`
	Outcome        string    `db:"outcome" json:"outcome"`
	ProviderStatus *string   `db:"provider_status" json:"provider_status"`
	CreatedAt      time.Time `db:"created_at" json:"created_at"`
}

// AdminTrackOrder returns the recorded payment history for one exact order.
func (s *Service) AdminTrackOrder(w http.ResponseWriter, r *http.Request, userID string) {
	w.Header().Set("Cache-Control", "no-store")
	ctx := r.Context()
	tx, err := s.db.BeginTxx(ctx, &sql.TxOptions{Isolation: sql.LevelRepeatableRead, ReadOnly: true})
	if err != nil {
		writeTrackingFailure(w)
		return
	}
	defer tx.Rollback()
	if err := financialledger.AuthorizeReadTx(ctx, tx, userID); err != nil {
		writeFailure(w, http.StatusForbidden, "FORBIDDEN", "Active Platform Admin access is required.")
		return
	}

	key := strings.ToUpper(strings.TrimSpace(r.PathValue("reference")))
	if !orderReferencePattern.MatchString(key) {
		writeFailure(w, http.StatusBadRequest, "INVALID_ORDER_REFERENCE", "Enter an order reference or UUID.")
		return
	}
	var orderID any
	if parsed, err := uuid.Parse(key); err == nil && len(key) == 36 {
		orderID = parsed.String()
	}
	data := struct {
		Order          trackedOrder            `json:"order"`
		Intent         *intent                 `json:"intent"`
		Attempts       []trackedAttempt        `json:"attempts"`
		Refunds        []trackedRefund         `json:"refunds"`
		MoreRefunds    bool                    `json:"more_refunds"`
		Reconciliation []trackedReconciliation `json:"reconciliation"`
		MoreAttempts   bool                    `json:"more_attempts"`
		MoreEvents     bool                    `json:"more_reconciliation_events"`
	}{
		Attempts:       []trackedAttempt{},
		Refunds:        []trackedRefund{},
		Reconciliation: []trackedReconciliation{},
	}
	err = tx.GetContext(ctx, &data.Order, `
		SELECT id::text, reference_code, status, payment_status, payment_method,
		       round(grand_total * 100)::bigint AS amount_minor, currency
		FROM customer_orders
		WHERE ($1::uuid IS NOT NULL AND id=$1) OR ($1::uuid IS NULL AND reference_code=$2)
	`, orderID, key)
	if errors.Is(err, sql.ErrNoRows) {
		writeFailure(w, http.StatusNotFound, "ORDER_NOT_FOUND", "No order matches that reference.")
		return
	}
	if err != nil {
		writeTrackingFailure(w)
		return
	}

	var paymentIntent intent
	err = tx.GetContext(ctx, &paymentIntent, `
		SELECT id::text, order_id::text, amount_minor, currency, status, created_at
		FROM payment_intents WHERE order_id=$1
	`, data.Order.ID)
	switch {
	case errors.Is(err, sql.ErrNoRows):
	case err != nil:
		writeTrackingFailure(w)
		return
	default:
		data.Intent = &paymentIntent
		if err := tx.SelectContext(ctx, &data.Attempts, `
			SELECT id::text, attempt_number, provider, status, amount_minor, currency, updated_at,
			       EXISTS (SELECT 1 FROM financial_journals j
			               WHERE j.source_id=a.id::text AND j.source_type='sandbox_payment_capture'
			                 AND j.source_event='verified_capture' AND j.status='posted') AS capture_posted
			FROM payment_attempts a WHERE payment_intent_id=$1
			ORDER BY attempt_number DESC LIMIT $2
		`, paymentIntent.ID, adminAttemptLimit+1); err != nil {
			writeTrackingFailure(w)
			return
		}
		if err := tx.SelectContext(ctx, &data.Reconciliation, `
			SELECT e.id::text, a.id::text AS attempt_id, a.attempt_number, e.outcome, e.provider_status, e.created_at
			FROM payment_reconciliation_events e
			JOIN payment_attempts a ON a.id=e.payment_attempt_id
			WHERE a.payment_intent_id=$1
			ORDER BY e.created_at DESC, e.id DESC LIMIT $2
		`, paymentIntent.ID, adminReconciliationLimit+1); err != nil {
			writeTrackingFailure(w)
			return
		}
	}
	if err := tx.SelectContext(ctx, &data.Refunds, `
		SELECT r.id::text, a.id::text AS attempt_id, a.attempt_number, r.provider,
		       r.amount_minor, r.currency, r.status, r.created_at
		FROM payment_refunds r JOIN payment_attempts a ON a.id=r.payment_attempt_id
		WHERE r.order_id=$1 ORDER BY r.created_at DESC, r.id DESC LIMIT $2
	`, data.Order.ID, adminRefundLimit+1); err != nil {
		writeTrackingFailure(w)
		return
	}
	if len(data.Refunds) > adminRefundLimit {
		data.Refunds = data.Refunds[:adminRefundLimit]
		data.MoreRefunds = true
	}
	if len(data.Attempts) > adminAttemptLimit {
		data.Attempts = data.Attempts[:adminAttemptLimit]
		data.MoreAttempts = true
	}
	if len(data.Reconciliation) > adminReconciliationLimit {
		data.Reconciliation = data.Reconciliation[:adminReconciliationLimit]
		data.MoreEvents = true
	}
	if err := tx.Commit(); err != nil {
		writeTrackingFailure(w)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"data": data})
}

func writeTrackingFailure(w http.ResponseWriter) {
	writeFailure(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Payment tracking could not be loaded.")
}
