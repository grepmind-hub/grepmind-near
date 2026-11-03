package businessclaims

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jmoiron/sqlx"
	"grepmind-near/backend/pkg/database"
)

type Service struct{ db *database.DB }

func NewService(db *database.DB) *Service { return &Service{db: db} }

type response map[string]interface{}

func writeJSON(w http.ResponseWriter, status int, value interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, map[string]interface{}{"error": map[string]string{"code": code, "message": message}})
}

// Search exposes only approved public listing fields and limits scope to launch cities.
func (s *Service) Search(w http.ResponseWriter, r *http.Request, userID string) {
	query := strings.TrimSpace(r.URL.Query().Get("query"))
	if !validateSearchQuery(query) {
		writeError(w, http.StatusBadRequest, "INVALID_QUERY", "Search text must be between 2 and 80 characters.")
		return
	}
	rows, err := s.db.QueryxContext(r.Context(), `
		SELECT b.id, b.name, b.category_slug, COALESCE(c.name, b.category_slug),
	       COALESCE(b.locality, ''), COALESCE(b.city, ''), COALESCE(b.cover_photo_url, '')
		FROM businesses b
		LEFT JOIN categories c ON c.slug = b.category_slug
		WHERE b.status = 'approved'
		  AND EXISTS (SELECT 1 FROM users claimant WHERE claimant.id=$2 AND claimant.status='active')
		  AND lower(b.city) IN ('cuttack', 'jajpur', 'jajpur town')
		  AND (b.name ILIKE $1 ESCAPE E'\\' OR COALESCE(b.locality, '') ILIKE $1 ESCAPE E'\\'
		       OR COALESCE(c.name, b.category_slug) ILIKE $1 ESCAPE E'\\')
		  AND NOT EXISTS (SELECT 1 FROM business_claim_requests cr WHERE cr.business_id=b.id AND cr.status='pending')
		  AND NOT EXISTS (SELECT 1 FROM businesses own WHERE own.id=b.id AND own.owner_user_id=$2)
		  AND NOT EXISTS (SELECT 1 FROM business_members bm WHERE bm.business_id=b.id AND bm.user_id=$2 AND bm.status='active')
		ORDER BY b.name, b.id LIMIT 30`, "%"+escapeLike(query)+"%", userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to search business listings.")
		return
	}
	defer rows.Close()
	type listing struct {
		ID           string `json:"id"`
		Name         string `json:"name"`
		CategorySlug string `json:"category_slug"`
		Category     string `json:"category"`
		Locality     string `json:"locality"`
		City         string `json:"city"`
		ImageURL     string `json:"image_url,omitempty"`
	}
	data := make([]listing, 0)
	for rows.Next() {
		var item listing
		if err := rows.Scan(&item.ID, &item.Name, &item.CategorySlug, &item.Category, &item.Locality, &item.City, &item.ImageURL); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to read business listings.")
			return
		}
		data = append(data, item)
	}
	if err := rows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to read business listings.")
		return
	}
	writeJSON(w, http.StatusOK, response{"data": data, "meta": map[string]interface{}{"count": len(data)}})
}

func escapeLike(value string) string {
	return strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`).Replace(value)
}

func (s *Service) Submit(w http.ResponseWriter, r *http.Request, userID string) {
	var req struct {
		Message string `json:"message"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 9000)).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "A valid claim statement is required.")
		return
	}
	req.Message = strings.TrimSpace(req.Message)
	if utf8.RuneCountInString(req.Message) < 10 || utf8.RuneCountInString(req.Message) > 2000 {
		writeError(w, http.StatusBadRequest, "INVALID_MESSAGE", "Please provide 10 to 2000 characters explaining your relationship to this business.")
		return
	}
	businessID := r.PathValue("id")
	if _, err := uuid.Parse(businessID); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_BUSINESS_ID", "A valid business identifier is required.")
		return
	}
	var requestID string
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		// Serialize per claimant before enforcing the abuse-control window.
		if _, err := tx.ExecContext(r.Context(), `SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`, userID); err != nil {
			return err
		}
		var recent int
		if err := tx.GetContext(r.Context(), &recent, `SELECT COUNT(*) FROM business_claim_requests WHERE claimant_user_id=$1 AND created_at>now()-interval '24 hours'`, userID); err != nil {
			return err
		}
		if !claimRateLimitAllows(recent) {
			return errRateLimited
		}
		return tx.QueryRowxContext(r.Context(), `
		INSERT INTO business_claim_requests (business_id, claimant_user_id, claimant_message)
		SELECT b.id, $2, $3 FROM businesses b
		WHERE b.id=$1 AND b.status='approved' AND lower(b.city) IN ('cuttack','jajpur','jajpur town')
		  AND EXISTS (SELECT 1 FROM users claimant WHERE claimant.id=$2 AND claimant.status='active')
		  AND b.owner_user_id<>$2
		  AND NOT EXISTS (SELECT 1 FROM business_members bm WHERE bm.business_id=b.id AND bm.user_id=$2 AND bm.status='active')
		RETURNING id`, businessID, userID, req.Message).Scan(&requestID)
	})
	if errors.Is(err, errRateLimited) {
		writeError(w, http.StatusTooManyRequests, "CLAIM_RATE_LIMITED", "You have submitted the maximum of 3 business claims in 24 hours.")
		return
	}
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, "LISTING_NOT_CLAIMABLE", "This listing is unavailable for a claim request.")
		return
	}
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			writeError(w, http.StatusConflict, "CLAIM_ALREADY_PENDING", "A claim request for this listing is already under review.")
			return
		}
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to submit the claim request.")
		return
	}
	writeJSON(w, http.StatusCreated, response{"data": map[string]string{"id": requestID, "status": "pending"}})
}

func (s *Service) ListPending(w http.ResponseWriter, r *http.Request, _ string) {
	rows, err := s.db.QueryxContext(r.Context(), `
		SELECT cr.id, b.id, b.name, b.category_slug, COALESCE(c.name,b.category_slug),
		       COALESCE(b.address_text,''), COALESCE(b.locality,''), COALESCE(b.city,''),
		       cr.claimant_user_id, COALESCE(u.display_name,''), COALESCE(u.phone_e164,''),
		       cr.claimant_message, cr.created_at
		FROM business_claim_requests cr JOIN businesses b ON b.id=cr.business_id
		JOIN users u ON u.id=cr.claimant_user_id LEFT JOIN categories c ON c.slug=b.category_slug
		WHERE cr.status='pending' ORDER BY cr.created_at ASC LIMIT 100`)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load claim requests.")
		return
	}
	defer rows.Close()
	type claim struct {
		ID            string `json:"id"`
		BusinessID    string `json:"business_id"`
		BusinessName  string `json:"business_name"`
		CategorySlug  string `json:"category_slug"`
		Category      string `json:"category"`
		Address       string `json:"address"`
		Locality      string `json:"locality"`
		City          string `json:"city"`
		ClaimantID    string `json:"claimant_id"`
		ClaimantName  string `json:"claimant_name"`
		ClaimantPhone string `json:"claimant_phone"`
		Message       string `json:"message"`
		CreatedAt     string `json:"created_at"`
	}
	data := make([]claim, 0)
	for rows.Next() {
		var item claim
		if err := rows.Scan(&item.ID, &item.BusinessID, &item.BusinessName, &item.CategorySlug, &item.Category, &item.Address, &item.Locality, &item.City, &item.ClaimantID, &item.ClaimantName, &item.ClaimantPhone, &item.Message, &item.CreatedAt); err != nil {
			writeError(w, 500, "INTERNAL_ERROR", "Unable to read claim requests.")
			return
		}
		data = append(data, item)
	}
	if err := rows.Err(); err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to read claim requests.")
		return
	}
	writeJSON(w, http.StatusOK, response{"data": data, "meta": map[string]int{"count": len(data)}})
}

// ListMine returns only claim requests owned by the authenticated user.
func (s *Service) ListMine(w http.ResponseWriter, r *http.Request, userID string) {
	rows, err := s.db.QueryxContext(r.Context(), `
		SELECT cr.id,b.id,b.name,COALESCE(b.city,''),cr.status,cr.created_at,cr.reviewed_at
		FROM business_claim_requests cr JOIN businesses b ON b.id=cr.business_id
		WHERE cr.claimant_user_id=$1 ORDER BY cr.created_at DESC LIMIT 50`, userID)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load your claim requests.")
		return
	}
	defer rows.Close()
	type claimStatus struct {
		ID           string  `json:"id"`
		BusinessID   string  `json:"business_id"`
		BusinessName string  `json:"business_name"`
		City         string  `json:"city"`
		Status       string  `json:"status"`
		CreatedAt    string  `json:"created_at"`
		ReviewedAt   *string `json:"reviewed_at,omitempty"`
	}
	data := make([]claimStatus, 0)
	for rows.Next() {
		var item claimStatus
		var createdAt time.Time
		var reviewedAt sql.NullTime
		if err := rows.Scan(&item.ID, &item.BusinessID, &item.BusinessName, &item.City, &item.Status, &createdAt, &reviewedAt); err != nil {
			writeError(w, 500, "INTERNAL_ERROR", "Unable to read your claim requests.")
			return
		}
		item.CreatedAt = createdAt.UTC().Format(time.RFC3339)
		if reviewedAt.Valid {
			value := reviewedAt.Time.UTC().Format(time.RFC3339)
			item.ReviewedAt = &value
		}
		data = append(data, item)
	}
	if err := rows.Err(); err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to read your claim requests.")
		return
	}
	writeJSON(w, http.StatusOK, response{"data": data, "meta": map[string]int{"count": len(data)}})
}

func (s *Service) Decide(w http.ResponseWriter, r *http.Request, adminID string) {
	var req struct {
		Decision string `json:"decision"`
		Note     string `json:"note"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8192)).Decode(&req); err != nil || (req.Decision != "approve" && req.Decision != "reject") {
		writeError(w, 400, "INVALID_DECISION", "Decision must be approve or reject.")
		return
	}
	req.Note = strings.TrimSpace(req.Note)
	minimumNoteLength := 5
	if req.Decision == "approve" {
		minimumNoteLength = 10
	}
	if utf8.RuneCountInString(req.Note) < minimumNoteLength || utf8.RuneCountInString(req.Note) > 1000 {
		writeError(w, 400, "INVALID_NOTE", "A decision note is required (10 characters for approval, 5 for rejection; maximum 1000).")
		return
	}
	requestID := r.PathValue("id")
	if _, err := uuid.Parse(requestID); err != nil {
		writeError(w, 400, "INVALID_CLAIM_ID", "A valid claim identifier is required.")
		return
	}
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var businessID, claimantID, status string
		err := tx.QueryRowxContext(r.Context(), `SELECT business_id,claimant_user_id,status FROM business_claim_requests WHERE id=$1 FOR UPDATE`, requestID).Scan(&businessID, &claimantID, &status)
		if err != nil {
			return err
		}
		if status != "pending" {
			return errInvalidState
		}
		if req.Decision == "approve" {
			var currentOwner string
			err = tx.QueryRowxContext(r.Context(), `SELECT owner_user_id FROM businesses WHERE id=$1 AND status='approved' FOR UPDATE`, businessID).Scan(&currentOwner)
			if err != nil {
				return err
			}
			if currentOwner == claimantID {
				return errInvalidState
			}
			if _, err = tx.ExecContext(r.Context(), `UPDATE businesses SET owner_user_id=$2,updated_at=now() WHERE id=$1`, businessID, claimantID); err != nil {
				return err
			}
			if _, err = tx.ExecContext(r.Context(), `UPDATE business_members SET status='revoked',updated_at=now() WHERE business_id=$1 AND user_id=$2 AND role='owner' AND status='active'`, businessID, currentOwner); err != nil {
				return err
			}
			if _, err = tx.ExecContext(r.Context(), `INSERT INTO business_members(business_id,user_id,role,status,invited_by,updated_at) VALUES($1,$2,'owner','active',$3,now()) ON CONFLICT(business_id,user_id) DO UPDATE SET role='owner',status='active',invited_by=EXCLUDED.invited_by,updated_at=now()`, businessID, claimantID, adminID); err != nil {
				return err
			}
			if _, err = tx.ExecContext(r.Context(), `INSERT INTO user_roles(user_id,role) VALUES($1,'merchant') ON CONFLICT(user_id,role) DO NOTHING`, claimantID); err != nil {
				return err
			}
		}
		decisionStatus := "rejected"
		action := "reject_business_claim"
		if req.Decision == "approve" {
			decisionStatus = "approved"
			action = "approve_business_claim"
		}
		if _, err = tx.ExecContext(r.Context(), `UPDATE business_claim_requests SET status=$2,reviewer_user_id=$3,review_note=NULLIF($4,''),reviewed_at=now() WHERE id=$1`, requestID, decisionStatus, adminID, req.Note); err != nil {
			return err
		}
		if _, err = tx.ExecContext(r.Context(), `INSERT INTO audit_logs(actor_user_id,action,target_type,target_id,reason,created_at) VALUES($1,$2,'business_claim',$3,NULLIF($4,''),now())`, adminID, action, requestID, req.Note); err != nil {
			return err
		}
		return nil
	})
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, 404, "NOT_FOUND", "Claim request not found.")
		return
	}
	if errors.Is(err, errInvalidState) {
		writeError(w, 409, "INVALID_STATE", "This claim request has already been reviewed or the listing is no longer eligible.")
		return
	}
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to record the claim decision.")
		return
	}
	writeJSON(w, http.StatusOK, response{"data": map[string]string{"id": requestID, "status": map[bool]string{true: "approved", false: "rejected"}[req.Decision == "approve"]}})
}

var errInvalidState = errors.New("invalid claim state")
var errRateLimited = errors.New("claim submission rate limited")

// Helpers used by focused unit tests without needing a live database.
func validateSearchQuery(query string) bool {
	size := utf8.RuneCountInString(strings.TrimSpace(query))
	return size >= 2 && size <= 80
}
func claimableCity(city string) bool {
	c := strings.ToLower(strings.TrimSpace(city))
	return c == "cuttack" || c == "jajpur" || c == "jajpur town"
}
func claimRateLimitAllows(recent int) bool { return recent < 3 }
