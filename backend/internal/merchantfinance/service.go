package merchantfinance

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"math/big"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jmoiron/sqlx"
	"grepmind-near/backend/internal/financialledger"
	"grepmind-near/backend/pkg/database"
)

const merchantSimulatedSettlementTotalQuery = `SELECT COALESCE(sum(simulated_net_minor),0)::bigint FROM merchant_settlement_batches WHERE business_id=$1 AND status IN ('simulated','reconciled')`

type Service struct {
	db            *database.DB
	qaEnvironment bool
}

const insertSettlementCreatedEventQuery = `INSERT INTO merchant_settlement_events(batch_id,actor_user_id,event_type,reason,metadata) VALUES($1,$2,'created','Settlement draft prepared for isolated simulation',jsonb_build_object('simulated_net_minor',$3::bigint,'funding_mode',$4::text))`

func NewService(db *database.DB, environment string) *Service {
	return &Service{db: db, qaEnvironment: environment == "qa" || environment == "test"}
}

type apiError struct {
	status        int
	code, message string
}

func (e *apiError) Error() string                         { return e.message }
func financeError(status int, code, message string) error { return &apiError{status, code, message} }
func writeError(w http.ResponseWriter, err error) {
	var e *apiError
	if errors.As(err, &e) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(e.status)
		_ = json.NewEncoder(w).Encode(map[string]any{"error": map[string]string{"code": e.code, "message": e.message}})
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusInternalServerError)
	_ = json.NewEncoder(w).Encode(map[string]any{"error": map[string]string{"code": "INTERNAL_ERROR", "message": "Merchant finance request failed."}})
}
func writeJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{"data": data})
}
func decode(w http.ResponseWriter, r *http.Request, out any) error {
	r.Body = http.MaxBytesReader(w, r.Body, 16<<10)
	d := json.NewDecoder(r.Body)
	d.DisallowUnknownFields()
	if err := d.Decode(out); err != nil {
		return financeError(400, "VALIDATION_ERROR", "The finance request is invalid.")
	}
	var extra any
	if err := d.Decode(&extra); err != io.EOF {
		return financeError(400, "VALIDATION_ERROR", "The finance request must contain one JSON value.")
	}
	return nil
}
func (s *Service) featureEnabled(ctx context.Context, tx *sqlx.Tx) bool {
	if !s.qaEnvironment {
		return false
	}
	var enabled bool
	return tx.GetContext(ctx, &enabled, `SELECT financial_posting_enabled AND sandbox_merchant_settlement_enabled AND NOT upi_enabled AND NOT cod_enabled AND NOT merchant_settlement_enabled AND NOT real_money_enabled FROM financial_feature_config WHERE singleton=true`) == nil && enabled
}
func authorize(ctx context.Context, tx *sqlx.Tx, actor, permission string) error {
	if err := financialledger.AuthorizeTx(ctx, tx, actor, permission); err != nil {
		return financeError(403, "FORBIDDEN", "The required finance permission is not granted.")
	}
	return nil
}
func fingerprint(v any) ([]byte, error) {
	b, err := json.Marshal(v)
	if err != nil {
		return nil, err
	}
	sum := sha256.Sum256(b)
	return sum[:], nil
}
func audit(ctx context.Context, tx *sqlx.Tx, actor, event, business, order, payable, policy, batch, reason string, metadata any) error {
	body, err := json.Marshal(metadata)
	if err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO merchant_finance_audit_events(actor_user_id,event_type,business_id,order_id,payable_id,policy_id,batch_id,reason,metadata) VALUES($1,$2,NULLIF($3,'')::uuid,NULLIF($4,'')::uuid,NULLIF($5,'')::uuid,NULLIF($6,'')::uuid,NULLIF($7,'')::uuid,$8,$9::jsonb)`, actor, event, business, order, payable, policy, batch, strings.TrimSpace(reason), string(body))
	return err
}

type policyInput struct {
	PolicyKey      string     `json:"policy_key"`
	Version        int        `json:"version"`
	BusinessID     string     `json:"business_id"`
	Vertical       string     `json:"vertical"`
	CommissionType string     `json:"commission_type"`
	PercentageBPS  *int64     `json:"percentage_bps"`
	FixedMinor     *int64     `json:"fixed_minor"`
	EffectiveFrom  time.Time  `json:"effective_from"`
	EffectiveUntil *time.Time `json:"effective_until"`
}

const insertPayableSnapshotQuery = `INSERT INTO merchant_payable_snapshots(order_id,business_id,policy_id,policy_version,currency,customer_gross_minor,partner_gross_minor,commission_basis_minor,commission_minor,net_payable_minor,source_event_id,source_event,payment_source,snapshot_hash,financial_journal_id,created_by) VALUES($1,$2,$3,$4,'INR',$5,$6,$6,$7,$8,'delivered_payment_verified','delivered_payment_verified',$9,$10,$11,$12) RETURNING id::text`

func insertPayableSnapshot(ctx context.Context, tx *sqlx.Tx, orderID, business, policyID string, version int, customerGross, partnerGross, commission, net int64, paymentSource string, hash []byte, journalID, actor string) (string, error) {
	var payableID string
	err := tx.QueryRowxContext(ctx, insertPayableSnapshotQuery, orderID, business, policyID, version, customerGross, partnerGross, commission, net, paymentSource, hash, journalID, actor).Scan(&payableID)
	return payableID, err
}

func (s *Service) ListPolicies(w http.ResponseWriter, r *http.Request, actor string) {
	if !s.qaEnvironment {
		writeError(w, financeError(404, "NOT_FOUND", "Merchant finance simulation is available only in isolated QA."))
		return
	}
	var rows []map[string]any
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := authorize(r.Context(), tx, actor, "finance.read"); err != nil {
			return err
		}
		var err error
		rows, err = queryMaps(r.Context(), tx, `SELECT p.id::text,p.policy_key,p.version,p.business_id::text,p.vertical,p.calculation_basis,p.commission_type,p.percentage_bps,p.fixed_minor,p.effective_from::text,p.effective_until::text,p.status,p.created_by::text,p.approved_by::text,p.approval_reason,p.created_at::text,p.approved_at::text,encode(p.policy_hash,'hex') policy_hash FROM merchant_commission_policies p ORDER BY p.created_at DESC LIMIT 300`)
		return err
	})
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, 200, rows)
}

func (s *Service) CreatePolicy(w http.ResponseWriter, r *http.Request, actor string) {
	if !s.qaEnvironment {
		writeError(w, financeError(404, "NOT_FOUND", "Merchant finance simulation is available only in isolated QA."))
		return
	}
	var in policyInput
	if err := decode(w, r, &in); err != nil {
		writeError(w, err)
		return
	}
	if len(strings.TrimSpace(in.PolicyKey)) < 1 || len(in.PolicyKey) > 100 || in.Version < 1 || (in.Vertical != "food" && in.Vertical != "grocery") || (in.CommissionType != "percentage_bps" && in.CommissionType != "fixed_minor") || in.EffectiveFrom.IsZero() || (in.EffectiveUntil != nil && !in.EffectiveUntil.After(in.EffectiveFrom)) {
		writeError(w, financeError(400, "VALIDATION_ERROR", "Policy scope, version, commission and effective period are required."))
		return
	}
	if in.BusinessID != "" {
		if _, err := uuid.Parse(in.BusinessID); err != nil {
			writeError(w, financeError(400, "VALIDATION_ERROR", "Business ID must be a UUID."))
			return
		}
	}
	if in.CommissionType == "percentage_bps" && (in.PercentageBPS == nil || *in.PercentageBPS < 0 || *in.PercentageBPS > 10000 || in.FixedMinor != nil) {
		writeError(w, financeError(400, "VALIDATION_ERROR", "Percentage policy requires basis points from 0 to 10000."))
		return
	}
	if in.CommissionType == "fixed_minor" && (in.FixedMinor == nil || *in.FixedMinor < 0 || in.PercentageBPS != nil) {
		writeError(w, financeError(400, "VALIDATION_ERROR", "Fixed policy requires a non-negative paise amount."))
		return
	}
	canonical := map[string]any{"key": in.PolicyKey, "version": in.Version, "business_id": in.BusinessID, "vertical": in.Vertical, "basis": "partner_supply", "type": in.CommissionType, "bps": in.PercentageBPS, "fixed_minor": in.FixedMinor, "effective_from": in.EffectiveFrom.UTC().Format(time.RFC3339Nano)}
	if in.EffectiveUntil != nil {
		canonical["effective_until"] = in.EffectiveUntil.UTC().Format(time.RFC3339Nano)
	}
	hash, err := fingerprint(canonical)
	if err != nil {
		writeError(w, err)
		return
	}
	var id string
	err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := authorize(r.Context(), tx, actor, "finance.configure"); err != nil {
			return err
		}
		if in.BusinessID != "" {
			var exists bool
			if err := tx.GetContext(r.Context(), &exists, `SELECT EXISTS(SELECT 1 FROM businesses WHERE id=$1 AND status<>'deleted')`, in.BusinessID); err != nil {
				return err
			}
			if !exists {
				return financeError(404, "NOT_FOUND", "Merchant business was not found.")
			}
		}
		if err := tx.QueryRowxContext(r.Context(), `INSERT INTO merchant_commission_policies(policy_key,version,business_id,vertical,calculation_basis,commission_type,percentage_bps,fixed_minor,effective_from,effective_until,policy_hash,created_by) VALUES($1,$2,NULLIF($3,'')::uuid,$4,'partner_supply',$5,$6,$7,$8,$9,$10,$11) RETURNING id::text`, in.PolicyKey, in.Version, in.BusinessID, in.Vertical, in.CommissionType, in.PercentageBPS, in.FixedMinor, in.EffectiveFrom, in.EffectiveUntil, hash, actor).Scan(&id); err != nil {
			return err
		}
		return audit(r.Context(), tx, actor, "commission_policy_created", in.BusinessID, "", "", id, "", "Create draft commission policy; no active rates assumed", canonical)
	})
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, 201, map[string]any{"id": id, "status": "draft", "classification": "synthetic_policy_framework_only"})
}

func (s *Service) DecidePolicy(w http.ResponseWriter, r *http.Request, actor string) {
	if !s.qaEnvironment {
		writeError(w, financeError(404, "NOT_FOUND", "Merchant finance simulation is available only in isolated QA."))
		return
	}
	var in struct {
		Decision string `json:"decision"`
		Reason   string `json:"reason"`
	}
	if err := decode(w, r, &in); err != nil {
		writeError(w, err)
		return
	}
	id := r.PathValue("policyId")
	if _, err := uuid.Parse(id); err != nil {
		writeError(w, financeError(400, "VALIDATION_ERROR", "Policy ID must be a UUID."))
		return
	}
	if (in.Decision != "approve" && in.Decision != "reject") || len(strings.TrimSpace(in.Reason)) < 5 || len(in.Reason) > 300 {
		writeError(w, financeError(400, "VALIDATION_ERROR", "Choose approve or reject and provide a review reason."))
		return
	}
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := authorize(r.Context(), tx, actor, "finance.configure"); err != nil {
			return err
		}
		var creator, status string
		if err := tx.QueryRowxContext(r.Context(), `SELECT created_by::text,status FROM merchant_commission_policies WHERE id=$1 FOR UPDATE`, id).Scan(&creator, &status); errors.Is(err, sql.ErrNoRows) {
			return financeError(404, "NOT_FOUND", "Commission policy was not found.")
		} else if err != nil {
			return err
		}
		if creator == actor {
			return financeError(403, "SELF_APPROVAL_FORBIDDEN", "The policy creator cannot approve or reject their own policy.")
		}
		if status != "draft" {
			return financeError(409, "INVALID_STATE", "Only draft commission policies can be reviewed.")
		}
		next := "rejected"
		if in.Decision == "approve" {
			next = "approved"
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE merchant_commission_policies SET status=$2,approved_by=$3,approved_at=CASE WHEN $2='approved' THEN now() END,approval_reason=$4 WHERE id=$1`, id, next, actor, strings.TrimSpace(in.Reason)); err != nil {
			return err
		}
		event := "commission_policy_rejected"
		if next == "approved" {
			event = "commission_policy_approved"
		}
		return audit(r.Context(), tx, actor, event, "", "", "", id, "", in.Reason, map[string]any{"status": next})
	})
	if err != nil {
		writeError(w, err)
		return
	}
	status := "rejected"
	if in.Decision == "approve" {
		status = "approved"
	}
	writeJSON(w, 200, map[string]string{"id": id, "status": status})
}

func selectPolicy(ctx context.Context, tx *sqlx.Tx, business, vertical string, at time.Time) (string, int, string, string, int64, int64, error) {
	var id, typ string
	var version int
	var bps sql.NullInt64
	var fixed sql.NullInt64
	err := tx.QueryRowxContext(ctx, `SELECT id::text,version,commission_type,percentage_bps,fixed_minor FROM merchant_commission_policies WHERE status='approved' AND vertical=$2 AND (business_id=$1 OR business_id IS NULL) AND effective_from<=$3 AND (effective_until IS NULL OR effective_until>$3) ORDER BY (business_id IS NOT NULL) DESC,effective_from DESC LIMIT 1`, business, vertical, at).Scan(&id, &version, &typ, &bps, &fixed)
	if errors.Is(err, sql.ErrNoRows) {
		return "", 0, "", "", 0, 0, financeError(409, "COMMISSION_POLICY_MISSING", "No approved commission policy applies to this merchant and order date.")
	}
	if err != nil {
		return "", 0, "", "", 0, 0, err
	}
	return id, version, typ, "partner_supply", bps.Int64, fixed.Int64, nil
}

func commissionAmount(basis int64, typ string, rate int64) (int64, error) {
	if basis < 0 || rate < 0 || (typ == "percentage_bps" && rate > 10000) {
		return 0, financeError(409, "PAYABLE_INVALID", "Commission inputs are outside their allowed range.")
	}
	if typ == "fixed_minor" {
		if rate > basis {
			return 0, financeError(409, "COMMISSION_EXCEEDS_PAYABLE", "Fixed commission exceeds the partner supply amount.")
		}
		return rate, nil
	}
	// Half-up rounding in integer paise: (basis*bps + 5000) / 10000.
	n := new(big.Int).Mul(big.NewInt(basis), big.NewInt(rate))
	n.Add(n, big.NewInt(5000))
	n.Quo(n, big.NewInt(10000))
	if !n.IsInt64() || n.Int64() > basis {
		return 0, financeError(409, "COMMISSION_EXCEEDS_PAYABLE", "Calculated commission exceeds the partner supply amount.")
	}
	return n.Int64(), nil
}

func checkedAddInt64(a, b int64) (int64, bool) {
	const maxInt64 = int64(^uint64(0) >> 1)
	const minInt64 = -maxInt64 - 1
	if (b > 0 && a > maxInt64-b) || (b < 0 && a < minInt64-b) {
		return 0, false
	}
	return a + b, true
}

// resolvePaymentMethod preserves nullable legacy order methods without
// treating an arbitrary paid order as UPI. A verified sandbox capture is the
// only evidence that can infer the UPI source for such an order.
func resolvePaymentMethod(method, paymentStatus string, verifiedSandboxCapture bool) string {
	if method == "" && paymentStatus == "paid" && verifiedSandboxCapture {
		return "upi"
	}
	return method
}

func (s *Service) Accrue(w http.ResponseWriter, r *http.Request, actor string) {
	if !s.qaEnvironment {
		writeError(w, financeError(404, "NOT_FOUND", "Merchant finance simulation is available only in isolated QA."))
		return
	}
	orderID := r.PathValue("orderId")
	if _, err := uuid.Parse(orderID); err != nil {
		writeError(w, financeError(400, "VALIDATION_ERROR", "Order ID must be a UUID."))
		return
	}
	var result map[string]any
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := authorize(r.Context(), tx, actor, "finance.post"); err != nil {
			return err
		}
		if !s.featureEnabled(r.Context(), tx) {
			return financeError(503, "SETTLEMENT_SIMULATION_DISABLED", "Merchant payable simulation is disabled in this environment.")
		}
		var business, vertical, orderStatus, paymentStatus, paymentMethod, currency string
		var created time.Time
		var customerGross int64
		var itemCount, pricedCount int
		err := tx.QueryRowxContext(r.Context(), `SELECT business_id::text,platform_vertical,status,payment_status,COALESCE(payment_method,''),currency,created_at,round(grand_total*100)::bigint FROM customer_orders WHERE id=$1 AND order_source='platform_catalog' FOR UPDATE`, orderID).Scan(&business, &vertical, &orderStatus, &paymentStatus, &paymentMethod, &currency, &created, &customerGross)
		if errors.Is(err, sql.ErrNoRows) {
			return financeError(404, "NOT_FOUND", "Platform order was not found.")
		}
		if err != nil {
			return err
		}
		// Older orders may legitimately have a NULL payment_method. Treat one as
		// sandbox UPI only when authoritative payment records prove a verified
		// sandbox capture; never rewrite the immutable historical order row.
		var verifiedCapture bool
		if paymentMethod == "" {
			if err := tx.GetContext(r.Context(), &verifiedCapture, `SELECT EXISTS(SELECT 1 FROM payment_intents pi JOIN payment_attempts pa ON pa.payment_intent_id=pi.id WHERE pi.order_id=$1 AND pa.provider='grepmind_sandbox' AND pa.status='succeeded')`, orderID); err != nil {
				return err
			}
		}
		paymentMethod = resolvePaymentMethod(paymentMethod, paymentStatus, verifiedCapture)
		if orderStatus != "delivered" || currency != "INR" {
			return financeError(409, "ORDER_NOT_ELIGIBLE", "Only delivered INR platform orders can accrue a payable.")
		}
		if err := tx.QueryRowxContext(r.Context(), `SELECT count(*),count(*) FILTER (WHERE partner_supply_price_minor IS NOT NULL AND partner_supply_currency='INR') FROM platform_customer_order_items WHERE order_id=$1`, orderID).Scan(&itemCount, &pricedCount); err != nil {
			return err
		}
		var partnerGross, retailGross int64
		if err := tx.QueryRowxContext(r.Context(), `SELECT COALESCE(sum(partner_supply_price_minor*quantity),0),COALESCE(sum(unit_price_minor*quantity),0) FROM platform_customer_order_items WHERE order_id=$1`, orderID).Scan(&partnerGross, &retailGross); err != nil {
			return err
		}
		if itemCount == 0 || pricedCount != itemCount || partnerGross <= 0 {
			return financeError(409, "SUPPLY_TERMS_MISSING", "The order has no complete immutable partner supply-price snapshot; no payable was created.")
		}
		if paymentMethod == "upi" {
			if paymentStatus != "paid" {
				return financeError(409, "PAYMENT_NOT_VERIFIED", "A verified sandbox capture is required before payable accrual.")
			}
			var refunds int
			if err := tx.GetContext(r.Context(), &refunds, `SELECT count(*) FROM payment_refunds WHERE order_id=$1 AND status IN ('succeeded','processing','reconciliation_required')`, orderID); err != nil {
				return err
			}
			if refunds > 0 {
				return financeError(409, "REFUND_REVIEW_REQUIRED", "Refund activity requires an approved payable adjustment review before accrual.")
			}
			var attempt bool
			if err := tx.GetContext(r.Context(), &attempt, `SELECT EXISTS(SELECT 1 FROM payment_intents i JOIN payment_attempts a ON a.payment_intent_id=i.id WHERE i.order_id=$1 AND a.provider='grepmind_sandbox' AND a.status='succeeded')`, orderID); err != nil {
				return err
			}
			if !attempt {
				return financeError(409, "PAYMENT_NOT_VERIFIED", "A verified sandbox capture is required before payable accrual.")
			}
		} else if paymentMethod == "cash_on_delivery" {
			var collected bool
			if err := tx.GetContext(r.Context(), &collected, `SELECT EXISTS(SELECT 1 FROM cod_collections WHERE order_id=$1)`, orderID); err != nil {
				return err
			}
			if !collected {
				return financeError(409, "COD_NOT_COLLECTED", "Synthetic COD collection is required before payable accrual.")
			}
		} else {
			return financeError(409, "PAYMENT_SOURCE_UNSUPPORTED", "This order has no supported verified payment source.")
		}
		policyID, version, commissionType, _, rate, _, err := selectPolicy(r.Context(), tx, business, vertical, created)
		if err != nil {
			return err
		}
		// Load the selected policy's correct numeric input while holding its version stable.
		var bps, fixed sql.NullInt64
		if err := tx.QueryRowxContext(r.Context(), `SELECT percentage_bps,fixed_minor FROM merchant_commission_policies WHERE id=$1 AND status='approved' FOR SHARE`, policyID).Scan(&bps, &fixed); err != nil {
			return err
		}
		if commissionType == "percentage_bps" {
			rate = bps.Int64
		} else {
			rate = fixed.Int64
		}
		commission, err := commissionAmount(partnerGross, commissionType, rate)
		if err != nil {
			return err
		}
		net := partnerGross - commission
		paymentSource := "sandbox_upi_capture"
		if paymentMethod == "cash_on_delivery" {
			paymentSource = "synthetic_cod_collection"
		}
		fingerprintInput := map[string]any{"order_id": orderID, "business_id": business, "customer_gross_minor": customerGross, "partner_gross_minor": partnerGross, "commission_basis_minor": partnerGross, "commission_minor": commission, "net_payable_minor": net, "policy_id": policyID, "policy_version": version, "payment_source": paymentSource, "currency": "INR", "calculation_version": 1}
		hash, err := fingerprint(fingerprintInput)
		if err != nil {
			return err
		}
		var existing string
		var savedHash []byte
		err = tx.QueryRowxContext(r.Context(), `SELECT id::text,snapshot_hash FROM merchant_payable_snapshots WHERE order_id=$1 AND source_event='delivered_payment_verified' FOR UPDATE`, orderID).Scan(&existing, &savedHash)
		if err == nil {
			if !strings.EqualFold(hex.EncodeToString(savedHash), hex.EncodeToString(hash)) {
				return financeError(409, "PAYABLE_SNAPSHOT_CONFLICT", "A payable already exists with a different immutable calculation.")
			}
			result = map[string]any{"id": existing, "order_id": orderID, "status": "accrued", "idempotent_replay": true}
			return nil
		} else if !errors.Is(err, sql.ErrNoRows) {
			return err
		}
		var costID, payableID, commissionID string
		if err := tx.QueryRowxContext(r.Context(), `SELECT id::text FROM financial_accounts WHERE account_code='merchant_fulfillment_cost' AND currency='INR' AND is_enabled`).Scan(&costID); err != nil {
			return err
		}
		if err := tx.QueryRowxContext(r.Context(), `SELECT id::text FROM financial_accounts WHERE account_code='merchant_payable_liability' AND currency='INR' AND is_enabled`).Scan(&payableID); err != nil {
			return err
		}
		if err := tx.QueryRowxContext(r.Context(), `SELECT id::text FROM financial_accounts WHERE account_code='platform_commission_clearing' AND currency='INR' AND is_enabled`).Scan(&commissionID); err != nil {
			return err
		}
		lines := []financialledger.Line{{AccountID: costID, Side: "debit", Amount: partnerGross, Memo: "Partner supply entitlement; contract classification pending"}}
		if net > 0 {
			lines = append(lines, financialledger.Line{AccountID: payableID, Side: "credit", Amount: net, Memo: "Merchant payable snapshot"})
		}
		if commission > 0 {
			lines = append(lines, financialledger.Line{AccountID: commissionID, Side: "credit", Amount: commission, Memo: "Commission clearing; revenue classification pending"})
		}
		journal, err := financialledger.PostJournalTx(r.Context(), tx, financialledger.PostInput{Currency: "INR", SourceType: "merchant_payable_accrual", SourceID: orderID, SourceEvent: "delivered_payment_verified", IdempotencyKey: "merchant-payable:" + orderID, Description: "Merchant payable accrual snapshot", ActorUserID: actor, Reason: "Accrue an eligible delivered order using its approved policy snapshot", Lines: lines})
		if err != nil {
			return err
		}
		payableIDOut, err := insertPayableSnapshot(r.Context(), tx, orderID, business, policyID, version, customerGross, partnerGross, commission, net, paymentSource, hash, journal.ID, actor)
		if err != nil {
			return err
		}
		if err := audit(r.Context(), tx, actor, "payable_accrued", business, orderID, payableIDOut, policyID, "", "Verified payment plus delivery; synthetic QA accounting only", fingerprintInput); err != nil {
			return err
		}
		result = map[string]any{"id": payableIDOut, "order_id": orderID, "business_id": business, "customer_gross_minor": customerGross, "partner_gross_minor": partnerGross, "commission_minor": commission, "net_payable_minor": net, "currency": "INR", "policy_id": policyID, "policy_version": version, "payment_source": paymentSource, "funding_status": "separate_verification_required", "financial_journal_id": journal.ID, "idempotent_replay": false}
		return nil
	})
	if err != nil {
		var expected *apiError
		var dbErr *pgconn.PgError
		if !errors.As(err, &expected) {
			if errors.As(err, &dbErr) {
				log.Printf("merchant finance accrual database error: SQLSTATE=%s constraint=%s message=%s", dbErr.Code, dbErr.ConstraintName, dbErr.Message)
			} else {
				log.Printf("merchant finance accrual internal error: %T", err)
			}
		}
		writeError(w, err)
		return
	}
	writeJSON(w, 201, result)
}

func (s *Service) ListPayables(w http.ResponseWriter, r *http.Request, actor string) {
	if !s.qaEnvironment {
		writeError(w, financeError(404, "NOT_FOUND", "Merchant finance simulation is available only in isolated QA."))
		return
	}
	if r.URL.Query().Get("limit") != "" {
		var n int
		if _, err := fmt.Sscan(r.URL.Query().Get("limit"), &n); err != nil || n < 1 || n > 200 {
			writeError(w, financeError(400, "VALIDATION_ERROR", "Limit must be between 1 and 200."))
			return
		}
	}
	limit := 200
	if n := r.URL.Query().Get("limit"); n != "" {
		_, _ = fmt.Sscan(n, &limit)
	}
	var rows []map[string]any
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := authorize(r.Context(), tx, actor, "finance.read"); err != nil {
			return err
		}
		if !s.featureEnabled(r.Context(), tx) {
			return financeError(503, "SETTLEMENT_SIMULATION_DISABLED", "Merchant finance is disabled in this environment.")
		}
		var err error
		rows, err = queryMaps(r.Context(), tx, `SELECT p.id::text,p.order_id::text,o.reference_code,p.business_id::text,b.name merchant_name,p.policy_id::text,p.policy_version,p.currency,p.customer_gross_minor,p.partner_gross_minor,p.commission_minor,p.net_payable_minor,p.payment_source,p.funding_state,p.financial_journal_id::text,p.created_at::text,COALESCE((SELECT sum(CASE WHEN a.adjustment_type='credit' THEN a.amount_minor ELSE -a.amount_minor END) FROM merchant_payable_adjustments a WHERE a.payable_id=p.id AND a.status='approved'),0) adjustment_minor,CASE WHEN EXISTS(SELECT 1 FROM merchant_settlement_batch_items bi JOIN merchant_settlement_batches sb ON sb.id=bi.batch_id WHERE bi.payable_id=p.id AND sb.status IN ('approved','simulated','reconciled')) THEN 'allocated' ELSE 'unallocated' END allocation_state FROM merchant_payable_snapshots p JOIN customer_orders o ON o.id=p.order_id JOIN businesses b ON b.id=p.business_id WHERE ($1='' OR p.business_id::text=$1) AND ($2='' OR p.currency=$2) ORDER BY p.created_at DESC LIMIT $3`, r.URL.Query().Get("business_id"), r.URL.Query().Get("currency"), limit)
		return err
	})
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, 200, rows)
}

func (s *Service) ListEligibleOrders(w http.ResponseWriter, r *http.Request, actor string) {
	if !s.qaEnvironment {
		writeError(w, financeError(404, "NOT_FOUND", "Merchant finance simulation is available only in isolated QA."))
		return
	}
	var rows []map[string]any
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := authorize(r.Context(), tx, actor, "finance.read"); err != nil {
			return err
		}
		if !s.featureEnabled(r.Context(), tx) {
			return financeError(503, "SETTLEMENT_SIMULATION_DISABLED", "Merchant payable simulation is disabled in this environment.")
		}
		var err error
		rows, err = queryMaps(r.Context(), tx, `SELECT o.id::text order_id,o.reference_code,o.business_id::text,b.name merchant_name,o.platform_vertical,CASE WHEN o.payment_method IS NULL AND o.payment_status='paid' AND EXISTS(SELECT 1 FROM payment_intents pi JOIN payment_attempts pa ON pa.payment_intent_id=pi.id WHERE pi.order_id=o.id AND pa.provider='grepmind_sandbox' AND pa.status='succeeded') THEN 'upi' ELSE o.payment_method END payment_method,o.payment_status,o.status,round(o.grand_total*100)::bigint customer_gross_minor,o.created_at::text,COALESCE(sum(i.partner_supply_price_minor*i.quantity),0)::bigint partner_supply_minor,count(i.variant_id)::int item_count,count(i.variant_id) FILTER(WHERE i.partner_supply_price_minor IS NOT NULL AND i.partner_supply_currency='INR')::int priced_item_count FROM customer_orders o JOIN businesses b ON b.id=o.business_id JOIN platform_customer_order_items i ON i.order_id=o.id WHERE o.order_source='platform_catalog' AND o.status='delivered' AND ((((o.payment_method='upi' OR o.payment_method IS NULL) AND o.payment_status='paid') AND EXISTS(SELECT 1 FROM payment_intents pi JOIN payment_attempts pa ON pa.payment_intent_id=pi.id WHERE pi.order_id=o.id AND pa.provider='grepmind_sandbox' AND pa.status='succeeded')) OR (o.payment_method='cash_on_delivery' AND EXISTS(SELECT 1 FROM cod_collections c WHERE c.order_id=o.id))) AND NOT EXISTS(SELECT 1 FROM merchant_payable_snapshots p WHERE p.order_id=o.id) GROUP BY o.id,b.name ORDER BY o.created_at DESC LIMIT 200`)
		return err
	})
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, 200, rows)
}

func (s *Service) MerchantOverview(w http.ResponseWriter, r *http.Request, actor, business string) {
	if !s.qaEnvironment {
		writeError(w, financeError(404, "NOT_FOUND", "Merchant finance simulation is available only in isolated QA."))
		return
	}
	var result map[string]any
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var allowed bool
		if err := tx.GetContext(r.Context(), &allowed, `SELECT EXISTS(SELECT 1 FROM businesses b WHERE b.id=$1 AND b.owner_user_id=$2) OR EXISTS(SELECT 1 FROM business_members m WHERE m.business_id=$1 AND m.user_id=$2 AND m.status='active' AND m.role IN ('owner','manager'))`, business, actor); err != nil {
			return err
		}
		if !allowed {
			return financeError(404, "NOT_FOUND", "Merchant finance view was not found for this business.")
		}
		var enabled bool
		if err := tx.GetContext(r.Context(), &enabled, `SELECT financial_posting_enabled AND sandbox_merchant_settlement_enabled AND NOT merchant_settlement_enabled AND NOT real_money_enabled FROM financial_feature_config WHERE singleton=true`); err != nil {
			return err
		}
		if !enabled {
			return financeError(503, "FINANCE_UNAVAILABLE", "Merchant finance is not enabled in this environment.")
		}
		result = map[string]any{}
		var currency string
		var customerGross, partnerGross, commission, netPayable, adjustments, pending, simulatedSettlement int64
		if err := tx.QueryRowxContext(r.Context(), `SELECT 'INR' currency,COALESCE(sum(customer_gross_minor),0)::bigint customer_gross_minor,COALESCE(sum(partner_gross_minor),0)::bigint partner_gross_minor,COALESCE(sum(commission_minor),0)::bigint commission_minor,COALESCE(sum(net_payable_minor),0)::bigint net_payable_minor,COALESCE(sum((SELECT COALESCE(sum(CASE WHEN a.adjustment_type='credit' THEN a.amount_minor ELSE -a.amount_minor END),0) FROM merchant_payable_adjustments a WHERE a.payable_id=p.id AND a.status='approved')),0)::bigint approved_adjustments_minor,COALESCE(sum(CASE WHEN NOT EXISTS(SELECT 1 FROM merchant_settlement_batch_items bi JOIN merchant_settlement_batches sb ON sb.id=bi.batch_id WHERE bi.payable_id=p.id AND sb.status IN ('approved','simulated','reconciled')) THEN p.net_payable_minor+COALESCE((SELECT sum(CASE WHEN a.adjustment_type='credit' THEN a.amount_minor ELSE -a.amount_minor END) FROM merchant_payable_adjustments a WHERE a.payable_id=p.id AND a.status='approved'),0) ELSE 0 END),0)::bigint pending_payable_minor FROM merchant_payable_snapshots p WHERE business_id=$1`, business).Scan(&currency, &customerGross, &partnerGross, &commission, &netPayable, &adjustments, &pending); err != nil {
			return err
		}
		result["currency"] = currency
		result["customer_gross_minor"] = customerGross
		result["partner_gross_minor"] = partnerGross
		result["commission_minor"] = commission
		result["net_payable_minor"] = netPayable
		result["approved_adjustments_minor"] = adjustments
		result["pending_payable_minor"] = pending
		if err := tx.GetContext(r.Context(), &simulatedSettlement, merchantSimulatedSettlementTotalQuery, business); err != nil {
			return err
		}
		result["simulated_settlement_minor"] = simulatedSettlement
		result["settlement_mode"] = "simulated_only"
		result["real_payouts_enabled"] = false
		return nil
	})
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, 200, result)
}

func (s *Service) MerchantPayables(w http.ResponseWriter, r *http.Request, actor, business string) {
	if !s.qaEnvironment {
		writeError(w, financeError(404, "NOT_FOUND", "Merchant finance simulation is available only in isolated QA."))
		return
	}
	var rows []map[string]any
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var allowed bool
		if err := tx.GetContext(r.Context(), &allowed, `SELECT EXISTS(SELECT 1 FROM businesses b WHERE b.id=$1 AND b.owner_user_id=$2) OR EXISTS(SELECT 1 FROM business_members m WHERE m.business_id=$1 AND m.user_id=$2 AND m.status='active' AND m.role IN ('owner','manager'))`, business, actor); err != nil {
			return err
		}
		if !allowed {
			return financeError(404, "NOT_FOUND", "Merchant finance view was not found for this business.")
		}
		var err error
		rows, err = queryMaps(r.Context(), tx, `SELECT p.id::text,p.order_id::text,o.reference_code,p.currency,p.customer_gross_minor,p.partner_gross_minor,p.commission_minor,p.net_payable_minor,p.payment_source,p.policy_version,p.created_at::text,COALESCE((SELECT sum(CASE WHEN a.adjustment_type='credit' THEN a.amount_minor ELSE -a.amount_minor END) FROM merchant_payable_adjustments a WHERE a.payable_id=p.id AND a.status='approved'),0) adjustment_minor,CASE WHEN EXISTS(SELECT 1 FROM merchant_settlement_batch_items bi JOIN merchant_settlement_batches sb ON sb.id=bi.batch_id WHERE bi.payable_id=p.id AND sb.status IN ('approved','simulated','reconciled')) THEN 'allocated' ELSE 'pending' END state FROM merchant_payable_snapshots p JOIN customer_orders o ON o.id=p.order_id WHERE p.business_id=$1 ORDER BY p.created_at DESC LIMIT 200`, business)
		return err
	})
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, 200, rows)
}

func (s *Service) MerchantSettlements(w http.ResponseWriter, r *http.Request, actor, business string) {
	if !s.qaEnvironment {
		writeError(w, financeError(404, "NOT_FOUND", "Merchant finance simulation is available only in isolated QA."))
		return
	}
	var rows []map[string]any
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var allowed bool
		if err := tx.GetContext(r.Context(), &allowed, `SELECT EXISTS(SELECT 1 FROM businesses b WHERE b.id=$1 AND b.owner_user_id=$2) OR EXISTS(SELECT 1 FROM business_members m WHERE m.business_id=$1 AND m.user_id=$2 AND m.status='active' AND m.role IN ('owner','manager'))`, business, actor); err != nil {
			return err
		}
		if !allowed {
			return financeError(404, "NOT_FOUND", "Merchant finance view was not found for this business.")
		}
		var err error
		rows, err = queryMaps(r.Context(), tx, `SELECT id::text,currency,period_start::text,period_end::text,payable_minor,adjustment_minor,simulated_net_minor,status,funding_mode,created_at::text,simulated_at::text,'SIMULATED ONLY — NOT A REAL PAYOUT'::text disclosure FROM merchant_settlement_batches WHERE business_id=$1 ORDER BY created_at DESC LIMIT 100`, business)
		return err
	})
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, 200, rows)
}

func (s *Service) CreateQAFundingPool(w http.ResponseWriter, r *http.Request, actor string, environment string) {
	var in struct {
		OrderID          string `json:"order_id"`
		AmountMinor      int64  `json:"amount_minor"`
		FundingReference string `json:"funding_reference"`
		Reason           string `json:"reason"`
	}
	if err := decode(w, r, &in); err != nil {
		writeError(w, err)
		return
	}
	if _, err := uuid.Parse(in.OrderID); err != nil || in.AmountMinor <= 0 || len(strings.TrimSpace(in.FundingReference)) < 8 || len(in.FundingReference) > 120 || len(strings.TrimSpace(in.Reason)) < 10 {
		writeError(w, financeError(400, "VALIDATION_ERROR", "QA pool requires order, positive paise amount, reference and reason."))
		return
	}
	if environment != "qa" && environment != "test" {
		writeError(w, financeError(403, "QA_ONLY", "Synthetic funding pools are available only in isolated QA/test environments."))
		return
	}
	var id, business string
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := authorize(r.Context(), tx, actor, "finance.post"); err != nil {
			return err
		}
		if !s.featureEnabled(r.Context(), tx) {
			return financeError(503, "SETTLEMENT_SIMULATION_DISABLED", "Settlement simulation is disabled in this environment.")
		}
		var method, status string
		var paymentStatus string
		if err := tx.QueryRowxContext(r.Context(), `SELECT business_id::text,COALESCE(payment_method,''),status,payment_status FROM customer_orders WHERE id=$1 AND order_source='platform_catalog' FOR UPDATE`, in.OrderID).Scan(&business, &method, &status, &paymentStatus); errors.Is(err, sql.ErrNoRows) {
			return financeError(404, "NOT_FOUND", "Platform order was not found.")
		} else if err != nil {
			return err
		}
		var verifiedCapture bool
		if method == "" {
			if err := tx.GetContext(r.Context(), &verifiedCapture, `SELECT EXISTS(SELECT 1 FROM payment_intents pi JOIN payment_attempts pa ON pa.payment_intent_id=pi.id WHERE pi.order_id=$1 AND pa.provider='grepmind_sandbox' AND pa.status='succeeded')`, in.OrderID); err != nil {
				return err
			}
		}
		method = resolvePaymentMethod(method, paymentStatus, verifiedCapture)
		if method != "upi" || paymentStatus != "paid" {
			return financeError(409, "PAYMENT_NOT_VERIFIED", "A synthetic QA pool can fund only a sandbox UPI order with verified capture.")
		}
		var captured int64
		if err := tx.GetContext(r.Context(), &captured, `SELECT COALESCE(sum(a.amount_minor),0)-COALESCE((SELECT sum(f.amount_minor) FROM payment_refunds f WHERE f.order_id=$1 AND f.status='succeeded'),0) FROM payment_intents i JOIN payment_attempts a ON a.payment_intent_id=i.id AND a.status='succeeded' WHERE i.order_id=$1`, in.OrderID); err != nil {
			return err
		}
		if in.AmountMinor > captured {
			return financeError(409, "FUNDING_EXCEEDS_CAPTURE", "Synthetic pool amount cannot exceed the verified sandbox capture net of refunds.")
		}
		err := tx.QueryRowxContext(r.Context(), `INSERT INTO merchant_settlement_qa_funding_pools(order_id,business_id,amount_minor,currency,funding_reference,created_by,reason) VALUES($1,$2,$3,'INR',$4,$5,$6) RETURNING id::text`, in.OrderID, business, in.AmountMinor, strings.TrimSpace(in.FundingReference), actor, strings.TrimSpace(in.Reason)).Scan(&id)
		if err != nil {
			return err
		}
		return audit(r.Context(), tx, actor, "qa_funding_pool_created", business, in.OrderID, "", "", "", in.Reason, map[string]any{"pool_id": id, "amount_minor": in.AmountMinor, "source": "synthetic_qa_pool"})
	})
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, 201, map[string]any{"id": id, "business_id": business, "amount_minor": in.AmountMinor, "currency": "INR", "funding_type": "synthetic_qa_pool", "disclosure": "Synthetic QA value only; not bank or provider-settled funds."})
}

type createBatchInput struct {
	PayableIDs     []string `json:"payable_ids"`
	PeriodStart    string   `json:"period_start"`
	PeriodEnd      string   `json:"period_end"`
	IdempotencyKey string   `json:"idempotency_key"`
}

func (s *Service) CreateSettlement(w http.ResponseWriter, r *http.Request, actor string) {
	if !s.qaEnvironment {
		writeError(w, financeError(404, "NOT_FOUND", "Merchant finance simulation is available only in isolated QA."))
		return
	}
	var in createBatchInput
	if err := decode(w, r, &in); err != nil {
		writeError(w, err)
		return
	}
	if len(in.PayableIDs) == 0 || len(in.PayableIDs) > 100 {
		writeError(w, financeError(400, "VALIDATION_ERROR", "Select between 1 and 100 payable records."))
		return
	}
	start, e1 := time.Parse("2006-01-02", in.PeriodStart)
	end, e2 := time.Parse("2006-01-02", in.PeriodEnd)
	key, e3 := uuid.Parse(in.IdempotencyKey)
	if e1 != nil || e2 != nil || e3 != nil || end.Before(start) {
		writeError(w, financeError(400, "VALIDATION_ERROR", "Provide a valid period and UUID idempotency key."))
		return
	}
	seen := map[string]bool{}
	for _, id := range in.PayableIDs {
		if _, err := uuid.Parse(id); err != nil || seen[id] {
			writeError(w, financeError(400, "VALIDATION_ERROR", "Payable IDs must be unique UUIDs."))
			return
		}
		seen[id] = true
	}
	fp, _ := fingerprint(in)
	var id string
	var replay bool
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := authorize(r.Context(), tx, actor, "finance.post"); err != nil {
			return err
		}
		if !s.featureEnabled(r.Context(), tx) {
			return financeError(503, "SETTLEMENT_SIMULATION_DISABLED", "Settlement simulation is disabled in this environment.")
		}
		var existing string
		var saved []byte
		err := tx.QueryRowxContext(r.Context(), `SELECT id::text,request_fingerprint FROM merchant_settlement_batches WHERE created_by=$1 AND idempotency_key=$2 FOR UPDATE`, actor, key.String()).Scan(&existing, &saved)
		if err == nil {
			if !equalHash(saved, fp) {
				return financeError(409, "IDEMPOTENCY_CONFLICT", "Idempotency key was reused with a different settlement request.")
			}
			id = existing
			replay = true
			return nil
		} else if !errors.Is(err, sql.ErrNoRows) {
			return err
		}
		var business string
		var total, payableTotal, adjustmentTotal int64
		var fundingModes = map[string]bool{}
		for _, pid := range in.PayableIDs {
			var b, order, paymentSource string
			var amount int64
			var created time.Time
			var adjustment int64
			var allocated bool
			if err := tx.QueryRowxContext(r.Context(), `SELECT p.business_id::text,p.order_id::text,p.net_payable_minor,p.payment_source,p.created_at,COALESCE((SELECT sum(CASE WHEN a.adjustment_type='credit' THEN a.amount_minor ELSE -a.amount_minor END) FROM merchant_payable_adjustments a WHERE a.payable_id=p.id AND a.status='approved'),0),EXISTS(SELECT 1 FROM merchant_settlement_batch_items bi WHERE bi.payable_id=p.id) FROM merchant_payable_snapshots p WHERE p.id=$1 FOR UPDATE`, pid).Scan(&b, &order, &amount, &paymentSource, &created, &adjustment, &allocated); errors.Is(err, sql.ErrNoRows) {
				return financeError(404, "PAYABLE_NOT_FOUND", "A selected payable was not found.")
			} else if err != nil {
				return err
			}
			if allocated {
				return financeError(409, "PAYABLE_ALREADY_ALLOCATED", "A selected payable is already assigned to a settlement batch.")
			}
			if created.Before(start) || created.After(end.Add(24*time.Hour-time.Nanosecond)) {
				return financeError(409, "PAYABLE_OUTSIDE_PERIOD", "A selected payable falls outside the requested settlement period.")
			}
			if business == "" {
				business = b
			} else if business != b {
				return financeError(409, "MULTI_MERCHANT_BATCH", "A settlement batch must contain one merchant only.")
			}
			available, ok := checkedAddInt64(amount, adjustment)
			if !ok {
				return financeError(409, "AMOUNT_OVERFLOW", "Payable adjustment total exceeds the supported range.")
			}
			if available <= 0 {
				return financeError(409, "PAYABLE_NOT_POSITIVE", "A non-positive payable cannot be simulated for settlement.")
			}
			if paymentSource == "sandbox_upi_capture" {
				var pool bool
				if err := tx.GetContext(r.Context(), &pool, `SELECT EXISTS(SELECT 1 FROM merchant_settlement_qa_funding_pools q WHERE q.order_id=$1 AND q.amount_minor-(SELECT COALESCE(sum(a.amount_minor),0) FROM merchant_settlement_funding_allocations a WHERE a.funding_type='synthetic_qa_pool' AND a.funding_source_id=q.id)>= $2)`, order, available); err != nil {
					return err
				}
				if !pool {
					return financeError(409, "FUNDS_UNAVAILABLE", "Verified sandbox capture is not provider settlement. An explicit synthetic QA pool is required for simulation.")
				}
				fundingModes["synthetic_qa_pool"] = true
			} else {
				var rider string
				var collection bool
				if err := tx.QueryRowxContext(r.Context(), `SELECT rider_user_id::text FROM cod_collections WHERE order_id=$1`, order).Scan(&rider); errors.Is(err, sql.ErrNoRows) {
					return financeError(409, "COD_REMITTANCE_REQUIRED", "A COD payable requires recorded collection and finance-verified remittance.")
				} else if err != nil {
					return err
				}
				if err := tx.GetContext(r.Context(), &collection, `SELECT EXISTS(SELECT 1 FROM cod_remittances r WHERE r.rider_user_id=$1 AND r.state='verified' AND r.amount_minor-(SELECT COALESCE(sum(a.amount_minor),0) FROM merchant_settlement_funding_allocations a WHERE a.funding_type='verified_cod_remittance' AND a.funding_source_id=r.id)>=$2)`, rider, available); err != nil {
					return err
				}
				if !collection {
					return financeError(409, "COD_REMITTANCE_REQUIRED", "No unallocated finance-verified remittance covers this COD payable.")
				}
				fundingModes["verified_cod_remittance"] = true
			}
			var sumOK bool
			total, sumOK = checkedAddInt64(total, available)
			if !sumOK {
				return financeError(409, "AMOUNT_OVERFLOW", "Settlement amount exceeds the supported range.")
			}
			payableTotal, sumOK = checkedAddInt64(payableTotal, amount)
			if !sumOK {
				return financeError(409, "AMOUNT_OVERFLOW", "Payable total exceeds the supported range.")
			}
			adjustmentTotal, sumOK = checkedAddInt64(adjustmentTotal, adjustment)
			if !sumOK {
				return financeError(409, "AMOUNT_OVERFLOW", "Adjustment total exceeds the supported range.")
			}
		}
		if len(fundingModes) != 1 {
			return financeError(409, "MIXED_FUNDING_BATCH", "Do not mix synthetic UPI pools and COD remittance funding in one settlement batch.")
		}
		var mode string
		for m := range fundingModes {
			mode = m
		}
		if err := tx.QueryRowxContext(r.Context(), `INSERT INTO merchant_settlement_batches(business_id,currency,period_start,period_end,payable_minor,adjustment_minor,simulated_net_minor,funding_mode,idempotency_key,request_fingerprint,created_by) VALUES($1,'INR',$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING id::text`, business, start, end, payableTotal, adjustmentTotal, total, mode, key.String(), fp, actor).Scan(&id); err != nil {
			return err
		}
		for _, pid := range in.PayableIDs {
			var amount int64
			if err := tx.GetContext(r.Context(), &amount, `SELECT p.net_payable_minor+COALESCE((SELECT sum(CASE WHEN a.adjustment_type='credit' THEN a.amount_minor ELSE -a.amount_minor END) FROM merchant_payable_adjustments a WHERE a.payable_id=p.id AND a.status='approved'),0) FROM merchant_payable_snapshots p WHERE p.id=$1`, pid); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `INSERT INTO merchant_settlement_batch_items(batch_id,payable_id,business_id,amount_minor,currency) VALUES($1,$2,$3,$4,'INR')`, id, pid, business, amount); err != nil {
				return err
			}
		}
		if _, err := tx.ExecContext(r.Context(), insertSettlementCreatedEventQuery, id, actor, total, mode); err != nil {
			return err
		}
		return audit(r.Context(), tx, actor, "settlement_batch_created", business, "", "", "", id, "Prepare synthetic settlement draft", map[string]any{"amount_minor": total, "funding_mode": mode})
	})
	if err != nil {
		var dbErr *pgconn.PgError
		if errors.As(err, &dbErr) {
			log.Printf("merchant finance settlement create database error: SQLSTATE=%s constraint=%s message=%s", dbErr.Code, dbErr.ConstraintName, dbErr.Message)
		} else {
			log.Printf("merchant finance settlement create internal error: %T", err)
		}
		writeError(w, err)
		return
	}
	writeJSON(w, 201, map[string]any{"id": id, "status": "draft", "idempotent_replay": replay, "disclosure": "Simulation only; not a real merchant payout."})
}

func (s *Service) ListSettlements(w http.ResponseWriter, r *http.Request, actor string) {
	if !s.qaEnvironment {
		writeError(w, financeError(404, "NOT_FOUND", "Merchant finance simulation is available only in isolated QA."))
		return
	}
	var rows []map[string]any
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := authorize(r.Context(), tx, actor, "finance.read"); err != nil {
			return err
		}
		var e error
		rows, e = queryMaps(r.Context(), tx, `SELECT b.id::text,b.business_id::text,m.name merchant_name,b.currency,b.period_start::text,b.period_end::text,b.payable_minor,b.adjustment_minor,b.simulated_net_minor,b.funding_mode,b.status,b.created_by::text,b.reviewed_by::text,b.approved_by::text,b.simulated_by::text,b.created_at::text,b.simulated_at::text,'SIMULATED ONLY — NOT A REAL PAYOUT'::text disclosure FROM merchant_settlement_batches b JOIN businesses m ON m.id=b.business_id ORDER BY b.created_at DESC LIMIT 200`)
		return e
	})
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, 200, rows)
}

func (s *Service) TransitionSettlement(w http.ResponseWriter, r *http.Request, actor, action string) {
	if !s.qaEnvironment {
		writeError(w, financeError(404, "NOT_FOUND", "Merchant finance simulation is available only in isolated QA."))
		return
	}
	var in struct {
		Reason string `json:"reason"`
	}
	if err := decode(w, r, &in); err != nil {
		writeError(w, err)
		return
	}
	if len(strings.TrimSpace(in.Reason)) < 5 || len(in.Reason) > 500 {
		writeError(w, financeError(400, "VALIDATION_ERROR", "A finance reason is required."))
		return
	}
	id := r.PathValue("batchId")
	if _, err := uuid.Parse(id); err != nil {
		writeError(w, financeError(400, "VALIDATION_ERROR", "Batch ID must be a UUID."))
		return
	}
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := authorize(r.Context(), tx, actor, "finance.post"); err != nil {
			return err
		}
		if !s.featureEnabled(r.Context(), tx) {
			return financeError(503, "SETTLEMENT_SIMULATION_DISABLED", "Settlement simulation is disabled in this environment.")
		}
		var business, mode, status, createdBy string
		var amount int64
		if err := tx.QueryRowxContext(r.Context(), `SELECT business_id::text,funding_mode,status,created_by::text,simulated_net_minor FROM merchant_settlement_batches WHERE id=$1 FOR UPDATE`, id).Scan(&business, &mode, &status, &createdBy, &amount); errors.Is(err, sql.ErrNoRows) {
			return financeError(404, "NOT_FOUND", "Settlement batch was not found.")
		} else if err != nil {
			return err
		}
		next := ""
		if action == "review" && status == "draft" {
			next = "reviewed"
		} else if action == "approve" && status == "reviewed" {
			next = "approved"
		} else if action == "simulate" && status == "approved" {
			next = "simulated"
		} else if action == "reconcile" && status == "simulated" {
			next = "reconciled"
		} else {
			return financeError(409, "INVALID_STATE", "This settlement transition is not available from the current state.")
		}
		var previousActor string
		column := map[string]string{"review": "created_by", "approve": "reviewed_by", "simulate": "approved_by", "reconcile": "simulated_by"}[action]
		if column != "" {
			if err := tx.GetContext(r.Context(), &previousActor, `SELECT `+column+`::text FROM merchant_settlement_batches WHERE id=$1`, id); err != nil {
				return err
			}
			if previousActor == actor {
				return financeError(403, "SEPARATION_OF_DUTIES", "Settlement preparation, review, approval and simulation require separate finance principals.")
			}
		}
		if action == "approve" {
			// Allocate funding while holding the batch and each funding source lock.
			items, err := queryMaps(r.Context(), tx, `SELECT bi.payable_id::text,bi.amount_minor,p.order_id::text,p.payment_source FROM merchant_settlement_batch_items bi JOIN merchant_payable_snapshots p ON p.id=bi.payable_id WHERE bi.batch_id=$1 ORDER BY bi.payable_id FOR UPDATE OF bi,p`, id)
			if err != nil {
				return err
			}
			for _, item := range items {
				pid := fmt.Sprint(item["payable_id"])
				order := fmt.Sprint(item["order_id"])
				needed := toInt64(item["amount_minor"])
				if mode == "synthetic_qa_pool" {
					var poolID string
					var poolAmount int64
					err := tx.QueryRowxContext(r.Context(), `SELECT q.id::text,q.amount_minor-(SELECT COALESCE(sum(a.amount_minor),0) FROM merchant_settlement_funding_allocations a WHERE a.funding_type='synthetic_qa_pool' AND a.funding_source_id=q.id) FROM merchant_settlement_qa_funding_pools q JOIN payment_intents i ON i.order_id=q.order_id JOIN payment_attempts pa ON pa.payment_intent_id=i.id AND pa.status='succeeded' WHERE q.order_id=$1 AND q.business_id=$2 AND q.amount_minor-(SELECT COALESCE(sum(a.amount_minor),0) FROM merchant_settlement_funding_allocations a WHERE a.funding_type='synthetic_qa_pool' AND a.funding_source_id=q.id)>=$3 ORDER BY q.created_at LIMIT 1 FOR UPDATE OF q`, order, business, needed).Scan(&poolID, &poolAmount)
					if errors.Is(err, sql.ErrNoRows) || poolAmount < needed {
						return financeError(409, "FUNDS_UNAVAILABLE", "Synthetic QA pool is missing or insufficient.")
					}
					if err != nil {
						return err
					}
					if _, err := tx.ExecContext(r.Context(), `INSERT INTO merchant_settlement_funding_allocations(batch_id,funding_type,funding_source_id,amount_minor,currency) VALUES($1,'synthetic_qa_pool',$2,$3,'INR')`, id, poolID, needed); err != nil {
						return err
					}
				} else {
					var rider string
					if err := tx.QueryRowxContext(r.Context(), `SELECT rider_user_id::text FROM cod_collections WHERE order_id=$1`, order).Scan(&rider); err != nil {
						return financeError(409, "COD_REMITTANCE_REQUIRED", "COD collection record is missing.")
					}
					var remittanceID string
					var available int64
					err := tx.QueryRowxContext(r.Context(), `SELECT r.id::text,r.amount_minor-(SELECT COALESCE(sum(a.amount_minor),0) FROM merchant_settlement_funding_allocations a WHERE a.funding_type='verified_cod_remittance' AND a.funding_source_id=r.id) FROM cod_remittances r WHERE r.rider_user_id=$1 AND r.state='verified' AND r.amount_minor-(SELECT COALESCE(sum(a.amount_minor),0) FROM merchant_settlement_funding_allocations a WHERE a.funding_type='verified_cod_remittance' AND a.funding_source_id=r.id)>=$2 ORDER BY r.reviewed_at LIMIT 1 FOR UPDATE OF r`, rider, needed).Scan(&remittanceID, &available)
					if errors.Is(err, sql.ErrNoRows) || available < needed {
						return financeError(409, "COD_REMITTANCE_REQUIRED", "Verified rider remittance does not cover this payable.")
					}
					if err != nil {
						return err
					}
					if _, err := tx.ExecContext(r.Context(), `INSERT INTO merchant_settlement_funding_allocations(batch_id,funding_type,funding_source_id,amount_minor,currency) VALUES($1,'verified_cod_remittance',$2,$3,'INR')`, id, remittanceID, needed); err != nil {
						return err
					}
				}
				_ = pid
			}
		}
		var journalID any
		if action == "simulate" {
			var payableID, settlementID string
			if err := tx.QueryRowxContext(r.Context(), `SELECT id::text FROM financial_accounts WHERE account_code='merchant_payable_liability' AND currency='INR'`).Scan(&payableID); err != nil {
				return err
			}
			if err := tx.QueryRowxContext(r.Context(), `SELECT id::text FROM financial_accounts WHERE account_code='simulated_merchant_settlement_clearing' AND currency='INR'`).Scan(&settlementID); err != nil {
				return err
			}
			j, err := financialledger.PostJournalTx(r.Context(), tx, financialledger.PostInput{Currency: "INR", SourceType: "merchant_settlement_simulation", SourceID: id, SourceEvent: "simulated", IdempotencyKey: "merchant-settlement-sim:" + id, Description: "Synthetic merchant settlement simulation; no transfer occurred", ActorUserID: actor, Reason: strings.TrimSpace(in.Reason), Lines: []financialledger.Line{{AccountID: payableID, Side: "debit", Amount: amount, Memo: "Move payable into simulated clearing only"}, {AccountID: settlementID, Side: "credit", Amount: amount, Memo: "Not a bank transfer or payout"}}})
			if err != nil {
				return err
			}
			journalID = j.ID
		}
		updates, ok := settlementTransitionUpdate(action)
		if !ok {
			return financeError(400, "VALIDATION_ERROR", "Unsupported settlement transition.")
		}
		var err error
		_, err = tx.ExecContext(r.Context(), `UPDATE merchant_settlement_batches SET status=$2,`+updates+` WHERE id=$1`, settlementTransitionArgs(action, id, next, actor, strings.TrimSpace(in.Reason), journalID)...)
		if err != nil {
			return err
		}
		if action == "reconcile" {
			issues, err := reconcileBatch(r.Context(), tx, id)
			if err != nil {
				return err
			}
			if len(issues) > 0 {
				return financeError(409, "RECONCILIATION_EXCEPTION", "Settlement simulation has reconciliation exceptions and cannot be marked reconciled.")
			}
		}
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO merchant_settlement_events(batch_id,actor_user_id,event_type,reason,financial_journal_id,metadata) VALUES($1,$2,$3,$4,$5::uuid,jsonb_build_object('amount_minor',$6::bigint,'disclosure','simulation_only'))`, id, actor, map[string]string{"review": "reviewed", "approve": "approved", "simulate": "simulated", "reconcile": "reconciled"}[action], strings.TrimSpace(in.Reason), journalID, amount); err != nil {
			return err
		}
		auditEvent := map[string]string{"review": "settlement_batch_reviewed", "approve": "settlement_batch_approved", "simulate": "settlement_batch_simulated", "reconcile": "settlement_batch_reconciled"}[action]
		return audit(r.Context(), tx, actor, auditEvent, business, "", "", "", id, in.Reason, map[string]any{"status": next, "amount_minor": amount, "journal_id": journalID, "real_transfer": false})
	})
	if err != nil {
		var apiErr *apiError
		if !errors.As(err, &apiErr) {
			var dbErr *pgconn.PgError
			if errors.As(err, &dbErr) {
				log.Printf("merchant finance settlement transition database error: action=%s SQLSTATE=%s constraint=%s", action, dbErr.Code, dbErr.ConstraintName)
			} else {
				log.Printf("merchant finance settlement transition internal error: action=%s type=%T", action, err)
			}
		}
		writeError(w, err)
		return
	}
	writeJSON(w, 200, map[string]any{"id": id, "status": map[string]string{"review": "reviewed", "approve": "approved", "simulate": "simulated_only", "reconcile": "reconciled"}[action], "real_transfer": false})
}

// settlementTransitionUpdate reserves $1 for the batch ID and $2 for its next
// state. Actor and reason parameters start at $3 so their PostgreSQL types do
// not conflict with the status parameter.
func settlementTransitionUpdate(action string) (string, bool) {
	updates, ok := map[string]string{
		"review":    "reviewed_by=$3,reviewed_at=now(),review_reason=$4",
		"approve":   "approved_by=$3,approved_at=now(),approval_reason=$4",
		"simulate":  "simulated_by=$3,simulated_at=now(),simulation_reason=$4,financial_journal_id=$5",
		"reconcile": "reconciled_at=now()",
	}[action]
	return updates, ok
}

// settlementTransitionArgs keeps the argument count aligned with each SQL
// transition. Reconciliation updates only status and reconciled_at; passing
// actor/reason values to its two-placeholder statement causes PostgreSQL to
// reject the transition. The actor and reason are still persisted in the
// immutable event and audit records below.
func settlementTransitionArgs(action, id, next, actor, reason string, journalID any) []any {
	switch action {
	case "review", "approve":
		return []any{id, next, actor, reason}
	case "simulate":
		return []any{id, next, actor, reason, journalID}
	case "reconcile":
		return []any{id, next}
	default:
		return nil
	}
}

func (s *Service) Reconcile(w http.ResponseWriter, r *http.Request, actor string) {
	if !s.qaEnvironment {
		writeError(w, financeError(404, "NOT_FOUND", "Merchant finance simulation is available only in isolated QA."))
		return
	}
	var rows []map[string]any
	run := uuid.NewString()
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := authorize(r.Context(), tx, actor, "finance.read"); err != nil {
			return err
		}
		var err error
		rows, err = reconcileAll(r.Context(), tx)
		if err != nil {
			return err
		}
		for _, row := range rows {
			order := nullableDBText(row["order_id"])
			payable := nullableDBText(row["payable_id"])
			batch := nullableDBText(row["batch_id"])
			business := nullableDBText(row["business_id"])
			_, err = tx.ExecContext(r.Context(), `INSERT INTO merchant_reconciliation_exceptions(run_key,issue_code,business_id,order_id,payable_id,batch_id,details) VALUES($1,$2,NULLIF($3,'')::uuid,NULLIF($4,'')::uuid,NULLIF($5,'')::uuid,NULLIF($6,'')::uuid,$7) ON CONFLICT DO NOTHING`, run, row["issue"], business, order, payable, batch, row["details"])
			if err != nil {
				return err
			}
		}
		return audit(r.Context(), tx, actor, "reconciliation_run", "", "", "", "", "", "Read-only merchant financial reconciliation; no automatic repair", map[string]any{"run_id": run, "issue_count": len(rows)})
	})
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, 200, map[string]any{"run_id": run, "exceptions": rows, "exception_count": len(rows), "automatic_repairs": false})
}
func (s *Service) ListReconciliationExceptions(w http.ResponseWriter, r *http.Request, actor string) {
	if !s.qaEnvironment {
		writeError(w, financeError(404, "NOT_FOUND", "Merchant finance simulation is available only in isolated QA."))
		return
	}
	var rows []map[string]any
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := authorize(r.Context(), tx, actor, "finance.read"); err != nil {
			return err
		}
		var e error
		rows, e = queryMaps(r.Context(), tx, `SELECT id::text,issue_code,business_id::text,order_id::text,payable_id::text,batch_id::text,details,created_at::text FROM merchant_reconciliation_exceptions ORDER BY created_at DESC LIMIT 300`)
		return e
	})
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, 200, rows)
}

func (s *Service) ReviewAdjustment(w http.ResponseWriter, r *http.Request, actor string) {
	if !s.qaEnvironment {
		writeError(w, financeError(404, "NOT_FOUND", "Merchant finance simulation is available only in isolated QA."))
		return
	}
	var in struct {
		Decision string `json:"decision"`
		Reason   string `json:"reason"`
	}
	if err := decode(w, r, &in); err != nil {
		writeError(w, err)
		return
	}
	id := r.PathValue("adjustmentId")
	if _, err := uuid.Parse(id); err != nil {
		writeError(w, financeError(400, "VALIDATION_ERROR", "Adjustment ID must be a UUID."))
		return
	}
	if (in.Decision != "approve" && in.Decision != "reject") || len(strings.TrimSpace(in.Reason)) < 5 {
		writeError(w, financeError(400, "VALIDATION_ERROR", "A valid decision and reason are required."))
		return
	}
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := authorize(r.Context(), tx, actor, "finance.post"); err != nil {
			return err
		}
		var payable, business, requester, kind string
		var amount int64
		var status string
		if err := tx.QueryRowxContext(r.Context(), `SELECT payable_id::text,business_id::text,requested_by::text,adjustment_type,amount_minor,status FROM merchant_payable_adjustments WHERE id=$1 FOR UPDATE`, id).Scan(&payable, &business, &requester, &kind, &amount, &status); errors.Is(err, sql.ErrNoRows) {
			return financeError(404, "NOT_FOUND", "Payable adjustment was not found.")
		} else if err != nil {
			return err
		}
		if requester == actor {
			return financeError(403, "SELF_APPROVAL_FORBIDDEN", "The requester cannot review their own payable adjustment.")
		}
		if status != "requested" {
			return financeError(409, "INVALID_STATE", "Only requested adjustments can be reviewed.")
		}
		if in.Decision == "reject" {
			_, err := tx.ExecContext(r.Context(), `UPDATE merchant_payable_adjustments SET status='rejected',reviewed_by=$2,reviewed_at=now(),review_reason=$3 WHERE id=$1`, id, actor, strings.TrimSpace(in.Reason))
			if err != nil {
				return err
			}
			return audit(r.Context(), tx, actor, "payable_adjustment_rejected", business, "", payable, "", "", in.Reason, map[string]any{"adjustment_id": id})
		}
		var inSettlementBatch bool
		if err := tx.GetContext(r.Context(), &inSettlementBatch, `SELECT EXISTS(SELECT 1 FROM merchant_settlement_batch_items WHERE payable_id=$1)`, payable); err != nil {
			return err
		}
		if inSettlementBatch {
			return financeError(409, "PAYABLE_ALREADY_ALLOCATED", "A payable included in a settlement draft cannot be adjusted; cancel or finish the batch first.")
		}
		var open int64
		if err := tx.GetContext(r.Context(), &open, `SELECT p.net_payable_minor+COALESCE((SELECT sum(CASE WHEN a.adjustment_type='credit' THEN a.amount_minor ELSE -a.amount_minor END) FROM merchant_payable_adjustments a WHERE a.payable_id=p.id AND a.status='approved'),0)-COALESCE((SELECT sum(bi.amount_minor) FROM merchant_settlement_batch_items bi JOIN merchant_settlement_batches b ON b.id=bi.batch_id WHERE bi.payable_id=p.id AND b.status IN ('simulated','reconciled')),0) FROM merchant_payable_snapshots p WHERE p.id=$1 FOR UPDATE`, payable); err != nil {
			return err
		}
		delta := amount
		if kind == "debit" {
			delta = -amount
		}
		adjustedOpen, ok := checkedAddInt64(open, delta)
		if !ok {
			return financeError(409, "AMOUNT_OVERFLOW", "Approved adjustment exceeds the supported range.")
		}
		if adjustedOpen < 0 {
			return financeError(409, "NEGATIVE_PAYABLE_FORBIDDEN", "This adjustment would create a negative payable; no automatic clawback is allowed.")
		}
		var costID, payableAccount string
		for code, target := range map[string]*string{"merchant_fulfillment_cost": &costID, "merchant_payable_liability": &payableAccount} {
			if err := tx.GetContext(r.Context(), target, `SELECT id::text FROM financial_accounts WHERE account_code=$1 AND currency='INR'`, code); err != nil {
				return err
			}
		}
		lines := []financialledger.Line{}
		if delta > 0 {
			lines = append(lines, financialledger.Line{AccountID: costID, Side: "debit", Amount: delta}, financialledger.Line{AccountID: payableAccount, Side: "credit", Amount: delta})
		} else {
			lines = append(lines, financialledger.Line{AccountID: payableAccount, Side: "debit", Amount: -delta}, financialledger.Line{AccountID: costID, Side: "credit", Amount: -delta, Memo: "Reverse partner fulfillment cost under approved payable adjustment"})
		}
		j, err := financialledger.PostJournalTx(r.Context(), tx, financialledger.PostInput{Currency: "INR", SourceType: "merchant_payable_adjustment", SourceID: id, SourceEvent: "approved", IdempotencyKey: "merchant-adjustment:" + id, Description: "Authorized merchant payable adjustment", ActorUserID: actor, Reason: strings.TrimSpace(in.Reason), Lines: lines})
		if err != nil {
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE merchant_payable_adjustments SET status='approved',reviewed_by=$2,reviewed_at=now(),review_reason=$3,financial_journal_id=$4 WHERE id=$1`, id, actor, strings.TrimSpace(in.Reason), j.ID); err != nil {
			return err
		}
		return audit(r.Context(), tx, actor, "payable_adjustment_approved", business, "", payable, "", "", in.Reason, map[string]any{"adjustment_id": id, "journal_id": j.ID, "delta_minor": delta})
	})
	if err != nil {
		writeError(w, err)
		return
	}
	status := "rejected"
	if in.Decision == "approve" {
		status = "approved"
	}
	writeJSON(w, 200, map[string]string{"id": id, "status": status})
}

func (s *Service) ListAdjustments(w http.ResponseWriter, r *http.Request, actor string) {
	if !s.qaEnvironment {
		writeError(w, financeError(404, "NOT_FOUND", "Merchant finance simulation is available only in isolated QA."))
		return
	}
	var rows []map[string]any
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := authorize(r.Context(), tx, actor, "finance.read"); err != nil {
			return err
		}
		var err error
		rows, err = queryMaps(r.Context(), tx, `SELECT a.id::text,a.payable_id::text,a.business_id::text,b.name merchant_name,a.amount_minor,a.currency,a.adjustment_type,a.reason_code,a.status,a.requested_by::text,a.reviewed_by::text,a.review_reason,a.financial_journal_id::text,a.created_at::text,a.reviewed_at::text FROM merchant_payable_adjustments a JOIN businesses b ON b.id=a.business_id ORDER BY a.created_at DESC LIMIT 300`)
		return err
	})
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, 200, rows)
}

func (s *Service) RequestAdjustment(w http.ResponseWriter, r *http.Request, actor string) {
	if !s.qaEnvironment {
		writeError(w, financeError(404, "NOT_FOUND", "Merchant finance simulation is available only in isolated QA."))
		return
	}
	var in struct {
		PayableID      string `json:"payable_id"`
		AmountMinor    int64  `json:"amount_minor"`
		AdjustmentType string `json:"adjustment_type"`
		ReasonCode     string `json:"reason_code"`
		Reason         string `json:"reason"`
		IdempotencyKey string `json:"idempotency_key"`
	}
	if err := decode(w, r, &in); err != nil {
		writeError(w, err)
		return
	}
	if _, err := uuid.Parse(in.PayableID); err != nil || in.AmountMinor <= 0 || (in.AdjustmentType != "credit" && in.AdjustmentType != "debit") || (in.ReasonCode != "refund_review" && in.ReasonCode != "return_review" && in.ReasonCode != "contract_correction" && in.ReasonCode != "other") || len(strings.TrimSpace(in.Reason)) < 10 {
		writeError(w, financeError(400, "VALIDATION_ERROR", "Payable, positive amount, type and reason are required."))
		return
	}
	key, err := uuid.Parse(in.IdempotencyKey)
	if err != nil {
		writeError(w, financeError(400, "VALIDATION_ERROR", "Idempotency key must be a UUID."))
		return
	}
	fp, _ := fingerprint(in)
	var id string
	err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := authorize(r.Context(), tx, actor, "finance.post"); err != nil {
			return err
		}
		var business string
		if err := tx.GetContext(r.Context(), &business, `SELECT business_id::text FROM merchant_payable_snapshots WHERE id=$1`, in.PayableID); errors.Is(err, sql.ErrNoRows) {
			return financeError(404, "NOT_FOUND", "Payable snapshot was not found.")
		} else if err != nil {
			return err
		}
		if err := tx.QueryRowxContext(r.Context(), `INSERT INTO merchant_payable_adjustments(payable_id,business_id,amount_minor,currency,adjustment_type,reason_code,idempotency_key,request_fingerprint,requested_by) VALUES($1,$2,$3,'INR',$4,$5,$6,$7,$8) ON CONFLICT(requested_by,idempotency_key) DO NOTHING RETURNING id::text`, in.PayableID, business, in.AmountMinor, in.AdjustmentType, in.ReasonCode, key.String(), fp, actor).Scan(&id); errors.Is(err, sql.ErrNoRows) {
			var oldHash []byte
			if e := tx.QueryRowxContext(r.Context(), `SELECT id::text,request_fingerprint FROM merchant_payable_adjustments WHERE requested_by=$1 AND idempotency_key=$2`, actor, key.String()).Scan(&id, &oldHash); e != nil {
				return e
			}
			if !equalHash(oldHash, fp) {
				return financeError(409, "IDEMPOTENCY_CONFLICT", "Idempotency key was reused with a different adjustment.")
			}
		} else if err != nil {
			return err
		}
		return audit(r.Context(), tx, actor, "payable_adjustment_requested", business, "", in.PayableID, "", "", in.Reason, map[string]any{"adjustment_id": id, "amount_minor": in.AmountMinor, "type": in.AdjustmentType})
	})
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, 201, map[string]string{"id": id, "status": "requested"})
}

func reconcileBatch(ctx context.Context, tx *sqlx.Tx, id string) ([]map[string]any, error) {
	return queryMaps(ctx, tx, `SELECT 'batch_total_mismatch' issue,b.business_id::text,b.id::text order_id,NULL::text payable_id,b.id::text batch_id,'Batch total does not equal item snapshots' details FROM merchant_settlement_batches b WHERE b.id=$1 AND b.simulated_net_minor<>(SELECT COALESCE(sum(i.amount_minor),0) FROM merchant_settlement_batch_items i WHERE i.batch_id=b.id) UNION ALL SELECT 'simulation_journal_missing',b.business_id::text,NULL::text,NULL::text,b.id::text,'Simulated batch has no posted financial journal' FROM merchant_settlement_batches b LEFT JOIN financial_journals j ON j.id=b.financial_journal_id AND j.status='posted' WHERE b.id=$1 AND b.status IN ('simulated','reconciled') AND j.id IS NULL UNION ALL SELECT 'funding_allocation_missing',b.business_id::text,NULL::text,NULL::text,b.id::text,'Approved or simulated batch has no funding allocation' FROM merchant_settlement_batches b WHERE b.id=$1 AND b.status IN ('approved','simulated','reconciled') AND NOT EXISTS(SELECT 1 FROM merchant_settlement_funding_allocations a WHERE a.batch_id=b.id)`, id)
}
func reconcileAll(ctx context.Context, tx *sqlx.Tx) ([]map[string]any, error) {
	rows, err := queryMaps(ctx, tx, `
SELECT 'delivered_payable_missing' issue,o.business_id::text,o.id::text order_id,NULL::text payable_id,NULL::text batch_id,'Delivered, verified platform order has no payable snapshot' details FROM customer_orders o JOIN platform_customer_order_items i ON i.order_id=o.id WHERE o.order_source='platform_catalog' AND o.status='delivered' AND ((((o.payment_method='upi' OR o.payment_method IS NULL) AND o.payment_status='paid') AND EXISTS(SELECT 1 FROM payment_intents pi JOIN payment_attempts pa ON pa.payment_intent_id=pi.id WHERE pi.order_id=o.id AND pa.provider='grepmind_sandbox' AND pa.status='succeeded')) OR (o.payment_method='cash_on_delivery' AND EXISTS(SELECT 1 FROM cod_collections c WHERE c.order_id=o.id))) GROUP BY o.business_id,o.id HAVING NOT EXISTS(SELECT 1 FROM merchant_payable_snapshots p WHERE p.order_id=o.id)
UNION ALL SELECT 'payable_source_invalid',p.business_id::text,p.order_id::text,p.id::text,NULL::text,'Payable source order is cancelled, returned, unpaid, or mismatched' FROM merchant_payable_snapshots p JOIN customer_orders o ON o.id=p.order_id WHERE o.order_source<>'platform_catalog' OR o.business_id<>p.business_id OR o.status<>'delivered' OR (p.payment_source='sandbox_upi_capture' AND (o.payment_status<>'paid' OR NOT EXISTS(SELECT 1 FROM payment_intents pi JOIN payment_attempts pa ON pa.payment_intent_id=pi.id WHERE pi.order_id=o.id AND pa.provider='grepmind_sandbox' AND pa.status='succeeded'))) OR (p.payment_source='synthetic_cod_collection' AND NOT EXISTS(SELECT 1 FROM cod_collections c WHERE c.order_id=o.id))
UNION ALL SELECT 'payable_journal_missing',p.business_id::text,p.order_id::text,p.id::text,NULL::text,'Payable snapshot journal is not posted' FROM merchant_payable_snapshots p LEFT JOIN financial_journals j ON j.id=p.financial_journal_id AND j.status='posted' WHERE j.id IS NULL
UNION ALL SELECT 'refund_requires_review',p.business_id::text,p.order_id::text,p.id::text,NULL::text,'Refund or return evidence requires policy-approved payable review' FROM merchant_payable_snapshots p JOIN customer_orders o ON o.id=p.order_id WHERE o.status='returned' OR EXISTS(SELECT 1 FROM payment_refunds f WHERE f.order_id=o.id AND f.status='succeeded')
ORDER BY 1,3 LIMIT 1000`)
	if err != nil {
		return nil, err
	}
	batches, err := queryMaps(ctx, tx, `SELECT id::text FROM merchant_settlement_batches ORDER BY created_at DESC LIMIT 500`)
	if err != nil {
		return nil, err
	}
	for _, batch := range batches {
		issues, e := reconcileBatch(ctx, tx, fmt.Sprint(batch["id"]))
		if e != nil {
			return nil, e
		}
		rows = append(rows, issues...)
	}
	return rows, nil
}

func queryMaps(ctx context.Context, tx *sqlx.Tx, q string, args ...any) ([]map[string]any, error) {
	rows, err := tx.QueryxContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]map[string]any, 0)
	for rows.Next() {
		v := map[string]any{}
		if err := rows.MapScan(v); err != nil {
			return nil, err
		}
		for k, x := range v {
			if b, ok := x.([]byte); ok {
				v[k] = string(b)
			}
		}
		out = append(out, v)
	}
	return out, rows.Err()
}

func nullableDBText(v any) string {
	if v == nil {
		return ""
	}
	return fmt.Sprint(v)
}

func equalHash(a, b []byte) bool {
	return len(a) == len(b) && strings.EqualFold(hex.EncodeToString(a), hex.EncodeToString(b))
}
func toInt64(v any) int64 {
	switch x := v.(type) {
	case int64:
		return x
	case int32:
		return int64(x)
	case int:
		return int64(x)
	case []byte:
		var n int64
		_, _ = fmt.Sscan(string(x), &n)
		return n
	case string:
		var n int64
		_, _ = fmt.Sscan(x, &n)
		return n
	}
	return 0
}
