package codcash

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
	"grepmind-near/backend/internal/financialledger"
	"grepmind-near/backend/pkg/database"
)

type Service struct {
	db      *database.DB
	enabled bool
}

func NewService(db *database.DB, enabled bool) *Service { return &Service{db: db, enabled: enabled} }

type apiError struct {
	status        int
	code, message string
}

func (e *apiError) Error() string                 { return e.message }
func fail(status int, code, message string) error { return &apiError{status, code, message} }
func writeError(w http.ResponseWriter, err error) {
	var e *apiError
	if errors.As(err, &e) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(e.status)
		_ = json.NewEncoder(w).Encode(map[string]any{"error": map[string]string{"code": e.code, "message": e.message}})
		return
	}
	http.Error(w, `{"error":{"code":"INTERNAL_ERROR","message":"Cash accountability request failed."}}`, http.StatusInternalServerError)
}

func (s *Service) allowed(ctx context.Context, tx *sqlx.Tx) bool {
	if s == nil || !s.enabled {
		return false
	}
	var enabled bool
	return tx.GetContext(ctx, &enabled, `SELECT financial_posting_enabled AND sandbox_cod_enabled AND NOT upi_enabled AND NOT cod_enabled AND NOT merchant_settlement_enabled AND NOT real_money_enabled FROM financial_feature_config WHERE singleton=true`) == nil && enabled
}

// RecordCollectionTx is called only after customer delivery OTP verification,
// in the same transaction that changes custody to delivered. It never updates
// customer_orders.payment_status and it posts no earnings or merchant payable.
func (s *Service) RecordCollectionTx(ctx context.Context, tx *sqlx.Tx, jobID, riderID string) error {
	if s == nil || !s.enabled {
		return fail(503, "SYNTHETIC_COD_DISABLED", "Synthetic COD is disabled in this environment.")
	}
	if !s.allowed(ctx, tx) {
		return fail(503, "SYNTHETIC_COD_DISABLED", "Synthetic COD is disabled in this environment.")
	}
	var obligationID, orderID, assignmentID, method, status, execution string
	var amount int64
	err := tx.QueryRowxContext(ctx, `SELECT ob.id::text,o.id::text,a.id::text,COALESCE(o.payment_method,''),o.status,j.execution_state,ob.amount_minor
		FROM delivery_jobs j JOIN customer_orders o ON o.id=j.order_id
		JOIN delivery_assignments a ON a.job_id=j.id AND a.rider_user_id=$2 AND a.state='active'
		JOIN cod_obligations ob ON ob.order_id=o.id
		WHERE j.id=$1 FOR UPDATE OF j,o,a,ob`, jobID, riderID).Scan(&obligationID, &orderID, &assignmentID, &method, &status, &execution, &amount)
	if errors.Is(err, sql.ErrNoRows) {
		return fail(409, "COD_OBLIGATION_REQUIRED", "This delivery has no active COD obligation for the assigned rider.")
	}
	if err != nil {
		return err
	}
	if method != "cash_on_delivery" || status != "out_for_delivery" || execution != "en_route" {
		return fail(409, "COD_CUSTODY_INVALID", "Synthetic COD can be recorded only for the assigned rider at verified customer handover.")
	}
	var deliveryOTP bool
	if err := tx.GetContext(ctx, &deliveryOTP, `SELECT EXISTS(SELECT 1 FROM delivery_verification_codes WHERE job_id=$1 AND purpose='delivery' AND consumed_at IS NOT NULL AND invalidated_at IS NULL)`, jobID); err != nil {
		return err
	}
	if !deliveryOTP {
		return fail(409, "DELIVERY_VERIFICATION_REQUIRED", "Customer delivery verification is required before collection.")
	}
	var count int
	if err := tx.GetContext(ctx, &count, `SELECT count(*) FROM cod_collections WHERE obligation_id=$1`, obligationID); err != nil {
		return err
	}
	if count != 0 {
		return fail(409, "COD_ALREADY_COLLECTED", "Synthetic COD collection was already recorded.")
	}
	var receivableID, clearingID string
	if err := tx.QueryRowxContext(ctx, `SELECT id::text FROM financial_accounts WHERE account_code='rider_cash_receivable' AND currency='INR' AND is_enabled`).Scan(&receivableID); errors.Is(err, sql.ErrNoRows) {
		return fail(503, "COD_ACCOUNTS_NOT_CONFIGURED", "Synthetic COD accounting accounts are not configured in this environment.")
	} else if err != nil {
		return err
	}
	if err := tx.QueryRowxContext(ctx, `SELECT id::text FROM financial_accounts WHERE account_code='cod_collection_clearing' AND currency='INR' AND is_enabled`).Scan(&clearingID); errors.Is(err, sql.ErrNoRows) {
		return fail(503, "COD_ACCOUNTS_NOT_CONFIGURED", "Synthetic COD accounting accounts are not configured in this environment.")
	} else if err != nil {
		return err
	}
	key := "cod-collection:" + obligationID
	journal, err := financialledger.PostSandboxCODJournalTx(ctx, tx, financialledger.PostInput{
		Currency: "INR", SourceType: "sandbox_cod_collection", SourceID: obligationID,
		SourceEvent: "collected", IdempotencyKey: key, Description: "Synthetic QA COD collection",
		Lines: []financialledger.Line{{AccountID: receivableID, Side: "debit", Amount: amount, Memo: "Synthetic due from assigned rider"}, {AccountID: clearingID, Side: "credit", Amount: amount, Memo: "Synthetic COD collection clearing"}},
	})
	if err != nil {
		return err
	}
	collectionID := uuid.NewString()
	idem := uuid.NewString()
	if _, err := tx.ExecContext(ctx, `INSERT INTO cod_collections(id,obligation_id,order_id,job_id,assignment_id,rider_user_id,amount_minor,currency,idempotency_key,financial_journal_id)
		VALUES($1,$2,$3,$4,$5,$6,$7,'INR',$8,$9)`, collectionID, obligationID, orderID, jobID, assignmentID, riderID, amount, idem, journal.ID); err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO cod_audit_events(actor_user_id,obligation_id,collection_id,event_type,reason,metadata)
		VALUES($1,$2,$3,'collection_recorded','Customer OTP handover confirmed; synthetic QA collection only',jsonb_build_object('amount_minor',$4::bigint,'environment','synthetic_qa'))`, riderID, obligationID, collectionID, amount)
	return err
}

func (s *Service) RiderSummary(w http.ResponseWriter, r *http.Request, riderID string) {
	var result map[string]any
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if !s.allowed(r.Context(), tx) {
			return fail(503, "SYNTHETIC_COD_DISABLED", "Synthetic COD is disabled in this environment.")
		}
		var collected, verified, pending, disputed int64
		if err := tx.QueryRowxContext(r.Context(), `SELECT
		 COALESCE((SELECT sum(amount_minor) FROM cod_collections WHERE rider_user_id=$1),0),
		 COALESCE((SELECT sum(amount_minor) FROM cod_remittances WHERE rider_user_id=$1 AND state='verified'),0),
		 COALESCE((SELECT sum(amount_minor) FROM cod_remittances WHERE rider_user_id=$1 AND state='submitted'),0),
		 COALESCE((SELECT sum(amount_minor) FROM cod_remittances WHERE rider_user_id=$1 AND state='disputed'),0)`, riderID).Scan(&collected, &verified, &pending, &disputed); err != nil {
			return err
		}
		result = map[string]any{"currency": "INR", "mode": "synthetic_qa", "collected_minor": collected, "verified_remitted_minor": verified, "outstanding_liability_minor": collected - verified, "pending_remittance_minor": pending, "disputed_remittance_minor": disputed}
		return nil
	})
	if err != nil {
		writeError(w, err)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"data": result})
}

func (s *Service) CustomerStatus(w http.ResponseWriter, r *http.Request, customerID string) {
	orderID := r.PathValue("id")
	if _, err := uuid.Parse(orderID); err != nil {
		writeError(w, fail(404, "NOT_FOUND", "Order was not found for this account."))
		return
	}
	var result map[string]any
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var exists bool
		if err := tx.GetContext(r.Context(), &exists, `SELECT EXISTS(SELECT 1 FROM customer_orders WHERE id=$1 AND customer_user_id=$2 AND order_source='platform_catalog')`, orderID, customerID); err != nil {
			return err
		}
		if !exists {
			return fail(404, "NOT_FOUND", "Order was not found for this account.")
		}
		var paymentMethod, paymentStatus string
		if err := tx.QueryRowxContext(r.Context(), `SELECT COALESCE(payment_method,''),payment_status FROM customer_orders WHERE id=$1 AND customer_user_id=$2`, orderID, customerID).Scan(&paymentMethod, &paymentStatus); err != nil {
			return err
		}
		result = map[string]any{"order_id": orderID, "payment_method": paymentMethod, "payment_status": paymentStatus}
		if paymentMethod == "cash_on_delivery" {
			var obligationID, state string
			var amount int64
			var collectionID sql.NullString
			if err := tx.QueryRowxContext(r.Context(), `SELECT ob.id::text,ob.amount_minor,ob.state,c.id::text FROM cod_obligations ob LEFT JOIN cod_collections c ON c.obligation_id=ob.id WHERE ob.order_id=$1 AND ob.customer_user_id=$2`, orderID, customerID).Scan(&obligationID, &amount, &state, &collectionID); err != nil {
				return err
			}
			result["cod"] = map[string]any{"obligation_id": obligationID, "amount_minor": amount, "currency": "INR", "collection_state": state, "collected": collectionID.Valid, "mode": "synthetic_qa"}
		}
		return nil
	})
	if err != nil {
		writeError(w, err)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"data": result})
}

type remittanceInput struct {
	AmountMinor int64  `json:"amount_minor"`
	Reference   string `json:"submission_reference"`
}

func (s *Service) SubmitRemittance(w http.ResponseWriter, r *http.Request, riderID string) {
	var in remittanceInput
	d := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096))
	d.DisallowUnknownFields()
	if d.Decode(&in) != nil || ensureJSONEOF(d) != nil || in.AmountMinor <= 0 || len(strings.TrimSpace(in.Reference)) < 1 || len(in.Reference) > 120 {
		writeError(w, fail(400, "VALIDATION_ERROR", "Provide a positive remittance amount and reference."))
		return
	}
	key, err := uuid.Parse(r.Header.Get("Idempotency-Key"))
	if err != nil {
		writeError(w, fail(400, "IDEMPOTENCY_KEY_REQUIRED", "A UUID Idempotency-Key is required."))
		return
	}
	fp := sha256.Sum256([]byte(fmt.Sprintf("%s|%d|%s", riderID, in.AmountMinor, strings.TrimSpace(in.Reference))))
	var result map[string]any
	statusCode := http.StatusCreated
	err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if !s.allowed(r.Context(), tx) {
			return fail(503, "SYNTHETIC_COD_DISABLED", "Synthetic COD is disabled in this environment.")
		}
		var lock string
		if err := tx.QueryRowxContext(r.Context(), `SELECT id::text FROM users WHERE id=$1 AND status='active' FOR UPDATE`, riderID).Scan(&lock); err != nil {
			return err
		}
		var priorID, priorState string
		var priorAmount int64
		var priorFP []byte
		err := tx.QueryRowxContext(r.Context(), `SELECT id::text,state,amount_minor,request_fingerprint FROM cod_remittances WHERE rider_user_id=$1 AND idempotency_key=$2 FOR UPDATE`, riderID, key.String()).Scan(&priorID, &priorState, &priorAmount, &priorFP)
		if err == nil {
			if string(priorFP) != string(fp[:]) {
				return fail(409, "IDEMPOTENCY_CONFLICT", "This key was used for another remittance.")
			}
			result = map[string]any{"id": priorID, "state": priorState, "amount_minor": priorAmount, "currency": "INR", "mode": "synthetic_qa", "idempotent_replay": true}
			statusCode = http.StatusOK
			return nil
		}
		if !errors.Is(err, sql.ErrNoRows) {
			return err
		}
		var collected, verified, pending int64
		if err := tx.QueryRowxContext(r.Context(), `SELECT COALESCE((SELECT sum(amount_minor) FROM cod_collections WHERE rider_user_id=$1),0),COALESCE((SELECT sum(amount_minor) FROM cod_remittances WHERE rider_user_id=$1 AND state='verified'),0),COALESCE((SELECT sum(amount_minor) FROM cod_remittances WHERE rider_user_id=$1 AND state='submitted'),0)`, riderID).Scan(&collected, &verified, &pending); err != nil {
			return err
		}
		if in.AmountMinor > collected-verified-pending {
			return fail(409, "REMITTANCE_EXCEEDS_LIABILITY", "Submitted remittance exceeds unverified available rider liability.")
		}
		id := uuid.NewString()
		_, err = tx.ExecContext(r.Context(), `INSERT INTO cod_remittances(id,rider_user_id,amount_minor,currency,submission_reference,idempotency_key,request_fingerprint) VALUES($1,$2,$3,'INR',$4,$5,$6)`, id, riderID, in.AmountMinor, strings.TrimSpace(in.Reference), key.String(), fp[:])
		if err != nil {
			return err
		}
		if _, err = tx.ExecContext(r.Context(), `INSERT INTO cod_audit_events(actor_user_id,remittance_id,event_type,reason,metadata) VALUES($1,$2,'remittance_submitted','Rider submitted a synthetic QA remittance claim',jsonb_build_object('amount_minor',$3::bigint))`, riderID, id, in.AmountMinor); err != nil {
			return err
		}
		result = map[string]any{"id": id, "state": "submitted", "amount_minor": in.AmountMinor, "currency": "INR", "mode": "synthetic_qa", "idempotent_replay": false}
		return nil
	})
	if err != nil {
		writeError(w, err)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	_ = json.NewEncoder(w).Encode(map[string]any{"data": result})
}

func (s *Service) ListAdminRemittances(w http.ResponseWriter, r *http.Request, actorID string) {
	rows := make([]map[string]any, 0)
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := financialledger.AuthorizeReadTx(r.Context(), tx, actorID); err != nil {
			return fail(403, "FORBIDDEN", "Active Platform Admin access is required.")
		}
		var e error
		rows, e = queryMaps(r.Context(), tx, `SELECT r.id::text,r.rider_user_id::text,p.display_name rider_name,r.amount_minor,r.currency,r.submission_reference,r.state,r.submitted_at::text,r.reviewed_at::text,r.verification_reason, EXISTS (SELECT 1 FROM financial_journals j WHERE j.id=r.financial_journal_id AND j.source_type='sandbox_cod_remittance' AND j.source_event='verified' AND j.status='posted') AS sandbox_verified FROM cod_remittances r JOIN rider_profiles p ON p.user_id=r.rider_user_id ORDER BY r.submitted_at DESC LIMIT 200`)
		return e
	})
	if err != nil {
		writeError(w, err)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"data": rows})
}

func (s *Service) ListAdminCollections(w http.ResponseWriter, r *http.Request, actorID string) {
	rows := make([]map[string]any, 0)
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := financialledger.AuthorizeReadTx(r.Context(), tx, actorID); err != nil {
			return fail(403, "FORBIDDEN", "Active Platform Admin access is required.")
		}
		var e error
		rows, e = queryMaps(r.Context(), tx, `SELECT c.id::text,c.order_id::text,o.reference_code,c.job_id::text,c.rider_user_id::text,p.display_name rider_name,c.amount_minor,c.currency,c.collected_at::text,c.financial_journal_id::text FROM cod_collections c JOIN customer_orders o ON o.id=c.order_id JOIN rider_profiles p ON p.user_id=c.rider_user_id ORDER BY c.collected_at DESC LIMIT 200`)
		return e
	})
	if err != nil {
		writeError(w, err)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"data": rows})
}

func (s *Service) Audit(w http.ResponseWriter, r *http.Request, actorID string) {
	rows := make([]map[string]any, 0)
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := financialledger.AuthorizeReadTx(r.Context(), tx, actorID); err != nil {
			return fail(403, "FORBIDDEN", "Active Platform Admin access is required.")
		}
		var e error
		rows, e = queryMaps(r.Context(), tx, `SELECT e.id::text,e.event_type,e.actor_user_id::text,e.obligation_id::text,e.collection_id::text,e.remittance_id::text,e.reason,e.metadata,e.created_at::text FROM cod_audit_events e ORDER BY e.created_at DESC LIMIT 300`)
		return e
	})
	if err != nil {
		writeError(w, err)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"data": rows})
}

func (s *Service) Reconcile(w http.ResponseWriter, r *http.Request, actorID string) {
	var issues []map[string]any
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := financialledger.AuthorizeReadTx(r.Context(), tx, actorID); err != nil {
			return fail(403, "FORBIDDEN", "Active Platform Admin access is required.")
		}
		var e error
		issues, e = queryMaps(r.Context(), tx, `SELECT 'delivered_without_collection'::text issue,o.id::text order_id,o.reference_code,NULL::text reference FROM customer_orders o LEFT JOIN cod_collections c ON c.order_id=o.id WHERE o.payment_method='cash_on_delivery' AND o.status='delivered' AND c.id IS NULL UNION ALL SELECT 'collection_journal_missing',c.order_id::text,o.reference_code,c.id::text FROM cod_collections c JOIN customer_orders o ON o.id=c.order_id LEFT JOIN financial_journals j ON j.id=c.financial_journal_id AND j.status='posted' WHERE j.id IS NULL UNION ALL SELECT 'verified_remittance_journal_missing',r.id::text,NULL::text,r.id::text FROM cod_remittances r LEFT JOIN financial_journals j ON j.id=r.financial_journal_id AND j.status='posted' WHERE r.state='verified' AND j.id IS NULL UNION ALL SELECT 'negative_rider_liability',q.rider_user_id::text,NULL::text,NULL::text FROM (SELECT c.rider_user_id,sum(c.amount_minor)-COALESCE((SELECT sum(r.amount_minor) FROM cod_remittances r WHERE r.rider_user_id=c.rider_user_id AND r.state='verified'),0) liability FROM cod_collections c GROUP BY c.rider_user_id) q WHERE q.liability<0 ORDER BY 1 LIMIT 500`)
		return e
	})
	if err != nil {
		writeError(w, err)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"data": map[string]any{"issues": issues, "issue_count": len(issues), "automatic_repairs": false}})
}

func (s *Service) ReviewRemittance(w http.ResponseWriter, r *http.Request, actorID string) {
	var in struct {
		Decision string `json:"decision"`
		Reason   string `json:"reason"`
	}
	d := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096))
	d.DisallowUnknownFields()
	if d.Decode(&in) != nil || ensureJSONEOF(d) != nil {
		writeError(w, fail(400, "VALIDATION_ERROR", "A remittance decision is required."))
		return
	}
	if (in.Decision != "verify" && in.Decision != "dispute" && in.Decision != "reject") || len(strings.TrimSpace(in.Reason)) < 5 || len(in.Reason) > 300 {
		writeError(w, fail(400, "VALIDATION_ERROR", "Choose verify, dispute or reject and provide a review reason."))
		return
	}
	remitID, err := uuid.Parse(r.PathValue("remittanceId"))
	if err != nil {
		writeError(w, fail(400, "VALIDATION_ERROR", "A valid remittance ID is required."))
		return
	}
	err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if !s.allowed(r.Context(), tx) {
			return fail(503, "SYNTHETIC_COD_DISABLED", "Synthetic COD is disabled in this environment.")
		}
		if err := financialledger.AuthorizeTx(r.Context(), tx, actorID, "finance.post"); err != nil {
			return fail(403, "FORBIDDEN", "Finance posting permission is required.")
		}
		var riderID, state string
		var amount int64
		if err := tx.QueryRowxContext(r.Context(), `SELECT rider_user_id::text,state,amount_minor FROM cod_remittances WHERE id=$1 FOR UPDATE`, remitID.String()).Scan(&riderID, &state, &amount); errors.Is(err, sql.ErrNoRows) {
			return fail(404, "NOT_FOUND", "Remittance was not found.")
		} else if err != nil {
			return err
		}
		if riderID == actorID {
			return fail(403, "SELF_REVIEW_FORBIDDEN", "A rider cannot review their own remittance.")
		}
		if state != "submitted" {
			return fail(409, "INVALID_STATE", "Only submitted remittances may be reviewed.")
		}
		if in.Decision == "verify" {
			var lock string
			if err := tx.QueryRowxContext(r.Context(), `SELECT id::text FROM users WHERE id=$1 FOR UPDATE`, riderID).Scan(&lock); err != nil {
				return err
			}
			var collected, verified int64
			if err := tx.QueryRowxContext(r.Context(), `SELECT COALESCE((SELECT sum(amount_minor) FROM cod_collections WHERE rider_user_id=$1),0),COALESCE((SELECT sum(amount_minor) FROM cod_remittances WHERE rider_user_id=$1 AND state='verified'),0)`, riderID).Scan(&collected, &verified); err != nil {
				return err
			}
			if verified+amount > collected {
				return fail(409, "REMITTANCE_EXCEEDS_LIABILITY", "Verified remittance would exceed collected rider liability.")
			}
			var receivableID, clearingID string
			if err := tx.QueryRowxContext(r.Context(), `SELECT id::text FROM financial_accounts WHERE account_code='rider_cash_receivable' AND currency='INR'`).Scan(&receivableID); err != nil {
				return err
			}
			if err := tx.QueryRowxContext(r.Context(), `SELECT id::text FROM financial_accounts WHERE account_code='synthetic_cash_remittance_clearing' AND currency='INR'`).Scan(&clearingID); err != nil {
				return err
			}
			j, err := financialledger.PostSandboxCODJournalTx(r.Context(), tx, financialledger.PostInput{Currency: "INR", SourceType: "sandbox_cod_remittance", SourceID: remitID.String(), SourceEvent: "verified", IdempotencyKey: "cod-remittance:" + remitID.String(), Description: "Verified synthetic QA rider remittance", Lines: []financialledger.Line{{AccountID: clearingID, Side: "debit", Amount: amount, Memo: "Synthetic verified remittance clearing"}, {AccountID: receivableID, Side: "credit", Amount: amount, Memo: "Reduce synthetic rider cash liability"}}})
			if err != nil {
				return err
			}
			if _, err = tx.ExecContext(r.Context(), `UPDATE cod_remittances SET state='verified',reviewed_by=$2,reviewed_at=now(),verification_reason=$3,financial_journal_id=$4 WHERE id=$1`, remitID.String(), actorID, strings.TrimSpace(in.Reason), j.ID); err != nil {
				return err
			}
		} else {
			next := "disputed"
			ev := "remittance_disputed"
			if in.Decision == "reject" {
				next = "rejected"
				ev = "remittance_rejected"
			}
			if _, err := tx.ExecContext(r.Context(), `UPDATE cod_remittances SET state=$2,reviewed_by=$3,reviewed_at=now(),verification_reason=$4 WHERE id=$1`, remitID.String(), next, actorID, strings.TrimSpace(in.Reason)); err != nil {
				return err
			}
			_, err := tx.ExecContext(r.Context(), `INSERT INTO cod_audit_events(actor_user_id,remittance_id,event_type,reason) VALUES($1,$2,$3,$4)`, actorID, remitID.String(), ev, strings.TrimSpace(in.Reason))
			return err
		}
		_, err := tx.ExecContext(r.Context(), `INSERT INTO cod_audit_events(actor_user_id,remittance_id,event_type,reason,metadata) VALUES($1,$2,'remittance_verified',$3,jsonb_build_object('amount_minor',$4::bigint))`, actorID, remitID.String(), strings.TrimSpace(in.Reason), amount)
		return err
	})
	if err != nil {
		writeError(w, err)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"data": map[string]string{"id": remitID.String(), "decision": in.Decision}})
}

func (s *Service) RiderRemittances(w http.ResponseWriter, r *http.Request, riderID string) {
	rows := make([]map[string]any, 0)
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if !s.allowed(r.Context(), tx) {
			return fail(503, "SYNTHETIC_COD_DISABLED", "Synthetic COD is disabled in this environment.")
		}
		var err error
		rows, err = queryMaps(r.Context(), tx, `SELECT id::text,state,amount_minor,currency,submission_reference,submitted_at::text,reviewed_at::text,verification_reason FROM cod_remittances WHERE rider_user_id=$1 ORDER BY submitted_at DESC LIMIT 100`, riderID)
		return err
	})
	if err != nil {
		writeError(w, err)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"data": rows})
}

func queryMaps(ctx context.Context, tx *sqlx.Tx, query string, args ...any) ([]map[string]any, error) {
	rows, err := tx.QueryxContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := make([]map[string]any, 0)
	for rows.Next() {
		item := map[string]any{}
		if err := rows.MapScan(item); err != nil {
			return nil, err
		}
		for k, v := range item {
			if b, ok := v.([]byte); ok {
				item[k] = string(b)
			}
		}
		result = append(result, item)
	}
	return result, rows.Err()
}

func fingerprintString(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func ensureJSONEOF(decoder *json.Decoder) error {
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		if err == nil {
			return errors.New("unexpected trailing JSON value")
		}
		return err
	}
	return nil
}
