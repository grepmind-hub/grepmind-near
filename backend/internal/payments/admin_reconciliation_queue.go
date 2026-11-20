package payments

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"time"

	"grepmind-near/backend/internal/financialledger"
)

const adminQueueLimit = 50

type reconciliationQueueEntry struct {
	ID            string    `db:"id" json:"id"`
	Kind          string    `db:"kind" json:"kind"`
	OrderID       string    `db:"order_id" json:"order_id"`
	ReferenceCode string    `db:"reference_code" json:"reference_code"`
	AttemptID     string    `db:"attempt_id" json:"attempt_id"`
	AttemptNumber int       `db:"attempt_number" json:"attempt_number"`
	AttemptStatus string    `db:"attempt_status" json:"attempt_status"`
	Outcome       *string   `db:"outcome" json:"outcome"`
	AmountMinor   int64     `db:"amount_minor" json:"amount_minor"`
	Currency      string    `db:"currency" json:"currency"`
	RecordedAt    time.Time `db:"recorded_at" json:"recorded_at"`
	ActorID       *string   `db:"actor_id" json:"actor_id,omitempty"`
	ActorName     *string   `db:"actor_name" json:"actor_name,omitempty"`
}

// AdminReconciliationQueue returns current work ahead of historical exceptions.
func (s *Service) AdminReconciliationQueue(w http.ResponseWriter, r *http.Request, userID string) {
	w.Header().Set("Cache-Control", "no-store")
	ctx := r.Context()
	tx, err := s.db.BeginTxx(ctx, &sql.TxOptions{ReadOnly: true})
	if err != nil {
		writeQueueFailure(w)
		return
	}
	defer tx.Rollback()
	if err := financialledger.AuthorizeReadTx(ctx, tx, userID); err != nil {
		writeFailure(w, http.StatusForbidden, "FORBIDDEN", "Active Platform Admin access is required.")
		return
	}

	if r.URL.Query().Get("view") != "" {
		writeReconciliationPage(w, r, tx)
		return
	}

	// Limit each source before joining it to payment and order details.
	entries := []reconciliationQueueEntry{}
	err = tx.SelectContext(ctx, &entries, `
		WITH queue AS (
			(SELECT id, id AS attempt_id, 'action_required' AS kind, NULL::text AS outcome,
			        updated_at AS recorded_at, 0 AS priority
			 FROM payment_attempts
			 WHERE status='reconciliation_required'
			 ORDER BY updated_at DESC, id DESC LIMIT $1)
			UNION ALL
			(SELECT id, payment_attempt_id, 'recorded_exception', outcome, created_at, 1
			 FROM payment_reconciliation_events
			 WHERE outcome <> 'matched'
			 ORDER BY created_at DESC, id DESC LIMIT $1)
		)
		SELECT q.id::text, q.kind, o.id::text AS order_id, o.reference_code, a.id::text AS attempt_id,
		       a.attempt_number, a.status AS attempt_status, q.outcome, a.amount_minor, a.currency, q.recorded_at
		FROM queue q
		JOIN payment_attempts a ON a.id=q.attempt_id
		JOIN payment_intents i ON i.id=a.payment_intent_id
		JOIN customer_orders o ON o.id=i.order_id
		ORDER BY q.priority, q.recorded_at DESC, q.id DESC
		LIMIT $1
	`, adminQueueLimit+1)
	if err != nil {
		writeQueueFailure(w)
		return
	}
	if err := tx.Commit(); err != nil {
		writeQueueFailure(w)
		return
	}

	more := len(entries) > adminQueueLimit
	if more {
		entries = entries[:adminQueueLimit]
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"data": entries, "more_results": more})
}

func writeQueueFailure(w http.ResponseWriter) {
	writeFailure(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Payment reconciliation queue could not be loaded.")
}
