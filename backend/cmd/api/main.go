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
	mux.HandleFunc("GET /api/v1/merchant/products", requireAuth(authSvc, merchantListProducts))
	mux.HandleFunc("POST /api/v1/merchant/products", requireAuth(authSvc, merchantCreateProduct))
	mux.HandleFunc("PATCH /api/v1/merchant/products/{id}", requireAuth(authSvc, merchantUpdateProduct))
	mux.HandleFunc("DELETE /api/v1/merchant/products/{id}", requireAuth(authSvc, merchantDeleteProduct))
	mux.HandleFunc("GET /api/v1/merchant/services", requireAuth(authSvc, merchantListServices))
	mux.HandleFunc("POST /api/v1/merchant/services", requireAuth(authSvc, merchantCreateService))
	mux.HandleFunc("PATCH /api/v1/merchant/services/{id}", requireAuth(authSvc, merchantUpdateService))
	mux.HandleFunc("DELETE /api/v1/merchant/services/{id}", requireAuth(authSvc, merchantDeleteService))
	mux.HandleFunc("GET /api/v1/merchant/operating-hours", requireAuth(authSvc, merchantGetOperatingHours))
	mux.HandleFunc("PUT /api/v1/merchant/operating-hours", requireAuth(authSvc, merchantUpdateOperatingHours))
	mux.HandleFunc("GET /api/v1/merchant/coverage", requireAuth(authSvc, merchantGetCoverage))
	mux.HandleFunc("PUT /api/v1/merchant/coverage", requireAuth(authSvc, merchantUpdateCoverage))

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

func merchantListProducts(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	var bizID string
	err := db.QueryRowxContext(r.Context(), `SELECT id FROM businesses WHERE owner_user_id = $1 AND status != 'deleted' LIMIT 1`, userID).Scan(&bizID)
	if err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Business profile not found.")
		return
	}
	rows, err := db.QueryxContext(r.Context(), `
		SELECT id, business_id, name, description, price, currency, stock_status, is_published, image_url, updated_at
		FROM products
		WHERE business_id = $1
		ORDER BY updated_at DESC
	`, bizID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load products.")
		return
	}
	defer rows.Close()

	var products []discovery.Product
	for rows.Next() {
		var p discovery.Product
		var price sql.NullFloat64
		var desc, image sql.NullString
		var updated sql.NullTime
		if err := rows.Scan(&p.ID, &p.BusinessID, &p.Name, &desc, &price, &p.Currency,
			&p.StockStatus, &p.IsPublished, &image, &updated); err != nil {
			continue
		}
		if desc.Valid {
			p.Description = desc.String
		}
		if price.Valid {
			p.Price = &price.Float64
		}
		if image.Valid {
			p.ImageURL = image.String
		}
		products = append(products, p)
	}
	writeJSON(w, http.StatusOK, envelope{
		"data": products,
		"meta": map[string]string{"request_id": "merchant-products"},
	})
}

func merchantCreateProduct(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	var bizID string
	err := db.QueryRowxContext(r.Context(), `SELECT id FROM businesses WHERE owner_user_id = $1 AND status != 'deleted' LIMIT 1`, userID).Scan(&bizID)
	if err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Business profile not found.")
		return
	}
	var req struct {
		Name        string   `json:"name"`
		Description *string  `json:"description"`
		Price       *float64 `json:"price"`
		StockStatus string   `json:"stock_status"`
		IsPublished bool     `json:"is_published"`
		ImageURL    *string  `json:"image_url"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || strings.TrimSpace(req.Name) == "" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Product name is required.")
		return
	}
	if req.StockStatus == "" {
		req.StockStatus = "in_stock"
	}
	var newID string
	err = db.QueryRowxContext(r.Context(), `
		INSERT INTO products (business_id, name, description, price, stock_status, is_published, image_url, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, now())
		RETURNING id
	`, bizID, req.Name, req.Description, req.Price, req.StockStatus, req.IsPublished, req.ImageURL).Scan(&newID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to create product: "+err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, envelope{
		"data": map[string]interface{}{"id": newID, "status": "created"},
		"meta": map[string]string{"request_id": "merchant-create-product"},
	})
}

func merchantUpdateProduct(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	var bizID string
	err := db.QueryRowxContext(r.Context(), `SELECT id FROM businesses WHERE owner_user_id = $1 AND status != 'deleted' LIMIT 1`, userID).Scan(&bizID)
	if err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Business profile not found.")
		return
	}
	prodID := r.PathValue("id")
	var req struct {
		Name        *string  `json:"name"`
		Description *string  `json:"description"`
		Price       *float64 `json:"price"`
		StockStatus *string  `json:"stock_status"`
		IsPublished *bool    `json:"is_published"`
		ImageURL    *string  `json:"image_url"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Invalid payload.")
		return
	}
	setParts := []string{"updated_at = now()"}
	args := []interface{}{prodID, bizID}
	argIdx := 3
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
	if req.Price != nil {
		setParts = append(setParts, fmt.Sprintf("price = $%d", argIdx))
		args = append(args, *req.Price)
		argIdx++
	}
	if req.StockStatus != nil {
		setParts = append(setParts, fmt.Sprintf("stock_status = $%d", argIdx))
		args = append(args, *req.StockStatus)
		argIdx++
	}
	if req.IsPublished != nil {
		setParts = append(setParts, fmt.Sprintf("is_published = $%d", argIdx))
		args = append(args, *req.IsPublished)
		argIdx++
	}
	if req.ImageURL != nil {
		setParts = append(setParts, fmt.Sprintf("image_url = $%d", argIdx))
		args = append(args, *req.ImageURL)
		argIdx++
	}
	query := fmt.Sprintf("UPDATE products SET %s WHERE id = $1 AND business_id = $2", strings.Join(setParts, ", "))
	_, err = db.ExecContext(r.Context(), query, args...)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to update product.")
		return
	}
	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]string{"status": "updated"},
		"meta": map[string]string{"request_id": "merchant-update-product"},
	})
}

func merchantDeleteProduct(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	var bizID string
	err := db.QueryRowxContext(r.Context(), `SELECT id FROM businesses WHERE owner_user_id = $1 AND status != 'deleted' LIMIT 1`, userID).Scan(&bizID)
	if err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Business profile not found.")
		return
	}
	prodID := r.PathValue("id")
	_, err = db.ExecContext(r.Context(), `DELETE FROM products WHERE id = $1 AND business_id = $2`, prodID, bizID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to delete product.")
		return
	}
	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]string{"status": "deleted"},
		"meta": map[string]string{"request_id": "merchant-delete-product"},
	})
}

func merchantListServices(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	var bizID string
	err := db.QueryRowxContext(r.Context(), `SELECT id FROM businesses WHERE owner_user_id = $1 AND status != 'deleted' LIMIT 1`, userID).Scan(&bizID)
	if err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Business profile not found.")
		return
	}
	rows, err := db.QueryxContext(r.Context(), `
		SELECT id, business_id, name, description, indicative_price_min, indicative_price_max, currency, is_active
		FROM services
		WHERE business_id = $1
		ORDER BY name ASC
	`, bizID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load services.")
		return
	}
	defer rows.Close()

	var services []discovery.ServiceOffering
	for rows.Next() {
		var srv discovery.ServiceOffering
		var desc sql.NullString
		var pmin, pmax sql.NullFloat64
		if err := rows.Scan(&srv.ID, &srv.BusinessID, &srv.Name, &desc, &pmin, &pmax, &srv.Currency, &srv.IsActive); err != nil {
			continue
		}
		if desc.Valid {
			srv.Description = desc.String
		}
		if pmin.Valid {
			srv.PriceMin = &pmin.Float64
		}
		if pmax.Valid {
			srv.PriceMax = &pmax.Float64
		}
		services = append(services, srv)
	}
	writeJSON(w, http.StatusOK, envelope{
		"data": services,
		"meta": map[string]string{"request_id": "merchant-services"},
	})
}

func merchantCreateService(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	var bizID string
	err := db.QueryRowxContext(r.Context(), `SELECT id FROM businesses WHERE owner_user_id = $1 AND status != 'deleted' LIMIT 1`, userID).Scan(&bizID)
	if err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Business profile not found.")
		return
	}
	var req struct {
		Name        string   `json:"name"`
		Description *string  `json:"description"`
		PriceMin    *float64 `json:"indicative_price_min"`
		PriceMax    *float64 `json:"indicative_price_max"`
		IsActive    bool     `json:"is_active"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || strings.TrimSpace(req.Name) == "" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Service name is required.")
		return
	}
	var newID string
	err = db.QueryRowxContext(r.Context(), `
		INSERT INTO services (business_id, name, description, indicative_price_min, indicative_price_max, is_active)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id
	`, bizID, req.Name, req.Description, req.PriceMin, req.PriceMax, req.IsActive).Scan(&newID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to create service: "+err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, envelope{
		"data": map[string]interface{}{"id": newID, "status": "created"},
		"meta": map[string]string{"request_id": "merchant-create-service"},
	})
}

func merchantUpdateService(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	var bizID string
	err := db.QueryRowxContext(r.Context(), `SELECT id FROM businesses WHERE owner_user_id = $1 AND status != 'deleted' LIMIT 1`, userID).Scan(&bizID)
	if err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Business profile not found.")
		return
	}
	srvID := r.PathValue("id")
	var req struct {
		Name        *string  `json:"name"`
		Description *string  `json:"description"`
		PriceMin    *float64 `json:"indicative_price_min"`
		PriceMax    *float64 `json:"indicative_price_max"`
		IsActive    *bool    `json:"is_active"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Invalid payload.")
		return
	}
	setParts := []string{}
	args := []interface{}{srvID, bizID}
	argIdx := 3
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
	if req.PriceMin != nil {
		setParts = append(setParts, fmt.Sprintf("indicative_price_min = $%d", argIdx))
		args = append(args, *req.PriceMin)
		argIdx++
	}
	if req.PriceMax != nil {
		setParts = append(setParts, fmt.Sprintf("indicative_price_max = $%d", argIdx))
		args = append(args, *req.PriceMax)
		argIdx++
	}
	if req.IsActive != nil {
		setParts = append(setParts, fmt.Sprintf("is_active = $%d", argIdx))
		args = append(args, *req.IsActive)
		argIdx++
	}
	if len(setParts) == 0 {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "No fields to update.")
		return
	}
	query := fmt.Sprintf("UPDATE services SET %s WHERE id = $1 AND business_id = $2", strings.Join(setParts, ", "))
	_, err = db.ExecContext(r.Context(), query, args...)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to update service.")
		return
	}
	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]string{"status": "updated"},
		"meta": map[string]string{"request_id": "merchant-update-service"},
	})
}

func merchantDeleteService(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	var bizID string
	err := db.QueryRowxContext(r.Context(), `SELECT id FROM businesses WHERE owner_user_id = $1 AND status != 'deleted' LIMIT 1`, userID).Scan(&bizID)
	if err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Business profile not found.")
		return
	}
	srvID := r.PathValue("id")
	_, err = db.ExecContext(r.Context(), `DELETE FROM services WHERE id = $1 AND business_id = $2`, srvID, bizID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to delete service.")
		return
	}
	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]string{"status": "deleted"},
		"meta": map[string]string{"request_id": "merchant-delete-service"},
	})
}

func merchantGetOperatingHours(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	var bizID string
	err := db.QueryRowxContext(r.Context(), `SELECT id FROM businesses WHERE owner_user_id = $1 AND status != 'deleted' LIMIT 1`, userID).Scan(&bizID)
	if err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Business profile not found.")
		return
	}
	rows, err := db.QueryxContext(r.Context(), `
		SELECT weekday, opens_at, closes_at, is_closed
		FROM business_hours
		WHERE business_id = $1
		ORDER BY weekday ASC
	`, bizID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load business hours.")
		return
	}
	defer rows.Close()

	type hourItem struct {
		Weekday  int     `json:"weekday"`
		OpensAt  *string `json:"opens_at"`
		ClosesAt *string `json:"closes_at"`
		IsClosed bool    `json:"is_closed"`
	}
	hoursMap := make(map[int]hourItem)
	for rows.Next() {
		var h hourItem
		var op, cl sql.NullString
		if err := rows.Scan(&h.Weekday, &op, &cl, &h.IsClosed); err == nil {
			if op.Valid {
				h.OpensAt = &op.String
			}
			if cl.Valid {
				h.ClosesAt = &cl.String
			}
			hoursMap[h.Weekday] = h
		}
	}
	var result []hourItem
	for i := 0; i <= 6; i++ {
		if h, ok := hoursMap[i]; ok {
			result = append(result, h)
		} else {
			defOpen := "09:00:00"
			defClose := "20:00:00"
			isClosed := (i == 0)
			result = append(result, hourItem{
				Weekday:  i,
				OpensAt:  &defOpen,
				ClosesAt: &defClose,
				IsClosed: isClosed,
			})
		}
	}
	writeJSON(w, http.StatusOK, envelope{
		"data": result,
		"meta": map[string]string{"request_id": "merchant-hours"},
	})
}

func merchantUpdateOperatingHours(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	var bizID string
	err := db.QueryRowxContext(r.Context(), `SELECT id FROM businesses WHERE owner_user_id = $1 AND status != 'deleted' LIMIT 1`, userID).Scan(&bizID)
	if err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Business profile not found.")
		return
	}
	var req struct {
		Hours []struct {
			Weekday  int     `json:"weekday"`
			OpensAt  *string `json:"opens_at"`
			ClosesAt *string `json:"closes_at"`
			IsClosed bool    `json:"is_closed"`
		} `json:"hours"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Invalid hours payload.")
		return
	}

	tx, err := db.BeginTxx(r.Context(), nil)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Database transaction error.")
		return
	}
	defer tx.Rollback()

	for _, h := range req.Hours {
		if h.Weekday < 0 || h.Weekday > 6 {
			continue
		}
		// If closed, opens_at and closes_at can be null or default
		var op, cl interface{}
		if h.OpensAt != nil && *h.OpensAt != "" {
			op = *h.OpensAt
		}
		if h.ClosesAt != nil && *h.ClosesAt != "" {
			cl = *h.ClosesAt
		}
		if !h.IsClosed && (op == nil || cl == nil) {
			defOp := "09:00:00"
			defCl := "20:00:00"
			op = defOp
			cl = defCl
		}
		_, err := tx.ExecContext(r.Context(), `
			INSERT INTO business_hours (business_id, weekday, opens_at, closes_at, is_closed)
			VALUES ($1, $2, $3, $4, $5)
			ON CONFLICT (business_id, weekday)
			DO UPDATE SET opens_at = EXCLUDED.opens_at, closes_at = EXCLUDED.closes_at, is_closed = EXCLUDED.is_closed
		`, bizID, h.Weekday, op, cl, h.IsClosed)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to save hours: "+err.Error())
			return
		}
	}
	if err := tx.Commit(); err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Transaction commit error.")
		return
	}
	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]string{"status": "updated"},
		"meta": map[string]string{"request_id": "merchant-update-hours"},
	})
}

func merchantGetCoverage(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	var bizID, name, address, locality, city string
	var lat, lon sql.NullFloat64
	err := db.QueryRowxContext(r.Context(), `
		SELECT id, name, address_text, COALESCE(locality, ''), COALESCE(city, ''),
		       ST_Y(location::geometry) as latitude, ST_X(location::geometry) as longitude
		FROM businesses
		WHERE owner_user_id = $1 AND status != 'deleted'
		LIMIT 1
	`, userID).Scan(&bizID, &name, &address, &locality, &city, &lat, &lon)
	if err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Business profile not found: "+err.Error())
		return
	}

	var serviceRadiusM int = 5000
	var acceptsRequests bool = true
	var expYears sql.NullInt32
	var desc sql.NullString
	_ = db.QueryRowxContext(r.Context(), `
		SELECT service_radius_m, accepts_requests, experience_years, service_description
		FROM professional_profiles
		WHERE business_id = $1
	`, bizID).Scan(&serviceRadiusM, &acceptsRequests, &expYears, &desc)

	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]interface{}{
			"business_id":         bizID,
			"business_name":       name,
			"address_line1":       address,
			"locality":            locality,
			"city":                city,
			"latitude":            lat.Float64,
			"longitude":           lon.Float64,
			"service_radius_m":    serviceRadiusM,
			"accepts_requests":    acceptsRequests,
			"experience_years":    expYears.Int32,
			"service_description": desc.String,
		},
		"meta": map[string]string{"request_id": "merchant-coverage"},
	})
}

func merchantUpdateCoverage(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	var bizID string
	err := db.QueryRowxContext(r.Context(), `SELECT id FROM businesses WHERE owner_user_id = $1 AND status != 'deleted' LIMIT 1`, userID).Scan(&bizID)
	if err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Business profile not found.")
		return
	}
	var req struct {
		ServiceRadiusM     int     `json:"service_radius_m"`
		AcceptsRequests    bool    `json:"accepts_requests"`
		ExperienceYears    *int    `json:"experience_years"`
		ServiceDescription *string `json:"service_description"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Invalid coverage payload.")
		return
	}
	if req.ServiceRadiusM < 100 {
		req.ServiceRadiusM = 100
	}
	if req.ServiceRadiusM > 100000 {
		req.ServiceRadiusM = 100000
	}

	_, err = db.ExecContext(r.Context(), `
		INSERT INTO professional_profiles (business_id, service_radius_m, accepts_requests, experience_years, service_description, updated_at)
		VALUES ($1, $2, $3, $4, $5, now())
		ON CONFLICT (business_id)
		DO UPDATE SET
			service_radius_m = EXCLUDED.service_radius_m,
			accepts_requests = EXCLUDED.accepts_requests,
			experience_years = COALESCE(EXCLUDED.experience_years, professional_profiles.experience_years),
			service_description = COALESCE(EXCLUDED.service_description, professional_profiles.service_description),
			updated_at = now()
	`, bizID, req.ServiceRadiusM, req.AcceptsRequests, req.ExperienceYears, req.ServiceDescription)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to update coverage: "+err.Error())
		return
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]string{"status": "updated"},
		"meta": map[string]string{"request_id": "merchant-update-coverage"},
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
