package payouts

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
	"grepmind-near/backend/internal/financialledger"
	"grepmind-near/backend/pkg/database"
)

type Service struct {
	db       *database.DB
	provider PayoutProvider
	env      string
}

func NewService(db *database.DB, provider PayoutProvider, env string) *Service {
	return &Service{
		db:       db,
		provider: provider,
		env:      env,
	}
}

func writeJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{"data": data})
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{
		"error": map[string]any{
			"code":    code,
			"message": message,
		},
	})
}

// CreatePayoutTransfer creates the payout transfer entity for an approved settlement batch
func (s *Service) CreatePayoutTransfer(ctx context.Context, batchType, batchID, requestedBy string) (string, error) {
	var transferID string
	err := s.db.Transaction(ctx, func(tx *sqlx.Tx) error {
		var amountMinor int64
		var beneID sql.NullString
		var batchStatus string

		if batchType == "merchant_settlement" {
			var businessID string
			err := tx.QueryRowxContext(ctx, `SELECT simulated_net_minor, business_id::text, status 
				FROM merchant_settlement_batches WHERE id=$1 FOR UPDATE`, batchID).Scan(&amountMinor, &businessID, &batchStatus)
			if errors.Is(err, sql.ErrNoRows) {
				return fmt.Errorf("merchant settlement batch not found")
			} else if err != nil {
				return err
			}
			if batchStatus != "approved" {
				return fmt.Errorf("settlement batch must be in approved status to create payout transfer (current: %s)", batchStatus)
			}
			// Find active verified beneficiary
			err = tx.GetContext(ctx, &beneID, `SELECT id::text FROM bank_beneficiaries 
				WHERE business_id=$1 AND verification_status='verified' ORDER BY created_at DESC LIMIT 1`, businessID)
			if errors.Is(err, sql.ErrNoRows) || !beneID.Valid {
				return ErrBeneficiaryUnverified
			}
		} else if batchType == "rider_earnings" {
			var riderID string
			err := tx.QueryRowxContext(ctx, `SELECT net_payout_minor, rider_user_id::text, status 
				FROM rider_settlement_batches WHERE id=$1 FOR UPDATE`, batchID).Scan(&amountMinor, &riderID, &batchStatus)
			if errors.Is(err, sql.ErrNoRows) {
				return fmt.Errorf("rider settlement batch not found")
			} else if err != nil {
				return err
			}
			if batchStatus != "approved" {
				return fmt.Errorf("rider settlement batch must be in approved status to create payout transfer (current: %s)", batchStatus)
			}
			// Find active verified beneficiary
			err = tx.GetContext(ctx, &beneID, `SELECT id::text FROM bank_beneficiaries 
				WHERE rider_user_id=$1 AND verification_status='verified' ORDER BY created_at DESC LIMIT 1`, riderID)
			if errors.Is(err, sql.ErrNoRows) || !beneID.Valid {
				return ErrBeneficiaryUnverified
			}
		} else {
			return fmt.Errorf("unsupported payout type: %s", batchType)
		}

		// Double-Entry Allocation Journal: Move liability to payout_clearing_liability
		var liabilityAccount, clearingAccount string
		if batchType == "merchant_settlement" {
			liabilityAccount = "merchant_payable_liability"
		} else {
			liabilityAccount = "rider_payable_liability"
		}
		clearingAccount = "payout_clearing_liability"

		var liabID, clearID string
		if err := tx.GetContext(ctx, &liabID, `SELECT id::text FROM financial_accounts WHERE account_code=$1 AND currency='INR' AND is_enabled`, liabilityAccount); err != nil {
			return fmt.Errorf("account %s not found: %w", liabilityAccount, err)
		}
		if err := tx.GetContext(ctx, &clearID, `SELECT id::text FROM financial_accounts WHERE account_code=$1 AND currency='INR' AND is_enabled`, clearingAccount); err != nil {
			return fmt.Errorf("account %s not found: %w", clearingAccount, err)
		}

		lines := []financialledger.Line{
			{AccountID: liabID, Side: "debit", Amount: amountMinor, Memo: "Settle partner payable; committed to payout clearing"},
			{AccountID: clearID, Side: "credit", Amount: amountMinor, Memo: "In-flight payout clearing liability"},
		}

		allocJournal, err := financialledger.PostJournalTx(ctx, tx, financialledger.PostInput{
			Currency:       "INR",
			SourceType:     "payout_allocation",
			SourceID:       batchID,
			SourceEvent:    "settlement_batch_allocated",
			IdempotencyKey: "payout-alloc:" + batchID,
			Description:    fmt.Sprintf("Payout allocation for %s batch %s", batchType, batchID),
			ActorUserID:    requestedBy,
			Reason:         "Commit approved settlement batch to payout clearing",
			Lines:          lines,
		})
		if err != nil {
			return fmt.Errorf("failed to post allocation journal: %w", err)
		}

		idempotencyKey := uuid.New()
		fingerprintData := fmt.Sprintf("%s|%s|%d|%s", batchType, batchID, amountMinor, beneID.String)
		fpHash := sha256.Sum256([]byte(fingerprintData))

		var query string
		if batchType == "merchant_settlement" {
			query = `INSERT INTO payout_transfers(
				payout_type, merchant_batch_id, beneficiary_id, amount_minor, currency, status,
				allocation_journal_id, idempotency_key, request_fingerprint, requested_by
			) VALUES('merchant_settlement', $1, $2, $3, 'INR', 'ready', $4, $5, $6, $7)
			RETURNING id::text`
		} else {
			query = `INSERT INTO payout_transfers(
				payout_type, rider_batch_id, beneficiary_id, amount_minor, currency, status,
				allocation_journal_id, idempotency_key, request_fingerprint, requested_by
			) VALUES('rider_earnings', $1, $2, $3, 'INR', 'ready', $4, $5, $6, $7)
			RETURNING id::text`
		}

		err = tx.QueryRowxContext(ctx, query, batchID, beneID.String, amountMinor, allocJournal.ID, idempotencyKey, fpHash[:], requestedBy).Scan(&transferID)
		return err
	})

	return transferID, err
}

// ExecutePayoutTransfer executes an approved transfer attempt through the configured provider
func (s *Service) ExecutePayoutTransfer(ctx context.Context, transferID, actorID string) (*TransferResult, error) {
	// 1. Verify operational gates
	var realMoneyEnabled, payoutEnabled bool
	err := s.db.QueryRowxContext(ctx, `SELECT real_money_enabled, payout_enabled FROM financial_feature_config WHERE singleton=true`).Scan(&realMoneyEnabled, &payoutEnabled)
	if err != nil {
		return nil, fmt.Errorf("failed to read feature gates: %w", err)
	}

	if s.env != "qa" && s.env != "test" && (!realMoneyEnabled || !payoutEnabled) {
		return nil, ErrRealMoneyPayoutDisabled
	}

	var tr struct {
		ID            string
		PayoutType    string
		MerchantBatch sql.NullString
		RiderBatch    sql.NullString
		BeneID        string
		AmountMinor   int64
		Status        string
		RequestedBy   string
		ApprovedBy    sql.NullString
	}

	var bene struct {
		ID           string
		HolderName   string
		EncryptedAcc []byte
		IFSC         string
		Status       string
	}

	var attemptNumber int

	err = s.db.Transaction(ctx, func(tx *sqlx.Tx) error {
		err := tx.QueryRowxContext(ctx, `SELECT 
			id::text, payout_type, merchant_batch_id::text, rider_batch_id::text, beneficiary_id::text, 
			amount_minor, status, requested_by::text, approved_by::text 
			FROM payout_transfers WHERE id=$1 FOR UPDATE`, transferID).Scan(
			&tr.ID, &tr.PayoutType, &tr.MerchantBatch, &tr.RiderBatch, &tr.BeneID,
			&tr.AmountMinor, &tr.Status, &tr.RequestedBy, &tr.ApprovedBy)
		if err != nil {
			return err
		}

		if tr.Status == "succeeded" {
			return fmt.Errorf("transfer already succeeded")
		}
		if tr.Status == "processing" || tr.Status == "reconciliation_required" {
			return ErrAttemptInFlight
		}

		// Two-person approval check: Approver must exist and differ from requester
		if !tr.ApprovedBy.Valid || tr.ApprovedBy.String == tr.RequestedBy {
			return fmt.Errorf("transfer requires independent two-person approval before execution")
		}

		// Check if active attempt in flight
		var activeAttempt bool
		if err := tx.GetContext(ctx, &activeAttempt, `SELECT EXISTS(
			SELECT 1 FROM payout_transfer_attempts WHERE transfer_id=$1 AND status IN ('initiated','processing','timeout')
		)`, transferID); err != nil {
			return err
		}
		if activeAttempt {
			return ErrAttemptInFlight
		}

		// Count attempts
		if err := tx.GetContext(ctx, &attemptNumber, `SELECT COALESCE(max(attempt_number),0)+1 FROM payout_transfer_attempts WHERE transfer_id=$1`, transferID); err != nil {
			return err
		}

		// Beneficiary details
		err = tx.QueryRowxContext(ctx, `SELECT id::text, account_holder_name, account_number_encrypted, ifsc_code, verification_status 
			FROM bank_beneficiaries WHERE id=$1`, tr.BeneID).Scan(&bene.ID, &bene.HolderName, &bene.EncryptedAcc, &bene.IFSC, &bene.Status)
		if err != nil {
			return err
		}
		if bene.Status != "verified" {
			return ErrBeneficiaryUnverified
		}

		return nil
	})
	if err != nil {
		return nil, err
	}

	plainAcc, err := decryptAccountNumber(bene.EncryptedAcc)
	if err != nil {
		return nil, fmt.Errorf("failed to decrypt account number: %w", err)
	}

	attemptIdempotency := uuid.New()

	// Record initiated attempt
	var attemptID string
	err = s.db.QueryRowxContext(ctx, `INSERT INTO payout_transfer_attempts(
		transfer_id, attempt_number, idempotency_key, provider, status
	) VALUES($1, $2, $3, $4, 'initiated') RETURNING id::text`,
		transferID, attemptNumber, attemptIdempotency, s.provider.Name()).Scan(&attemptID)
	if err != nil {
		return nil, fmt.Errorf("failed to persist transfer attempt: %w", err)
	}

	// Dispatch to provider
	tReq := TransferRequest{
		TransferID:     transferID,
		AttemptNumber:  attemptNumber,
		IdempotencyKey: attemptIdempotency.String(),
		BeneficiaryID:  bene.ID,
		AccountNumber:  plainAcc,
		IFSC:           bene.IFSC,
		AccountHolder:  bene.HolderName,
		AmountMinor:    tr.AmountMinor,
		Currency:       "INR",
		Purpose:        tr.PayoutType,
		Narration:      fmt.Sprintf("GM_%s_%s", tr.PayoutType[:4], transferID[:8]),
	}

	tResult, err := s.provider.InitiateTransfer(ctx, tReq)

	// Handle Outcome in Database and Financial Ledger
	if errors.Is(err, ErrProviderTimeout) {
		// Timeout: lock in processing / reconciliation_required without reversing ledger
		if txErr := s.db.Transaction(ctx, func(tx *sqlx.Tx) error {
			res1, err1 := tx.ExecContext(ctx, `UPDATE payout_transfer_attempts 
				SET status='timeout', error_code='TIMEOUT', error_message='Provider response timed out', completed_at=now() 
				WHERE id=$1`, attemptID)
			if err1 != nil {
				return fmt.Errorf("attempt update error: %w", err1)
			}
			rows1, _ := res1.RowsAffected()
			res2, err2 := tx.ExecContext(ctx, `UPDATE payout_transfers 
				SET status='reconciliation_required', updated_at=now() WHERE id=$1`, transferID)
			if err2 != nil {
				return fmt.Errorf("transfer update error: %w", err2)
			}
			rows2, _ := res2.RowsAffected()
			log.Printf("[TIMEOUT_HANDLER] attemptID=%s rows=%d, transferID=%s rows=%d", attemptID, rows1, transferID, rows2)
			return nil
		}); txErr != nil {
			log.Printf("[TIMEOUT_HANDLER] txErr: %v", txErr)
		}
		return &TransferResult{Status: "timeout", ErrorCode: "TIMEOUT", ErrorMessage: "Provider request timed out"}, ErrProviderTimeout
	} else if err != nil || tResult.Status == "failed" {
		// Failure before disbursement: Compensating journal restores payable liability
		failCode := tResult.ErrorCode
		failMsg := tResult.ErrorMessage
		if err != nil {
			failCode = "PROVIDER_ERROR"
			failMsg = err.Error()
		}

		_ = s.db.Transaction(ctx, func(tx *sqlx.Tx) error {
			var liabilityAccount string
			if tr.PayoutType == "merchant_settlement" {
				liabilityAccount = "merchant_payable_liability"
			} else {
				liabilityAccount = "rider_payable_liability"
			}

			var liabID, clearID string
			_ = tx.GetContext(ctx, &liabID, `SELECT id::text FROM financial_accounts WHERE account_code=$1 AND currency='INR'`, liabilityAccount)
			_ = tx.GetContext(ctx, &clearID, `SELECT id::text FROM financial_accounts WHERE account_code='payout_clearing_liability' AND currency='INR'`)

			lines := []financialledger.Line{
				{AccountID: clearID, Side: "debit", Amount: tr.AmountMinor, Memo: "Clear in-flight payout liability following transfer failure"},
				{AccountID: liabID, Side: "credit", Amount: tr.AmountMinor, Memo: "Restore partner payable liability following failed transfer"},
			}

			revJournal, _ := financialledger.PostJournalTx(ctx, tx, financialledger.PostInput{
				Currency:       "INR",
				SourceType:     "payout_failure_reversal",
				SourceID:       attemptID,
				SourceEvent:    "transfer_failed",
				IdempotencyKey: "payout-fail-rev:" + attemptID,
				Description:    fmt.Sprintf("Restore %s following failed transfer attempt %d", liabilityAccount, attemptNumber),
				ActorUserID:    actorID,
				Reason:         "Pre-disbursement transfer failure; restoring partner balance",
				Lines:          lines,
			})

			_, _ = tx.ExecContext(ctx, `UPDATE payout_transfer_attempts 
				SET status='failed', error_code=$2, error_message=$3, completed_at=now() WHERE id=$1`, attemptID, failCode, failMsg)
			_, _ = tx.ExecContext(ctx, `UPDATE payout_transfers 
				SET status='failed', reversal_journal_id=$2, updated_at=now() WHERE id=$1`, transferID, revJournal.ID)

			// Release batch items
			if tr.MerchantBatch.Valid {
				_, _ = tx.ExecContext(ctx, `UPDATE merchant_settlement_batch_items SET status='released' WHERE batch_id=$1`, tr.MerchantBatch.String)
			} else if tr.RiderBatch.Valid {
				_, _ = tx.ExecContext(ctx, `UPDATE rider_settlement_batch_items SET status='released' WHERE batch_id=$1`, tr.RiderBatch.String)
				_, _ = tx.ExecContext(ctx, `UPDATE rider_settlement_batches SET status='failed' WHERE id=$1`, tr.RiderBatch.String)
			}
			return nil
		})
		return &TransferResult{Status: "failed", ErrorCode: failCode, ErrorMessage: failMsg}, nil
	}

	// Success: Confirm disbursement in financial ledger
	err = s.db.Transaction(ctx, func(tx *sqlx.Tx) error {
		var disbursementAccount string
		if s.env == "qa" || s.env == "test" {
			disbursementAccount = "simulated_payout_disbursement_clearing"
		} else {
			disbursementAccount = "bank_disbursement_clearing"
		}

		var clearID, disbID string
		_ = tx.GetContext(ctx, &clearID, `SELECT id::text FROM financial_accounts WHERE account_code='payout_clearing_liability' AND currency='INR'`)
		_ = tx.GetContext(ctx, &disbID, `SELECT id::text FROM financial_accounts WHERE account_code=$1 AND currency='INR'`, disbursementAccount)

		lines := []financialledger.Line{
			{AccountID: clearID, Side: "debit", Amount: tr.AmountMinor, Memo: "Discharge payout clearing liability upon verified provider transfer"},
			{AccountID: disbID, Side: "credit", Amount: tr.AmountMinor, Memo: "Settlement disbursement confirmed by provider"},
		}

		disbJournal, err := financialledger.PostJournalTx(ctx, tx, financialledger.PostInput{
			Currency:       "INR",
			SourceType:     "payout_disbursement",
			SourceID:       attemptID,
			SourceEvent:    "transfer_succeeded",
			IdempotencyKey: "payout-disb:" + attemptID,
			Description:    fmt.Sprintf("Disbursement confirmed with UTR %s", tResult.UTR),
			ActorUserID:    actorID,
			Reason:         "Provider confirmed successful bank disbursement",
			Lines:          lines,
		})
		if err != nil {
			return err
		}

		_, _ = tx.ExecContext(ctx, `UPDATE payout_transfer_attempts 
			SET status='succeeded', provider_transfer_id=$2, utr_number=$3, completed_at=now() WHERE id=$1`,
			attemptID, tResult.ProviderTransferID, tResult.UTR)

		_, _ = tx.ExecContext(ctx, `UPDATE payout_transfers 
			SET status='succeeded', disbursement_journal_id=$2, completed_at=now(), updated_at=now() 
			WHERE id=$1`, transferID, disbJournal.ID)

		// Mark batch settled
		if tr.MerchantBatch.Valid {
			_, _ = tx.ExecContext(ctx, `UPDATE merchant_settlement_batch_items SET status='settled' WHERE batch_id=$1`, tr.MerchantBatch.String)
		} else if tr.RiderBatch.Valid {
			_, _ = tx.ExecContext(ctx, `UPDATE rider_settlement_batch_items SET status='settled' WHERE batch_id=$1`, tr.RiderBatch.String)
			_, _ = tx.ExecContext(ctx, `UPDATE rider_settlement_batches SET status='succeeded' WHERE id=$1`, tr.RiderBatch.String)
		}
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("failed to finalize disbursement: %w", err)
	}

	return &tResult, nil
}

// ReconcileTransfer queries provider for authoritative status and applies ledger resolution
func (s *Service) ReconcileTransfer(ctx context.Context, transferID, actorID string) (*TransferResult, error) {
	var attempt struct {
		ID                 string
		TransferID         string
		AttemptNumber      int
		ProviderTransferID sql.NullString
		Status             string
	}
	err := s.db.QueryRowxContext(ctx, `SELECT id::text, transfer_id::text, attempt_number, provider_transfer_id, status 
		FROM payout_transfer_attempts WHERE transfer_id=$1 ORDER BY attempt_number DESC LIMIT 1`, transferID).Scan(
		&attempt.ID, &attempt.TransferID, &attempt.AttemptNumber, &attempt.ProviderTransferID, &attempt.Status)
	if err != nil {
		return nil, fmt.Errorf("no attempt found for transfer %s: %w", transferID, err)
	}

	pID := fmt.Sprintf("qa_tx_%s_%d", transferID[:8], attempt.AttemptNumber)
	if attempt.ProviderTransferID.Valid && attempt.ProviderTransferID.String != "" {
		pID = attempt.ProviderTransferID.String
	}

	fResult, err := s.provider.FetchTransfer(ctx, pID)
	if err != nil {
		return nil, err
	}

	if fResult.Status == "succeeded" && attempt.Status != "succeeded" {
		var tr struct {
			AmountMinor   int64
			PayoutType    string
			MerchantBatch sql.NullString
			RiderBatch    sql.NullString
		}
		_ = s.db.QueryRowxContext(ctx, `SELECT amount_minor, payout_type, merchant_batch_id::text, rider_batch_id::text FROM payout_transfers WHERE id=$1`, transferID).Scan(
			&tr.AmountMinor, &tr.PayoutType, &tr.MerchantBatch, &tr.RiderBatch)

		_ = s.db.Transaction(ctx, func(tx *sqlx.Tx) error {
			var disbursementAccount string
			if s.env == "qa" || s.env == "test" {
				disbursementAccount = "simulated_payout_disbursement_clearing"
			} else {
				disbursementAccount = "bank_disbursement_clearing"
			}

			var clearID, disbID string
			_ = tx.GetContext(ctx, &clearID, `SELECT id::text FROM financial_accounts WHERE account_code='payout_clearing_liability' AND currency='INR'`)
			_ = tx.GetContext(ctx, &disbID, `SELECT id::text FROM financial_accounts WHERE account_code=$1 AND currency='INR'`, disbursementAccount)

			lines := []financialledger.Line{
				{AccountID: clearID, Side: "debit", Amount: tr.AmountMinor, Memo: "Discharge payout clearing liability via reconciliation resolution"},
				{AccountID: disbID, Side: "credit", Amount: tr.AmountMinor, Memo: "Settlement disbursement confirmed by provider status query"},
			}

			disbJournal, _ := financialledger.PostJournalTx(ctx, tx, financialledger.PostInput{
				Currency:       "INR",
				SourceType:     "payout_disbursement",
				SourceID:       attempt.ID,
				SourceEvent:    "reconciliation_succeeded",
				IdempotencyKey: "payout-recon-disb:" + attempt.ID,
				Description:    fmt.Sprintf("Disbursement resolved with UTR %s", fResult.UTR),
				ActorUserID:    actorID,
				Reason:         "Reconciliation resolved in-flight transfer to succeeded",
				Lines:          lines,
			})

			_, _ = tx.ExecContext(ctx, `UPDATE payout_transfer_attempts 
				SET status='succeeded', provider_transfer_id=$2, utr_number=$3, completed_at=now() WHERE id=$1`,
				attempt.ID, fResult.ProviderTransferID, fResult.UTR)

			_, _ = tx.ExecContext(ctx, `UPDATE payout_transfers 
				SET status='succeeded', disbursement_journal_id=$2, completed_at=now(), updated_at=now() 
				WHERE id=$1`, transferID, disbJournal.ID)

			if tr.MerchantBatch.Valid {
				_, _ = tx.ExecContext(ctx, `UPDATE merchant_settlement_batch_items SET status='settled' WHERE batch_id=$1`, tr.MerchantBatch.String)
			} else if tr.RiderBatch.Valid {
				_, _ = tx.ExecContext(ctx, `UPDATE rider_settlement_batch_items SET status='settled' WHERE batch_id=$1`, tr.RiderBatch.String)
				_, _ = tx.ExecContext(ctx, `UPDATE rider_settlement_batches SET status='reconciled' WHERE id=$1`, tr.RiderBatch.String)
			}
			return nil
		})
	}

	return &fResult, nil
}

// ProcessWebhook handles idempotent webhook delivery including post-success reversals
func (s *Service) ProcessWebhook(ctx context.Context, headers http.Header, rawBody []byte) error {
	event, err := s.provider.VerifyWebhook(ctx, headers, rawBody)
	if err != nil {
		return err
	}

	payloadHash := sha256.Sum256(rawBody)

	// Idempotent webhook receipt
	var inserted bool
	err = s.db.Transaction(ctx, func(tx *sqlx.Tx) error {
		var existingID string
		err := tx.QueryRowxContext(ctx, `INSERT INTO payout_provider_events(
			provider, provider_event_id, transfer_id, event_type, payload_sha256, processing_state
		) VALUES($1, $2, $3, $4, $5, 'received') 
		ON CONFLICT(provider, provider_event_id) DO NOTHING RETURNING id::text`,
			event.Provider, event.EventID, event.TransferID, event.EventType, payloadHash[:]).Scan(&existingID)
		if err == nil {
			inserted = true
			return nil
		}
		if errors.Is(err, sql.ErrNoRows) {
			// Duplicate webhook!
			inserted = false
			return nil
		}
		return err
	})
	if err != nil {
		return err
	}
	if !inserted {
		// Duplicate webhook already processed; no-op
		return nil
	}

	// Look up transfer record
	var tr struct {
		AmountMinor   int64
		PayoutType    string
		MerchantBatch sql.NullString
		RiderBatch    sql.NullString
		Status        string
		RequestedBy   string
	}
	err = s.db.QueryRowxContext(ctx, `SELECT amount_minor, payout_type, merchant_batch_id::text, rider_batch_id::text, status, requested_by::text 
		FROM payout_transfers WHERE id=$1 FOR UPDATE`, event.TransferID).Scan(
		&tr.AmountMinor, &tr.PayoutType, &tr.MerchantBatch, &tr.RiderBatch, &tr.Status, &tr.RequestedBy)
	if err != nil {
		// Unknown transfer or lookup error -> quarantine event
		_, _ = s.db.ExecContext(ctx, `UPDATE payout_provider_events SET processing_state='quarantined' WHERE provider=$1 AND provider_event_id=$2`, event.Provider, event.EventID)
		return nil
	}

	// 1. Reversal Event
	if event.EventType == "payout.reversed" || event.Status == "reversed" {
		if tr.Status == "reversed" {
			// Duplicate reversal event
			_, _ = s.db.ExecContext(ctx, `UPDATE payout_provider_events SET processing_state='duplicate' WHERE provider=$1 AND provider_event_id=$2`, event.Provider, event.EventID)
			return nil
		}
		if tr.Status != "succeeded" {
			// Contradictory event: cannot reverse a transfer that never succeeded
			_, _ = s.db.ExecContext(ctx, `UPDATE payout_provider_events SET processing_state='quarantined' WHERE provider=$1 AND provider_event_id=$2`, event.Provider, event.EventID)
			return nil
		}

		// Valid post-success reversal
		return s.db.Transaction(ctx, func(tx *sqlx.Tx) error {
			var liabilityAccount, returnClearingAccount string
			if tr.PayoutType == "merchant_settlement" {
				liabilityAccount = "merchant_payable_liability"
			} else {
				liabilityAccount = "rider_payable_liability"
			}

			if s.env == "qa" || s.env == "test" {
				returnClearingAccount = "simulated_payout_disbursement_clearing"
			} else {
				returnClearingAccount = "payout_return_clearing"
			}

			var liabID, retID string
			_ = tx.GetContext(ctx, &liabID, `SELECT id::text FROM financial_accounts WHERE account_code=$1 AND currency='INR'`, liabilityAccount)
			_ = tx.GetContext(ctx, &retID, `SELECT id::text FROM financial_accounts WHERE account_code=$1 AND currency='INR'`, returnClearingAccount)

			lines := []financialledger.Line{
				{AccountID: retID, Side: "debit", Amount: tr.AmountMinor, Memo: "Debit return clearing following bank reversal"},
				{AccountID: liabID, Side: "credit", Amount: tr.AmountMinor, Memo: "Restore partner payable balance following bank transfer reversal"},
			}

			revJournal, err := financialledger.PostJournalTx(ctx, tx, financialledger.PostInput{
				Currency:       "INR",
				SourceType:     "payout_post_disbursement_reversal",
				SourceID:       event.EventID,
				SourceEvent:    "transfer_reversed",
				IdempotencyKey: "payout-post-rev:" + event.EventID,
				Description:    fmt.Sprintf("Post-disbursement reversal for transfer %s", event.TransferID),
				ActorUserID:    tr.RequestedBy,
				Reason:         "Bank transfer returned after clearance; restoring partner payable",
				Lines:          lines,
			})
			if err != nil {
				return err
			}

			if _, err = tx.ExecContext(ctx, `UPDATE payout_transfers 
				SET status='reversed', reversal_journal_id=$2, updated_at=now() 
				WHERE id=$1`, event.TransferID, revJournal.ID); err != nil {
				return fmt.Errorf("failed to update transfer status to reversed: %w", err)
			}

			if _, err = tx.ExecContext(ctx, `UPDATE payout_provider_events 
				SET processing_state='processed' WHERE provider=$1 AND provider_event_id=$2`, event.Provider, event.EventID); err != nil {
				return fmt.Errorf("failed to update provider event state: %w", err)
			}
			return nil
		})
	}

	// 2. Failure Event
	if event.EventType == "payout.failed" || event.Status == "failed" {
		if tr.Status == "succeeded" {
			// Contradictory: Success followed by stale failure!
			_, _ = s.db.ExecContext(ctx, `UPDATE payout_provider_events SET processing_state='quarantined' WHERE provider=$1 AND provider_event_id=$2`, event.Provider, event.EventID)
			return nil
		}
		if tr.Status == "failed" {
			// Duplicate failure event
			_, _ = s.db.ExecContext(ctx, `UPDATE payout_provider_events SET processing_state='duplicate' WHERE provider=$1 AND provider_event_id=$2`, event.Provider, event.EventID)
			return nil
		}
		if tr.Status == "reconciliation_required" || tr.Status == "processing" {
			// Delayed failure after timeout/processing: restore partner liability
			return s.db.Transaction(ctx, func(tx *sqlx.Tx) error {
				var liabilityAccount string
				if tr.PayoutType == "merchant_settlement" {
					liabilityAccount = "merchant_payable_liability"
				} else {
					liabilityAccount = "rider_payable_liability"
				}

				var liabID, clearID string
				_ = tx.GetContext(ctx, &liabID, `SELECT id::text FROM financial_accounts WHERE account_code=$1 AND currency='INR'`, liabilityAccount)
				_ = tx.GetContext(ctx, &clearID, `SELECT id::text FROM financial_accounts WHERE account_code='payout_clearing_liability' AND currency='INR'`)

				lines := []financialledger.Line{
					{AccountID: clearID, Side: "debit", Amount: tr.AmountMinor, Memo: "Clear in-flight payout liability following transfer failure"},
					{AccountID: liabID, Side: "credit", Amount: tr.AmountMinor, Memo: "Restore partner payable liability following failed transfer"},
				}

				revJournal, err := financialledger.PostJournalTx(ctx, tx, financialledger.PostInput{
					Currency:       "INR",
					SourceType:     "payout_failure_reversal",
					SourceID:       event.EventID,
					SourceEvent:    "transfer_failed",
					IdempotencyKey: "payout-fail-rev:" + event.EventID,
					Description:    fmt.Sprintf("Restore %s following delayed transfer failure", liabilityAccount),
					ActorUserID:    tr.RequestedBy,
					Reason:         "Delayed transfer failure confirmed by provider; restoring partner balance",
					Lines:          lines,
				})
				if err != nil {
					return err
				}

				_, _ = tx.ExecContext(ctx, `UPDATE payout_transfers 
					SET status='failed', reversal_journal_id=$2, updated_at=now() WHERE id=$1`, event.TransferID, revJournal.ID)

				if tr.MerchantBatch.Valid {
					_, _ = tx.ExecContext(ctx, `UPDATE merchant_settlement_batch_items SET status='released' WHERE batch_id=$1`, tr.MerchantBatch.String)
				} else if tr.RiderBatch.Valid {
					_, _ = tx.ExecContext(ctx, `UPDATE rider_settlement_batch_items SET status='released' WHERE batch_id=$1`, tr.RiderBatch.String)
					_, _ = tx.ExecContext(ctx, `UPDATE rider_settlement_batches SET status='failed' WHERE id=$1`, tr.RiderBatch.String)
				}

				_, _ = tx.ExecContext(ctx, `UPDATE payout_provider_events 
					SET processing_state='processed' WHERE provider=$1 AND provider_event_id=$2`, event.Provider, event.EventID)
				return nil
			})
		}
		// Any other state -> quarantine
		_, _ = s.db.ExecContext(ctx, `UPDATE payout_provider_events SET processing_state='quarantined' WHERE provider=$1 AND provider_event_id=$2`, event.Provider, event.EventID)
		return nil
	}

	// 3. Success Event
	if event.EventType == "payout.succeeded" || event.Status == "succeeded" {
		if tr.Status == "failed" {
			// Highly Contradictory: Failure followed by unexpected late success!
			_, _ = s.db.ExecContext(ctx, `UPDATE payout_provider_events SET processing_state='quarantined' WHERE provider=$1 AND provider_event_id=$2`, event.Provider, event.EventID)
			return nil
		}
		if tr.Status == "succeeded" {
			// Duplicate success event
			_, _ = s.db.ExecContext(ctx, `UPDATE payout_provider_events SET processing_state='duplicate' WHERE provider=$1 AND provider_event_id=$2`, event.Provider, event.EventID)
			return nil
		}
		if tr.Status == "reconciliation_required" || tr.Status == "processing" {
			// Delayed success after timeout: confirm disbursement
			return s.db.Transaction(ctx, func(tx *sqlx.Tx) error {
				var disbursementAccount string
				if s.env == "qa" || s.env == "test" {
					disbursementAccount = "simulated_payout_disbursement_clearing"
				} else {
					disbursementAccount = "bank_disbursement_clearing"
				}

				var clearID, disbID string
				_ = tx.GetContext(ctx, &clearID, `SELECT id::text FROM financial_accounts WHERE account_code='payout_clearing_liability' AND currency='INR'`)
				_ = tx.GetContext(ctx, &disbID, `SELECT id::text FROM financial_accounts WHERE account_code=$1 AND currency='INR'`, disbursementAccount)

				lines := []financialledger.Line{
					{AccountID: clearID, Side: "debit", Amount: tr.AmountMinor, Memo: "Discharge payout clearing liability upon verified provider transfer"},
					{AccountID: disbID, Side: "credit", Amount: tr.AmountMinor, Memo: "Settlement disbursement confirmed by provider"},
				}

				disbJournal, err := financialledger.PostJournalTx(ctx, tx, financialledger.PostInput{
					Currency:       "INR",
					SourceType:     "payout_disbursement",
					SourceID:       event.EventID,
					SourceEvent:    "transfer_succeeded",
					IdempotencyKey: "payout-disb:" + event.EventID,
					Description:    fmt.Sprintf("Disbursement confirmed with UTR %s", event.UTR),
					ActorUserID:    tr.RequestedBy,
					Reason:         "Provider confirmed delayed successful bank disbursement",
					Lines:          lines,
				})
				if err != nil {
					return err
				}

				_, _ = tx.ExecContext(ctx, `UPDATE payout_transfers 
					SET status='succeeded', disbursement_journal_id=$2, completed_at=now(), updated_at=now() 
					WHERE id=$1`, event.TransferID, disbJournal.ID)

				if tr.MerchantBatch.Valid {
					_, _ = tx.ExecContext(ctx, `UPDATE merchant_settlement_batch_items SET status='settled' WHERE batch_id=$1`, tr.MerchantBatch.String)
				} else if tr.RiderBatch.Valid {
					_, _ = tx.ExecContext(ctx, `UPDATE rider_settlement_batch_items SET status='settled' WHERE batch_id=$1`, tr.RiderBatch.String)
					_, _ = tx.ExecContext(ctx, `UPDATE rider_settlement_batches SET status='succeeded' WHERE id=$1`, tr.RiderBatch.String)
				}

				_, _ = tx.ExecContext(ctx, `UPDATE payout_provider_events 
					SET processing_state='processed' WHERE provider=$1 AND provider_event_id=$2`, event.Provider, event.EventID)
				return nil
			})
		}
		// Any other state -> quarantine
		_, _ = s.db.ExecContext(ctx, `UPDATE payout_provider_events SET processing_state='quarantined' WHERE provider=$1 AND provider_event_id=$2`, event.Provider, event.EventID)
		return nil
	}

	// 4. Unknown or Unhandled Provider Event -> Quarantine
	_, _ = s.db.ExecContext(ctx, `UPDATE payout_provider_events SET processing_state='quarantined' WHERE provider=$1 AND provider_event_id=$2`, event.Provider, event.EventID)
	return nil
}

// ApprovePayoutTransfer handles independent two-person approval for payout transfers
func (s *Service) ApprovePayoutTransfer(ctx context.Context, transferID, actorID, reason string) error {
	return s.db.Transaction(ctx, func(tx *sqlx.Tx) error {
		var requestedBy string
		var status string
		err := tx.QueryRowxContext(ctx, `SELECT requested_by::text, status FROM payout_transfers WHERE id=$1 FOR UPDATE`, transferID).Scan(&requestedBy, &status)
		if err != nil {
			return err
		}
		if requestedBy == actorID {
			return fmt.Errorf("SELF_APPROVAL_FORBIDDEN: requester cannot approve their own transfer")
		}
		if status != "ready" && status != "pending_review" {
			return fmt.Errorf("transfer cannot be approved in state: %s", status)
		}
		_, err = tx.ExecContext(ctx, `UPDATE payout_transfers 
			SET approved_by=$2, updated_at=now() WHERE id=$1`, transferID, actorID)
		return err
	})
}
