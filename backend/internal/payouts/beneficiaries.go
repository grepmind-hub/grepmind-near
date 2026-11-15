package payouts

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"regexp"
	"strings"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
)

var (
	ifscRegex = regexp.MustCompile(`^[A-Z]{4}0[A-Z0-9]{6}$`)
)

func getEncryptionKeys() ([]byte, string, map[string][]byte) {
	historical := make(map[string][]byte)
	k1 := os.Getenv("PAYOUT_BENEFICIARY_ENCRYPTION_KEY")
	if len(k1) < 32 {
		k1 = "grepmind_qa_bene_aes_enc_key_32b"
	}
	historical["v1"] = []byte(k1[:32])

	currentVersion := "v1"
	currentKey := historical["v1"]

	k2 := os.Getenv("PAYOUT_BENEFICIARY_ENCRYPTION_KEY_V2")
	if len(k2) >= 32 {
		historical["v2"] = []byte(k2[:32])
		currentKey = historical["v2"]
		currentVersion = "v2"
	}
	return currentKey, currentVersion, historical
}

func getLookupKey() []byte {
	k := os.Getenv("PAYOUT_BENEFICIARY_LOOKUP_KEY")
	if len(k) >= 32 {
		return []byte(k[:32])
	}
	// Deterministic 32-byte fallback key for isolated QA only
	return []byte("grepmind_qa_bene_hmac_lookup_32b")
}

func encryptAccountNumber(plaintext string) ([]byte, error) {
	key, version, _ := getEncryptionKeys()
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return nil, err
	}
	sealed := gcm.Seal(nonce, nonce, []byte(plaintext), nil)
	// Versioned envelope format: version:sealed_bytes
	result := append([]byte(version+":"), sealed...)
	return result, nil
}

func decryptAccountNumber(ciphertext []byte) (string, error) {
	_, defaultVersion, keys := getEncryptionKeys()
	decryptWithKey := func(key, data []byte) (string, error) {
		block, err := aes.NewCipher(key)
		if err != nil {
			return "", err
		}
		gcm, err := cipher.NewGCM(block)
		if err != nil {
			return "", err
		}
		nonceSize := gcm.NonceSize()
		if len(data) < nonceSize {
			return "", errors.New("malformed ciphertext")
		}
		nonce, ciphertextActual := data[:nonceSize], data[nonceSize:]
		plaintext, err := gcm.Open(nil, nonce, ciphertextActual, nil)
		if err != nil {
			return "", err
		}
		return string(plaintext), nil
	}

	// Check if versioned prefix exists
	if len(ciphertext) > 3 && ciphertext[2] == ':' {
		version := string(ciphertext[:2])
		payload := ciphertext[3:]
		if key, exists := keys[version]; exists {
			return decryptWithKey(key, payload)
		}
		return "", fmt.Errorf("unknown encryption key version: %s", version)
	}

	// Fallback to legacy unversioned format using v1 key
	if v1Key, exists := keys[defaultVersion]; exists {
		return decryptWithKey(v1Key, ciphertext)
	}
	return "", errors.New("no valid encryption key available for decryption")
}

func hashAccountNumber(accountNumber string) []byte {
	mac := hmac.New(sha256.New, getLookupKey())
	mac.Write([]byte(strings.TrimSpace(accountNumber)))
	return mac.Sum(nil)
}

func maskAccountNumber(accountNumber string) string {
	clean := strings.TrimSpace(accountNumber)
	if len(clean) <= 4 {
		return "XXXX" + clean
	}
	last4 := clean[len(clean)-4:]
	return strings.Repeat("X", len(clean)-4) + last4
}

type RegisterBeneficiaryRequest struct {
	AccountHolderName string `json:"account_holder_name"`
	AccountNumber     string `json:"account_number"`
	IFSC              string `json:"ifsc"`
	IFSCCode          string `json:"ifsc_code"`
	BankName          string `json:"bank_name"`
}

type BeneficiaryResponse struct {
	ID                 string `json:"id"`
	BeneficiaryType    string `json:"beneficiary_type"`
	BusinessID         string `json:"business_id,omitempty"`
	RiderUserID        string `json:"rider_user_id,omitempty"`
	AccountHolderName  string `json:"account_holder_name"`
	AccountNumberMasked string `json:"account_number_masked"`
	IFSC               string `json:"ifsc"`
	IFSCCode           string `json:"ifsc_code,omitempty"`
	BankName           string `json:"bank_name"`
	VerificationStatus string `json:"verification_status"`
	VerifiedAt         string `json:"verified_at,omitempty"`
	RejectionReason    string `json:"rejection_reason,omitempty"`
}

func (s *Service) RegisterMerchantBeneficiary(w http.ResponseWriter, r *http.Request, actorID, businessID string) {
	var in RegisterBeneficiaryRequest
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeError(w, 400, "INVALID_REQUEST", "Invalid request body")
		return
	}
	in.AccountHolderName = strings.TrimSpace(in.AccountHolderName)
	in.AccountNumber = strings.TrimSpace(in.AccountNumber)
	if in.IFSC == "" {
		in.IFSC = in.IFSCCode
	}
	in.IFSC = strings.ToUpper(strings.TrimSpace(in.IFSC))
	in.BankName = strings.TrimSpace(in.BankName)

	if len(in.AccountHolderName) < 3 || len(in.AccountNumber) < 8 || len(in.AccountNumber) > 20 || !ifscRegex.MatchString(in.IFSC) || len(in.BankName) < 2 {
		writeError(w, 400, "VALIDATION_FAILED", "Valid account holder name, account number (8-20 digits), bank name, and Indian IFSC code are required")
		return
	}

	encryptedAccount, err := encryptAccountNumber(in.AccountNumber)
	if err != nil {
		writeError(w, 500, "ENCRYPTION_ERROR", "Failed to secure account details")
		return
	}
	accountHMAC := hashAccountNumber(in.AccountNumber)
	masked := maskAccountNumber(in.AccountNumber)

	var id string
	err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		// Deactivate any existing active or prior beneficiary for this merchant
		_, err := tx.ExecContext(r.Context(), `UPDATE bank_beneficiaries 
			SET verification_status='deactivated', updated_at=now() 
			WHERE business_id=$1 AND verification_status != 'deactivated'`, businessID)
		if err != nil {
			return err
		}

		err = tx.QueryRowxContext(r.Context(), `INSERT INTO bank_beneficiaries(
			beneficiary_type, business_id, account_holder_name, account_number_encrypted, 
			account_number_masked, account_number_hmac, ifsc_code, bank_name, 
			verification_status, created_by
		) VALUES('merchant', $1, $2, $3, $4, $5, $6, $7, 'pending_verification', $8)
		RETURNING id::text`, businessID, in.AccountHolderName, encryptedAccount, masked, accountHMAC, in.IFSC, in.BankName, actorID).Scan(&id)
		if err != nil {
			return err
		}

		_, err = tx.ExecContext(r.Context(), `INSERT INTO bank_beneficiary_audit_events(
			beneficiary_id, actor_user_id, event_type, reason, metadata
		) VALUES($1, $2, 'created', 'Merchant registered new bank details', jsonb_build_object('masked_account', $3::text, 'ifsc', $4::text))`,
			id, actorID, masked, in.IFSC)
		return err
	})
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Failed to save bank beneficiary: "+err.Error())
		return
	}

	writeJSON(w, 201, map[string]any{
		"id":                  id,
		"business_id":         businessID,
		"account_holder_name": in.AccountHolderName,
		"account_masked":      masked,
		"ifsc":                in.IFSC,
		"bank_name":           in.BankName,
		"verification_status": "pending_verification",
	})
}

func (s *Service) RegisterRiderBeneficiary(w http.ResponseWriter, r *http.Request, riderID string) {
	var in RegisterBeneficiaryRequest
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeError(w, 400, "INVALID_REQUEST", "Invalid request body")
		return
	}
	in.AccountHolderName = strings.TrimSpace(in.AccountHolderName)
	in.AccountNumber = strings.TrimSpace(in.AccountNumber)
	if in.IFSC == "" {
		in.IFSC = in.IFSCCode
	}
	in.IFSC = strings.ToUpper(strings.TrimSpace(in.IFSC))
	in.BankName = strings.TrimSpace(in.BankName)

	if len(in.AccountHolderName) < 3 || len(in.AccountNumber) < 8 || len(in.AccountNumber) > 20 || !ifscRegex.MatchString(in.IFSC) || len(in.BankName) < 2 {
		writeError(w, 400, "VALIDATION_FAILED", "Valid account holder name, account number (8-20 digits), bank name, and Indian IFSC code are required")
		return
	}

	encryptedAccount, err := encryptAccountNumber(in.AccountNumber)
	if err != nil {
		writeError(w, 500, "ENCRYPTION_ERROR", "Failed to secure account details")
		return
	}
	accountHMAC := hashAccountNumber(in.AccountNumber)
	masked := maskAccountNumber(in.AccountNumber)

	var id string
	err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		// Deactivate any existing active or prior beneficiary for this rider
		_, err := tx.ExecContext(r.Context(), `UPDATE bank_beneficiaries 
			SET verification_status='deactivated', updated_at=now() 
			WHERE rider_user_id=$1 AND verification_status != 'deactivated'`, riderID)
		if err != nil {
			return err
		}

		err = tx.QueryRowxContext(r.Context(), `INSERT INTO bank_beneficiaries(
			beneficiary_type, rider_user_id, account_holder_name, account_number_encrypted, 
			account_number_masked, account_number_hmac, ifsc_code, bank_name, 
			verification_status, created_by
		) VALUES('rider', $1, $2, $3, $4, $5, $6, $7, 'pending_verification', $1)
		RETURNING id::text`, riderID, in.AccountHolderName, encryptedAccount, masked, accountHMAC, in.IFSC, in.BankName).Scan(&id)
		if err != nil {
			return err
		}

		_, err = tx.ExecContext(r.Context(), `INSERT INTO bank_beneficiary_audit_events(
			beneficiary_id, actor_user_id, event_type, reason, metadata
		) VALUES($1, $2, 'created', 'Rider registered new bank details', jsonb_build_object('masked_account', $3::text, 'ifsc', $4::text))`,
			id, riderID, masked, in.IFSC)
		return err
	})
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Failed to save bank beneficiary: "+err.Error())
		return
	}

	writeJSON(w, 201, map[string]any{
		"id":                  id,
		"rider_user_id":       riderID,
		"account_holder_name": in.AccountHolderName,
		"account_masked":      masked,
		"ifsc":                in.IFSC,
		"bank_name":           in.BankName,
		"verification_status": "pending_verification",
	})
}

func (s *Service) GetMerchantBeneficiary(w http.ResponseWriter, r *http.Request, businessID string) {
	var resp BeneficiaryResponse
	var verifiedAt, rejection sql.NullString
	err := s.db.QueryRowxContext(r.Context(), `SELECT 
		id::text, beneficiary_type, COALESCE(business_id::text,''), account_holder_name, 
		account_number_masked, ifsc_code, bank_name, verification_status, 
		verified_at::text, rejection_reason 
		FROM bank_beneficiaries 
		WHERE business_id=$1 AND verification_status IN ('pending_verification','verified')
		ORDER BY created_at DESC LIMIT 1`, businessID).Scan(
		&resp.ID, &resp.BeneficiaryType, &resp.BusinessID, &resp.AccountHolderName,
		&resp.AccountNumberMasked, &resp.IFSC, &resp.BankName, &resp.VerificationStatus,
		&verifiedAt, &rejection)

	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, 404, "NOT_FOUND", "No active bank account registered for this merchant")
		return
	} else if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Failed to load bank beneficiary: "+err.Error())
		return
	}
	if verifiedAt.Valid {
		resp.VerifiedAt = verifiedAt.String
	}
	if rejection.Valid {
		resp.RejectionReason = rejection.String
	}

	writeJSON(w, 200, resp)
}

func (s *Service) GetRiderBeneficiary(w http.ResponseWriter, r *http.Request, riderID string) {
	var resp BeneficiaryResponse
	var verifiedAt, rejection sql.NullString
	err := s.db.QueryRowxContext(r.Context(), `SELECT 
		id::text, beneficiary_type, COALESCE(rider_user_id::text,''), account_holder_name, 
		account_number_masked, ifsc_code, bank_name, verification_status, 
		verified_at::text, rejection_reason 
		FROM bank_beneficiaries 
		WHERE rider_user_id=$1 AND verification_status IN ('pending_verification','verified')
		ORDER BY created_at DESC LIMIT 1`, riderID).Scan(
		&resp.ID, &resp.BeneficiaryType, &resp.RiderUserID, &resp.AccountHolderName,
		&resp.AccountNumberMasked, &resp.IFSC, &resp.BankName, &resp.VerificationStatus,
		&verifiedAt, &rejection)

	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, 404, "NOT_FOUND", "No active bank account registered for this rider")
		return
	} else if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Failed to load bank beneficiary: "+err.Error())
		return
	}
	if verifiedAt.Valid {
		resp.VerifiedAt = verifiedAt.String
	}
	if rejection.Valid {
		resp.RejectionReason = rejection.String
	}

	writeJSON(w, 200, resp)
}

func (s *Service) GetBeneficiary(w http.ResponseWriter, r *http.Request, beneID string) {
	if _, err := uuid.Parse(beneID); err != nil {
		writeError(w, 400, "INVALID_ID", "Beneficiary ID must be a UUID")
		return
	}
	var resp BeneficiaryResponse
	var verifiedAt, rejection sql.NullString
	err := s.db.QueryRowxContext(r.Context(), `SELECT 
		id::text, beneficiary_type, COALESCE(business_id::text,''), COALESCE(rider_user_id::text,''),
		account_holder_name, account_number_masked, ifsc_code, bank_name, verification_status, 
		verified_at::text, rejection_reason 
		FROM bank_beneficiaries 
		WHERE id=$1`, beneID).Scan(
		&resp.ID, &resp.BeneficiaryType, &resp.BusinessID, &resp.RiderUserID,
		&resp.AccountHolderName, &resp.AccountNumberMasked, &resp.IFSC, &resp.BankName,
		&resp.VerificationStatus, &verifiedAt, &rejection)

	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, 404, "NOT_FOUND", "Bank beneficiary not found")
		return
	} else if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Failed to load bank beneficiary: "+err.Error())
		return
	}
	if verifiedAt.Valid {
		resp.VerifiedAt = verifiedAt.String
	}
	if rejection.Valid {
		resp.RejectionReason = rejection.String
	}

	writeJSON(w, 200, resp)
}

func (s *Service) VerifyBeneficiary(w http.ResponseWriter, r *http.Request, actorID, beneID string) {
	if _, err := uuid.Parse(beneID); err != nil {
		writeError(w, 400, "INVALID_ID", "Beneficiary ID must be a UUID")
		return
	}

	var bene struct {
		ID            string
		HolderName    string
		EncryptedAcc  []byte
		IFSC          string
		CurrentStatus string
	}
	err := s.db.QueryRowxContext(r.Context(), `SELECT id::text, account_holder_name, account_number_encrypted, ifsc_code, verification_status 
		FROM bank_beneficiaries WHERE id=$1`, beneID).Scan(&bene.ID, &bene.HolderName, &bene.EncryptedAcc, &bene.IFSC, &bene.CurrentStatus)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, 404, "NOT_FOUND", "Beneficiary not found")
		return
	} else if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Database error: "+err.Error())
		return
	}

	plainAcc, err := decryptAccountNumber(bene.EncryptedAcc)
	if err != nil {
		writeError(w, 500, "DECRYPTION_ERROR", "Failed to decrypt beneficiary account")
		return
	}

	// Call provider validation
	vResult, err := s.provider.ValidateBeneficiary(r.Context(), BeneficiaryValidationRequest{
		BeneficiaryID: beneID,
		AccountHolder: bene.HolderName,
		AccountNumber: plainAcc,
		IFSC:          bene.IFSC,
	})
	if err != nil {
		writeError(w, 502, "PROVIDER_ERROR", "Beneficiary provider verification failed: "+err.Error())
		return
	}

	evidenceJSON, _ := json.Marshal(vResult.Evidence)

	err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if vResult.Status == "verified" {
			_, err := tx.ExecContext(r.Context(), `UPDATE bank_beneficiaries 
				SET verification_status='verified', provider_beneficiary_id=$2, verification_evidence=$3, 
				    verified_at=now(), rejection_reason=NULL, updated_at=now() 
				WHERE id=$1`, beneID, vResult.ProviderBeneficiaryID, evidenceJSON)
			if err != nil {
				return err
			}
			_, err = tx.ExecContext(r.Context(), `INSERT INTO bank_beneficiary_audit_events(
				beneficiary_id, actor_user_id, event_type, reason, metadata
			) VALUES($1, $2, 'verified', 'Penny-drop verification confirmed by provider', $3)`,
				beneID, actorID, evidenceJSON)
			return err
		} else {
			_, err := tx.ExecContext(r.Context(), `UPDATE bank_beneficiaries 
				SET verification_status='rejected', rejection_reason=$2, verification_evidence=$3, updated_at=now() 
				WHERE id=$1`, beneID, vResult.FailureReason, evidenceJSON)
			if err != nil {
				return err
			}
			_, err = tx.ExecContext(r.Context(), `INSERT INTO bank_beneficiary_audit_events(
				beneficiary_id, actor_user_id, event_type, reason, metadata
			) VALUES($1, $2, 'rejected', $3, $4)`,
				beneID, actorID, vResult.FailureReason, evidenceJSON)
			return err
		}
	})
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Failed to update beneficiary status: "+err.Error())
		return
	}

	writeJSON(w, 200, map[string]any{
		"id":                  beneID,
		"verification_status": vResult.Status,
		"provider_bene_id":    vResult.ProviderBeneficiaryID,
		"rejection_reason":    vResult.FailureReason,
	})
}
