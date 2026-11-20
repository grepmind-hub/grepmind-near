package payments

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
)

type reconciliationPage struct {
	view, status, outcome, reference string
	orderID, attemptID, cursorID     *string
	from, until, cursorTime          *time.Time
	limit                            int
}

func parseReconciliationPage(values url.Values) (reconciliationPage, error) {
	page := reconciliationPage{
		view: values.Get("view"), status: values.Get("status"), outcome: values.Get("outcome"),
		limit: 20,
	}
	if page.view != "needs_action" && page.view != "history" {
		return page, errors.New("Choose needs_action or history.")
	}
	if raw := values.Get("limit"); raw != "" {
		limit, err := strconv.Atoi(raw)
		if err != nil || limit < 1 || limit > adminQueueLimit {
			return page, errors.New("Limit must be between 1 and 50.")
		}
		page.limit = limit
	}
	switch page.status {
	case "", "initialized", "session_created", "pending", "succeeded", "failed", "expired", "reconciliation_required":
	default:
		return page, errors.New("Unsupported payment attempt status.")
	}
	switch page.outcome {
	case "", "matched", "missing_webhook", "late_success", "amount_mismatch", "currency_mismatch", "unknown_reference", "provider_unavailable":
	default:
		return page, errors.New("Unsupported reconciliation outcome.")
	}
	if ref := strings.ToUpper(strings.TrimSpace(values.Get("reference"))); ref != "" {
		if !orderReferencePattern.MatchString(ref) {
			return page, errors.New("Enter a valid order reference or UUID.")
		}
		if id, err := uuid.Parse(ref); err == nil && len(ref) == 36 {
			parsed := id.String()
			page.orderID = &parsed
		} else {
			page.reference = ref
		}
	}
	if raw := values.Get("attempt_id"); raw != "" {
		id, err := uuid.Parse(raw)
		if err != nil || len(raw) != 36 {
			return page, errors.New("Invalid payment attempt ID.")
		}
		parsed := id.String()
		page.attemptID = &parsed
	}
	if raw := values.Get("from"); raw != "" {
		day, err := time.Parse(time.DateOnly, raw)
		if err != nil {
			return page, errors.New("Invalid start date. Use YYYY-MM-DD.")
		}
		page.from = &day
	}
	if raw := values.Get("to"); raw != "" {
		day, err := time.Parse(time.DateOnly, raw)
		if err != nil {
			return page, errors.New("Invalid end date. Use YYYY-MM-DD.")
		}
		if page.from != nil && day.Before(*page.from) {
			return page, errors.New("End date must be on or after the start date.")
		}
		nextDay := day.AddDate(0, 0, 1)
		page.until = &nextDay
	}
	if raw := values.Get("before"); raw != "" {
		// Match the order listing's timestamp|UUID cursor convention.
		if len(raw) > 128 {
			return page, errors.New("Invalid reconciliation page cursor.")
		}
		decoded, err := base64.RawURLEncoding.DecodeString(raw)
		stamp, identifier, found := strings.Cut(string(decoded), "|")
		cursorTime, timeErr := time.Parse(time.RFC3339Nano, stamp)
		cursorID, idErr := uuid.Parse(identifier)
		if err != nil || !found || timeErr != nil || idErr != nil || len(identifier) != 36 {
			return page, errors.New("Invalid reconciliation page cursor.")
		}
		id := cursorID.String()
		page.cursorTime, page.cursorID = &cursorTime, &id
	}
	return page, nil
}

const needsActionSource = `
	SELECT a.id, a.id AS attempt_id, 'action_required' AS kind, latest.outcome,
	       a.updated_at AS recorded_at, NULL::uuid AS actor_user_id
	FROM payment_attempts a
	LEFT JOIN LATERAL (
		SELECT e.outcome FROM payment_reconciliation_events e
		WHERE e.payment_attempt_id=a.id AND e.outcome<>'matched'
		ORDER BY e.created_at DESC, e.id DESC LIMIT 1
	) latest ON true
	WHERE a.status='reconciliation_required'
`

const recordedHistorySource = `
	SELECT e.id, e.payment_attempt_id AS attempt_id,
	       CASE WHEN e.outcome='matched' THEN 'recorded_event' ELSE 'recorded_exception' END AS kind,
	       e.outcome, e.created_at AS recorded_at, e.actor_user_id
	FROM payment_reconciliation_events e
`

func writeReconciliationPage(w http.ResponseWriter, r *http.Request, tx *sqlx.Tx) {
	page, err := parseReconciliationPage(r.URL.Query())
	if err != nil {
		writeFailure(w, http.StatusBadRequest, "VALIDATION_ERROR", err.Error())
		return
	}
	source := needsActionSource
	if page.view == "history" {
		source = recordedHistorySource
	}
	entries := []reconciliationQueueEntry{}
	err = tx.SelectContext(r.Context(), &entries, `
		WITH queue AS (`+source+`)
		SELECT q.id::text, q.kind, o.id::text AS order_id, o.reference_code, a.id::text AS attempt_id,
		       a.attempt_number, a.status AS attempt_status, q.outcome, a.amount_minor, a.currency, q.recorded_at,
		       q.actor_user_id::text AS actor_id, NULLIF(btrim(actor.display_name),'') AS actor_name
		FROM queue q
		JOIN payment_attempts a ON a.id=q.attempt_id
		JOIN payment_intents i ON i.id=a.payment_intent_id
		JOIN customer_orders o ON o.id=i.order_id
		LEFT JOIN users actor ON actor.id=q.actor_user_id
		WHERE ($1='' OR a.status=$1)
		  AND ($2='' OR q.outcome=$2)
		  AND ($3='' OR o.reference_code=$3)
		  AND ($4::uuid IS NULL OR o.id=$4)
		  AND ($5::uuid IS NULL OR a.id=$5)
		  AND ($6::timestamptz IS NULL OR q.recorded_at >= $6)
		  AND ($7::timestamptz IS NULL OR q.recorded_at < $7)
		  AND ($8::timestamptz IS NULL OR (q.recorded_at, q.id) < ($8,$9::uuid))
		ORDER BY q.recorded_at DESC, q.id DESC
		LIMIT $10
	`, page.status, page.outcome, page.reference, page.orderID, page.attemptID,
		page.from, page.until, page.cursorTime, page.cursorID, page.limit+1)
	if err != nil || tx.Commit() != nil {
		writeQueueFailure(w)
		return
	}

	more := len(entries) > page.limit
	meta := map[string]any{"view": page.view, "has_more": more}
	if more {
		entries = entries[:page.limit]
		last := entries[len(entries)-1]
		meta["next_cursor"] = base64.RawURLEncoding.EncodeToString([]byte(last.RecordedAt.UTC().Format(time.RFC3339Nano) + "|" + last.ID))
	}
	meta["count"] = len(entries)
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"data": entries, "more_results": more, "meta": meta})
}
