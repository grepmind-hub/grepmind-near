package payments

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
	"grepmind-near/backend/internal/financialledger"
	"grepmind-near/backend/pkg/logger"
)

type refundRow struct {
	ID          string `json:"id"`
	OrderID     string `json:"order_id"`
	Status      string `json:"status"`
	Currency    string `json:"currency"`
	ReasonCode  string `json:"reason_code"`
	CreatedAt   string `json:"created_at"`
	AmountMinor int64  `json:"amount_minor"`
}

// GetPaymentState returns only the authenticated customer's authoritative
// payment projection and current attempt. No provider payload or credentials
// are returned to the client.
func (s *Service) GetPaymentState(w http.ResponseWriter, r *http.Request, userID string) {
	if !s.requireCustomer(w, r, userID) {
		return
	}
	orderID, err := uuid.Parse(r.PathValue("id"))
	if err != nil {
		writeFailure(w, 400, "VALIDATION_ERROR", "A valid order ID is required.")
		return
	}
	var state struct {
		OrderID                                                                              string
		PaymentStatus                                                                        string
		OrderStatus, OrderSource, IntentID, IntentStatus, Currency, AttemptID, AttemptStatus string
		Amount, Refundable                                                                   int64
		SandboxReady                                                                         bool
	}
	err = s.db.QueryRowxContext(r.Context(), `SELECT o.id::text,o.payment_status,o.status,o.order_source,COALESCE(i.id::text,''),COALESCE(i.status,''),COALESCE(i.currency,o.currency),COALESCE(a.id::text,''),COALESCE(a.status,''),COALESCE(i.amount_minor,round(o.grand_total*100)::bigint),COALESCE((SELECT a2.amount_minor FROM payment_attempts a2 WHERE a2.payment_intent_id=i.id AND a2.status='succeeded' ORDER BY a2.attempt_number DESC LIMIT 1),0)-COALESCE((SELECT sum(pr.amount_minor) FROM payment_refunds pr WHERE pr.payment_intent_id=i.id AND pr.status IN ('requested','approved','processing','failed','succeeded','reconciliation_required')),0),
		(SELECT payment_intent_creation_enabled AND payment_attempt_creation_enabled AND financial_posting_enabled AND sandbox_payment_enabled AND NOT upi_enabled AND NOT cod_enabled AND NOT merchant_settlement_enabled AND NOT real_money_enabled FROM financial_feature_config WHERE singleton=true)
		FROM customer_orders o LEFT JOIN payment_intents i ON i.order_id=o.id LEFT JOIN LATERAL (SELECT id,status FROM payment_attempts WHERE payment_intent_id=i.id ORDER BY attempt_number DESC LIMIT 1) a ON true
		WHERE o.id=$1 AND o.customer_user_id=$2`, orderID.String(), userID).Scan(&state.OrderID, &state.PaymentStatus, &state.OrderStatus, &state.OrderSource, &state.IntentID, &state.IntentStatus, &state.Currency, &state.AttemptID, &state.AttemptStatus, &state.Amount, &state.Refundable, &state.SandboxReady)
	if errors.Is(err, sql.ErrNoRows) {
		writeFailure(w, 404, "ORDER_NOT_FOUND", "Order was not found for this account.")
		return
	}
	if err != nil {
		writeFailure(w, 500, "INTERNAL_ERROR", "Payment status could not be loaded.")
		return
	}
	refunds, err := s.listRefunds(r.Context(), orderID.String(), userID)
	if err != nil {
		writeFailure(w, 500, "INTERNAL_ERROR", "Refund history could not be loaded.")
		return
	}
	eligible := state.SandboxReady && s.provider != nil && s.provider.Name() == sandboxProviderName && state.OrderSource == "platform_catalog" && state.PaymentStatus != "paid" && state.OrderStatus != "cancelled" && state.OrderStatus != "returned" && state.OrderStatus != "delivered" && state.OrderStatus != "completed" && state.AttemptStatus != "pending" && state.AttemptStatus != "session_created" && state.AttemptStatus != "reconciliation_required"
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"data": map[string]any{"order_id": state.OrderID, "payment_status": state.PaymentStatus, "payment_intent_id": state.IntentID, "intent_status": state.IntentStatus, "amount_minor": state.Amount, "currency": state.Currency, "latest_attempt_id": state.AttemptID, "latest_attempt_status": state.AttemptStatus, "eligible": eligible, "refundable_amount_minor": max64(state.Refundable, 0), "refunds": refunds, "sandbox": true}})
}

func (s *Service) RequestRefund(w http.ResponseWriter, r *http.Request, userID string) {
	if !s.requireCustomer(w, r, userID) {
		return
	}
	orderID, err := uuid.Parse(r.PathValue("id"))
	if err != nil {
		writeFailure(w, 400, "VALIDATION_ERROR", "A valid order ID is required.")
		return
	}
	key, err := uuid.Parse(r.Header.Get("Idempotency-Key"))
	if err != nil {
		writeFailure(w, 400, "IDEMPOTENCY_KEY_REQUIRED", "A valid Idempotency-Key is required.")
		return
	}
	var in struct {
		AmountMinor int64  `json:"amount_minor"`
		ReasonCode  string `json:"reason_code"`
	}
	r.Body = http.MaxBytesReader(w, r.Body, 4096)
	if err = json.NewDecoder(r.Body).Decode(&in); err != nil || in.AmountMinor <= 0 || !validRefundReason(in.ReasonCode) {
		writeFailure(w, 400, "VALIDATION_ERROR", "A positive refund amount and supported reason code are required.")
		return
	}
	fingerprint := sha256.Sum256([]byte(fmt.Sprintf("%s|%d|%s", orderID, in.AmountMinor, in.ReasonCode)))
	var out refundRow
	replay := false
	err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		// Serialize a customer's requests so concurrent retries of one
		// idempotency key replay the same row instead of exposing a unique
		// constraint violation as a 500 response.
		var lockedUser string
		if e := tx.GetContext(r.Context(), &lockedUser, `SELECT id::text FROM users WHERE id=$1 AND status='active' FOR UPDATE`, userID); e != nil {
			return e
		}
		var prior refundRow
		var priorHash []byte
		e := tx.QueryRowxContext(r.Context(), `SELECT id::text,order_id::text,status,currency,reason_code,amount_minor,created_at::text,request_fingerprint FROM payment_refunds WHERE customer_user_id=$1 AND idempotency_key=$2 FOR UPDATE`, userID, key.String()).Scan(&prior.ID, &prior.OrderID, &prior.Status, &prior.Currency, &prior.ReasonCode, &prior.AmountMinor, &prior.CreatedAt, &priorHash)
		if e == nil {
			if prior.OrderID != orderID.String() || !equalHash(priorHash, fingerprint[:]) {
				return &apiFailure{409, "IDEMPOTENCY_CONFLICT", "This key was used for a different refund request."}
			}
			out = prior
			replay = true
			return nil
		}
		if !errors.Is(e, sql.ErrNoRows) {
			return e
		}
		var platform, paid bool
		if e = tx.QueryRowxContext(r.Context(), `SELECT (o.order_source='platform_catalog'),(o.payment_status='paid') FROM customer_orders o WHERE o.id=$1 AND o.customer_user_id=$2 FOR UPDATE`, orderID.String(), userID).Scan(&platform, &paid); e != nil {
			if errors.Is(e, sql.ErrNoRows) {
				return &apiFailure{404, "ORDER_NOT_FOUND", "Order was not found for this account."}
			}
			return e
		}
		if !platform || !paid {
			return &apiFailure{409, "REFUND_NOT_ELIGIBLE", "A refund can only be requested for a verified paid platform order."}
		}
		var intentID, attemptID, currency, paymentRef string
		var captured, remaining int64
		e = tx.QueryRowxContext(r.Context(), `SELECT i.id::text,a.id::text,a.currency,a.amount_minor,a.provider_reference,
			a.amount_minor-COALESCE((SELECT sum(amount_minor) FROM payment_refunds WHERE payment_attempt_id=a.id AND status IN ('requested','approved','processing','failed','succeeded','reconciliation_required')),0)
			FROM payment_intents i JOIN payment_attempts a ON a.payment_intent_id=i.id WHERE i.order_id=$1 AND i.customer_user_id=$2 AND a.status='succeeded' AND a.provider='grepmind_sandbox' ORDER BY a.attempt_number DESC LIMIT 1 FOR UPDATE OF i,a`, orderID.String(), userID).Scan(&intentID, &attemptID, &currency, &captured, &paymentRef, &remaining)
		if errors.Is(e, sql.ErrNoRows) {
			return &apiFailure{409, "REFUND_NOT_ELIGIBLE", "No verified sandbox capture is available to refund."}
		}
		if e != nil {
			return e
		}
		if in.AmountMinor > remaining || in.AmountMinor > captured {
			return &apiFailure{409, "REFUND_AMOUNT_EXCEEDED", "Requested amount exceeds the remaining verified captured balance."}
		}
		out = refundRow{ID: uuid.NewString(), OrderID: orderID.String(), Status: "requested", Currency: currency, ReasonCode: in.ReasonCode, AmountMinor: in.AmountMinor, CreatedAt: time.Now().UTC().Format(time.RFC3339Nano)}
		if _, e = tx.ExecContext(r.Context(), `INSERT INTO payment_refunds(id,payment_intent_id,payment_attempt_id,order_id,customer_user_id,amount_minor,currency,reason_code,idempotency_key,request_fingerprint,requested_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$5)`, out.ID, intentID, attemptID, orderID.String(), userID, in.AmountMinor, currency, in.ReasonCode, key.String(), fingerprint[:]); e != nil {
			return e
		}
		_, e = tx.ExecContext(r.Context(), `INSERT INTO payment_refund_audit_events(refund_id,actor_user_id,event_type,reason,metadata) VALUES($1,$2,'requested','Customer submitted a sandbox refund request; eligibility is subject to finance review',jsonb_build_object('amount_minor',$3::bigint,'currency',$4::text,'reason_code',$5::text))`, out.ID, userID, in.AmountMinor, currency, in.ReasonCode)
		return e
	})
	if err != nil {
		var failure *apiFailure
		if !errors.As(err, &failure) {
			logger.Log.Error().Err(err).Msg("payment refund request failed")
		}
		writeServiceError(w, err, "Refund request could not be created.")
		return
	}
	status := http.StatusCreated
	if replay {
		status = http.StatusOK
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{"data": out, "meta": map[string]bool{"idempotent_replay": replay, "requires_finance_review": true}})
}

func (s *Service) ListRefunds(w http.ResponseWriter, r *http.Request, userID string) {
	if !s.requireCustomer(w, r, userID) {
		return
	}
	id, err := uuid.Parse(r.PathValue("id"))
	if err != nil {
		writeFailure(w, 400, "VALIDATION_ERROR", "A valid order ID is required.")
		return
	}
	values, err := s.listRefunds(r.Context(), id.String(), userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeFailure(w, 404, "ORDER_NOT_FOUND", "Order was not found for this account.")
			return
		}
		writeFailure(w, 500, "INTERNAL_ERROR", "Refund history could not be loaded.")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"data": values})
}

func (s *Service) listRefunds(ctx context.Context, orderID, userID string) ([]map[string]any, error) {
	var owned bool
	if err := s.db.GetContext(ctx, &owned, `SELECT EXISTS(SELECT 1 FROM customer_orders WHERE id=$1 AND customer_user_id=$2)`, orderID, userID); err != nil {
		return nil, err
	}
	if !owned {
		return nil, sql.ErrNoRows
	}
	rows, err := s.db.QueryxContext(ctx, `SELECT id::text,amount_minor,currency,status,reason_code,created_at FROM payment_refunds WHERE order_id=$1 AND customer_user_id=$2 ORDER BY created_at DESC`, orderID, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var id, currency, status, reason, created string
		var amount int64
		if err := rows.Scan(&id, &amount, &currency, &status, &reason, &created); err != nil {
			return nil, err
		}
		out = append(out, map[string]any{"id": id, "amount_minor": amount, "currency": currency, "status": status, "reason_code": reason, "created_at": created})
	}
	return out, rows.Err()
}

func (s *Service) ReviewRefund(w http.ResponseWriter, r *http.Request, userID string) {
	refundID, err := uuid.Parse(r.PathValue("id"))
	if err != nil {
		writeFailure(w, 400, "VALIDATION_ERROR", "A valid refund ID is required.")
		return
	}
	var body struct {
		Decision string `json:"decision"`
		Reason   string `json:"reason"`
	}
	r.Body = http.MaxBytesReader(w, r.Body, 4096)
	if json.NewDecoder(r.Body).Decode(&body) != nil || (body.Decision != "approve" && body.Decision != "reject") || len(strings.TrimSpace(body.Reason)) < 8 || len(body.Reason) > 300 {
		writeFailure(w, 400, "VALIDATION_ERROR", "A valid approve/reject decision and review reason are required.")
		return
	}
	if body.Decision == "reject" {
		err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
			if e := financialledger.AuthorizeTx(r.Context(), tx, userID, "finance.post"); e != nil {
				return e
			}
			var requester, status string
			if e := tx.QueryRowxContext(r.Context(), `SELECT requested_by::text,status FROM payment_refunds WHERE id=$1 FOR UPDATE`, refundID.String()).Scan(&requester, &status); e != nil {
				return e
			}
			if requester == userID {
				return &apiFailure{403, "SEPARATION_OF_DUTIES", "The refund requester cannot review their own request."}
			}
			if status != "requested" {
				return &apiFailure{409, "REFUND_STATE_CONFLICT", "Refund is no longer awaiting review."}
			}
			if _, e := tx.ExecContext(r.Context(), `UPDATE payment_refunds SET status='rejected',updated_at=now() WHERE id=$1`, refundID.String()); e != nil {
				return e
			}
			_, e := tx.ExecContext(r.Context(), `INSERT INTO payment_refund_audit_events(refund_id,actor_user_id,event_type,reason) VALUES($1,$2,'rejected',$3)`, refundID.String(), userID, strings.TrimSpace(body.Reason))
			return e
		})
		if err != nil {
			writeServiceError(w, err, "Refund could not be rejected.")
			return
		}
		w.WriteHeader(204)
		return
	}
	if s.provider == nil || s.provider.Name() != sandboxProviderName {
		writeFailure(w, 503, "SANDBOX_PROVIDER_DISABLED", "Sandbox refund provider is unavailable.")
		return
	}
	var req CreateRefundRequest
	err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if e := financialledger.AuthorizeTx(r.Context(), tx, userID, "finance.post"); e != nil {
			return e
		}
		var requester, status string
		e := tx.QueryRowxContext(r.Context(), `SELECT r.requested_by::text,r.status,r.id::text,r.amount_minor,r.currency,a.provider_reference FROM payment_refunds r JOIN payment_attempts a ON a.id=r.payment_attempt_id WHERE r.id=$1 FOR UPDATE OF r,a`, refundID.String()).Scan(&requester, &status, &req.RefundID, &req.AmountMinor, &req.Currency, &req.PaymentReference)
		if e != nil {
			return e
		}
		if requester == userID {
			return &apiFailure{403, "SEPARATION_OF_DUTIES", "The refund requester cannot review their own request."}
		}
		if status != "requested" && status != "approved" {
			return &apiFailure{409, "REFUND_STATE_CONFLICT", "Refund is no longer awaiting review."}
		}
		req.IdempotencyKey = "refund-" + req.RefundID
		if status == "requested" {
			_, e = tx.ExecContext(r.Context(), `UPDATE payment_refunds SET status='approved',approved_by=$2,updated_at=now() WHERE id=$1`, refundID.String(), userID)
			if e != nil {
				return e
			}
			_, e = tx.ExecContext(r.Context(), `INSERT INTO payment_refund_audit_events(refund_id,actor_user_id,event_type,reason) VALUES($1,$2,'approved',$3)`, refundID.String(), userID, strings.TrimSpace(body.Reason))
			return e
		}
		return nil
	})
	if err != nil {
		writeServiceError(w, err, "Refund could not be approved.")
		return
	}
	providerRefund, providerErr := s.provider.CreateRefund(r.Context(), req)
	if providerErr != nil {
		_ = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
			_, e := tx.ExecContext(r.Context(), `UPDATE payment_refunds SET failure_code='provider_ambiguous',updated_at=now() WHERE id=$1 AND status='approved'`, refundID.String())
			if e != nil {
				return e
			}
			_, e = tx.ExecContext(r.Context(), `INSERT INTO payment_refund_audit_events(refund_id,actor_user_id,event_type,reason) VALUES($1,$2,'reconciliation_required','Sandbox provider result was ambiguous; retry uses the same idempotent refund reference')`, refundID.String(), userID)
			return e
		})
		writeFailure(w, 202, "REFUND_RECONCILIATION_REQUIRED", "Approval was recorded; retry the idempotent sandbox request to reconcile its result.")
		return
	}
	err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var current string
		if e := tx.GetContext(r.Context(), &current, `SELECT status FROM payment_refunds WHERE id=$1 FOR UPDATE`, refundID.String()); e != nil {
			return e
		}
		if current != "approved" && current != "reconciliation_required" {
			return &apiFailure{409, "REFUND_STATE_CONFLICT", "Refund state changed while provider request was running."}
		}
		if _, e := tx.ExecContext(r.Context(), `UPDATE payment_refunds SET status='processing',provider_reference=$2,updated_at=now() WHERE id=$1`, refundID.String(), providerRefund.Reference); e != nil {
			return e
		}
		_, e := tx.ExecContext(r.Context(), `INSERT INTO payment_refund_audit_events(refund_id,actor_user_id,event_type,reason,metadata) VALUES($1,$2,'provider_started','Synthetic refund initiated with the QA provider',jsonb_build_object('provider_reference',$3::text))`, refundID.String(), userID, providerRefund.Reference)
		return e
	})
	if err != nil {
		writeFailure(w, 500, "REFUND_PERSISTENCE_FAILED", "Provider refund reference could not be recorded; reconciliation is required.")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"data": map[string]any{"refund_id": refundID.String(), "status": "processing", "provider": "grepmind_sandbox", "sandbox": true}})
}

func (s *Service) ListAdminRefunds(w http.ResponseWriter, r *http.Request, userID string) {
	if err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error { return financialledger.AuthorizeTx(r.Context(), tx, userID, "finance.read") }); err != nil {
		writeFailure(w, 403, "FORBIDDEN", "Finance read permission is required.")
		return
	}
	status := r.URL.Query().Get("status")
	if status == "" {
		status = "requested"
	}
	if !map[string]bool{"requested": true, "approved": true, "processing": true, "succeeded": true, "failed": true, "rejected": true, "reconciliation_required": true}[status] {
		writeFailure(w, 400, "VALIDATION_ERROR", "Unsupported refund status filter.")
		return
	}
	limit := 50
	if raw := r.URL.Query().Get("limit"); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed < 1 || parsed > 100 {
			writeFailure(w, 400, "VALIDATION_ERROR", "Limit must be between 1 and 100.")
			return
		}
		limit = parsed
	}
	rows, err := s.db.QueryxContext(r.Context(), `SELECT id::text,order_id::text,customer_user_id::text,amount_minor,currency,status,reason_code,created_at FROM payment_refunds WHERE status=$1 ORDER BY created_at LIMIT $2`, status, limit)
	if err != nil {
		writeFailure(w, 500, "INTERNAL_ERROR", "Refund queue could not be loaded.")
		return
	}
	defer rows.Close()
	data := []map[string]any{}
	for rows.Next() {
		var id, orderID, customerID, currency, state, reason string
		var amount int64
		var created time.Time
		if err := rows.Scan(&id, &orderID, &customerID, &amount, &currency, &state, &reason, &created); err != nil {
			writeFailure(w, 500, "INTERNAL_ERROR", "Refund queue could not be loaded.")
			return
		}
		data = append(data, map[string]any{"id": id, "order_id": orderID, "customer_user_id": customerID, "amount_minor": amount, "currency": currency, "status": state, "reason_code": reason, "created_at": created.UTC()})
	}
	if err := rows.Err(); err != nil {
		writeFailure(w, 500, "INTERNAL_ERROR", "Refund queue could not be loaded.")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"data": data})
}

func (s *Service) processVerifiedRefundEvent(ctx context.Context, event VerifiedProviderEvent, raw []byte, signature string) (string, error) {
	if event.ObjectType != "refund" {
		return "", errors.New("not a refund provider event")
	}
	payloadHash := sha256.Sum256(raw)
	result := "processed"
	err := s.db.Transaction(ctx, func(tx *sqlx.Tx) error {
		var eventID string
		err := tx.QueryRowxContext(ctx, `INSERT INTO payment_provider_events(provider,provider_event_id,provider_reference,event_type,amount_minor,currency,event_at,payload_sha256,signature_key_id) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) ON CONFLICT(provider,provider_event_id) DO NOTHING RETURNING id::text`, event.Provider, event.EventID, event.ProviderReference, "refund."+event.Status, event.AmountMinor, event.Currency, event.EventAt, payloadHash[:], signatureKeyID(signature)).Scan(&eventID)
		if errors.Is(err, sql.ErrNoRows) {
			var prior []byte
			if e := tx.GetContext(ctx, &prior, `SELECT payload_sha256 FROM payment_provider_events WHERE provider=$1 AND provider_event_id=$2`, event.Provider, event.EventID); e != nil {
				return e
			}
			if !equalHash(prior, payloadHash[:]) {
				return ErrWebhookReplayConflict
			}
			result = "duplicate"
			return nil
		}
		if err != nil {
			return err
		}
		var id, orderID, status, currency string
		var amount int64
		err = tx.QueryRowxContext(ctx, `SELECT id::text,order_id::text,status,currency,amount_minor FROM payment_refunds WHERE provider=$1 AND provider_reference=$2 FOR UPDATE`, event.Provider, event.ProviderReference).Scan(&id, &orderID, &status, &currency, &amount)
		if errors.Is(err, sql.ErrNoRows) {
			result = "quarantined"
			_, e := tx.ExecContext(ctx, `UPDATE payment_provider_events SET processing_state='quarantined',processing_result='unknown refund reference' WHERE id=$1`, eventID)
			return e
		}
		if err != nil {
			return err
		}
		var attemptID string
		if err = tx.GetContext(ctx, &attemptID, `SELECT payment_attempt_id::text FROM payment_refunds WHERE id=$1`, id); err != nil {
			return err
		}
		if amount != event.AmountMinor || currency != event.Currency {
			result = "reconciliation_required"
			if status == "processing" || status == "approved" {
				if _, e := tx.ExecContext(ctx, `UPDATE payment_refunds SET status='reconciliation_required',failure_code='provider_amount_mismatch',updated_at=now() WHERE id=$1`, id); e != nil {
					return e
				}
				if _, e := tx.ExecContext(ctx, `INSERT INTO payment_refund_audit_events(refund_id,event_type,reason) VALUES($1,'reconciliation_required','Verified sandbox refund amount or currency mismatch')`, id); e != nil {
					return e
				}
			}
			_, e := tx.ExecContext(ctx, `UPDATE payment_provider_events SET processing_state='reconciliation_required',processing_result='refund amount or currency mismatch',refund_id=$2 WHERE id=$1`, eventID, id)
			return e
		}
		if event.Status == "pending" {
			if status == "approved" || status == "reconciliation_required" {
				if _, err = tx.ExecContext(ctx, `UPDATE payment_refunds SET status='processing',provider_event_id=$2,updated_at=now() WHERE id=$1`, id, event.EventID); err != nil {
					return err
				}
			}
			_, err = tx.ExecContext(ctx, `UPDATE payment_provider_events SET processing_state='processed',processing_result='verified refund pending',refund_id=$2 WHERE id=$1`, eventID, id)
			return err
		}
		if event.Status == "failed" {
			if status == "processing" || status == "reconciliation_required" {
				if _, err = tx.ExecContext(ctx, `UPDATE payment_refunds SET status='failed',provider_event_id=$2,failure_code='provider_refund_failed',updated_at=now() WHERE id=$1`, id, event.EventID); err != nil {
					return err
				}
				if _, err = tx.ExecContext(ctx, `INSERT INTO payment_refund_audit_events(refund_id,event_type,reason) VALUES($1,'provider_failed','Verified synthetic provider refund failure')`, id); err != nil {
					return err
				}
			}
			_, err = tx.ExecContext(ctx, `UPDATE payment_provider_events SET processing_state='processed',processing_result='verified refund failed',refund_id=$2 WHERE id=$1`, eventID, id)
			return err
		}
		if event.Status != "succeeded" {
			return errors.New("unsupported refund status")
		}
		journalID, err := postSandboxRefund(ctx, tx, id, attemptID, event)
		if err != nil {
			return err
		}
		if status != "processing" && status != "reconciliation_required" && status != "failed" && status != "succeeded" {
			return &apiFailure{409, "REFUND_STATE_CONFLICT", "Verified refund success requires an approved provider refund."}
		}
		if status != "succeeded" {
			if _, err = tx.ExecContext(ctx, `UPDATE payment_refunds SET status='succeeded',provider_event_id=$2,financial_journal_id=$3,failure_code=NULL,updated_at=now() WHERE id=$1`, id, event.EventID, journalID); err != nil {
				return err
			}
			if _, err = tx.ExecContext(ctx, `INSERT INTO payment_refund_audit_events(refund_id,event_type,reason,metadata) VALUES($1,'provider_succeeded','Verified synthetic provider refund succeeded',jsonb_build_object('journal_id',$2::text))`, id, journalID); err != nil {
				return err
			}
		}
		_, err = tx.ExecContext(ctx, `UPDATE payment_provider_events SET processing_state='processed',processing_result='verified refund success recorded',refund_id=$2,financial_journal_id=$3 WHERE id=$1`, eventID, id, journalID)
		return err
	})
	return result, err
}

func postSandboxRefund(ctx context.Context, tx *sqlx.Tx, refundID, attemptID string, event VerifiedProviderEvent) (string, error) {
	var clearing, receipts string
	if err := tx.QueryRowxContext(ctx, `SELECT max(account_id::text) FILTER(WHERE purpose='provider_clearing'),max(account_id::text) FILTER(WHERE purpose='customer_receipts_unapplied') FROM payment_ledger_account_mappings`).Scan(&clearing, &receipts); err != nil {
		return "", err
	}
	if clearing == "" || receipts == "" {
		return "", errors.New("sandbox refund ledger mapping is incomplete")
	}
	j, err := financialledger.PostSandboxPaymentJournalTx(ctx, tx, financialledger.PostInput{Currency: event.Currency, SourceType: "sandbox_payment_refund", SourceID: refundID, SourceEvent: "verified_refund", IdempotencyKey: "sandbox-refund-" + refundID, Description: "Verified synthetic sandbox refund", Lines: []financialledger.Line{{AccountID: receipts, Side: "debit", Amount: event.AmountMinor, Memo: "Sandbox customer refund obligation discharged"}, {AccountID: clearing, Side: "credit", Amount: event.AmountMinor, Memo: "Sandbox provider refund clearing"}}})
	return j.ID, err
}

func (s *Service) ReconcileSandboxRefund(w http.ResponseWriter, r *http.Request, userID string) {
	if s.provider == nil || s.provider.Name() != sandboxProviderName {
		writeFailure(w, 503, "SANDBOX_PROVIDER_DISABLED", "Sandbox refund reconciliation is unavailable.")
		return
	}
	id, err := uuid.Parse(r.PathValue("id"))
	if err != nil {
		writeFailure(w, 400, "VALIDATION_ERROR", "A valid refund ID is required.")
		return
	}
	if err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error { return financialledger.AuthorizeTx(r.Context(), tx, userID, "finance.post") }); err != nil {
		writeFailure(w, 403, "FORBIDDEN", "Finance posting permission is required for reconciliation.")
		return
	}
	var ref string
	if err = s.db.GetContext(r.Context(), &ref, `SELECT provider_reference FROM payment_refunds WHERE id=$1 AND provider_reference IS NOT NULL`, id.String()); err != nil {
		writeFailure(w, 404, "REFUND_NOT_FOUND", "Refund provider reference was not found.")
		return
	}
	pr, err := s.provider.FetchRefund(r.Context(), ref)
	if err != nil {
		writeFailure(w, 404, "REFUND_RECONCILIATION_REQUIRED", "Sandbox provider has no matching refund reference.")
		return
	}
	ev := VerifiedProviderEvent{ObjectType: "refund", Provider: sandboxProviderName, EventID: "reconcile-" + ref + "-" + pr.Status + "-" + shortHash(fmt.Sprintf("%d:%s", pr.AmountMinor, pr.Currency)), ProviderReference: pr.Reference, Status: pr.Status, Currency: pr.Currency, AmountMinor: pr.AmountMinor, EventAt: time.Now().UTC()}
	raw, _ := json.Marshal(ev)
	result, err := s.processVerifiedRefundEvent(r.Context(), ev, raw, "kid=server-reconcile")
	if err != nil {
		writeFailure(w, 500, "RECONCILIATION_FAILED", "Refund status could not be reconciled.")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"data": map[string]string{"refund_id": id.String(), "provider_status": pr.Status, "processing_state": result}})
}

func (s *Service) SimulatePaymentOutcome(w http.ResponseWriter, r *http.Request, userID string) {
	if !sandboxSimulationAllowed(userID) {
		writeFailure(w, 404, "NOT_FOUND", "Sandbox simulation is unavailable.")
		return
	}
	var in struct {
		Status string `json:"status"`
	}
	if json.NewDecoder(http.MaxBytesReader(w, r.Body, 1024)).Decode(&in) != nil || !validProviderStatus(in.Status) {
		writeFailure(w, 400, "VALIDATION_ERROR", "A supported sandbox outcome is required.")
		return
	}
	if s.provider == nil || s.provider.Name() != sandboxProviderName {
		writeFailure(w, 503, "SANDBOX_PROVIDER_DISABLED", "Sandbox simulation is unavailable.")
		return
	}
	orderID, err := uuid.Parse(r.PathValue("id"))
	if err != nil {
		writeFailure(w, 400, "VALIDATION_ERROR", "A valid order ID is required.")
		return
	}
	if !s.requireCustomer(w, r, userID) {
		return
	}
	var a paymentAttempt
	err = s.db.QueryRowxContext(r.Context(), `SELECT a.id::text,a.payment_intent_id::text,i.order_id::text,a.provider,COALESCE(a.provider_reference,''),a.status,a.currency,a.amount_minor,COALESCE(a.expires_at,now()) FROM payment_attempts a JOIN payment_intents i ON i.id=a.payment_intent_id WHERE i.order_id=$1 AND i.customer_user_id=$2 ORDER BY a.attempt_number DESC LIMIT 1`, orderID.String(), userID).Scan(&a.ID, &a.IntentID, &a.OrderID, &a.Provider, &a.ProviderReference, &a.Status, &a.Currency, &a.AmountMinor, &a.ExpiresAt)
	if err != nil {
		writeFailure(w, 404, "PAYMENT_ATTEMPT_NOT_FOUND", "Payment attempt was not found.")
		return
	}
	provider, ok := s.provider.(*SandboxProvider)
	if !ok {
		writeFailure(w, 503, "SANDBOX_PROVIDER_DISABLED", "Sandbox simulation is unavailable.")
		return
	}
	provider.SetPayment(ProviderPayment{Reference: a.ProviderReference, Status: in.Status, AmountMinor: a.AmountMinor, Currency: a.Currency})
	ev := VerifiedProviderEvent{ObjectType: "payment", Provider: sandboxProviderName, EventID: "qa-" + uuid.NewString(), ProviderReference: a.ProviderReference, Status: in.Status, AmountMinor: a.AmountMinor, Currency: a.Currency, EventAt: time.Now().UTC()}
	raw, _ := json.Marshal(ev)
	result, err := s.processVerifiedEvent(r.Context(), ev, raw, "kid=qa-simulation")
	if err != nil {
		writeFailure(w, 500, "SANDBOX_SIMULATION_FAILED", "Sandbox event could not be processed.")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"data": map[string]string{"attempt_id": a.ID, "provider_status": in.Status, "processing_state": result, "sandbox": "true"}})
}

func (s *Service) SimulateRefundOutcome(w http.ResponseWriter, r *http.Request, userID string) {
	if !sandboxSimulationAllowed(userID) {
		writeFailure(w, 404, "NOT_FOUND", "Sandbox simulation is unavailable.")
		return
	}
	var in struct {
		Status string `json:"status"`
	}
	if json.NewDecoder(http.MaxBytesReader(w, r.Body, 1024)).Decode(&in) != nil || (in.Status != "pending" && in.Status != "succeeded" && in.Status != "failed") {
		writeFailure(w, 400, "VALIDATION_ERROR", "A supported sandbox refund outcome is required.")
		return
	}
	if !s.requireCustomer(w, r, userID) {
		return
	}
	orderID, e := uuid.Parse(r.PathValue("id"))
	refundID, e2 := uuid.Parse(r.PathValue("refundId"))
	if e != nil || e2 != nil {
		writeFailure(w, 400, "VALIDATION_ERROR", "Valid order and refund IDs are required.")
		return
	}
	var ev VerifiedProviderEvent
	e = s.db.QueryRowxContext(r.Context(), `SELECT r.id::text,r.provider_reference,r.amount_minor,r.currency,r.status FROM payment_refunds r WHERE r.id=$1 AND r.order_id=$2 AND r.customer_user_id=$3`, refundID.String(), orderID.String(), userID).Scan(&ev.EventID, &ev.ProviderReference, &ev.AmountMinor, &ev.Currency, &ev.Status)
	if e != nil {
		writeFailure(w, 404, "REFUND_NOT_FOUND", "Refund was not found for this account.")
		return
	}
	if ev.ProviderReference == "" {
		writeFailure(w, 409, "REFUND_NOT_PROCESSING", "Refund has not been approved by finance.")
		return
	}
	provider, ok := s.provider.(*SandboxProvider)
	if !ok {
		writeFailure(w, 503, "SANDBOX_PROVIDER_DISABLED", "Sandbox simulation is unavailable.")
		return
	}
	pr, e := provider.FetchRefund(r.Context(), ev.ProviderReference)
	if e != nil {
		writeFailure(w, 404, "REFUND_PROVIDER_REFERENCE_UNKNOWN", "Sandbox provider reference is unavailable.")
		return
	}
	pr.Status = in.Status
	provider.SetRefund(pr)
	ev.ObjectType = "refund"
	ev.Provider = sandboxProviderName
	ev.EventID = "qa-refund-" + uuid.NewString()
	ev.Status = in.Status
	ev.EventAt = time.Now().UTC()
	raw, _ := json.Marshal(ev)
	result, e := s.processVerifiedRefundEvent(r.Context(), ev, raw, "kid=qa-simulation")
	if e != nil {
		writeFailure(w, 500, "SANDBOX_SIMULATION_FAILED", "Sandbox refund event could not be processed.")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"data": map[string]string{"refund_id": refundID.String(), "provider_status": in.Status, "processing_state": result, "sandbox": "true"}})
}

func (s *Service) requireCustomer(w http.ResponseWriter, r *http.Request, userID string) bool {
	allowed, err := s.customerAllowed(r.Context(), userID)
	if err != nil {
		writeFailure(w, 500, "INTERNAL_ERROR", "Customer access could not be verified.")
		return false
	}
	if !allowed {
		writeFailure(w, 403, "FORBIDDEN", "Customer access is required.")
		return false
	}
	return true
}
func sandboxSimulationAllowed(userID string) bool {
	env := os.Getenv("APP_ENV")
	if env != "qa" && env != "test" {
		return false
	}
	for _, id := range strings.Split(os.Getenv("PAYMENT_SANDBOX_QA_USER_IDS"), ",") {
		if strings.TrimSpace(id) == userID && userID != "" {
			return true
		}
	}
	return false
}
func validRefundReason(reason string) bool {
	switch reason {
	case "order_cancelled", "items_missing", "items_damaged", "duplicate_payment", "other":
		return true
	}
	return false
}
func max64(a, b int64) int64 {
	if a > b {
		return a
	}
	return b
}
