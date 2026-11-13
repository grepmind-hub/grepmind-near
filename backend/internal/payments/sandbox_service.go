package payments

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
	"grepmind-near/backend/internal/financialledger"
	"grepmind-near/backend/pkg/logger"
)

var ErrWebhookReplayConflict = errors.New("provider event ID was replayed with different content")

type paymentAttempt struct {
	ID, IntentID, OrderID, Provider, ProviderReference, Status, Currency string
	AmountMinor                                                          int64
	ExpiresAt                                                            time.Time
}

// CreateSandboxSession creates an immutable attempt, then calls the provider
// outside the database transaction. The provider idempotency reference is
// stable so retrying an ambiguous call cannot create another sandbox session.
func (s *Service) CreateSandboxSession(w http.ResponseWriter, r *http.Request, userID string) {
	if s.provider == nil || s.provider.Name() != sandboxProviderName {
		writeFailure(w, http.StatusServiceUnavailable, "SANDBOX_PROVIDER_DISABLED", "Sandbox payments are unavailable.")
		return
	}
	if r.ContentLength > 0 {
		writeFailure(w, 400, "VALIDATION_ERROR", "Sandbox session creation does not accept client pricing or provider fields.")
		return
	}
	if r.Body != nil {
		body, bodyErr := io.ReadAll(http.MaxBytesReader(w, r.Body, 0))
		if len(body) != 0 || bodyErr != nil {
			writeFailure(w, 400, "VALIDATION_ERROR", "Sandbox session creation does not accept client pricing or provider fields.")
			return
		}
	}
	orderID, err := uuid.Parse(r.PathValue("id"))
	if err != nil {
		writeFailure(w, 400, "VALIDATION_ERROR", "A valid order ID is required.")
		return
	}
	key, err := uuid.Parse(r.Header.Get("Idempotency-Key"))
	if err != nil {
		writeFailure(w, 400, "PAYMENT_IDEMPOTENCY_KEY_REQUIRED", "A valid Idempotency-Key is required.")
		return
	}
	allowed, err := s.customerAllowed(r.Context(), userID)
	if err != nil {
		writeFailure(w, 500, "INTERNAL_ERROR", "Customer access could not be verified.")
		return
	}
	if !allowed {
		writeFailure(w, 403, "FORBIDDEN", "Customer access is required.")
		return
	}

	var attempt paymentAttempt
	replay := false
	err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var sandboxEnabled, attemptEnabled, upiEnabled, realMoney bool
		if err := tx.QueryRowxContext(r.Context(), `SELECT sandbox_payment_enabled,payment_attempt_creation_enabled,upi_enabled,real_money_enabled FROM financial_feature_config WHERE singleton=true FOR SHARE`).Scan(&sandboxEnabled, &attemptEnabled, &upiEnabled, &realMoney); err != nil {
			return err
		}
		if !sandboxEnabled || !attemptEnabled || upiEnabled || realMoney {
			return &apiFailure{503, "SANDBOX_PROVIDER_DISABLED", "Sandbox payment sessions are disabled."}
		}
		var intentID string
		var amount int64
		var currency string
		if err := tx.QueryRowxContext(r.Context(), `SELECT i.id::text,i.amount_minor,i.currency FROM payment_intents i JOIN customer_orders o ON o.id=i.order_id WHERE i.order_id=$1 AND i.customer_user_id=$2 AND o.customer_user_id=$2 FOR UPDATE OF i,o`, orderID.String(), userID).Scan(&intentID, &amount, &currency); err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return &apiFailure{404, "PAYMENT_INTENT_NOT_FOUND", "An owned payment intent was not found."}
			}
			return err
		}
		if amount <= 0 || currency != "INR" {
			return &apiFailure{409, "PAYMENT_NOT_ELIGIBLE", "Payment intent amount or currency is not eligible."}
		}
		var orderStatus, payStatus string
		if err := tx.QueryRowxContext(r.Context(), `SELECT status,payment_status FROM customer_orders WHERE id=$1 FOR UPDATE`, orderID.String()).Scan(&orderStatus, &payStatus); err != nil {
			return err
		}
		if orderStatus == "cancelled" || orderStatus == "returned" || orderStatus == "delivered" || orderStatus == "completed" || payStatus == "paid" {
			return &apiFailure{409, "PAYMENT_NOT_ELIGIBLE", "This order is not eligible for a new payment attempt."}
		}
		providerKey := "sandbox-" + key.String()
		var priorOrder string
		err := tx.QueryRowxContext(r.Context(), `SELECT a.id::text,a.payment_intent_id::text,i.order_id::text,a.provider,COALESCE(a.provider_reference,''),a.amount_minor,a.currency,a.status,COALESCE(a.expires_at,now()+interval '5 minutes') FROM payment_attempts a JOIN payment_intents i ON i.id=a.payment_intent_id WHERE a.provider_idempotency_key=$1 FOR UPDATE OF a,i`, providerKey).Scan(&attempt.ID, &attempt.IntentID, &priorOrder, &attempt.Provider, &attempt.ProviderReference, &attempt.AmountMinor, &attempt.Currency, &attempt.Status, &attempt.ExpiresAt)
		if err == nil {
			if priorOrder != orderID.String() {
				return &apiFailure{http.StatusConflict, "PAYMENT_IDEMPOTENCY_CONFLICT", "This idempotency key is already bound to another payment order."}
			}
			attempt.OrderID = orderID.String()
			replay = true
			return nil
		}
		if !errors.Is(err, sql.ErrNoRows) {
			return err
		}
		var active int
		if err := tx.GetContext(r.Context(), &active, `SELECT count(*) FROM payment_attempts WHERE payment_intent_id=$1 AND status IN ('initialized','session_created','pending','reconciliation_required')`, intentID); err != nil {
			return err
		}
		if active > 0 {
			return &apiFailure{409, "PAYMENT_ATTEMPT_ACTIVE", "A payment attempt is already active."}
		}
		var next int
		if err := tx.GetContext(r.Context(), &next, `SELECT COALESCE(max(attempt_number),0)+1 FROM payment_attempts WHERE payment_intent_id=$1`, intentID); err != nil {
			return err
		}
		attempt.ID = uuid.NewString()
		attempt.IntentID = intentID
		attempt.OrderID = orderID.String()
		attempt.Provider = sandboxProviderName
		attempt.AmountMinor = amount
		attempt.Currency = currency
		attempt.Status = "initialized"
		attempt.ExpiresAt = time.Now().UTC().Add(5 * time.Minute)
		_, err = tx.ExecContext(r.Context(), `INSERT INTO payment_attempts(id,payment_intent_id,attempt_number,provider,amount_minor,currency,status,provider_idempotency_key,expires_at) VALUES($1,$2,$3,$4,$5,$6,'initialized',$7,$8)`, attempt.ID, intentID, next, sandboxProviderName, amount, currency, providerKey, attempt.ExpiresAt)
		return err
	})
	if err != nil {
		writeServiceError(w, err, "Sandbox payment session could not be created.")
		return
	}
	if replay && (attempt.Status == "succeeded" || attempt.Status == "failed" || attempt.Status == "expired") {
		var currentPayment string
		_ = s.db.GetContext(r.Context(), &currentPayment, `SELECT payment_status FROM customer_orders WHERE id=$1 AND customer_user_id=$2`, attempt.OrderID, userID)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(map[string]any{"data": map[string]any{"attempt_id": attempt.ID, "payment_intent_id": attempt.IntentID, "provider": sandboxProviderName, "amount_minor": attempt.AmountMinor, "currency": attempt.Currency, "status": attempt.Status, "payment_status": currentPayment, "session_available": false}, "meta": map[string]bool{"idempotent_replay": true}})
		return
	}
	session, providerErr := s.provider.CreateSession(r.Context(), CreateSessionRequest{OrderID: attempt.OrderID, IntentID: attempt.IntentID, IdempotencyKey: "sandbox-" + key.String(), Currency: attempt.Currency, AmountMinor: attempt.AmountMinor, ExpiresAt: attempt.ExpiresAt})
	if providerErr != nil {
		_ = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
			_, e := tx.ExecContext(r.Context(), `UPDATE payment_attempts SET status='reconciliation_required',updated_at=clock_timestamp() WHERE id=$1 AND status='initialized'`, attempt.ID)
			return e
		})
		writeFailure(w, 503, "PAYMENT_PROVIDER_UNAVAILABLE", "Sandbox provider did not return a confirmed session; retry with the same key.")
		return
	}
	err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		_, e := tx.ExecContext(r.Context(), `UPDATE payment_attempts SET provider_reference=$2,status='session_created',updated_at=clock_timestamp() WHERE id=$1 AND status IN ('initialized','reconciliation_required')`, attempt.ID, session.Reference)
		if e != nil {
			return e
		}
		_, e = tx.ExecContext(r.Context(), `UPDATE payment_intents SET status='pending' WHERE id=$1 AND status IN ('created','failed')`, attempt.IntentID)
		if e != nil {
			return e
		}
		_, e = tx.ExecContext(r.Context(), `UPDATE customer_orders SET payment_status='pending',updated_at=now() WHERE id=$1 AND payment_status IN ('not_collected','failed') AND status NOT IN ('cancelled','returned','delivered','completed')`, attempt.OrderID)
		return e
	})
	if err != nil {
		writeFailure(w, 500, "INTERNAL_ERROR", "Sandbox session result could not be persisted.")
		return
	}
	status := http.StatusCreated
	if replay {
		status = http.StatusOK
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{"data": map[string]any{"attempt_id": attempt.ID, "payment_intent_id": attempt.IntentID, "provider": sandboxProviderName, "provider_reference": session.Reference, "launch_uri": session.LaunchURL, "amount_minor": attempt.AmountMinor, "currency": attempt.Currency, "status": "pending", "expires_at": session.ExpiresAt.UTC()}, "meta": map[string]bool{"idempotent_replay": replay}})
}

func (s *Service) ReceiveSandboxWebhook(w http.ResponseWriter, r *http.Request) {
	if s.provider == nil || s.provider.Name() != sandboxProviderName {
		writeFailure(w, 503, "SANDBOX_PROVIDER_DISABLED", "Sandbox webhook processing is disabled.")
		return
	}
	if r.PathValue("provider") != sandboxProviderName {
		writeFailure(w, 404, "PROVIDER_NOT_FOUND", "Provider is not allowlisted.")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 16*1024)
	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeFailure(w, 413, "WEBHOOK_TOO_LARGE", "Webhook body is invalid or too large.")
		return
	}
	verified, err := s.provider.VerifyWebhook(r.Context(), r.Header, body)
	if err != nil {
		writeFailure(w, 401, "WEBHOOK_SIGNATURE_INVALID", "Provider webhook authentication failed.")
		return
	}
	if verified.Provider != sandboxProviderName || verified.EventID == "" || verified.ProviderReference == "" || verified.AmountMinor <= 0 || verified.Currency != "INR" || !validProviderStatus(verified.Status) || verified.EventAt.IsZero() {
		writeFailure(w, 400, "WEBHOOK_EVENT_INVALID", "Provider event is invalid.")
		return
	}
	if verified.ObjectType == "" {
		verified.ObjectType = "payment"
	}
	if verified.ObjectType == "refund" {
		if verified.Status != "pending" && verified.Status != "succeeded" && verified.Status != "failed" {
			writeFailure(w, 400, "WEBHOOK_EVENT_INVALID", "Refund event status is invalid.")
			return
		}
		result, err := s.processVerifiedRefundEvent(r.Context(), verified, body, r.Header.Get("X-Grepmind-Sandbox-Signature"))
		if errors.Is(err, ErrWebhookReplayConflict) {
			writeFailure(w, 409, "WEBHOOK_EVENT_CONFLICT", "Provider event ID was previously received with different content.")
			return
		}
		if err != nil {
			writeFailure(w, 500, "WEBHOOK_PROCESSING_FAILED", "Verified refund event could not be processed.")
			return
		}
		status := http.StatusOK
		if result == "quarantined" || result == "reconciliation_required" {
			status = http.StatusAccepted
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		_ = json.NewEncoder(w).Encode(map[string]string{"provider_event_id": verified.EventID, "processing_state": result})
		return
	}
	if verified.ObjectType != "payment" {
		writeFailure(w, 400, "WEBHOOK_EVENT_INVALID", "Provider event object type is invalid.")
		return
	}
	result, err := s.processVerifiedEvent(r.Context(), verified, body, r.Header.Get("X-Grepmind-Sandbox-Signature"))
	if errors.Is(err, ErrWebhookReplayConflict) {
		writeFailure(w, 409, "WEBHOOK_EVENT_CONFLICT", "Provider event ID was previously received with different content.")
		return
	}
	if err != nil {
		logger.Log.Error().Err(err).Msg("verified payment provider event processing failed")
		writeFailure(w, 500, "WEBHOOK_PROCESSING_FAILED", "Verified provider event could not be processed.")
		return
	}
	status := http.StatusOK
	if result == "quarantined" || result == "reconciliation_required" {
		status = http.StatusAccepted
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{"data": map[string]string{"provider_event_id": verified.EventID, "processing_state": result}})
}

func (s *Service) processVerifiedEvent(ctx context.Context, event VerifiedProviderEvent, rawBody []byte, signature string) (string, error) {
	if event.ObjectType == "refund" {
		return s.processVerifiedRefundEvent(ctx, event, rawBody, signature)
	}
	status := eventTypeForStatus(event.Status)
	payloadHash := sha256.Sum256(rawBody)
	result := "processed"
	err := s.db.Transaction(ctx, func(tx *sqlx.Tx) error {
		var eventID string
		err := tx.QueryRowxContext(ctx, `INSERT INTO payment_provider_events(provider,provider_event_id,provider_reference,event_type,amount_minor,currency,event_at,payload_sha256,signature_key_id) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) ON CONFLICT(provider,provider_event_id) DO NOTHING RETURNING id::text`, event.Provider, event.EventID, event.ProviderReference, status, event.AmountMinor, event.Currency, event.EventAt, payloadHash[:], signatureKeyID(signature)).Scan(&eventID)
		if errors.Is(err, sql.ErrNoRows) {
			var priorHash []byte
			if e := tx.QueryRowxContext(ctx, `SELECT payload_sha256 FROM payment_provider_events WHERE provider=$1 AND provider_event_id=$2`, event.Provider, event.EventID).Scan(&priorHash); e != nil {
				return e
			}
			if !equalHash(priorHash, payloadHash[:]) {
				return ErrWebhookReplayConflict
			}
			result = "duplicate"
			return nil
		}
		if err != nil {
			return err
		}
		var a paymentAttempt
		err = tx.QueryRowxContext(ctx, `SELECT a.id::text,a.payment_intent_id::text,i.order_id::text,a.provider,a.provider_reference,a.status,a.amount_minor,a.currency,COALESCE(a.expires_at,now()) FROM payment_attempts a JOIN payment_intents i ON i.id=a.payment_intent_id WHERE a.provider=$1 AND a.provider_reference=$2 FOR UPDATE OF a,i`, event.Provider, event.ProviderReference).Scan(&a.ID, &a.IntentID, &a.OrderID, &a.Provider, &a.ProviderReference, &a.Status, &a.AmountMinor, &a.Currency, &a.ExpiresAt)
		if errors.Is(err, sql.ErrNoRows) {
			result = "quarantined"
			_, e := tx.ExecContext(ctx, `UPDATE payment_provider_events SET processing_state='quarantined',processing_result='unknown provider reference' WHERE id=$1`, eventID)
			return e
		}
		if err != nil {
			return err
		}
		if a.AmountMinor != event.AmountMinor || a.Currency != event.Currency {
			result = "reconciliation_required"
			_, e := tx.ExecContext(ctx, `UPDATE payment_provider_events SET processing_state='reconciliation_required',processing_result='amount or currency mismatch',payment_attempt_id=$2 WHERE id=$1`, eventID, a.ID)
			if e != nil {
				return e
			}
			_, e = tx.ExecContext(ctx, `UPDATE payment_attempts SET status='reconciliation_required',updated_at=clock_timestamp() WHERE id=$1 AND status IN ('initialized','session_created','pending','failed','expired')`, a.ID)
			if e != nil {
				return e
			}
			_, e = tx.ExecContext(ctx, `INSERT INTO payment_reconciliation_events(payment_attempt_id,provider,outcome,provider_status,details) VALUES($1,$2,$3,$4,'Verified provider event amount or currency differs from immutable attempt')`, a.ID, event.Provider, func() string {
				if a.AmountMinor != event.AmountMinor {
					return "amount_mismatch"
				}
				return "currency_mismatch"
			}(), event.Status)
			return e
		}
		var orderStatus, paymentStatus, intentStatus string
		if err := tx.QueryRowxContext(ctx, `SELECT o.status,o.payment_status,i.status FROM customer_orders o JOIN payment_intents i ON i.order_id=o.id WHERE o.id=$1 FOR UPDATE OF o,i`, a.OrderID).Scan(&orderStatus, &paymentStatus, &intentStatus); err != nil {
			return err
		}
		if event.Status == "succeeded" {
			// A success is an immutable financial fact, even when the order has
			// since been cancelled/returned. Such captures are reconciliation cases.
			journalID, err := postSandboxCapture(ctx, tx, a, event)
			if err != nil {
				return err
			}
			_, err = tx.ExecContext(ctx, `UPDATE payment_attempts SET status='succeeded',updated_at=clock_timestamp() WHERE id=$1 AND status IN ('initialized','session_created','pending','failed','expired','reconciliation_required')`, a.ID)
			if err != nil {
				return err
			}
			eligible := orderStatus != "cancelled" && orderStatus != "returned" && orderStatus != "delivered" && orderStatus != "completed"
			var alreadyPaid bool
			if err := tx.GetContext(ctx, &alreadyPaid, `SELECT EXISTS(SELECT 1 FROM payment_attempts WHERE payment_intent_id=$1 AND id<>$2 AND status='succeeded')`, a.IntentID, a.ID); err != nil {
				return err
			}
			if a.Status == "succeeded" {
				result = "processed"
				_, err = tx.ExecContext(ctx, `UPDATE payment_provider_events SET processing_state='processed',processing_result='additional verified event for already captured attempt',payment_attempt_id=$2,financial_journal_id=$3 WHERE id=$1`, eventID, a.ID, journalID)
				return err
			}
			lateByExpiry := !a.ExpiresAt.IsZero() && time.Now().UTC().After(a.ExpiresAt)
			lateCapture := lateByExpiry || a.Status == "expired" || a.Status == "failed"
			if eligible && !alreadyPaid && intentStatus != "paid" && !lateCapture {
				if _, err = tx.ExecContext(ctx, `UPDATE payment_intents SET status='paid' WHERE id=$1 AND status IN ('created','pending','failed','reconciliation_required')`, a.IntentID); err != nil {
					return err
				}
				if _, err = tx.ExecContext(ctx, `UPDATE customer_orders SET payment_status='paid',updated_at=now() WHERE id=$1 AND payment_status IN ('pending','failed','not_collected')`, a.OrderID); err != nil {
					return err
				}
			} else {
				result = "reconciliation_required"
				if intentStatus != "paid" {
					if _, err = tx.ExecContext(ctx, `UPDATE payment_intents SET status='reconciliation_required' WHERE id=$1 AND status IN ('created','pending','failed')`, a.IntentID); err != nil {
						return err
					}
				}
				if _, err = tx.ExecContext(ctx, `UPDATE customer_orders SET payment_status='paid',updated_at=now() WHERE id=$1 AND payment_status IN ('pending','failed','not_collected')`, a.OrderID); err != nil {
					return err
				}
				outcome := "late_success"
				if _, err = tx.ExecContext(ctx, `INSERT INTO payment_reconciliation_events(payment_attempt_id,provider,outcome,provider_status,details) VALUES($1,$2,$3,'succeeded',$4)`, a.ID, event.Provider, outcome, func() string {
					if !eligible {
						return "Verified capture belongs to cancelled/returned/completed order; order lifecycle was not reopened"
					}
					if lateCapture {
						return "Verified capture arrived after local failure or expiry; payment is retained for authorized reconciliation"
					}
					return "A separate attempt captured after an earlier capture; review duplicate payment"
				}()); err != nil {
					return err
				}
			}
			_, err = tx.ExecContext(ctx, `UPDATE payment_provider_events SET processing_state=$2,processing_result=$3,payment_attempt_id=$4,financial_journal_id=$5 WHERE id=$1`, eventID, result, "verified capture recorded", a.ID, journalID)
			return err
		}
		if intentStatus == "paid" || paymentStatus == "paid" {
			result = "processed"
			_, err := tx.ExecContext(ctx, `UPDATE payment_provider_events SET processing_state='processed',processing_result='stale non-success event ignored after verified capture',payment_attempt_id=$2 WHERE id=$1`, eventID, a.ID)
			return err
		}
		attemptState := map[string]string{"failed": "failed", "expired": "expired", "pending": "pending"}[event.Status]
		if attemptState == "" {
			return errors.New("unsupported event state")
		}
		if attemptState != "pending" {
			if _, err = tx.ExecContext(ctx, `UPDATE payment_attempts SET status=$2,updated_at=clock_timestamp() WHERE id=$1 AND status IN ('initialized','session_created','pending','reconciliation_required')`, a.ID, attemptState); err != nil {
				return err
			}
		}
		if event.Status == "pending" {
			_, err = tx.ExecContext(ctx, `UPDATE payment_attempts SET status='pending',updated_at=clock_timestamp() WHERE id=$1 AND status IN ('initialized','session_created')`, a.ID)
			if err != nil {
				return err
			}
		}
		if event.Status == "failed" || event.Status == "expired" {
			if _, err = tx.ExecContext(ctx, `UPDATE payment_intents SET status='failed' WHERE id=$1 AND status='pending'`, a.IntentID); err != nil {
				return err
			}
			if _, err = tx.ExecContext(ctx, `UPDATE customer_orders SET payment_status='failed',updated_at=now() WHERE id=$1 AND payment_status='pending'`, a.OrderID); err != nil {
				return err
			}
		}
		_, err = tx.ExecContext(ctx, `UPDATE payment_provider_events SET processing_state='processed',processing_result=$2,payment_attempt_id=$3 WHERE id=$1`, eventID, "verified "+event.Status+" event", a.ID)
		return err
	})
	return result, err
}

func postSandboxCapture(ctx context.Context, tx *sqlx.Tx, a paymentAttempt, event VerifiedProviderEvent) (string, error) {
	var clearing, receipts string
	err := tx.QueryRowxContext(ctx, `SELECT max(account_id::text) FILTER (WHERE purpose='provider_clearing'),max(account_id::text) FILTER (WHERE purpose='customer_receipts_unapplied') FROM payment_ledger_account_mappings`).Scan(&clearing, &receipts)
	if err != nil {
		return "", err
	}
	if clearing == "" || receipts == "" {
		return "", errors.New("sandbox payment ledger account mapping is incomplete")
	}
	j, err := financialledger.PostSandboxPaymentJournalTx(ctx, tx, financialledger.PostInput{Currency: event.Currency, SourceType: "sandbox_payment_capture", SourceID: a.ID, SourceEvent: "verified_capture", IdempotencyKey: "sandbox-capture-" + a.ID, Description: "Verified synthetic sandbox payment capture", Lines: []financialledger.Line{{AccountID: clearing, Side: "debit", Amount: event.AmountMinor, Memo: "Sandbox provider receivable"}, {AccountID: receipts, Side: "credit", Amount: event.AmountMinor, Memo: "Unapplied customer receipt"}}})
	return j.ID, err
}

func eventTypeForStatus(status string) string { return "payment." + status }
func signatureKeyID(value string) string {
	for _, part := range strings.Split(value, ",") {
		k, v, ok := strings.Cut(strings.TrimSpace(part), "=")
		if ok && k == "kid" && len(v) <= 80 {
			return v
		}
	}
	return "unknown"
}
func equalHash(a, b []byte) bool { return len(a) == len(b) && subtle.ConstantTimeCompare(a, b) == 1 }
func writeServiceError(w http.ResponseWriter, err error, fallback string) {
	var failure *apiFailure
	if errors.As(err, &failure) {
		writeFailure(w, failure.status, failure.code, failure.message)
		return
	}
	if errors.Is(err, financialledger.ErrUnauthorized) {
		writeFailure(w, 403, "FORBIDDEN", "Finance permission is required for this operation.")
		return
	}
	writeFailure(w, 500, "INTERNAL_ERROR", fallback)
}

// VerifySandboxReconciliation fetches provider state server-to-server. The
// service is deliberately unavailable unless the injected provider is the QA fake.
func (s *Service) VerifySandboxReconciliation(ctx context.Context, attemptID string) (ProviderPayment, error) {
	if s.provider == nil || s.provider.Name() != sandboxProviderName {
		return ProviderPayment{}, ErrProviderUnavailable
	}
	var reference string
	if err := s.db.GetContext(ctx, &reference, `SELECT provider_reference FROM payment_attempts WHERE id=$1 AND provider=$2`, attemptID, sandboxProviderName); err != nil {
		return ProviderPayment{}, err
	}
	return s.provider.FetchPayment(ctx, reference)
}

func (s *Service) ReconcileSandboxPayment(w http.ResponseWriter, r *http.Request, userID string) {
	if s.provider == nil || s.provider.Name() != sandboxProviderName {
		writeFailure(w, 503, "SANDBOX_PROVIDER_DISABLED", "Sandbox reconciliation is unavailable.")
		return
	}
	attemptID, err := uuid.Parse(r.PathValue("id"))
	if err != nil {
		writeFailure(w, 400, "VALIDATION_ERROR", "A valid payment attempt ID is required.")
		return
	}
	if err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error { return financialledger.AuthorizeTx(r.Context(), tx, userID, "finance.read") }); err != nil {
		writeFailure(w, 403, "FORBIDDEN", "Finance reconciliation permission is required.")
		return
	}
	var a paymentAttempt
	err = s.db.QueryRowxContext(r.Context(), `SELECT a.id::text,a.payment_intent_id::text,i.order_id::text,a.provider,a.provider_reference,a.amount_minor,a.currency,a.status,COALESCE(a.expires_at,now()) FROM payment_attempts a JOIN payment_intents i ON i.id=a.payment_intent_id WHERE a.id=$1 AND a.provider=$2`, attemptID.String(), sandboxProviderName).Scan(&a.ID, &a.IntentID, &a.OrderID, &a.Provider, &a.ProviderReference, &a.AmountMinor, &a.Currency, &a.Status, &a.ExpiresAt)
	if errors.Is(err, sql.ErrNoRows) {
		writeFailure(w, 404, "PAYMENT_ATTEMPT_NOT_FOUND", "Sandbox payment attempt was not found.")
		return
	}
	if err != nil {
		writeFailure(w, 500, "INTERNAL_ERROR", "Payment attempt could not be loaded.")
		return
	}
	var sandboxEnabled bool
	if err = s.db.GetContext(r.Context(), &sandboxEnabled, `SELECT sandbox_payment_enabled AND NOT upi_enabled AND NOT real_money_enabled FROM financial_feature_config WHERE singleton=true`); err != nil || !sandboxEnabled {
		writeFailure(w, 503, "SANDBOX_PROVIDER_DISABLED", "Sandbox reconciliation is disabled.")
		return
	}
	providerPayment, fetchErr := s.provider.FetchPayment(r.Context(), a.ProviderReference)
	if fetchErr != nil {
		_ = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
			_, e := tx.ExecContext(r.Context(), `INSERT INTO payment_reconciliation_events(payment_attempt_id,provider,outcome,details,actor_user_id) VALUES($1,$2,'unknown_reference','Sandbox provider has no matching reference',$3)`, a.ID, sandboxProviderName, userID)
			return e
		})
		writeFailure(w, 404, "PAYMENT_RECONCILIATION_REQUIRED", "Provider reference is unknown; exception recorded.")
		return
	}
	if providerPayment.Status != "pending" && providerPayment.Status != "succeeded" && providerPayment.Status != "failed" && providerPayment.Status != "expired" {
		writeFailure(w, 502, "PAYMENT_PROVIDER_UNAVAILABLE", "Provider returned an unsupported status.")
		return
	}
	now := time.Now().UTC()
	event := VerifiedProviderEvent{Provider: sandboxProviderName, EventID: "reconcile-" + a.ID + "-" + providerPayment.Status + "-" + shortHash(fmt.Sprintf("%d:%s", providerPayment.AmountMinor, providerPayment.Currency)), ProviderReference: providerPayment.Reference, Status: providerPayment.Status, AmountMinor: providerPayment.AmountMinor, Currency: providerPayment.Currency, EventAt: now}
	raw, _ := json.Marshal(event)
	result, err := s.processVerifiedEvent(r.Context(), event, raw, "kid=server-reconcile")
	if errors.Is(err, ErrWebhookReplayConflict) {
		result = "duplicate"
		err = nil
	}
	if err != nil {
		writeFailure(w, 500, "RECONCILIATION_FAILED", "Provider status could not be reconciled.")
		return
	}
	outcome := "matched"
	if providerPayment.Status == "succeeded" && (a.Status == "failed" || a.Status == "expired" || a.Status == "reconciliation_required") {
		outcome = "late_success"
	} else if providerPayment.Status == "succeeded" && a.Status != "succeeded" {
		outcome = "missing_webhook"
	}
	if providerPayment.AmountMinor != a.AmountMinor {
		outcome = "amount_mismatch"
	}
	if providerPayment.Currency != a.Currency {
		outcome = "currency_mismatch"
	}
	err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		_, e := tx.ExecContext(r.Context(), `INSERT INTO payment_reconciliation_events(payment_attempt_id,provider,outcome,provider_status,details,actor_user_id) VALUES($1,$2,$3,$4,$5,$6)`, a.ID, sandboxProviderName, outcome, providerPayment.Status, "Server-to-server sandbox provider status reconciliation", userID)
		return e
	})
	if err != nil {
		writeFailure(w, 500, "RECONCILIATION_FAILED", "Reconciliation outcome could not be persisted.")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"data": map[string]string{"attempt_id": a.ID, "provider_status": providerPayment.Status, "processing_state": result, "reconciliation_outcome": outcome}})
}
