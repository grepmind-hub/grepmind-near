package riderearnings

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
	"grepmind-near/backend/pkg/config"
	"grepmind-near/backend/pkg/database"
)

type Service struct {
	db             *database.DB
	postingEnabled bool
	allowSynthetic bool
}

func NewService(db *database.DB, cfg *config.Config) *Service {
	s := &Service{db: db}
	if cfg != nil {
		s.postingEnabled = cfg.RiderEarningsPostingEnabled
		s.allowSynthetic = cfg.RiderEarningsAllowSynthetic
	}
	return s
}

// RecordCompletionTx must be called in the same transaction that commits the
// customer-verified Delivered transition. Unpriced rows make missing policy or
// disabled posting visible without fabricating a zero balance.
func (s *Service) RecordCompletionTx(ctx context.Context, tx *sqlx.Tx, jobID, riderID string) error {
	var orderID, assignmentID, localityID string
	err := tx.QueryRowxContext(ctx, `SELECT j.order_id::text,a.id::text,j.locality_id::text
		FROM delivery_jobs j JOIN customer_orders o ON o.id=j.order_id
		JOIN delivery_assignments a ON a.job_id=j.id
			AND a.id=(SELECT latest.id FROM delivery_assignments latest WHERE latest.job_id=j.id ORDER BY latest.assigned_at DESC,latest.id DESC LIMIT 1)
			AND a.rider_user_id=$2
		WHERE j.id=$1 AND j.execution_state='delivered' AND o.status='delivered'
		AND EXISTS (SELECT 1 FROM delivery_execution_events e WHERE e.job_id=j.id AND e.event_type='customer_otp_verified' AND e.to_state='delivered')
		ORDER BY a.assigned_at DESC LIMIT 1 FOR SHARE OF j,o,a`, jobID, riderID).Scan(&orderID, &assignmentID, &localityID)
	if err != nil {
		return err
	}

	var policyID, currency string
	var version int
	var amount int64
	policyErr := tx.QueryRowxContext(ctx, `SELECT id::text,version,currency,fixed_amount_minor
		FROM rider_compensation_policies
		WHERE status='active' AND effective_from <= now() AND (effective_until IS NULL OR effective_until > now())
		AND (locality_id=$1 OR locality_id IS NULL)
		AND (is_synthetic=false OR $2)
		ORDER BY (locality_id IS NOT NULL) DESC,effective_from DESC,version DESC LIMIT 1`, localityID, s.allowSynthetic).
		Scan(&policyID, &version, &currency, &amount)
	priced := s.postingEnabled && policyErr == nil
	entryType, source, idem := "unpriced", "delivery_completed_unpriced", "delivery-unpriced:"+jobID
	var amountValue any
	var policyValue, versionValue, rateValue any
	metadata := map[string]string{}
	if priced {
		entryType, source, idem = "delivery_earning", "customer_otp_verified", "delivery-earned:"+jobID
		amountValue, policyValue, versionValue, rateValue = amount, policyID, version, amount
	} else if !s.postingEnabled {
		metadata["reason"] = "posting_disabled"
	} else if errors.Is(policyErr, sql.ErrNoRows) {
		metadata["reason"] = "no_active_compensation_policy"
	} else if policyErr != nil {
		return policyErr
	}
	meta, _ := json.Marshal(metadata)
	var entryID string
	err = tx.QueryRowxContext(ctx, `INSERT INTO rider_earning_entries
		(rider_user_id,delivery_job_id,order_id,assignment_id,policy_id,policy_version,rate_snapshot_minor,amount_minor,currency,entry_type,source_event,idempotency_key,effective_at,reason,metadata)
		VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,now(),CASE WHEN $10='unpriced' THEN 'Compensation requires an approved active policy.' ELSE NULL END,$13::jsonb)
		ON CONFLICT DO NOTHING RETURNING id::text`, riderID, jobID, orderID, assignmentID, policyValue, versionValue, rateValue, amountValue, currencyOrINR(currency, priced), entryType, source, idem, string(meta)).Scan(&entryID)
	if errors.Is(err, sql.ErrNoRows) {
		return nil // the unique delivery effect has already been recorded
	}
	if err != nil {
		return err
	}
	auditType := "unpriced_recorded"
	if priced {
		auditType = "earning_recorded"
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO rider_earning_audit_events(entry_id,rider_user_id,event_type,reason,metadata)
		VALUES($1,$2,$3,CASE WHEN $3='unpriced_recorded' THEN 'No approved active compensation policy or posting gate is disabled.' ELSE NULL END,$4::jsonb)`, entryID, riderID, auditType, string(meta))
	return err
}

func currencyOrINR(value string, priced bool) string {
	if priced && value != "" {
		return value
	}
	return "INR"
}

func validCurrency(value string) bool {
	if len(value) != 3 {
		return false
	}
	for _, r := range value {
		if r < 'A' || r > 'Z' {
			return false
		}
	}
	return true
}

type entry struct {
	ID            string    `db:"id" json:"id"`
	DeliveryJobID *string   `db:"delivery_job_id" json:"delivery_job_id"`
	OrderID       *string   `db:"order_id" json:"order_id"`
	EntryType     string    `db:"entry_type" json:"entry_type"`
	AmountMinor   *string   `db:"amount_minor" json:"amount_minor"`
	Currency      string    `db:"currency" json:"currency"`
	EffectiveAt   time.Time `db:"effective_at" json:"effective_at"`
	Reason        *string   `db:"reason" json:"reason"`
	PolicyVersion *int      `db:"policy_version" json:"policy_version"`
}

func (s *Service) RiderSummary(w http.ResponseWriter, r *http.Request, riderID string) {
	from, to, ok := dateRange(w, r)
	if !ok {
		return
	}
	var currencyTotals []map[string]any
	err := selectMapRows(r.Context(), s.db, &currencyTotals, `SELECT currency,COALESCE(sum(amount_minor) FILTER (WHERE entry_type<>'unpriced'),0)::text total_recorded_minor,
		count(*) FILTER(WHERE entry_type='delivery_earning')::int completed_deliveries,
		count(*) FILTER(WHERE entry_type='unpriced')::int unpriced_deliveries FROM rider_earning_entries WHERE rider_user_id=$1 AND effective_at >= $2 AND effective_at < $3 GROUP BY currency ORDER BY currency`, riderID, from, to)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load rider earnings summary.")
		return
	}
	out := map[string]any{"currency_totals": currencyTotals, "payouts_available": false, "from": from, "to": to}
	if len(currencyTotals) == 1 {
		for key, value := range currencyTotals[0] {
			out[key] = value
		}
	} else if len(currencyTotals) == 0 {
		out["total_recorded_minor"], out["currency"] = "0", "INR"
		out["completed_deliveries"], out["unpriced_deliveries"] = 0, 0
	} else {
		out["total_recorded_minor"], out["currency"] = nil, nil
	}
	writeJSON(w, 200, map[string]any{"data": out})
}

func (s *Service) RiderHistory(w http.ResponseWriter, r *http.Request, riderID string) {
	from, to, ok := dateRange(w, r)
	if !ok {
		return
	}
	limit, offset, ok := page(w, r)
	if !ok {
		return
	}
	var rows []entry
	err := s.db.SelectContext(r.Context(), &rows, `SELECT id::text,delivery_job_id::text,order_id::text,entry_type,amount_minor::text amount_minor,currency,effective_at,reason,policy_version FROM rider_earning_entries WHERE rider_user_id=$1 AND effective_at >= $2 AND effective_at < $3 ORDER BY effective_at DESC,id DESC LIMIT $4 OFFSET $5`, riderID, from, to, limit, offset)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load rider earnings history.")
		return
	}
	if rows == nil {
		rows = []entry{}
	}
	writeJSON(w, 200, map[string]any{"data": rows, "meta": map[string]any{"limit": limit, "offset": offset, "payouts_available": false}})
}

func (s *Service) RiderDetail(w http.ResponseWriter, r *http.Request, riderID string) {
	var row entry
	err := s.db.GetContext(r.Context(), &row, `SELECT id::text,delivery_job_id::text,order_id::text,entry_type,amount_minor::text amount_minor,currency,effective_at,reason,policy_version FROM rider_earning_entries WHERE id=$1 AND rider_user_id=$2`, r.PathValue("entryId"), riderID)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, 404, "NOT_FOUND", "Earning entry not found.")
		return
	}
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load earning entry.")
		return
	}
	writeJSON(w, 200, map[string]any{"data": row, "payouts_available": false})
}

func (s *Service) AdminOverview(w http.ResponseWriter, r *http.Request, _ string) {
	from, to, ok := dateRange(w, r)
	if !ok {
		return
	}
	var rows []map[string]any
	localityID := strings.TrimSpace(r.URL.Query().Get("locality_id"))
	err := selectMapRows(r.Context(), s.db, &rows, `SELECT e.rider_user_id::text,COALESCE(u.display_name,'Rider') rider_name,count(*) FILTER(WHERE e.entry_type='delivery_earning')::int completed_deliveries,
		count(*) FILTER(WHERE e.entry_type='unpriced')::int unpriced_deliveries,COALESCE(sum(e.amount_minor) FILTER(WHERE e.entry_type<>'unpriced'),0)::text total_recorded_minor,e.currency currency
		FROM rider_earning_entries e JOIN users u ON u.id=e.rider_user_id LEFT JOIN delivery_jobs j ON j.id=e.delivery_job_id
		WHERE e.effective_at >= $1 AND e.effective_at < $2 AND ($3='' OR j.locality_id::text=$3) GROUP BY e.rider_user_id,u.display_name,e.currency ORDER BY total_recorded_minor DESC LIMIT 200`, from, to, localityID)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load rider earnings overview.")
		return
	}
	if rows == nil {
		rows = []map[string]any{}
	}
	writeJSON(w, 200, map[string]any{"data": rows, "meta": map[string]any{"from": from, "to": to, "payouts_available": false}})
}

func (s *Service) AdminEntries(w http.ResponseWriter, r *http.Request, _ string) {
	from, to, ok := dateRange(w, r)
	if !ok {
		return
	}
	limit, offset, ok := page(w, r)
	if !ok {
		return
	}
	var rows []map[string]any
	query := `SELECT e.id::text,e.rider_user_id::text,COALESCE(u.display_name,'Rider') rider_name,e.delivery_job_id::text,e.order_id::text,e.entry_type,e.amount_minor::text amount_minor,e.currency,e.effective_at,e.reason,e.policy_version,l.name locality
		FROM rider_earning_entries e JOIN users u ON u.id=e.rider_user_id LEFT JOIN delivery_jobs j ON j.id=e.delivery_job_id LEFT JOIN platform_delivery_localities l ON l.id=j.locality_id
		WHERE e.effective_at >= $1 AND e.effective_at < $2 AND ($3='' OR e.rider_user_id::text=$3) AND ($4='' OR j.locality_id::text=$4) ORDER BY e.effective_at DESC,e.id DESC LIMIT $5 OFFSET $6`
	err := selectMapRows(r.Context(), s.db, &rows, query, from, to, r.URL.Query().Get("rider_id"), strings.TrimSpace(r.URL.Query().Get("locality_id")), limit, offset)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load earnings ledger.")
		return
	}
	if rows == nil {
		rows = []map[string]any{}
	}
	writeJSON(w, 200, map[string]any{"data": rows, "meta": map[string]any{"limit": limit, "offset": offset, "from": from, "to": to}})
}

func (s *Service) AdminLocalities(w http.ResponseWriter, r *http.Request, _ string) {
	var rows []map[string]any
	err := selectMapRows(r.Context(), s.db, &rows, `SELECT DISTINCT l.id::text locality_id,l.name,d.name district
		FROM platform_delivery_localities l
		JOIN platform_districts d ON d.id=l.district_id
		JOIN delivery_jobs j ON j.locality_id=l.id
		JOIN rider_earning_entries e ON e.delivery_job_id=j.id
		ORDER BY d.name,l.name`)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load earnings localities.")
		return
	}
	if rows == nil {
		rows = []map[string]any{}
	}
	writeJSON(w, 200, map[string]any{"data": rows})
}

func (s *Service) AdminAudit(w http.ResponseWriter, r *http.Request, _ string) {
	limit, offset, ok := page(w, r)
	if !ok {
		return
	}
	var rows []map[string]any
	err := selectMapRows(r.Context(), s.db, &rows, `SELECT a.id::text,a.entry_id::text,a.rider_user_id::text,COALESCE(r.display_name,'Rider') rider_name,a.actor_user_id::text,COALESCE(actor.display_name,'System') actor_name,a.event_type,a.reason,a.metadata,a.created_at
		FROM rider_earning_audit_events a JOIN users r ON r.id=a.rider_user_id LEFT JOIN users actor ON actor.id=a.actor_user_id ORDER BY a.created_at DESC,a.id DESC LIMIT $1 OFFSET $2`, limit, offset)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load earnings audit history.")
		return
	}
	if rows == nil {
		rows = []map[string]any{}
	}
	writeJSON(w, 200, map[string]any{"data": rows, "meta": map[string]any{"limit": limit, "offset": offset}})
}

func (s *Service) AdminPolicies(w http.ResponseWriter, r *http.Request, _ string) {
	var rows []map[string]any
	err := selectMapRows(r.Context(), s.db, &rows, `SELECT p.id::text,p.policy_key,p.version,p.locality_id::text,l.name locality,p.currency,p.fixed_amount_minor::text fixed_amount_minor,p.effective_from,p.effective_until,p.status,p.is_synthetic,p.created_at FROM rider_compensation_policies p LEFT JOIN platform_delivery_localities l ON l.id=p.locality_id ORDER BY p.policy_key,p.version DESC LIMIT 200`)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load compensation policies.")
		return
	}
	if rows == nil {
		rows = []map[string]any{}
	}
	writeJSON(w, 200, map[string]any{"data": rows, "meta": map[string]any{"policy_changes_enabled": false, "reason": "No commercial compensation policy has been approved."}})
}

func (s *Service) AdminReconciliation(w http.ResponseWriter, r *http.Request, _ string) {
	var rows []map[string]any
	err := selectMapRows(r.Context(), s.db, &rows, `SELECT j.id::text delivery_job_id,j.order_id::text,o.reference_code,j.execution_state,
		CASE WHEN j.execution_state<>'delivered' THEN 'earning_for_non_delivered_job' WHEN e.rider_user_id IS DISTINCT FROM (SELECT a.rider_user_id FROM delivery_assignments a WHERE a.job_id=j.id ORDER BY a.assigned_at DESC LIMIT 1) THEN 'incorrect_rider_linkage' WHEN e.entry_type='delivery_earning' AND (e.policy_id IS NULL OR e.policy_version IS DISTINCT FROM p.version OR e.amount_minor IS DISTINCT FROM e.rate_snapshot_minor OR e.rate_snapshot_minor IS DISTINCT FROM p.fixed_amount_minor OR e.currency IS DISTINCT FROM p.currency) THEN 'invalid_policy_snapshot' ELSE 'delivered_job_without_earning' END discrepancy
		FROM delivery_jobs j JOIN customer_orders o ON o.id=j.order_id LEFT JOIN rider_earning_entries e ON e.delivery_job_id=j.id AND e.entry_type IN ('delivery_earning','unpriced') LEFT JOIN rider_compensation_policies p ON p.id=e.policy_id
		WHERE (j.execution_state='delivered' AND e.id IS NULL) OR (e.id IS NOT NULL AND (j.execution_state<>'delivered' OR e.rider_user_id IS DISTINCT FROM (SELECT a.rider_user_id FROM delivery_assignments a WHERE a.job_id=j.id ORDER BY a.assigned_at DESC LIMIT 1) OR (e.entry_type='delivery_earning' AND (e.policy_id IS NULL OR e.policy_version IS DISTINCT FROM p.version OR e.amount_minor IS DISTINCT FROM e.rate_snapshot_minor OR e.rate_snapshot_minor IS DISTINCT FROM p.fixed_amount_minor OR e.currency IS DISTINCT FROM p.currency))))
		ORDER BY j.updated_at DESC LIMIT 200`)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to reconcile delivery earnings.")
		return
	}
	if rows == nil {
		rows = []map[string]any{}
	}
	var reversalIssues []map[string]any
	if err = selectMapRows(r.Context(), s.db, &reversalIssues, `SELECT original.id::text entry_id,original.rider_user_id::text,original.amount_minor::text amount_minor,COALESCE(sum(-rev.amount_minor),0)::text reversed_minor,'reversal_exceeds_original' discrepancy FROM rider_earning_entries original JOIN rider_earning_entries rev ON rev.metadata->>'reverses_entry_id'=original.id::text WHERE original.entry_type='delivery_earning' GROUP BY original.id HAVING COALESCE(sum(-rev.amount_minor),0)>original.amount_minor LIMIT 100`); err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to validate earning reversals.")
		return
	}
	rows = append(rows, reversalIssues...)
	writeJSON(w, 200, map[string]any{"data": rows, "meta": map[string]any{"count": len(rows), "automatic_repairs": false}})
}

func (s *Service) AdminAdjustment(w http.ResponseWriter, r *http.Request, adminID string) {
	var in struct {
		RiderID        string `json:"rider_user_id"`
		JobID          string `json:"delivery_job_id"`
		AmountMinor    int64  `json:"amount_minor"`
		Currency       string `json:"currency"`
		Reason         string `json:"reason"`
		IdempotencyKey string `json:"idempotency_key"`
	}
	if json.NewDecoder(http.MaxBytesReader(w, r.Body, 8192)).Decode(&in) != nil || uuid.Validate(in.RiderID) != nil || in.AmountMinor == 0 || in.AmountMinor > 100000000 || in.AmountMinor < -100000000 || !validCurrency(in.Currency) || len([]rune(strings.TrimSpace(in.Reason))) < 10 || len([]rune(in.Reason)) > 500 || len(in.IdempotencyKey) < 8 || len(in.IdempotencyKey) > 160 {
		writeError(w, 400, "VALIDATION_ERROR", "Provide a valid rider, non-zero bounded integer minor-unit amount, ISO currency code, 10–500 character reason, and idempotency key.")
		return
	}
	if in.JobID != "" && uuid.Validate(in.JobID) != nil {
		writeError(w, 400, "VALIDATION_ERROR", "Invalid delivery job ID.")
		return
	}
	var id string
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if in.JobID != "" {
			var linked bool
			if err := tx.GetContext(r.Context(), &linked, `SELECT j.execution_state='delivered' AND EXISTS(SELECT 1 FROM delivery_assignments a WHERE a.job_id=j.id AND a.rider_user_id=$2) FROM delivery_jobs j WHERE j.id=$1`, in.JobID, in.RiderID); err != nil {
				return err
			}
			if !linked {
				return errors.New("adjustment delivery job is not completed for this rider")
			}
		}
		err := tx.QueryRowxContext(r.Context(), `INSERT INTO rider_earning_entries(rider_user_id,delivery_job_id,entry_type,source_event,idempotency_key,amount_minor,currency,effective_at,actor_user_id,reason)
			VALUES($1,NULLIF($2,'')::uuid,'manual_adjustment','admin_adjustment',$3,$4,$5,now(),$6,$7) ON CONFLICT(idempotency_key) DO NOTHING RETURNING id::text`, in.RiderID, in.JobID, in.IdempotencyKey, in.AmountMinor, in.Currency, adminID, strings.TrimSpace(in.Reason)).Scan(&id)
		if errors.Is(err, sql.ErrNoRows) {
			var existingRider, existingReason string
			var existingJob sql.NullString
			var existingAmount int64
			var existingCurrency string
			if err = tx.QueryRowxContext(r.Context(), `SELECT id::text,rider_user_id::text,delivery_job_id::text,amount_minor,currency,reason FROM rider_earning_entries WHERE idempotency_key=$1`, in.IdempotencyKey).Scan(&id, &existingRider, &existingJob, &existingAmount, &existingCurrency, &existingReason); err != nil {
				return err
			}
			if existingRider != in.RiderID || existingJob.String != in.JobID || existingAmount != in.AmountMinor || existingCurrency != in.Currency || existingReason != strings.TrimSpace(in.Reason) {
				return errors.New("idempotency key payload mismatch")
			}
			return nil
		}
		if err != nil {
			return err
		}
		_, err = tx.ExecContext(r.Context(), `INSERT INTO rider_earning_audit_events(entry_id,rider_user_id,actor_user_id,event_type,reason) VALUES($1,$2,$3,'adjustment_recorded',$4)`, id, in.RiderID, adminID, strings.TrimSpace(in.Reason))
		return err
	})
	if err != nil {
		writeError(w, 400, "ADJUSTMENT_REJECTED", "Adjustment was not recorded; verify the rider and delivery eligibility.")
		return
	}
	writeJSON(w, 201, map[string]any{"data": map[string]any{"entry_id": id, "recorded": true}})
}

func (s *Service) AdminReverse(w http.ResponseWriter, r *http.Request, adminID string) {
	var in struct {
		Reason         string `json:"reason"`
		IdempotencyKey string `json:"idempotency_key"`
	}
	if json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&in) != nil || len([]rune(strings.TrimSpace(in.Reason))) < 10 || len([]rune(in.Reason)) > 500 || len(in.IdempotencyKey) < 8 || len(in.IdempotencyKey) > 160 {
		writeError(w, 400, "VALIDATION_ERROR", "A 10–500 character reason and idempotency key are required.")
		return
	}
	original := r.PathValue("entryId")
	var id string
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var rider string
		var amount int64
		var kind, currency string
		var job sql.NullString
		var existingRider, existingType, existingOriginal, existingReason, existingCurrency string
		if err := tx.QueryRowxContext(r.Context(), `SELECT rider_user_id::text,amount_minor,entry_type,delivery_job_id::text,currency FROM rider_earning_entries WHERE id=$1 FOR SHARE`, original).Scan(&rider, &amount, &kind, &job, &currency); err != nil {
			return err
		}
		if kind != "delivery_earning" || amount <= 0 {
			return errors.New("only a positive delivery earning can be reversed")
		}
		if err := tx.QueryRowxContext(r.Context(), `SELECT id::text,rider_user_id::text,entry_type,metadata->>'reverses_entry_id',reason,currency FROM rider_earning_entries WHERE idempotency_key=$1`, in.IdempotencyKey).Scan(&id, &existingRider, &existingType, &existingOriginal, &existingReason, &existingCurrency); err == nil {
			if existingRider != rider || existingType != "reversal" || existingOriginal != original || existingReason != strings.TrimSpace(in.Reason) || existingCurrency != currency {
				return errors.New("idempotency key payload mismatch")
			}
			return nil
		} else if !errors.Is(err, sql.ErrNoRows) {
			return err
		}
		var already bool
		if err := tx.GetContext(r.Context(), &already, `SELECT EXISTS(SELECT 1 FROM rider_earning_entries WHERE entry_type='reversal' AND metadata->>'reverses_entry_id'=$1)`, original); err != nil {
			return err
		}
		if already {
			return errors.New("earning already reversed")
		}
		meta, _ := json.Marshal(map[string]string{"reverses_entry_id": original})
		if err := tx.QueryRowxContext(r.Context(), `INSERT INTO rider_earning_entries(rider_user_id,delivery_job_id,entry_type,source_event,idempotency_key,amount_minor,currency,effective_at,actor_user_id,reason,metadata)
			VALUES($1,$2,'reversal','admin_reversal',$3,-($4::bigint),$5,now(),$6,$7,$8::jsonb) ON CONFLICT(idempotency_key) DO NOTHING RETURNING id::text`, rider, job.String, in.IdempotencyKey, amount, currency, adminID, strings.TrimSpace(in.Reason), string(meta)).Scan(&id); err != nil {
			if !errors.Is(err, sql.ErrNoRows) {
				return err
			}
			if err = tx.QueryRowxContext(r.Context(), `SELECT id::text,rider_user_id::text,entry_type,metadata->>'reverses_entry_id',reason,currency FROM rider_earning_entries WHERE idempotency_key=$1`, in.IdempotencyKey).Scan(&id, &existingRider, &existingType, &existingOriginal, &existingReason, &existingCurrency); err != nil {
				return err
			}
			if existingRider != rider || existingType != "reversal" || existingOriginal != original || existingReason != strings.TrimSpace(in.Reason) || existingCurrency != currency {
				return errors.New("idempotency key payload mismatch")
			}
			return nil
		}
		_, err := tx.ExecContext(r.Context(), `INSERT INTO rider_earning_audit_events(entry_id,rider_user_id,actor_user_id,event_type,reason) VALUES($1,$2,$3,'reversal_recorded',$4)`, id, rider, adminID, strings.TrimSpace(in.Reason))
		return err
	})
	if err != nil {
		log.Printf("rider earnings reversal failed: %v", err)
		writeError(w, 409, "REVERSAL_REJECTED", "The earning cannot be reversed or has already been reversed.")
		return
	}
	writeJSON(w, 201, map[string]any{"data": map[string]any{"entry_id": id, "recorded": true}})
}

func dateRange(w http.ResponseWriter, r *http.Request) (time.Time, time.Time, bool) {
	q := r.URL.Query()
	now := time.Now().UTC()
	to := now.Add(time.Second)
	from := now.AddDate(0, 0, -30)
	var err error
	if q.Get("from") != "" {
		from, err = time.Parse(time.RFC3339, q.Get("from"))
		if err != nil {
			writeError(w, 400, "VALIDATION_ERROR", "from must be an RFC3339 timestamp.")
			return time.Time{}, time.Time{}, false
		}
	}
	if q.Get("to") != "" {
		to, err = time.Parse(time.RFC3339, q.Get("to"))
		if err != nil {
			writeError(w, 400, "VALIDATION_ERROR", "to must be an RFC3339 timestamp.")
			return time.Time{}, time.Time{}, false
		}
	}
	if !to.After(from) || to.Sub(from) > 366*24*time.Hour {
		writeError(w, 400, "VALIDATION_ERROR", "Date range must be positive and no longer than 366 days.")
		return time.Time{}, time.Time{}, false
	}
	return from.UTC(), to.UTC(), true
}
func page(w http.ResponseWriter, r *http.Request) (int, int, bool) {
	limit, offset := 50, 0
	var err error
	if x := r.URL.Query().Get("limit"); x != "" {
		limit, err = strconv.Atoi(x)
		if err != nil || limit < 1 || limit > 100 {
			writeError(w, 400, "VALIDATION_ERROR", "limit must be between 1 and 100.")
			return 0, 0, false
		}
	}
	if x := r.URL.Query().Get("offset"); x != "" {
		offset, err = strconv.Atoi(x)
		if err != nil || offset < 0 || offset > 10000 {
			writeError(w, 400, "VALIDATION_ERROR", "offset must be between 0 and 10000.")
			return 0, 0, false
		}
	}
	return limit, offset, true
}
func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, map[string]any{"error": map[string]string{"code": code, "message": message}})
}

// selectMapRows materializes untyped reporting rows without sqlx reflection,
// which rejects []map destinations. JSONB columns are decoded for ordinary
// JSON responses rather than emitted as base64-encoded byte slices.
func selectMapRows(ctx context.Context, db *database.DB, dest *[]map[string]any, query string, args ...any) error {
	rows, err := db.QueryxContext(ctx, query, args...)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		item := make(map[string]any)
		if err := rows.MapScan(item); err != nil {
			return err
		}
		for key, value := range item {
			if raw, ok := value.([]byte); ok {
				var decoded any
				if json.Unmarshal(raw, &decoded) == nil {
					item[key] = decoded
				} else {
					item[key] = string(raw)
				}
			}
		}
		*dest = append(*dest, item)
	}
	return rows.Err()
}
