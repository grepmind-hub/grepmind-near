package moderation

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"grepmind-near/backend/pkg/config"
	"grepmind-near/backend/pkg/database"
)

type Service struct {
	db  *database.DB
	cfg *config.Config
}

func NewService(db *database.DB, cfg *config.Config) *Service {
	return &Service{
		db:  db,
		cfg: cfg,
	}
}

// ---------- Models ----------

type Stats struct {
	PendingVerifications int `json:"pending_verifications"`
	ReportedListings     int `json:"reported_listings"`
	PendingOffers        int `json:"pending_offers"`
	ActiveListings       int `json:"active_listings"`
	PendingClaims        int `json:"pending_claims"`
	ServiceRequests      int `json:"service_requests"`
	CustomerOrders       int `json:"customer_orders"`
	ActiveAccounts       int `json:"active_accounts"`
	NotificationEvents   int `json:"notification_events"`
}

type AdminBusiness struct {
	ID                 string   `json:"id"`
	Name               string   `json:"name"`
	Slug               string   `json:"slug,omitempty"`
	CategorySlug       string   `json:"category_slug"`
	CategoryName       string   `json:"category_name,omitempty"`
	AddressText        string   `json:"address_text"`
	City               string   `json:"city,omitempty"`
	Status             string   `json:"status"`
	VerificationStatus string   `json:"verification_status"`
	PhoneE164          string   `json:"phone_e164,omitempty"`
	OwnerPhone         string   `json:"owner_phone,omitempty"`
	CreatedAt          string   `json:"created_at"`
}

type AdminReport struct {
	ID               string  `json:"id"`
	ReporterPhone    string  `json:"reporter_phone,omitempty"`
	TargetType       string  `json:"target_type"`
	TargetID         string  `json:"target_id"`
	TargetName       string  `json:"target_name,omitempty"`
	Reason           string  `json:"reason"`
	Status           string  `json:"status"`
	CreatedAt        string  `json:"created_at"`
	ResolvedAt       *string `json:"resolved_at,omitempty"`
	ResolutionReason *string `json:"resolution_reason,omitempty"`
}

type AdminOffer struct {
	ID              string  `json:"id"`
	BusinessID      string  `json:"business_id"`
	BusinessName    string  `json:"business_name"`
	Title           string  `json:"title"`
	Description     string  `json:"description,omitempty"`
	StartsAt        string  `json:"starts_at"`
	EndsAt          string  `json:"ends_at"`
	Status          string  `json:"status"`
	DiscountPercent *int    `json:"discount_percent,omitempty"`
}

type AdminAuditLog struct {
	ID         string  `json:"id"`
	ActorPhone string  `json:"actor_phone,omitempty"`
	Action     string  `json:"action"`
	TargetType string  `json:"target_type"`
	TargetID   string  `json:"target_id"`
	Reason     *string `json:"reason,omitempty"`
	CreatedAt  string  `json:"created_at"`
}

// ---------- Helper functions ----------

type envelope map[string]interface{}

func writeJSON(w http.ResponseWriter, code int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, code int, errCode, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"error": map[string]interface{}{
			"code":       errCode,
			"message":    message,
			"request_id": "err",
		},
	})
}

func (s *Service) logAudit(ctx context.Context, actorID, action, targetType, targetID, reason string) {
	var reasonNull sql.NullString
	if reason != "" {
		reasonNull = sql.NullString{String: reason, Valid: true}
	}
	_, _ = s.db.ExecContext(ctx, `
		INSERT INTO audit_logs (actor_user_id, action, target_type, target_id, reason, created_at)
		VALUES ($1, $2, $3, $4, $5, now())
	`, actorID, action, targetType, targetID, reasonNull)
}

// ---------- Handlers ----------

// GetStats returns counts for the admin dashboard.
func (s *Service) GetStats(w http.ResponseWriter, r *http.Request, adminUserID string) {
	var stats Stats
	city, days, filterErr := parseStatsFilters(r.URL.Query().Get("city"), r.URL.Query().Get("range"))
	if filterErr != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", filterErr.Error())
		return
	}
	err := s.db.QueryRowContext(r.Context(), `
		SELECT
		 (SELECT COUNT(*) FROM businesses b WHERE (b.status IN ('pending','pending_review','draft') OR b.verification_status = 'pending') AND ($1 = '' OR lower(b.city) = lower($1))),
		 (SELECT COUNT(*) FROM reports WHERE status = 'open'),
		 (SELECT COUNT(*) FROM offers o JOIN businesses b ON b.id=o.business_id WHERE o.status IN ('draft','pending') AND ($1 = '' OR lower(b.city) = lower($1))),
		 (SELECT COUNT(*) FROM businesses b WHERE b.status = 'approved' AND ($1 = '' OR lower(b.city) = lower($1))),
		 (SELECT COUNT(*) FROM business_claim_requests c JOIN businesses b ON b.id=c.business_id WHERE c.status='pending' AND ($1 = '' OR lower(b.city) = lower($1))),
		 (SELECT COUNT(*) FROM service_requests sr JOIN businesses b ON b.id=sr.business_id WHERE sr.created_at >= now() - ($2 * interval '1 day') AND ($1 = '' OR lower(b.city) = lower($1))),
		 (SELECT COUNT(*) FROM customer_orders co JOIN businesses b ON b.id=co.business_id WHERE co.created_at >= now() - ($2 * interval '1 day') AND ($1 = '' OR lower(b.city) = lower($1))),
		 (SELECT COUNT(*) FROM users WHERE status='active'),
		 (SELECT COUNT(*) FROM notifications n LEFT JOIN businesses b ON b.id=n.business_id WHERE n.created_at >= now() - ($2 * interval '1 day') AND ($1 = '' OR n.business_id IS NULL OR lower(b.city) = lower($1)))
	`).Scan(&stats.PendingVerifications, &stats.ReportedListings, &stats.PendingOffers, &stats.ActiveListings, &stats.PendingClaims, &stats.ServiceRequests, &stats.CustomerOrders, &stats.ActiveAccounts, &stats.NotificationEvents)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load operational statistics.")
		return
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": stats,
		"meta": map[string]string{"request_id": "admin-stats"},
	})
}

func parseStatsFilters(city, period string) (string, int, error) {
	if city != "" && city != "Cuttack" && city != "Jajpur" {
		return "", 0, fmt.Errorf("city must be Cuttack or Jajpur.")
	}
	days := 14
	switch period {
	case "", "14d":
	case "7d":
		days = 7
	case "30d":
		days = 30
	default:
		return "", 0, fmt.Errorf("range must be 7d, 14d, or 30d.")
	}
	return city, days, nil
}

// ListPendingBusinesses returns businesses awaiting review or verification.
func (s *Service) ListPendingBusinesses(w http.ResponseWriter, r *http.Request, adminUserID string) {
	rows, err := s.db.QueryxContext(r.Context(), `
		SELECT b.id, b.name, b.slug, b.category_slug, c.name as category_name,
		       b.address_text, b.city, b.status, b.verification_status,
		       b.phone_e164, COALESCE(u.phone_e164, '') as owner_phone,
		       b.created_at
		FROM businesses b
		LEFT JOIN categories c ON c.slug = b.category_slug
		LEFT JOIN users u ON u.id = b.owner_user_id
		WHERE b.status = 'pending_review' OR b.verification_status = 'pending' OR b.status = 'draft'
		ORDER BY b.created_at DESC
		LIMIT 50
	`)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load pending businesses.")
		return
	}
	defer rows.Close()

	list := []AdminBusiness{}
	for rows.Next() {
		var b AdminBusiness
		var slug, catName, city, phone, ownerPhone sql.NullString
		var createdAt time.Time
		if err := rows.Scan(&b.ID, &b.Name, &slug, &b.CategorySlug, &catName,
			&b.AddressText, &city, &b.Status, &b.VerificationStatus,
			&phone, &ownerPhone, &createdAt); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to parse business row.")
			return
		}
		if slug.Valid {
			b.Slug = slug.String
		}
		if catName.Valid {
			b.CategoryName = catName.String
		}
		if city.Valid {
			b.City = city.String
		}
		if phone.Valid {
			b.PhoneE164 = phone.String
		}
		if ownerPhone.Valid {
			b.OwnerPhone = ownerPhone.String
		}
		b.CreatedAt = createdAt.Format(time.RFC3339)
		list = append(list, b)
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": list,
		"meta": map[string]interface{}{"request_id": "admin-pending-businesses", "count": len(list)},
	})
}

// ListAllBusinesses returns all businesses with optional status filter.
func (s *Service) ListAllBusinesses(w http.ResponseWriter, r *http.Request, adminUserID string) {
	statusFilter := r.URL.Query().Get("status")
	query := `
		SELECT b.id, b.name, b.slug, b.category_slug, c.name as category_name,
		       b.address_text, b.city, b.status, b.verification_status,
		       b.phone_e164, COALESCE(u.phone_e164, '') as owner_phone,
		       b.created_at
		FROM businesses b
		LEFT JOIN categories c ON c.slug = b.category_slug
		LEFT JOIN users u ON u.id = b.owner_user_id
	`
	args := []interface{}{}
	if statusFilter != "" && statusFilter != "all" {
		query += " WHERE b.status = $1"
		args = append(args, statusFilter)
	}
	query += " ORDER BY b.created_at DESC LIMIT 50"

	rows, err := s.db.QueryxContext(r.Context(), query, args...)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load businesses.")
		return
	}
	defer rows.Close()

	list := []AdminBusiness{}
	for rows.Next() {
		var b AdminBusiness
		var slug, catName, city, phone, ownerPhone sql.NullString
		var createdAt time.Time
		if err := rows.Scan(&b.ID, &b.Name, &slug, &b.CategorySlug, &catName,
			&b.AddressText, &city, &b.Status, &b.VerificationStatus,
			&phone, &ownerPhone, &createdAt); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to parse business row.")
			return
		}
		if slug.Valid {
			b.Slug = slug.String
		}
		if catName.Valid {
			b.CategoryName = catName.String
		}
		if city.Valid {
			b.City = city.String
		}
		if phone.Valid {
			b.PhoneE164 = phone.String
		}
		if ownerPhone.Valid {
			b.OwnerPhone = ownerPhone.String
		}
		b.CreatedAt = createdAt.Format(time.RFC3339)
		list = append(list, b)
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": list,
		"meta": map[string]interface{}{"request_id": "admin-all-businesses", "count": len(list)},
	})
}

// ApproveBusiness sets business status to approved and logs audit.
func (s *Service) ApproveBusiness(w http.ResponseWriter, r *http.Request, adminUserID string) {
	id := r.PathValue("id")
	var req struct {
		Reason string `json:"reason"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	reason := req.Reason
	if reason == "" {
		reason = "Listing approved by administrator"
	}

	result, err := s.db.ExecContext(r.Context(), `
		UPDATE businesses SET status = 'approved', updated_at = now() WHERE id = $1
	`, id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to approve business.")
		return
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Business not found.")
		return
	}

	s.logAudit(r.Context(), adminUserID, "approve_business", "business", id, reason)

	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]interface{}{"id": id, "status": "approved"},
		"meta": map[string]string{"request_id": "admin-approve"},
	})
}

// RejectBusiness sets business status to rejected and logs audit.
func (s *Service) RejectBusiness(w http.ResponseWriter, r *http.Request, adminUserID string) {
	id := r.PathValue("id")
	var req struct {
		Reason string `json:"reason"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	reason := req.Reason
	if reason == "" {
		reason = "Listing rejected by administrator"
	}

	result, err := s.db.ExecContext(r.Context(), `
		UPDATE businesses SET status = 'rejected', updated_at = now() WHERE id = $1
	`, id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to reject business.")
		return
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Business not found.")
		return
	}

	s.logAudit(r.Context(), adminUserID, "reject_business", "business", id, reason)

	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]interface{}{"id": id, "status": "rejected"},
		"meta": map[string]string{"request_id": "admin-reject"},
	})
}

// VerifyBusiness sets business verification_status to verified or rejected and logs audit.
func (s *Service) VerifyBusiness(w http.ResponseWriter, r *http.Request, adminUserID string) {
	id := r.PathValue("id")
	var req struct {
		VerificationStatus string `json:"verification_status"`
		Reason             string `json:"reason"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.VerificationStatus == "" {
		req.VerificationStatus = "verified"
	}
	reason := req.Reason
	if reason == "" {
		reason = "Verification outcome recorded"
	}

	result, err := s.db.ExecContext(r.Context(), `
		UPDATE businesses SET verification_status = $1, updated_at = now() WHERE id = $2
	`, req.VerificationStatus, id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to update verification status.")
		return
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Business not found.")
		return
	}

	s.logAudit(r.Context(), adminUserID, "verify_business", "business", id, reason)

	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]interface{}{"id": id, "verification_status": req.VerificationStatus},
		"meta": map[string]string{"request_id": "admin-verify"},
	})
}

// ListReports returns user reports.
func (s *Service) ListReports(w http.ResponseWriter, r *http.Request, adminUserID string) {
	statusFilter := r.URL.Query().Get("status")
	query := `
		SELECT rep.id, rep.target_type, rep.target_id, rep.reason, rep.status,
		       rep.created_at, rep.resolved_at, rep.resolution_reason,
		       COALESCE(u.phone_e164, '') as reporter_phone
		FROM reports rep
		LEFT JOIN users u ON u.id = rep.reporter_user_id
	`
	args := []interface{}{}
	if statusFilter != "" && statusFilter != "all" {
		query += " WHERE rep.status = $1"
		args = append(args, statusFilter)
	}
	query += " ORDER BY rep.created_at DESC LIMIT 50"

	rows, err := s.db.QueryxContext(r.Context(), query, args...)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load reports.")
		return
	}
	defer rows.Close()

	list := []AdminReport{}
	for rows.Next() {
		var rep AdminReport
		var reporterPhone, resReason sql.NullString
		var createdAt time.Time
		var resAt sql.NullTime
		if err := rows.Scan(&rep.ID, &rep.TargetType, &rep.TargetID, &rep.Reason,
			&rep.Status, &createdAt, &resAt, &resReason, &reporterPhone); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to parse report row.")
			return
		}
		if reporterPhone.Valid {
			rep.ReporterPhone = reporterPhone.String
		}
		if resReason.Valid {
			rStr := resReason.String
			rep.ResolutionReason = &rStr
		}
		if resAt.Valid {
			rTime := resAt.Time.Format(time.RFC3339)
			rep.ResolvedAt = &rTime
		}
		rep.CreatedAt = createdAt.Format(time.RFC3339)
		list = append(list, rep)
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": list,
		"meta": map[string]interface{}{"request_id": "admin-reports", "count": len(list)},
	})
}

// ResolveReport marks report as resolved with action taken or dismissed.
func (s *Service) ResolveReport(w http.ResponseWriter, r *http.Request, adminUserID string) {
	id := r.PathValue("id")
	var req struct {
		Resolution string `json:"resolution"`
		Reason     string `json:"reason"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		req.Resolution = "action_taken"
	}
	if req.Resolution != "dismissed" && req.Resolution != "action_taken" {
		req.Resolution = "action_taken"
	}

	result, err := s.db.ExecContext(r.Context(), `
		UPDATE reports SET status = $1, resolved_at = now(), resolution_reason = $2 WHERE id = $3
	`, req.Resolution, req.Reason, id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to resolve report.")
		return
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Report not found.")
		return
	}

	s.logAudit(r.Context(), adminUserID, "resolve_report", "report", id, req.Reason)

	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]interface{}{"id": id, "status": req.Resolution},
		"meta": map[string]string{"request_id": "admin-resolve-report"},
	})
}

// ListOffers returns all merchant offers for moderation.
func (s *Service) ListOffers(w http.ResponseWriter, r *http.Request, adminUserID string) {
	statusFilter := r.URL.Query().Get("status")
	query := `
		SELECT o.id, o.business_id, b.name as business_name, o.title, o.description,
		       o.starts_at, o.ends_at, o.status, o.discount_percent
		FROM offers o
		JOIN businesses b ON b.id = o.business_id
	`
	args := []interface{}{}
	if statusFilter != "" && statusFilter != "all" {
		query += " WHERE o.status = $1"
		args = append(args, statusFilter)
	}
	query += " ORDER BY o.starts_at DESC LIMIT 50"

	rows, err := s.db.QueryxContext(r.Context(), query, args...)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load offers.")
		return
	}
	defer rows.Close()

	list := []AdminOffer{}
	for rows.Next() {
		var o AdminOffer
		var desc sql.NullString
		var disc sql.NullInt64
		var startsAt, endsAt time.Time
		if err := rows.Scan(&o.ID, &o.BusinessID, &o.BusinessName, &o.Title, &desc,
			&startsAt, &endsAt, &o.Status, &disc); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to parse offer row.")
			return
		}
		if desc.Valid {
			o.Description = desc.String
		}
		if disc.Valid {
			d := int(disc.Int64)
			o.DiscountPercent = &d
		}
		o.StartsAt = startsAt.Format(time.RFC3339)
		o.EndsAt = endsAt.Format(time.RFC3339)
		list = append(list, o)
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": list,
		"meta": map[string]interface{}{"request_id": "admin-offers", "count": len(list)},
	})
}

// ApproveOffer publishes an offer.
func (s *Service) ApproveOffer(w http.ResponseWriter, r *http.Request, adminUserID string) {
	id := r.PathValue("id")
	result, err := s.db.ExecContext(r.Context(), `
		UPDATE offers SET status = 'published' WHERE id = $1
	`, id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to approve offer.")
		return
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Offer not found.")
		return
	}

	s.logAudit(r.Context(), adminUserID, "approve_offer", "offer", id, "Offer approved and published")

	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]interface{}{"id": id, "status": "published"},
		"meta": map[string]string{"request_id": "admin-approve-offer"},
	})
}

// RejectOffer archives an offer.
func (s *Service) RejectOffer(w http.ResponseWriter, r *http.Request, adminUserID string) {
	id := r.PathValue("id")
	result, err := s.db.ExecContext(r.Context(), `
		UPDATE offers SET status = 'archived' WHERE id = $1
	`, id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to archive offer.")
		return
	}
	n, _ := result.RowsAffected()
	if n == 0 {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Offer not found.")
		return
	}

	s.logAudit(r.Context(), adminUserID, "archive_offer", "offer", id, "Offer rejected/archived by admin")

	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]interface{}{"id": id, "status": "archived"},
		"meta": map[string]string{"request_id": "admin-archive-offer"},
	})
}

// ListAuditLogs returns the admin activity history.
func (s *Service) ListAuditLogs(w http.ResponseWriter, r *http.Request, adminUserID string) {
	limit := 50
	if v := r.URL.Query().Get("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= 1 && n <= 100 {
			limit = n
		}
	}

	rows, err := s.db.QueryxContext(r.Context(), `
		SELECT al.id, COALESCE(u.phone_e164, 'System') as actor_phone, al.action,
		       al.target_type, al.target_id, al.reason, al.created_at
		FROM audit_logs al
		LEFT JOIN users u ON u.id = al.actor_user_id
		ORDER BY al.created_at DESC
		LIMIT $1
	`, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load audit logs.")
		return
	}
	defer rows.Close()

	list := []AdminAuditLog{}
	for rows.Next() {
		var l AdminAuditLog
		var reason sql.NullString
		var createdAt time.Time
		if err := rows.Scan(&l.ID, &l.ActorPhone, &l.Action, &l.TargetType,
			&l.TargetID, &reason, &createdAt); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to parse audit log row.")
			return
		}
		if reason.Valid {
			rStr := reason.String
			l.Reason = &rStr
		}
		l.CreatedAt = createdAt.Format(time.RFC3339)
		list = append(list, l)
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": list,
		"meta": map[string]interface{}{"request_id": "admin-audit-logs", "count": len(list)},
	})
}

type AdminUser struct {
	ID          string `json:"id"`
	PhoneE164   string `json:"phone_e164"`
	DisplayName string `json:"display_name"`
	Role        string `json:"role"`
	CreatedAt   string `json:"created_at"`
}

// ListAdmins returns all platform administrator users.
func (s *Service) ListAdmins(w http.ResponseWriter, r *http.Request, adminUserID string) {
	rows, err := s.db.QueryxContext(r.Context(), `
		SELECT u.id, u.phone_e164, COALESCE(u.display_name, 'Platform Admin') as display_name,
		       ur.role, u.created_at
		FROM users u
		JOIN user_roles ur ON ur.user_id = u.id
		WHERE ur.role = 'admin'
		ORDER BY u.created_at ASC
	`)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load admins.")
		return
	}
	defer rows.Close()

	list := []AdminUser{}
	for rows.Next() {
		var a AdminUser
		var createdAt time.Time
		if err := rows.Scan(&a.ID, &a.PhoneE164, &a.DisplayName, &a.Role, &createdAt); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to parse admin row.")
			return
		}
		a.CreatedAt = createdAt.Format(time.RFC3339)
		list = append(list, a)
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": list,
		"meta": map[string]interface{}{"request_id": "admin-list-admins", "count": len(list)},
	})
}

// AddAdmin grants admin permissions to a user by mobile number.
func (s *Service) AddAdmin(w http.ResponseWriter, r *http.Request, adminUserID string) {
	var req struct {
		PhoneE164   string `json:"phone_e164"`
		DisplayName string `json:"display_name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.PhoneE164 == "" {
		writeError(w, http.StatusBadRequest, "INVALID_INPUT", "Phone number is required.")
		return
	}

	var userID string
	err := s.db.QueryRowxContext(r.Context(), `
		INSERT INTO users (phone_e164, display_name, status, preferred_language)
		VALUES ($1, $2, 'active', 'en')
		ON CONFLICT (phone_e164) DO UPDATE SET
			display_name = CASE WHEN EXCLUDED.display_name != '' THEN EXCLUDED.display_name ELSE users.display_name END,
			updated_at = now()
		RETURNING id
	`, req.PhoneE164, req.DisplayName).Scan(&userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to create/update user.")
		return
	}

	_, err = s.db.ExecContext(r.Context(), `
		INSERT INTO user_roles (user_id, role)
		VALUES ($1, 'admin')
		ON CONFLICT DO NOTHING
	`, userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to grant admin role.")
		return
	}

	s.logAudit(r.Context(), adminUserID, "grant_admin", "user", userID, fmt.Sprintf("Granted platform admin role to %s", req.PhoneE164))

	writeJSON(w, http.StatusCreated, envelope{
		"data": map[string]interface{}{
			"id":           userID,
			"phone_e164":   req.PhoneE164,
			"display_name": req.DisplayName,
			"role":         "admin",
		},
		"meta": map[string]string{"request_id": "admin-add-admin"},
	})
}

// RevokeAdmin revokes admin permissions from a user.
func (s *Service) RevokeAdmin(w http.ResponseWriter, r *http.Request, adminUserID string) {
	targetUserID := r.PathValue("userId")
	if targetUserID == "" {
		writeError(w, http.StatusBadRequest, "INVALID_INPUT", "User ID is required.")
		return
	}

	// Protect primary platform superadmin
	var phone string
	_ = s.db.QueryRowxContext(r.Context(), "SELECT phone_e164 FROM users WHERE id = $1", targetUserID).Scan(&phone)
	if phone == "+910000000000" {
		writeError(w, http.StatusForbidden, "FORBIDDEN", "Primary platform superadmin cannot be revoked.")
		return
	}

	_, err := s.db.ExecContext(r.Context(), `
		DELETE FROM user_roles WHERE user_id = $1 AND role = 'admin'
	`, targetUserID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to revoke admin role.")
		return
	}

	s.logAudit(r.Context(), adminUserID, "revoke_admin", "user", targetUserID, "Revoked platform admin role")

	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]interface{}{"id": targetUserID, "revoked": true},
		"meta": map[string]string{"request_id": "admin-revoke-admin"},
	})
}
