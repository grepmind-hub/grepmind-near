package payouts

import (
	"context"
	"crypto/sha256"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
	"grepmind-near/backend/internal/financialledger"
)

type CreateRiderSettlementRequest struct {
	PeriodStart string `json:"period_start"`
	PeriodEnd   string `json:"period_end"`
}

type RiderSettlementBatchResponse struct {
	ID                 string `json:"id"`
	RiderUserID        string `json:"rider_user_id"`
	PeriodStart        string `json:"period_start"`
	PeriodEnd          string `json:"period_end"`
	GrossEarningsMinor int64  `json:"gross_earnings_minor"`
	AdjustmentsMinor   int64  `json:"adjustments_minor"`
	NetPayoutMinor     int64  `json:"net_payout_minor"`
	Status             string `json:"status"`
	CreatedAt          string `json:"created_at"`
	ApprovedBy         string `json:"approved_by,omitempty"`
}

// AccrueRiderEarnings maps unaccrued rider_earning_entries into rider_payable_liability exactly once
func (s *Service) AccrueRiderEarnings(ctx context.Context, riderID, actorID string) (int64, error) {
	var totalAccrued int64

	err := s.db.Transaction(ctx, func(tx *sqlx.Tx) error {
		type unmappedEntry struct {
			ID          string `db:"id"`
			AmountMinor int64  `db:"amount_minor"`
			EntryType   string `db:"entry_type"`
		}

		var entries []unmappedEntry
		err := tx.SelectContext(ctx, &entries, `SELECT e.id::text, e.amount_minor, e.entry_type 
			FROM rider_earning_entries e 
			WHERE e.rider_user_id=$1 
			  AND e.entry_type <> 'unpriced' 
			  AND e.amount_minor IS NOT NULL 
			  AND NOT EXISTS (SELECT 1 FROM rider_earning_financial_mappings m WHERE m.earning_entry_id=e.id)
			ORDER BY e.effective_at ASC FOR UPDATE OF e`, riderID)
		if err != nil {
			return err
		}

		if len(entries) == 0 {
			return nil
		}

		var costID, payableID string
		if err := tx.GetContext(ctx, &costID, `SELECT id::text FROM financial_accounts WHERE account_code='rider_fulfillment_cost' AND currency='INR'`); err != nil {
			return err
		}
		if err := tx.GetContext(ctx, &payableID, `SELECT id::text FROM financial_accounts WHERE account_code='rider_payable_liability' AND currency='INR'`); err != nil {
			return err
		}

		for _, e := range entries {
			var lines []financialledger.Line
			if e.AmountMinor > 0 {
				lines = append(lines,
					financialledger.Line{AccountID: costID, Side: "debit", Amount: e.AmountMinor, Memo: "Rider delivery earning recognition"},
					financialledger.Line{AccountID: payableID, Side: "credit", Amount: e.AmountMinor, Memo: "Rider earnings payable liability"},
				)
			} else {
				lines = append(lines,
					financialledger.Line{AccountID: payableID, Side: "debit", Amount: -e.AmountMinor, Memo: "Rider earning adjustment debit"},
					financialledger.Line{AccountID: costID, Side: "credit", Amount: -e.AmountMinor, Memo: "Rider fulfillment expense correction"},
				)
			}

			journal, err := financialledger.PostJournalTx(ctx, tx, financialledger.PostInput{
				Currency:       "INR",
				SourceType:     "rider_earning_accrual",
				SourceID:       e.ID,
				SourceEvent:    "earning_recognized",
				IdempotencyKey: "rider-accrual:" + e.ID,
				Description:    fmt.Sprintf("Recognize rider %s earning %s", riderID[:8], e.ID[:8]),
				ActorUserID:    actorID,
				Reason:         "Authoritative rider earning accrual into double-entry ledger",
				Lines:          lines,
			})
			if err != nil {
				return fmt.Errorf("failed to post rider accrual journal for entry %s: %w", e.ID, err)
			}

			_, err = tx.ExecContext(ctx, `INSERT INTO rider_earning_financial_mappings(
				earning_entry_id, financial_journal_id, rider_user_id, amount_minor
			) VALUES($1, $2, $3, $4)`, e.ID, journal.ID, riderID, e.AmountMinor)
			if err != nil {
				return err
			}

			totalAccrued += e.AmountMinor
		}

		return nil
	})

	return totalAccrued, err
}

// CreateRiderSettlementBatch creates a settlement draft for a rider after verifying COD liability isolation
func (s *Service) CreateRiderSettlementBatch(ctx context.Context, riderID, periodStart, periodEnd, actorID string) (*RiderSettlementBatchResponse, error) {
	// 1. Verify COD cash liability: Rider must NOT have unremitted COD liabilities
	var unremittedCOD int64
	err := s.db.QueryRowxContext(ctx, `SELECT 
		COALESCE((SELECT sum(amount_minor) FROM cod_collections WHERE rider_user_id=$1),0) - 
		COALESCE((SELECT sum(amount_minor) FROM cod_remittances WHERE rider_user_id=$1 AND state='verified'),0)`, riderID).Scan(&unremittedCOD)
	if err != nil {
		return nil, fmt.Errorf("failed to verify COD cash accountability: %w", err)
	}

	if unremittedCOD > 0 {
		return nil, fmt.Errorf("COD_REMITTANCE_REQUIRED: Rider has unremitted COD cash liability of ₹%.2f; payout is blocked until cash is remitted to branch", float64(unremittedCOD)/100)
	}

	// 2. Accrue any unaccrued earnings first
	_, err = s.AccrueRiderEarnings(ctx, riderID, actorID)
	if err != nil {
		return nil, fmt.Errorf("failed to accrue rider earnings: %w", err)
	}

	var batchResp RiderSettlementBatchResponse

	err = s.db.Transaction(ctx, func(tx *sqlx.Tx) error {
		type eligibleItem struct {
			ID          string `db:"id"`
			AmountMinor int64  `db:"amount_minor"`
		}

		var items []eligibleItem
		// Select accrued earnings within period that are NOT currently allocated to any batch
		err := tx.SelectContext(ctx, &items, `SELECT e.id::text, e.amount_minor 
			FROM rider_earning_entries e 
			JOIN rider_earning_financial_mappings m ON m.earning_entry_id=e.id 
			WHERE e.rider_user_id=$1 
			  AND e.effective_at >= $2::date AND e.effective_at <= ($3::date + interval '1 day')
			  AND NOT EXISTS (
				  SELECT 1 FROM rider_settlement_batch_items bi 
				  WHERE bi.earning_entry_id=e.id AND bi.status='allocated'
			  )
			ORDER BY e.effective_at ASC FOR UPDATE OF e`, riderID, periodStart, periodEnd)
		if err != nil {
			return err
		}

		if len(items) == 0 {
			return fmt.Errorf("NO_ELIGIBLE_EARNINGS: No unallocated earnings found for rider in this period")
		}

		var grossMinor, adjMinor int64
		for _, it := range items {
			if it.AmountMinor > 0 {
				grossMinor += it.AmountMinor
			} else {
				adjMinor += it.AmountMinor
			}
		}

		netPayout := grossMinor + adjMinor
		if netPayout <= 0 {
			return fmt.Errorf("NEGATIVE_BALANCE_FORBIDDEN: Net payable amount must be positive (got ₹%.2f)", float64(netPayout)/100)
		}

		idempotencyKey := uuid.New()
		fpData := fmt.Sprintf("%s|%s|%s|%d", riderID, periodStart, periodEnd, netPayout)
		fpHash := sha256.Sum256([]byte(fpData))

		var batchID string
		err = tx.QueryRowxContext(ctx, `INSERT INTO rider_settlement_batches(
			rider_user_id, period_start, period_end, gross_earnings_minor, adjustments_minor, 
			net_payout_minor, status, idempotency_key, request_fingerprint, created_by
		) VALUES($1, $2, $3, $4, $5, $6, 'draft', $7, $8, $9) 
		RETURNING id::text`, riderID, periodStart, periodEnd, grossMinor, adjMinor, netPayout, idempotencyKey, fpHash[:], actorID).Scan(&batchID)
		if err != nil {
			return err
		}

		// Allocate items with database uniqueness guard
		for _, it := range items {
			_, err = tx.ExecContext(ctx, `INSERT INTO rider_settlement_batch_items(
				batch_id, earning_entry_id, rider_user_id, amount_minor, status
			) VALUES($1, $2, $3, $4, 'allocated')`, batchID, it.ID, riderID, it.AmountMinor)
			if err != nil {
				return fmt.Errorf("concurrent allocation conflict on item %s: %w", it.ID, err)
			}
		}

		batchResp = RiderSettlementBatchResponse{
			ID:                 batchID,
			RiderUserID:        riderID,
			PeriodStart:        periodStart,
			PeriodEnd:          periodEnd,
			GrossEarningsMinor: grossMinor,
			AdjustmentsMinor:   adjMinor,
			NetPayoutMinor:     netPayout,
			Status:             "draft",
			CreatedAt:          time.Now().UTC().Format(time.RFC3339),
		}

		return nil
	})

	return &batchResp, err
}

// ApproveRiderSettlementBatch provides two-person approval for rider settlement batches
func (s *Service) ApproveRiderSettlementBatch(ctx context.Context, batchID, actorID, reason string) error {
	return s.db.Transaction(ctx, func(tx *sqlx.Tx) error {
		var createdBy string
		var status string
		err := tx.QueryRowxContext(ctx, `SELECT created_by::text, status FROM rider_settlement_batches WHERE id=$1 FOR UPDATE`, batchID).Scan(&createdBy, &status)
		if err != nil {
			return err
		}
		if createdBy == actorID {
			return fmt.Errorf("SELF_APPROVAL_FORBIDDEN: creator cannot approve their own rider settlement batch")
		}
		if status != "draft" && status != "reviewed" {
			return fmt.Errorf("batch cannot be approved in state: %s", status)
		}

		_, err = tx.ExecContext(ctx, `UPDATE rider_settlement_batches 
			SET status='approved', approved_by=$2, approved_at=now(), approval_reason=$3 WHERE id=$1`,
			batchID, actorID, reason)
		return err
	})
}
