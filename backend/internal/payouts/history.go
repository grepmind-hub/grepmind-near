package payouts

import (
	"net/http"
	"strconv"
	"strings"
	"time"
)

// SettlementHistoryRecord is a read-only projection. It deliberately excludes
// beneficiary details, provider identifiers, UTRs, audit internals, and COD
// liability. The response is available only from isolated QA/test.
type SettlementHistoryRecord struct {
	SettlementID       string     `db:"settlement_id" json:"settlement_id"`
	Currency           string     `db:"currency" json:"currency"`
	PeriodStart        string     `db:"period_start" json:"period_start"`
	PeriodEnd          string     `db:"period_end" json:"period_end"`
	GrossMinor         int64      `db:"gross_minor" json:"gross_minor,omitempty"`
	PayableMinor       int64      `db:"payable_minor" json:"payable_minor,omitempty"`
	AdjustmentsMinor   int64      `db:"adjustments_minor" json:"adjustments_minor"`
	NetMinor           int64      `db:"net_minor" json:"net_minor"`
	SettlementStatus   string     `db:"settlement_status" json:"settlement_status"`
	PayoutStatus       *string    `db:"payout_status" json:"payout_status,omitempty"`
	LatestAttemptStatus *string   `db:"latest_attempt_status" json:"latest_attempt_status,omitempty"`
	CreatedAt          time.Time  `db:"created_at" json:"created_at"`
	SimulatedAt        *time.Time `db:"simulated_at" json:"simulated_at,omitempty"`
	PayoutCompletedAt  *time.Time `db:"payout_completed_at" json:"payout_completed_at,omitempty"`
	SimulationOnly     bool       `db:"simulation_only" json:"simulation_only"`
	Disclosure         string     `db:"disclosure" json:"disclosure"`
}

func historyLimit(r *http.Request) (int, bool) {
	value := strings.TrimSpace(r.URL.Query().Get("limit"))
	if value == "" {
		return 100, true
	}
	limit, err := strconv.Atoi(value)
	return limit, err == nil && limit >= 1 && limit <= 200
}

func (s *Service) RiderSettlementHistory(w http.ResponseWriter, r *http.Request, riderID string) {
	if s.env != "qa" && s.env != "test" {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Settlement payout history is available only in isolated QA/test.")
		return
	}
	limit, ok := historyLimit(r)
	if !ok {
		writeError(w, http.StatusBadRequest, "INVALID_LIMIT", "Limit must be between 1 and 200.")
		return
	}
	var rows []SettlementHistoryRecord
	err := s.db.SelectContext(r.Context(), &rows, `
		SELECT b.id::text AS settlement_id,'INR'::text AS currency,b.period_start::text,b.period_end::text,
			b.gross_earnings_minor AS gross_minor,b.adjustments_minor,b.net_payout_minor AS net_minor,b.status AS settlement_status,
			b.created_at,NULL::timestamptz AS simulated_at,pt.status AS payout_status,
			attempt.status AS latest_attempt_status,pt.completed_at AS payout_completed_at,true AS simulation_only,
			'QA simulation only. No bank transfer or real payout is implied.'::text AS disclosure
		FROM rider_settlement_batches b
		LEFT JOIN payout_transfers pt ON pt.rider_batch_id=b.id
		LEFT JOIN LATERAL (
			SELECT a.status FROM payout_transfer_attempts a
			WHERE a.transfer_id=pt.id ORDER BY a.attempt_number DESC LIMIT 1
		) attempt ON true
		WHERE b.rider_user_id=$1
		ORDER BY b.created_at DESC,b.id DESC LIMIT $2`, riderID, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to load rider settlement history.")
		return
	}
	for i := range rows {
		rows[i].SimulationOnly = true
		rows[i].Disclosure = "QA simulation only. No bank transfer or real payout is implied."
	}
	if rows == nil {
		rows = []SettlementHistoryRecord{}
	}
	writeJSON(w, http.StatusOK, rows)
}

