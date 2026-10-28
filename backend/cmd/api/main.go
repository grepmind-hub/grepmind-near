package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/golang-jwt/jwt/v4"

	"grepmind-near/backend/internal/auth"
	"grepmind-near/backend/internal/discovery"
	"grepmind-near/backend/internal/moderation"
	"grepmind-near/backend/pkg/config"
	"grepmind-near/backend/pkg/database"
	"grepmind-near/backend/pkg/logger"
)

func main() {
	cfg := config.Load()
	logger.Init(cfg.LogLevel)
	log := logger.Log

	db, err := database.Open(cfg.DBDSN(), 25, 25, 5*time.Minute)
	if err != nil {
		log.Fatal().Err(err).Msg("database connect failed")
	}
	defer db.Close()

	authSvc := auth.NewService(db, cfg)
	discSvc := discovery.NewService(db, cfg)
	modSvc := moderation.NewService(db, cfg)

	mux := setupRouter(authSvc, discSvc, modSvc)

	srv := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      mux,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		log.Info().Str("addr", srv.Addr).Msg("api server starting")
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatal().Err(err).Msg("api server failed")
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Info().Msg("shutting down")
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Error().Err(err).Msg("shutdown error")
	}
	fmt.Println("api stopped")
}

func setupRouter(authSvc *auth.Service, discSvc *discovery.Service, modSvc *moderation.Service) *http.ServeMux {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, envelope{"status": "ok"})
	})

	mux.HandleFunc("POST /api/v1/auth/otp/request", authSvc.RequestOTP)
	mux.HandleFunc("POST /api/v1/auth/otp/verify", authSvc.VerifyOTP)
	mux.HandleFunc("POST /api/v1/auth/refresh", authSvc.Refresh)
	mux.HandleFunc("POST /api/v1/auth/logout", authSvc.Logout)

	mux.HandleFunc("GET /api/v1/me", requireAuth(authSvc, authMe))
	mux.HandleFunc("PATCH /api/v1/me", requireAuth(authSvc, authUpdateMe))

	mux.HandleFunc("GET /api/v1/categories", discSvc.ListCategories)
	mux.HandleFunc("GET /api/v1/businesses", discSvc.SearchBusinesses)
	mux.HandleFunc("GET /api/v1/businesses/{id}", discSvc.GetBusiness)
	mux.HandleFunc("GET /api/v1/businesses/{id}/products", discSvc.ListProducts)
	mux.HandleFunc("GET /api/v1/businesses/{id}/services", discSvc.ListServices)
	mux.HandleFunc("GET /api/v1/businesses/{id}/offers", discSvc.ListOffers)
	mux.HandleFunc("GET /api/v1/nearby", discSvc.Nearby)

	// Favorites (require auth)
	mux.HandleFunc("GET /api/v1/favorites", requireAuth(authSvc, discSvc.ListFavorites))
	mux.HandleFunc("POST /api/v1/businesses/{id}/favorite", requireAuth(authSvc, discSvc.ToggleFavorite))

	// Merchant workspace (require auth + merchant role)
	mux.HandleFunc("GET /api/v1/merchant/profile", requireAuth(authSvc, merchantProfile))
	mux.HandleFunc("PATCH /api/v1/merchant/profile", requireAuth(authSvc, merchantUpdateProfile))
	mux.HandleFunc("GET /api/v1/merchant/requests", requireAuth(authSvc, merchantRequests))
	mux.HandleFunc("PATCH /api/v1/merchant/requests/{id}/status", requireAuth(authSvc, merchantRequestStatus))

	// Admin operations & moderation (Phase 4)
	mux.HandleFunc("POST /api/v1/admin/session", modSvc.AdminSession)
	mux.HandleFunc("GET /api/v1/admin/stats", requireAdmin(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, uid string) {
		modSvc.GetStats(w, r, uid)
	}))
	mux.HandleFunc("GET /api/v1/admin/businesses/pending", requireAdmin(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, uid string) {
		modSvc.ListPendingBusinesses(w, r, uid)
	}))
	mux.HandleFunc("GET /api/v1/admin/businesses", requireAdmin(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, uid string) {
		modSvc.ListAllBusinesses(w, r, uid)
	}))
	mux.HandleFunc("POST /api/v1/admin/businesses/{id}/approve", requireAdmin(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, uid string) {
		modSvc.ApproveBusiness(w, r, uid)
	}))
	mux.HandleFunc("POST /api/v1/admin/businesses/{id}/reject", requireAdmin(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, uid string) {
		modSvc.RejectBusiness(w, r, uid)
	}))
	mux.HandleFunc("POST /api/v1/admin/businesses/{id}/verify", requireAdmin(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, uid string) {
		modSvc.VerifyBusiness(w, r, uid)
	}))
	mux.HandleFunc("GET /api/v1/admin/reports", requireAdmin(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, uid string) {
		modSvc.ListReports(w, r, uid)
	}))
	mux.HandleFunc("POST /api/v1/admin/reports/{id}/resolve", requireAdmin(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, uid string) {
		modSvc.ResolveReport(w, r, uid)
	}))
	mux.HandleFunc("GET /api/v1/admin/offers", requireAdmin(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, uid string) {
		modSvc.ListOffers(w, r, uid)
	}))
	mux.HandleFunc("POST /api/v1/admin/offers/{id}/approve", requireAdmin(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, uid string) {
		modSvc.ApproveOffer(w, r, uid)
	}))
	mux.HandleFunc("POST /api/v1/admin/offers/{id}/reject", requireAdmin(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, uid string) {
		modSvc.RejectOffer(w, r, uid)
	}))
	mux.HandleFunc("GET /api/v1/admin/audit-logs", requireAdmin(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, uid string) {
		modSvc.ListAuditLogs(w, r, uid)
	}))

	return mux
}

func authMe(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	type userRow struct {
		ID                string         `db:"id"`
		PhoneE164         string         `db:"phone_e164"`
		DisplayName       sql.NullString `db:"display_name"`
		Status            string         `db:"status"`
		PreferredLanguage string         `db:"preferred_language"`
	}
	var u userRow
	err := db.QueryRowxContext(r.Context(), `
		SELECT id, phone_e164, display_name, status, preferred_language FROM users WHERE id = $1
	`, userID).Scan(&u.ID, &u.PhoneE164, &u.DisplayName, &u.Status, &u.PreferredLanguage)
	if err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "User not found.")
		return
	}
	var roles []string
	rows, err := db.QueryxContext(r.Context(), `SELECT role FROM user_roles WHERE user_id = $1`, userID)
	if err == nil {
		for rows.Next() {
			var role string
			_ = rows.Scan(&role)
			roles = append(roles, role)
		}
		rows.Close()
	}
	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]interface{}{
			"id":                 u.ID,
			"phone_e164":         u.PhoneE164,
			"display_name":       u.DisplayName.String,
			"status":             u.Status,
			"preferred_language": u.PreferredLanguage,
			"roles":              roles,
		},
		"meta": map[string]string{"request_id": "me"},
	})
}

func authUpdateMe(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]string{"status": "updated"},
		"meta": map[string]string{"request_id": "me-update"},
	})
}

// ---------------------------------------------------------------
// Merchant Workspace Handlers
// ---------------------------------------------------------------

func merchantProfile(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	// Get user roles to verify merchant
	var roles []string
	rows, err := db.QueryxContext(r.Context(), `SELECT role FROM user_roles WHERE user_id = $1`, userID)
	if err == nil {
		for rows.Next() {
			var role string
			_ = rows.Scan(&role)
			roles = append(roles, role)
		}
		rows.Close()
	}
	isMerchant := false
	for _, r := range roles {
		if r == "merchant" || r == "professional" {
			isMerchant = true
			break
		}
	}
	if !isMerchant {
		writeError(w, http.StatusForbidden, "FORBIDDEN", "Merchant role required.")
		return
	}

	// Get business profile for this user
	var bizID, bizName, bizSlug, bizDesc, bizAddr, bizCity, bizPhone string
	var bizStatus, bizVerify sql.NullString
	var lat, lng sql.NullFloat64
	err = db.QueryRowxContext(r.Context(), `
		SELECT b.id, b.name, b.slug, b.description, b.address_text, b.city, b.phone_e164,
		       b.status, b.verification_status, ST_Y(b.location::geometry), ST_X(b.location::geometry)
		FROM businesses b
		WHERE b.owner_user_id = $1 AND b.status != 'deleted'
		LIMIT 1
	`, userID).Scan(&bizID, &bizName, &bizSlug, &bizDesc, &bizAddr, &bizCity, &bizPhone,
		&bizStatus, &bizVerify, &lat, &lng)
	if err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Business profile not found.")
		return
	}

	// Get business hours
	type bizHour struct {
		Weekday  int     `json:"weekday"`
		OpensAt  *string `json:"opens_at"`
		ClosesAt *string `json:"closes_at"`
		IsClosed bool    `json:"is_closed"`
	}
	var hours []bizHour
	hRows, err := db.QueryxContext(r.Context(), `
		SELECT weekday, opens_at, closes_at, is_closed FROM business_hours WHERE business_id = $1 ORDER BY weekday
	`, bizID)
	if err == nil {
		for hRows.Next() {
			var h bizHour
			_ = hRows.Scan(&h.Weekday, &h.OpensAt, &h.ClosesAt, &h.IsClosed)
			hours = append(hours, h)
		}
		hRows.Close()
	}

	statusStr := ""
	if bizStatus.Valid {
		statusStr = bizStatus.String
	}
	verifyStr := ""
	if bizVerify.Valid {
		verifyStr = bizVerify.String
	}
	var latVal, lngVal interface{}
	if lat.Valid {
		latVal = lat.Float64
	}
	if lng.Valid {
		lngVal = lng.Float64
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]interface{}{
			"id":                  bizID,
			"name":                bizName,
			"slug":                bizSlug,
			"description":         bizDesc,
			"address_text":        bizAddr,
			"city":                bizCity,
			"phone_e164":          bizPhone,
			"status":              statusStr,
			"verification_status": verifyStr,
			"latitude":            latVal,
			"longitude":           lngVal,
			"business_hours":      hours,
		},
		"meta": map[string]string{"request_id": "merchant-profile"},
	})
}

func merchantUpdateProfile(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	var req struct {
		Name        *string `json:"name"`
		Description *string `json:"description"`
		AddressText *string `json:"address_text"`
		City        *string `json:"city"`
		PhoneE164   *string `json:"phone_e164"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Invalid request body.")
		return
	}

	// Check business exists
	var bizID string
	err := db.QueryRowxContext(r.Context(), `SELECT id FROM businesses WHERE owner_user_id = $1 AND status != 'deleted' LIMIT 1`, userID).Scan(&bizID)
	if err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Business profile not found.")
		return
	}

	// Build dynamic update
	setParts := []string{}
	args := []interface{}{bizID}
	argIdx := 2
	if req.Name != nil {
		setParts = append(setParts, fmt.Sprintf("name = $%d", argIdx))
		args = append(args, *req.Name)
		argIdx++
	}
	if req.Description != nil {
		setParts = append(setParts, fmt.Sprintf("description = $%d", argIdx))
		args = append(args, *req.Description)
		argIdx++
	}
	if req.AddressText != nil {
		setParts = append(setParts, fmt.Sprintf("address_text = $%d", argIdx))
		args = append(args, *req.AddressText)
		argIdx++
	}
	if req.City != nil {
		setParts = append(setParts, fmt.Sprintf("city = $%d", argIdx))
		args = append(args, *req.City)
		argIdx++
	}
	if req.PhoneE164 != nil {
		setParts = append(setParts, fmt.Sprintf("phone_e164 = $%d", argIdx))
		args = append(args, *req.PhoneE164)
		argIdx++
	}

	if len(setParts) == 0 {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "No fields to update.")
		return
	}

	query := fmt.Sprintf("UPDATE businesses SET %s WHERE id = $1", strings.Join(setParts, ", "))
	_, err = db.ExecContext(r.Context(), query, args...)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to update business profile.")
		return
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]string{"status": "updated"},
		"meta": map[string]string{"request_id": "merchant-update-profile"},
	})
}

func merchantRequests(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	// Get merchant's business ID
	var bizID string
	err := db.QueryRowxContext(r.Context(), `SELECT id FROM businesses WHERE owner_user_id = $1 AND status != 'deleted' LIMIT 1`, userID).Scan(&bizID)
	if err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Business profile not found.")
		return
	}

	// Get service requests for this business
	type reqItem struct {
		ID             string     `json:"id"`
		CustomerName   string     `json:"customer_name"`
		CustomerPhone  string     `json:"customer_phone"`
		ServiceName    *string    `json:"service_name"`
		Description    string     `json:"description"`
		RequestedFor   *string    `json:"requested_for"`
		Status         string     `json:"status"`
		CreatedAt      string     `json:"created_at"`
		UpdatedAt      string     `json:"updated_at"`
	}
	var requests []reqItem
	rRows, err := db.QueryxContext(r.Context(), `
		SELECT sr.id, u.phone_e164 as customer_phone, u.display_name as customer_name,
		       sr.service_id, sr.description, sr.requested_for, sr.status,
		       sr.created_at, sr.updated_at
		FROM service_requests sr
		JOIN users u ON u.id = sr.customer_user_id
		WHERE sr.business_id = $1
		ORDER BY sr.created_at DESC
		LIMIT 50
	`, bizID)
	if err == nil {
		for rRows.Next() {
			var item reqItem
			_ = rRows.Scan(&item.ID, &item.CustomerPhone, &item.CustomerName,
				&item.ServiceName, &item.Description, &item.RequestedFor,
				&item.Status, &item.CreatedAt, &item.UpdatedAt)
			requests = append(requests, item)
		}
		rRows.Close()
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]interface{}{
			"requests": requests,
		},
		"meta": map[string]string{"request_id": "merchant-requests"},
	})
}

func merchantRequestStatus(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	// Get merchant's business ID
	var bizID string
	err := db.QueryRowxContext(r.Context(), `SELECT id FROM businesses WHERE owner_user_id = $1 AND status != 'deleted' LIMIT 1`, userID).Scan(&bizID)
	if err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Business profile not found.")
		return
	}

	reqID := r.PathValue("id")
	if reqID == "" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Request ID required.")
		return
	}

	var reqBody struct {
		Status string `json:"status"`
	}
	if err := json.NewDecoder(r.Body).Decode(&reqBody); err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Invalid request body.")
		return
	}

	if reqBody.Status != "accepted" && reqBody.Status != "declined" && reqBody.Status != "completed" && reqBody.Status != "cancelled" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Invalid status. Use: accepted, declined, completed, cancelled.")
		return
	}

	// Verify request belongs to this business
	var exists bool
	err = db.QueryRowxContext(r.Context(), `
		SELECT EXISTS(SELECT 1 FROM service_requests WHERE id = $1 AND business_id = $2)
	`, reqID, bizID).Scan(&exists)
	if err != nil || !exists {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Request not found.")
		return
	}

	// Update status
	_, err = db.ExecContext(r.Context(), `
		UPDATE service_requests SET status = $1, updated_at = now() WHERE id = $2 AND business_id = $3
	`, reqBody.Status, reqID, bizID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to update request status.")
		return
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]interface{}{
			"id":     reqID,
			"status": reqBody.Status,
		},
		"meta": map[string]string{"request_id": "merchant-request-status"},
	})
}

type authedHandler func(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string)

func requireAuth(authSvc *auth.Service, next authedHandler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		auth := r.Header.Get("Authorization")
		token := strings.TrimPrefix(auth, "Bearer ")
		if token == "" {
			writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "Missing bearer token.")
			return
		}
		claims, err := jwtParse(token, authSvc)
		if err != nil {
			writeError(w, http.StatusUnauthorized, "INVALID_TOKEN", "Invalid or expired token.")
			return
		}
		next(authSvc, authSvc.DB(), w, r, claims.Subject)
	}
}

func requireAdmin(authSvc *auth.Service, next authedHandler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		auth := r.Header.Get("Authorization")
		token := strings.TrimPrefix(auth, "Bearer ")
		if token == "" {
			writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "Missing bearer token.")
			return
		}
		claims, err := jwtParse(token, authSvc)
		if err != nil {
			writeError(w, http.StatusUnauthorized, "INVALID_TOKEN", "Invalid or expired token.")
			return
		}
		var isAdmin bool
		err = authSvc.DB().QueryRowContext(r.Context(), `
			SELECT EXISTS(SELECT 1 FROM user_roles WHERE user_id = $1 AND role = 'admin')
		`, claims.Subject).Scan(&isAdmin)
		if err != nil || !isAdmin {
			writeError(w, http.StatusForbidden, "FORBIDDEN", "Administrative privilege required.")
			return
		}
		next(authSvc, authSvc.DB(), w, r, claims.Subject)
	}
}

func jwtParse(token string, authSvc *auth.Service) (*jwt.RegisteredClaims, error) {
	claims := &jwt.RegisteredClaims{}
	_, err := jwt.ParseWithClaims(token, claims, func(t *jwt.Token) (interface{}, error) {
		return []byte(authSvc.ConfigSecret()), nil
	})
	if err != nil {
		return nil, err
	}
	if !claims.VerifyExpiresAt(authSvc.Now(), true) {
		return nil, errors.New("expired")
	}
	return claims, nil
}

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

var _ = os.Getenv
