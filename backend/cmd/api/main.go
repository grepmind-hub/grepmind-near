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
	"github.com/jmoiron/sqlx"

	"grepmind-near/backend/internal/auth"
	"grepmind-near/backend/internal/businessclaims"
	"grepmind-near/backend/internal/discovery"
	"grepmind-near/backend/internal/media"
	"grepmind-near/backend/internal/moderation"
	"grepmind-near/backend/internal/notifications"
	"grepmind-near/backend/internal/operations"
	"grepmind-near/backend/pkg/config"
	"grepmind-near/backend/pkg/database"
	"grepmind-near/backend/pkg/logger"
)

func main() {
	cfg := config.Load()
	logger.Init(cfg.LogLevel)
	log := logger.Log
	if err := cfg.ValidateAuth(); err != nil {
		log.Fatal().Err(err).Msg("unsafe authentication configuration")
	}

	db, err := database.Open(cfg.DBDSN(), 25, 25, 5*time.Minute)
	if err != nil {
		log.Fatal().Err(err).Msg("database connect failed")
	}
	defer db.Close()

	authSvc := auth.NewService(db, cfg)
	discSvc := discovery.NewService(db, cfg)
	modSvc := moderation.NewService(db, cfg)
	mediaSvc, err := media.NewService(db, cfg)
	if err != nil {
		log.Warn().Err(err).Msg("media service initialization warning")
	}
	notifHub := notifications.NewHub(db.DB)
	opsSvc := operations.NewService(db)

	mux := setupRouter(authSvc, discSvc, modSvc, mediaSvc, notifHub, opsSvc)

	srv := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      mux,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 0, // Disabled for long-lived Server-Sent Events (SSE) streams
		IdleTimeout:  120 * time.Second,
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

func setupRouter(authSvc *auth.Service, discSvc *discovery.Service, modSvc *moderation.Service, mediaSvc *media.Service, notifHub *notifications.Hub, opsSvc *operations.Service) *http.ServeMux {
	mux := http.NewServeMux()
	claimsSvc := businessclaims.NewService(authSvc.DB())

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, envelope{"status": "ok"})
	})

	// Real-Time Events (Server-Sent Events) & In-App Notifications (Option 5)
	if notifHub != nil {
		mux.HandleFunc("GET /api/v1/events", requireAuth(authSvc, func(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
			if !authorizeEventSubscription(r.Context(), db, r, userID) {
				writeError(w, http.StatusForbidden, "FORBIDDEN", "You do not have access to this event stream.")
				return
			}
			notifHub.ServeSSE(w, r)
		}))
		mux.HandleFunc("GET /api/v1/notifications", requireAuth(authSvc, func(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
			bizID := r.URL.Query().Get("business_id")
			requestedUserID := r.URL.Query().Get("user_id")
			if !authorizeNotificationScope(r.Context(), db, userID, bizID, requestedUserID) {
				writeError(w, http.StatusForbidden, "FORBIDDEN", "You do not have access to these notifications.")
				return
			}
			if bizID == "" && requestedUserID == "" {
				requestedUserID = userID
			}
			items, err := notifHub.ListNotifications(r.Context(), bizID, requestedUserID, 30)
			if err != nil {
				writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to list notifications: "+err.Error())
				return
			}
			writeJSON(w, http.StatusOK, envelope{
				"data": items,
				"meta": map[string]interface{}{"count": len(items)},
			})
		}))
		mux.HandleFunc("POST /api/v1/notifications/{id}/read", requireAuth(authSvc, func(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
			id := r.PathValue("id")
			if id == "" {
				writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Notification ID required")
				return
			}
			result, err := db.ExecContext(r.Context(), `
				UPDATE notifications n SET is_read = true
				WHERE n.id = $1 AND (n.user_id = $2 OR EXISTS (
					SELECT 1 FROM business_members bm WHERE bm.business_id = n.business_id AND bm.user_id = $2 AND bm.status = 'active'
					UNION SELECT 1 FROM businesses b WHERE b.id = n.business_id AND b.owner_user_id = $2 AND b.status != 'deleted'
				))
			`, id, userID)
			if err != nil {
				writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to mark as read")
				return
			}
			if count, _ := result.RowsAffected(); count == 0 {
				writeError(w, http.StatusNotFound, "NOT_FOUND", "Notification not found")
				return
			}
			writeJSON(w, http.StatusOK, envelope{"data": map[string]string{"id": id, "status": "read"}})
		}))
		mux.HandleFunc("POST /api/v1/notifications/broadcast-test", requireAdmin(authSvc, func(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
			var body struct {
				BusinessID string                 `json:"business_id"`
				RequestID  string                 `json:"request_id"`
				Title      string                 `json:"title"`
				Body       string                 `json:"body"`
				Type       string                 `json:"type"`
				Payload    map[string]interface{} `json:"payload"`
			}
			_ = json.NewDecoder(r.Body).Decode(&body)
			if body.Type == "" {
				body.Type = "service_request.created"
			}
			if body.Title == "" {
				body.Title = "Test Service Booking"
			}
			if body.Body == "" {
				body.Body = "Test notification broadcast"
			}
			notifHub.Publish(r.Context(), notifications.Event{
				Type:       body.Type,
				BusinessID: body.BusinessID,
				RequestID:  body.RequestID,
				Title:      body.Title,
				Body:       body.Body,
				Payload:    body.Payload,
			})
			writeJSON(w, http.StatusOK, envelope{"data": map[string]string{"status": "published"}})
		}))
	}

	// Media Object Storage (Option 4: MinIO Direct Upload)
	if mediaSvc != nil {
		mux.HandleFunc("POST /api/v1/media/upload", requireAuth(authSvc, func(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
			mediaSvc.Upload(w, r, userID)
		}))
		mux.HandleFunc("GET /api/v1/media", requireAuth(authSvc, func(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
			mediaSvc.ListMedia(w, r, userID)
		}))
	}

	mux.HandleFunc("POST /api/v1/auth/otp/request", authSvc.RequestOTP)
	mux.HandleFunc("POST /api/v1/auth/otp/verify", authSvc.VerifyOTP)
	mux.HandleFunc("POST /api/v1/auth/refresh", authSvc.Refresh)
	mux.HandleFunc("POST /api/v1/auth/logout", authSvc.Logout)

	mux.HandleFunc("GET /api/v1/me", requireAuth(authSvc, authMe))
	mux.HandleFunc("PATCH /api/v1/me", requireAuth(authSvc, authUpdateMe))

	mux.HandleFunc("GET /api/v1/categories", discSvc.ListCategories)
	mux.HandleFunc("GET /api/v1/locations", discSvc.Locations)
	mux.HandleFunc("GET /api/v1/businesses", discSvc.SearchBusinesses)
	mux.HandleFunc("GET /api/v1/businesses/{id}", discSvc.GetBusiness)
	mux.HandleFunc("GET /api/v1/businesses/{id}/products", discSvc.ListProducts)
	mux.HandleFunc("GET /api/v1/businesses/{id}/services", discSvc.ListServices)
	mux.HandleFunc("GET /api/v1/businesses/{id}/offers", discSvc.ListOffers)
	mux.HandleFunc("GET /api/v1/offers", discSvc.ListCityOffers)
	mux.HandleFunc("GET /api/v1/businesses/{id}/availability", opsSvc.Availability)
	mux.HandleFunc("GET /api/v1/merchant/businesses/{id}/availability", requireAuth(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
		opsSvc.MerchantAvailability(w, r, userID)
	}))
	mux.HandleFunc("POST /api/v1/merchant/businesses/{id}/availability-slots", requireAuth(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
		opsSvc.CreateAvailabilitySlot(w, r, userID)
	}))
	mux.HandleFunc("PATCH /api/v1/merchant/businesses/{id}/availability-slots/{slotId}", requireAuth(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
		opsSvc.UpdateAvailabilitySlot(w, r, userID)
	}))
	mux.HandleFunc("PUT /api/v1/merchant/businesses/{id}/availability-exceptions", requireAuth(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
		opsSvc.UpsertAvailabilityException(w, r, userID)
	}))
	mux.HandleFunc("GET /api/v1/nearby", discSvc.Nearby)
	mux.HandleFunc("POST /api/v1/businesses/{id}/orders", requireAuth(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
		opsSvc.CreateOrder(w, r, userID)
	}))
	mux.HandleFunc("GET /api/v1/customer/orders", requireAuth(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
		opsSvc.ListOrders(w, r, userID)
	}))
	mux.HandleFunc("GET /api/v1/orders/{id}", requireAuth(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
		opsSvc.GetOrder(w, r, userID)
	}))
	mux.HandleFunc("POST /api/v1/orders/{id}/cancel", requireAuth(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
		opsSvc.CancelOrder(w, r, userID)
	}))
	mux.HandleFunc("PATCH /api/v1/merchant/orders/{id}/status", requireAuth(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
		opsSvc.UpdateOrderStatus(w, r, userID)
	}))

	// Favorites (require auth)
	mux.HandleFunc("GET /api/v1/favorites", requireAuth(authSvc, discSvc.ListFavorites))
	mux.HandleFunc("POST /api/v1/businesses/{id}/favorite", requireAuth(authSvc, discSvc.ToggleFavorite))

	// Customer service requests & appointment bookings
	mux.HandleFunc("POST /api/v1/businesses/{id}/requests", requireAuth(authSvc, handleCreateServiceRequest(notifHub)))
	mux.HandleFunc("GET /api/v1/requests/{id}", requireAuth(authSvc, handleGetServiceRequest))
	mux.HandleFunc("POST /api/v1/requests/{id}/cancel", requireAuth(authSvc, handleCancelServiceRequest))
	mux.HandleFunc("GET /api/v1/customer/requests", requireAuth(authSvc, handleListCustomerRequests))

	// Analytics & unserved location demand tracking (Market expansion)
	mux.HandleFunc("POST /api/v1/analytics/unserved-location", handleRecordUnservedLocation(authSvc, authSvc.DB()))
	mux.HandleFunc("GET /api/v1/admin/unserved-locations", requireAdmin(authSvc, func(_ *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, _ string) {
		handleListUnservedLocations(db)(w, r)
	}))

	// Merchant workspace. Creating the first listing establishes merchant role
	// transactionally; existing merchant operations enforce ownership below.
	mux.HandleFunc("POST /api/v1/merchant/businesses", requireAuth(authSvc, func(_ *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
		createMerchantBusiness(db, w, r, userID)
	}))
	mux.HandleFunc("GET /api/v1/merchant/catalog-categories", requireAuth(authSvc, merchantCatalogCategories))
	mux.HandleFunc("POST /api/v1/merchant/catalog-categories", requireAuth(authSvc, merchantCatalogCategories))
	mux.HandleFunc("PATCH /api/v1/merchant/catalog-categories/{id}", requireAuth(authSvc, merchantCatalogCategories))
	mux.HandleFunc("DELETE /api/v1/merchant/catalog-categories/{id}", requireAuth(authSvc, merchantCatalogCategories))
	mux.HandleFunc("GET /api/v1/merchant/profile", requireAuth(authSvc, merchantProfile))
	mux.HandleFunc("GET /api/v1/merchant/businesses", requireAuth(authSvc, merchantListBusinesses))
	mux.HandleFunc("PATCH /api/v1/merchant/profile", requireAuth(authSvc, merchantUpdateProfile))
	mux.HandleFunc("GET /api/v1/merchant/requests", requireAuth(authSvc, merchantRequests))
	mux.HandleFunc("PATCH /api/v1/merchant/requests/{id}/status", requireAuth(authSvc, func(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
		merchantRequestStatus(authSvc, db, w, r, userID, notifHub)
	}))
	mux.HandleFunc("PATCH /api/v1/merchant/businesses/{bizId}/requests/{id}/status", requireAuth(authSvc, func(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
		merchantRequestStatus(authSvc, db, w, r, userID, notifHub)
	}))
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
	mux.HandleFunc("GET /api/v1/merchant/businesses/{id}/offers", requireAuth(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
		opsSvc.ListMerchantOffers(w, r, userID)
	}))
	mux.HandleFunc("POST /api/v1/merchant/businesses/{id}/offers", requireAuth(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
		opsSvc.CreateMerchantOffer(w, r, userID)
	}))
	mux.HandleFunc("PATCH /api/v1/merchant/offers/{id}", requireAuth(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
		opsSvc.UpdateMerchantOffer(w, r, userID)
	}))
	mux.HandleFunc("DELETE /api/v1/merchant/offers/{id}", requireAuth(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
		opsSvc.DeleteMerchantOffer(w, r, userID)
	}))
	mux.HandleFunc("GET /api/v1/merchant/coverage", requireAuth(authSvc, merchantGetCoverage))
	mux.HandleFunc("PUT /api/v1/merchant/coverage", requireAuth(authSvc, merchantUpdateCoverage))

	// Merchant team & staff access management
	mux.HandleFunc("GET /api/v1/merchant/businesses/{id}/members", requireAuth(authSvc, merchantListMembers))
	mux.HandleFunc("POST /api/v1/merchant/businesses/{id}/members", requireAuth(authSvc, merchantAddMember))
	mux.HandleFunc("DELETE /api/v1/merchant/businesses/{id}/members/{userId}", requireAuth(authSvc, merchantRevokeMember))
	mux.HandleFunc("GET /api/v1/merchant/members", requireAuth(authSvc, merchantListCurrentMembers))
	mux.HandleFunc("POST /api/v1/merchant/members", requireAuth(authSvc, merchantAddCurrentMember))
	mux.HandleFunc("DELETE /api/v1/merchant/members/{userId}", requireAuth(authSvc, merchantRevokeCurrentMember))
	mux.HandleFunc("GET /api/v1/merchant/claimable-businesses", requireAuth(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
		claimsSvc.Search(w, r, userID)
	}))
	mux.HandleFunc("GET /api/v1/merchant/business-claims", requireAuth(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
		claimsSvc.ListMine(w, r, userID)
	}))
	mux.HandleFunc("POST /api/v1/merchant/businesses/{id}/claim", requireAuth(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
		claimsSvc.Submit(w, r, userID)
	}))

	// Admin operations & moderation (Phase 4)
	mux.HandleFunc("GET /api/v1/admin/business-claims", requireAdmin(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, adminID string) {
		claimsSvc.ListPending(w, r, adminID)
	}))
	mux.HandleFunc("POST /api/v1/admin/business-claims/{id}/decision", requireAdmin(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, adminID string) {
		claimsSvc.Decide(w, r, adminID)
	}))
	mux.HandleFunc("GET /api/v1/admin/stats", requireAdmin(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, uid string) {
		modSvc.GetStats(w, r, uid)
	}))
	mux.HandleFunc("GET /api/v1/admin/trends", requireAdmin(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, uid string) {
		modSvc.GetTrends(w, r, uid)
	}))
	mux.HandleFunc("GET /api/v1/admin/listing-activity", requireAdmin(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, uid string) {
		modSvc.ListListingActivity(w, r, uid)
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
	mux.HandleFunc("GET /api/v1/admin/admins", requireAdmin(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, uid string) {
		modSvc.ListAdmins(w, r, uid)
	}))
	mux.HandleFunc("GET /api/v1/admin/user-access", requireAdmin(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, uid string) {
		modSvc.ListUserAccess(w, r, uid)
	}))
	mux.HandleFunc("POST /api/v1/admin/user-access", requirePrimarySuperadmin(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, uid string) {
		modSvc.SetUserAccess(w, r, uid)
	}))
	mux.HandleFunc("POST /api/v1/admin/admins", requirePrimarySuperadmin(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, uid string) {
		modSvc.AddAdmin(w, r, uid)
	}))
	mux.HandleFunc("DELETE /api/v1/admin/admins/{userId}", requirePrimarySuperadmin(authSvc, func(_ *auth.Service, _ *database.DB, w http.ResponseWriter, r *http.Request, uid string) {
		modSvc.RevokeAdmin(w, r, uid)
	}))

	return mux
}

func authMe(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	type userRow struct {
		ID                      string         `db:"id"`
		PhoneE164               string         `db:"phone_e164"`
		DisplayName             sql.NullString `db:"display_name"`
		AvatarURL               sql.NullString `db:"avatar_url"`
		Status                  string         `db:"status"`
		PreferredLanguage       string         `db:"preferred_language"`
		NotificationPreferences []byte         `db:"notification_preferences"`
	}
	var u userRow
	err := db.QueryRowxContext(r.Context(), `
		SELECT id, phone_e164, display_name, avatar_url, status, preferred_language, notification_preferences
		FROM users WHERE id = $1
	`, userID).Scan(&u.ID, &u.PhoneE164, &u.DisplayName, &u.AvatarURL, &u.Status, &u.PreferredLanguage, &u.NotificationPreferences)
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
			"id":                       u.ID,
			"phone_e164":               u.PhoneE164,
			"display_name":             u.DisplayName.String,
			"avatar_url":               u.AvatarURL.String,
			"status":                   u.Status,
			"preferred_language":       u.PreferredLanguage,
			"notification_preferences": json.RawMessage(u.NotificationPreferences),
			"roles":                    roles,
		},
		"meta": map[string]string{"request_id": "me"},
	})
}

func authUpdateMe(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	var input struct {
		DisplayName             *string         `json:"display_name"`
		PreferredLanguage       *string         `json:"preferred_language"`
		AvatarURL               *string         `json:"avatar_url"`
		NotificationPreferences map[string]bool `json:"notification_preferences"`
	}
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16*1024))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&input); err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Invalid profile settings.")
		return
	}
	if input.DisplayName != nil {
		name := strings.TrimSpace(*input.DisplayName)
		if len([]rune(name)) > 80 {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Display name must be 80 characters or fewer.")
			return
		}
		input.DisplayName = &name
	}
	if input.PreferredLanguage != nil && *input.PreferredLanguage != "en" && *input.PreferredLanguage != "or" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Choose a supported language.")
		return
	}
	if input.AvatarURL != nil {
		avatar := strings.TrimSpace(*input.AvatarURL)
		if avatar != "" && (!strings.HasPrefix(avatar, "/media/avatar/") || strings.Contains(avatar, "..")) {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Choose a profile photo uploaded to your account.")
			return
		}
		if avatar != "" {
			objectKey := strings.TrimPrefix(avatar, "/media/")
			var owned bool
			if err := db.GetContext(r.Context(), &owned, `
				SELECT EXISTS(SELECT 1 FROM media_uploads WHERE user_id = $1 AND purpose = 'avatar' AND object_key = $2)
			`, userID, objectKey); err != nil || !owned {
				writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Choose a profile photo uploaded to your account.")
				return
			}
		}
		input.AvatarURL = &avatar
	}
	if input.NotificationPreferences != nil {
		allowed := map[string]bool{"booking_updates": true, "offers": true, "service_updates": true}
		if len(input.NotificationPreferences) != len(allowed) {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Invalid notification preferences.")
			return
		}
		for key := range input.NotificationPreferences {
			if !allowed[key] {
				writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Invalid notification preferences.")
				return
			}
		}
	}

	preferences, err := json.Marshal(input.NotificationPreferences)
	if err != nil && input.NotificationPreferences != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Invalid notification preferences.")
		return
	}
	_, err = db.ExecContext(r.Context(), `
		UPDATE users SET
			display_name = COALESCE($1, display_name),
			preferred_language = COALESCE($2, preferred_language),
			avatar_url = COALESCE($3, avatar_url),
			notification_preferences = COALESCE($4::jsonb, notification_preferences),
			updated_at = now()
		WHERE id = $5 AND status = 'active'
	`, input.DisplayName, input.PreferredLanguage, input.AvatarURL, nullableJSON(preferences, input.NotificationPreferences != nil), userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to update profile settings.")
		return
	}
	authMe(authSvc, db, w, r, userID)
}

func nullableJSON(value []byte, valid bool) interface{} {
	if !valid {
		return nil
	}
	return string(value)
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

	// Resolve an owned or explicitly requested member business. The resolver
	// enforces active business_members membership before any profile data loads.
	bizID, _, err := resolveMerchantBusiness(r.Context(), db, userID, r.URL.Query().Get("business_id"))
	if err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Business profile not found.")
		return
	}
	var bizName, bizSlug string
	var bizDesc, bizAddr, bizCity, bizPhone, bizLocality, bizCategorySlug, bizCategoryName sql.NullString
	var bizCover sql.NullString
	var bizStatus, bizVerify sql.NullString
	var lat, lng sql.NullFloat64
	err = db.QueryRowxContext(r.Context(), `
		SELECT b.id, b.name, b.slug, b.description, b.address_text, b.city, b.phone_e164, b.cover_photo_url,
		       b.status, b.verification_status, ST_Y(b.location::geometry), ST_X(b.location::geometry)
		       , b.locality, b.category_slug, c.name
		FROM businesses b
		LEFT JOIN categories c ON c.slug=b.category_slug
		WHERE b.id = $1 AND b.status != 'deleted'
	`, bizID).Scan(&bizID, &bizName, &bizSlug, &bizDesc, &bizAddr, &bizCity, &bizPhone, &bizCover,
		&bizStatus, &bizVerify, &lat, &lng, &bizLocality, &bizCategorySlug, &bizCategoryName)
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
			"description":         nullableStringValue(bizDesc),
			"address_text":        nullableStringValue(bizAddr),
			"city":                nullableStringValue(bizCity),
			"locality":            nullableStringValue(bizLocality),
			"category_slug":       nullableStringValue(bizCategorySlug),
			"category_name":       nullableStringValue(bizCategoryName),
			"phone_e164":          nullableStringValue(bizPhone),
			"cover_photo_url":     nullableStringValue(bizCover),
			"status":              statusStr,
			"verification_status": verifyStr,
			"latitude":            latVal,
			"longitude":           lngVal,
			"business_hours":      hours,
		},
		"meta": map[string]string{"request_id": "merchant-profile"},
	})
}

func merchantListBusinesses(_ *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	rows, err := db.QueryxContext(r.Context(), `
		SELECT b.id::text, b.name, b.category_slug, COALESCE(c.name,''), COALESCE(b.locality,''),
		       COALESCE(b.city,''), COALESCE(b.phone_e164,''), COALESCE(b.address_text,''),
		       COALESCE(b.cover_photo_url,''), b.status, b.verification_status,
	       COALESCE(pp.accepts_requests,false), COALESCE(pp.service_radius_m,5000)
		FROM businesses b
		LEFT JOIN categories c ON c.slug=b.category_slug
		LEFT JOIN professional_profiles pp ON pp.business_id=b.id
		WHERE b.status!='deleted' AND (b.owner_user_id=$1 OR EXISTS (
			SELECT 1 FROM business_members bm WHERE bm.business_id=b.id AND bm.user_id=$1 AND bm.status='active'
		))
		ORDER BY CASE WHEN b.owner_user_id=$1 THEN 0 ELSE 1 END, b.created_at DESC
	`, userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load accessible businesses.")
		return
	}
	defer rows.Close()
	items := make([]map[string]interface{}, 0)
	for rows.Next() {
		var id, name, categorySlug, categoryName, locality, city, phone, address, cover, status, verification string
		var accepts bool
		var radius int
		if err := rows.Scan(&id, &name, &categorySlug, &categoryName, &locality, &city, &phone, &address, &cover, &status, &verification, &accepts, &radius); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to read accessible businesses.")
			return
		}
		items = append(items, map[string]interface{}{
			"id": id, "name": name, "category_slug": categorySlug, "category_name": categoryName,
			"locality": locality, "city": city, "phone_e164": phone, "address_text": address,
			"cover_photo_url": cover, "status": status, "verification_status": verification,
			"accepts_requests": accepts, "service_radius_m": radius,
		})
	}
	writeJSON(w, http.StatusOK, envelope{"data": items, "meta": map[string]string{"request_id": "merchant-businesses"}})
}

func merchantUpdateProfile(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	var req struct {
		Name          *string `json:"name"`
		Description   *string `json:"description"`
		AddressText   *string `json:"address_text"`
		City          *string `json:"city"`
		PhoneE164     *string `json:"phone_e164"`
		CoverPhotoURL *string `json:"cover_photo_url"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Invalid request body.")
		return
	}

	bizID, ok := merchantWorkspaceBusiness(w, r, db, userID, "owner")
	if !ok {
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
		city := strings.ToLower(strings.TrimSpace(*req.City))
		if city != "cuttack" && city != "jajpur" {
			writeError(w, 400, "VALIDATION_ERROR", "Only Cuttack and Jajpur are supported.")
			return
		}
		setParts = append(setParts, fmt.Sprintf("city = $%d", argIdx))
		args = append(args, *req.City)
		argIdx++
	}
	if req.PhoneE164 != nil {
		setParts = append(setParts, fmt.Sprintf("phone_e164 = $%d", argIdx))
		args = append(args, *req.PhoneE164)
		argIdx++
	}
	if req.CoverPhotoURL != nil {
		setParts = append(setParts, fmt.Sprintf("cover_photo_url = $%d", argIdx))
		args = append(args, strings.TrimSpace(*req.CoverPhotoURL))
		argIdx++
	}

	if len(setParts) == 0 {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "No fields to update.")
		return
	}

	query := fmt.Sprintf("UPDATE businesses SET %s WHERE id = $1", strings.Join(setParts, ", "))
	_, err := db.ExecContext(r.Context(), query, args...)
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
	bizID, ok := merchantWorkspaceBusiness(w, r, db, userID, "view")
	if !ok {
		return
	}

	// Get service requests for this business
	type reqItem struct {
		ID            string  `json:"id"`
		CustomerName  string  `json:"customer_name"`
		CustomerPhone string  `json:"customer_phone"`
		ServiceName   *string `json:"service_name"`
		Description   string  `json:"description"`
		RequestedFor  *string `json:"requested_for"`
		Status        string  `json:"status"`
		CreatedAt     string  `json:"created_at"`
		UpdatedAt     string  `json:"updated_at"`
	}
	var requests []reqItem
	rRows, err := db.QueryxContext(r.Context(), `
		SELECT sr.id, u.phone_e164 as customer_phone, u.display_name as customer_name,
		       COALESCE(s.name, 'Service request'), sr.description, sr.requested_for, sr.status,
		       sr.created_at, sr.updated_at
		FROM service_requests sr
		JOIN users u ON u.id = sr.customer_user_id
		LEFT JOIN services s ON s.id = sr.service_id AND s.business_id=sr.business_id
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

func merchantRequestStatus(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string, notifHub *notifications.Hub) {
	// Support multi-branch switcher via query param ?business_id=... or path {bizId}
	var bizID string
	requestedBiz := r.PathValue("bizId")
	if requestedBiz == "" {
		requestedBiz = r.URL.Query().Get("business_id")
	}
	if requestedBiz != "" {
		var ok bool
		_ = db.QueryRowxContext(r.Context(), `
			SELECT EXISTS(
				SELECT 1 FROM businesses WHERE id = $1 AND owner_user_id = $2 AND status != 'deleted'
				UNION
				SELECT 1 FROM business_members WHERE business_id = $1 AND user_id = $2 AND status = 'active'
			)
		`, requestedBiz, userID).Scan(&ok)
		if ok {
			bizID = requestedBiz
		}
	}
	if bizID == "" {
		err := db.QueryRowxContext(r.Context(), `SELECT id FROM businesses WHERE owner_user_id = $1 AND status != 'deleted' LIMIT 1`, userID).Scan(&bizID)
		if err != nil {
			writeError(w, http.StatusNotFound, "NOT_FOUND", "Business profile not found.")
			return
		}
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

	if reqBody.Status != "accepted" && reqBody.Status != "declined" && reqBody.Status != "in_progress" && reqBody.Status != "rescheduled" && reqBody.Status != "completed" && reqBody.Status != "cancelled" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Invalid status. Use: accepted, in_progress, rescheduled, declined, completed, cancelled.")
		return
	}

	var previousStatus string
	err := db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := tx.QueryRowxContext(r.Context(), `SELECT status FROM service_requests WHERE id=$1 AND business_id=$2 FOR UPDATE`, reqID, bizID).Scan(&previousStatus); err != nil {
			return sql.ErrNoRows
		}
		if !validServiceRequestTransition(previousStatus, reqBody.Status) {
			return errors.New("invalid request transition")
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE service_requests SET status=$1,updated_at=now() WHERE id=$2 AND business_id=$3`, reqBody.Status, reqID, bizID); err != nil {
			return err
		}
		if reqBody.Status == "declined" || reqBody.Status == "cancelled" {
			if _, err := tx.ExecContext(r.Context(), `UPDATE availability_slots SET booked_count=GREATEST(booked_count-1,0),updated_at=now() WHERE id=(SELECT slot_id FROM service_requests WHERE id=$1 AND business_id=$2) AND booked_count>0`, reqID, bizID); err != nil {
				return err
			}
		}
		return nil
	})
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Request not found.")
		return
	}
	if err != nil {
		if err.Error() == "invalid request transition" {
			writeError(w, http.StatusConflict, "INVALID_STATE", "This request cannot transition from its current state.")
			return
		}
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to update request status.")
		return
	}

	// Publish real-time status update event to SSE subscribers
	if notifHub != nil {
		notifHub.Publish(r.Context(), notifications.Event{
			Type:       "service_request.status_updated",
			BusinessID: bizID,
			RequestID:  reqID,
			Title:      "Booking Status Updated",
			Body:       fmt.Sprintf("Service request status changed to %s", reqBody.Status),
			Payload: map[string]interface{}{
				"request_id":  reqID,
				"business_id": bizID,
				"status":      reqBody.Status,
				"updated_at":  time.Now().UTC().Format(time.RFC3339),
			},
		})
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]interface{}{
			"id":     reqID,
			"status": reqBody.Status,
		},
		"meta": map[string]string{"request_id": "merchant-request-status"},
	})
}

func validServiceRequestTransition(from, to string) bool {
	allowed := map[string]map[string]bool{
		"requested":   {"accepted": true, "declined": true, "cancelled": true},
		"accepted":    {"in_progress": true, "rescheduled": true, "cancelled": true},
		"rescheduled": {"accepted": true, "cancelled": true},
		"in_progress": {"completed": true, "cancelled": true},
	}
	return allowed[from][to]
}

func merchantListProducts(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	bizID, ok := merchantWorkspaceBusiness(w, r, db, userID, "view")
	if !ok {
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

	products := make([]discovery.Product, 0)
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
	bizID, ok := merchantWorkspaceBusiness(w, r, db, userID, "manage")
	if !ok {
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
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&req); err != nil || strings.TrimSpace(req.Name) == "" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Product name is required.")
		return
	}
	if req.StockStatus == "" {
		req.StockStatus = "unknown"
	}
	if !validProductInput(req.Name, req.Price, req.StockStatus) || req.Description != nil && len(*req.Description) > 2000 {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Product name, price, or stock status is invalid.")
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	var newID string
	err := db.QueryRowxContext(r.Context(), `
		INSERT INTO products (business_id, name, description, price, stock_status, is_published, image_url, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, now())
		RETURNING id
	`, bizID, req.Name, req.Description, req.Price, req.StockStatus, req.IsPublished, req.ImageURL).Scan(&newID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to create product.")
		return
	}
	writeJSON(w, http.StatusCreated, envelope{
		"data": map[string]interface{}{"id": newID, "status": "created"},
		"meta": map[string]string{"request_id": "merchant-create-product"},
	})
}

func merchantUpdateProduct(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	bizID, ok := merchantWorkspaceBusiness(w, r, db, userID, "manage")
	if !ok {
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
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Invalid payload.")
		return
	}
	if req.Name != nil && (len(strings.TrimSpace(*req.Name)) < 2 || len(strings.TrimSpace(*req.Name)) > 100) || req.Description != nil && len(*req.Description) > 2000 || req.Price != nil && (*req.Price < 0 || *req.Price > 9999999999.99) || req.StockStatus != nil && !validStockStatus(*req.StockStatus) {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Product name, price, or stock status is invalid.")
		return
	}
	if req.Name != nil {
		trimmed := strings.TrimSpace(*req.Name)
		req.Name = &trimmed
	}
	if req.Name == nil && req.Description == nil && req.Price == nil && req.StockStatus == nil && req.IsPublished == nil && req.ImageURL == nil {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "No product fields to update.")
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
	result, err := db.ExecContext(r.Context(), query, args...)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to update product.")
		return
	}
	if affected, _ := result.RowsAffected(); affected == 0 {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Product not found.")
		return
	}
	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]string{"status": "updated"},
		"meta": map[string]string{"request_id": "merchant-update-product"},
	})
}

func merchantDeleteProduct(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	bizID, ok := merchantWorkspaceBusiness(w, r, db, userID, "manage")
	if !ok {
		return
	}
	prodID := r.PathValue("id")
	result, err := db.ExecContext(r.Context(), `DELETE FROM products WHERE id = $1 AND business_id = $2`, prodID, bizID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to delete product.")
		return
	}
	if affected, _ := result.RowsAffected(); affected == 0 {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Product not found.")
		return
	}
	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]string{"status": "deleted"},
		"meta": map[string]string{"request_id": "merchant-delete-product"},
	})
}

func merchantListServices(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	bizID, ok := merchantWorkspaceBusiness(w, r, db, userID, "view")
	if !ok {
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
	bizID, ok := merchantWorkspaceBusiness(w, r, db, userID, "manage")
	if !ok {
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
	err := db.QueryRowxContext(r.Context(), `
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
	bizID, ok := merchantWorkspaceBusiness(w, r, db, userID, "manage")
	if !ok {
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
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&req); err != nil {
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
	_, err := db.ExecContext(r.Context(), query, args...)
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
	bizID, ok := merchantWorkspaceBusiness(w, r, db, userID, "manage")
	if !ok {
		return
	}
	srvID := r.PathValue("id")
	_, err := db.ExecContext(r.Context(), `DELETE FROM services WHERE id = $1 AND business_id = $2`, srvID, bizID)
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
	bizID, ok := merchantWorkspaceBusiness(w, r, db, userID, "view")
	if !ok {
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
	var result []hourItem
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
			result = append(result, h)
		}
	}
	writeJSON(w, http.StatusOK, envelope{
		"data": result,
		"meta": map[string]string{"request_id": "merchant-hours"},
	})
}

func merchantUpdateOperatingHours(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	bizID, ok := merchantWorkspaceBusiness(w, r, db, userID, "manage")
	if !ok {
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
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Invalid hours payload.")
		return
	}
	if len(req.Hours) == 0 || len(req.Hours) > 7 {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Provide one to seven operating-hour entries.")
		return
	}
	seenWeekdays := make(map[int]bool, len(req.Hours))
	for _, h := range req.Hours {
		if h.Weekday < 0 || h.Weekday > 6 || seenWeekdays[h.Weekday] {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Weekdays must be unique values from 0 through 6.")
			return
		}
		seenWeekdays[h.Weekday] = true
		if h.IsClosed {
			continue
		}
		if h.OpensAt == nil || h.ClosesAt == nil || !validBusinessTime(*h.OpensAt) || !validBusinessTime(*h.ClosesAt) || *h.OpensAt == *h.ClosesAt {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Open days require valid, different opening and closing times.")
			return
		}
	}

	tx, err := db.BeginTxx(r.Context(), nil)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Database transaction error.")
		return
	}
	defer tx.Rollback()

	for _, h := range req.Hours {
		// If closed, opens_at and closes_at can be null or default
		var op, cl interface{}
		if h.OpensAt != nil && *h.OpensAt != "" {
			op = *h.OpensAt
		}
		if h.ClosesAt != nil && *h.ClosesAt != "" {
			cl = *h.ClosesAt
		}
		_, err := tx.ExecContext(r.Context(), `
			INSERT INTO business_hours (business_id, weekday, opens_at, closes_at, is_closed)
			VALUES ($1, $2, $3, $4, $5)
			ON CONFLICT (business_id, weekday)
			DO UPDATE SET opens_at = EXCLUDED.opens_at, closes_at = EXCLUDED.closes_at, is_closed = EXCLUDED.is_closed
		`, bizID, h.Weekday, op, cl, h.IsClosed)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to save hours.")
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
	requestedBizID, ok := merchantWorkspaceBusiness(w, r, db, userID, "view")
	if !ok {
		return
	}
	err := db.QueryRowxContext(r.Context(), `
		SELECT id, name, address_text, COALESCE(locality, ''), COALESCE(city, ''),
		       ST_Y(location::geometry) as latitude, ST_X(location::geometry) as longitude
		FROM businesses
		WHERE id = $1 AND status != 'deleted'
	`, requestedBizID).Scan(&bizID, &name, &address, &locality, &city, &lat, &lon)
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
	bizID, ok := merchantWorkspaceBusiness(w, r, db, userID, "manage")
	if !ok {
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

	_, err := db.ExecContext(r.Context(), `
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

// ---------------------------------------------------------------
// Merchant Team & Staff Multi-User Access Handlers
// ---------------------------------------------------------------

type memberItem struct {
	ID          string    `json:"id" db:"id"`
	BusinessID  string    `json:"business_id" db:"business_id"`
	UserID      string    `json:"user_id" db:"user_id"`
	DisplayName string    `json:"display_name" db:"display_name"`
	PhoneE164   string    `json:"phone_e164" db:"phone_e164"`
	Role        string    `json:"role" db:"role"`
	Status      string    `json:"status" db:"status"`
	CreatedAt   time.Time `json:"created_at" db:"created_at"`
}

func resolveMerchantBusiness(ctx context.Context, db *database.DB, userID string, explicitBizID string) (string, string, error) {
	if explicitBizID != "" {
		var role string
		err := db.QueryRowxContext(ctx, `
			SELECT role FROM business_members 
			WHERE business_id = $1 AND user_id = $2 AND status = 'active'
		`, explicitBizID, userID).Scan(&role)
		if err == nil {
			return explicitBizID, role, nil
		}
		var ownerID string
		err = db.QueryRowxContext(ctx, `
			SELECT owner_user_id FROM businesses WHERE id = $1 AND status != 'deleted'
		`, explicitBizID).Scan(&ownerID)
		if err == nil && ownerID == userID {
			return explicitBizID, "owner", nil
		}
		return "", "", errors.New("forbidden: not a member of this business")
	}

	var bizID, role string
	err := db.QueryRowxContext(ctx, `
		SELECT bm.business_id, bm.role
		FROM business_members bm
		JOIN businesses b ON bm.business_id = b.id
		WHERE bm.user_id = $1 AND bm.status = 'active' AND b.status != 'deleted'
		ORDER BY CASE bm.role WHEN 'owner' THEN 1 WHEN 'manager' THEN 2 ELSE 3 END, bm.created_at ASC
		LIMIT 1
	`, userID).Scan(&bizID, &role)
	if err == nil {
		return bizID, role, nil
	}

	err = db.QueryRowxContext(ctx, `
		SELECT id, 'owner' FROM businesses WHERE owner_user_id = $1 AND status != 'deleted' LIMIT 1
	`, userID).Scan(&bizID, &role)
	return bizID, role, err
}

// merchantWorkspaceBusiness applies a capability check after resolving the
// requested business from the authenticated owner/member relationship.
func merchantWorkspaceBusiness(w http.ResponseWriter, r *http.Request, db *database.DB, userID, capability string) (string, bool) {
	bizID, role, err := resolveMerchantBusiness(r.Context(), db, userID, r.URL.Query().Get("business_id"))
	if err != nil {
		writeError(w, http.StatusForbidden, "FORBIDDEN", "You do not have access to this business.")
		return "", false
	}
	allowed := true
	switch capability {
	case "manage":
		allowed = role == "owner" || role == "manager"
	case "owner":
		allowed = role == "owner"
	}
	if !allowed {
		writeError(w, http.StatusForbidden, "FORBIDDEN", "Your business role cannot perform this action.")
		return "", false
	}
	return bizID, true
}

func merchantListMembers(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	bizID := r.PathValue("id")
	bizID, _, err := resolveMerchantBusiness(r.Context(), db, userID, bizID)
	if err != nil {
		writeError(w, http.StatusForbidden, "FORBIDDEN", "You do not have access to manage this business.")
		return
	}

	rows, err := db.QueryxContext(r.Context(), `
		SELECT bm.id, bm.business_id, bm.user_id, COALESCE(u.display_name, '') AS display_name,
		       u.phone_e164, bm.role, bm.status, bm.created_at
		FROM business_members bm
		JOIN users u ON bm.user_id = u.id
		WHERE bm.business_id = $1 AND bm.status != 'revoked'
		ORDER BY CASE bm.role WHEN 'owner' THEN 1 WHEN 'manager' THEN 2 ELSE 3 END, bm.created_at ASC
	`, bizID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to query team members: "+err.Error())
		return
	}
	defer rows.Close()

	var members []memberItem
	for rows.Next() {
		var m memberItem
		if err := rows.StructScan(&m); err == nil {
			members = append(members, m)
		}
	}
	if members == nil {
		members = []memberItem{}
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]interface{}{
			"business_id": bizID,
			"members":     members,
		},
		"meta": map[string]string{"request_id": "merchant-members-list"},
	})
}

func merchantAddMember(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	bizID := r.PathValue("id")
	bizID, callerRole, err := resolveMerchantBusiness(r.Context(), db, userID, bizID)
	if err != nil || callerRole != "owner" {
		writeError(w, http.StatusForbidden, "FORBIDDEN", "Only store owners can invite or add team members.")
		return
	}

	var req struct {
		PhoneE164   string `json:"phone_e164"`
		Role        string `json:"role"`
		DisplayName string `json:"display_name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Invalid member payload.")
		return
	}

	req.PhoneE164 = strings.TrimSpace(req.PhoneE164)
	if req.PhoneE164 == "" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Phone number is required.")
		return
	}
	if !strings.HasPrefix(req.PhoneE164, "+") {
		req.PhoneE164 = "+91" + req.PhoneE164
	}

	req.Role = strings.ToLower(strings.TrimSpace(req.Role))
	if req.Role != "manager" && req.Role != "staff" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Role must be 'manager' or 'staff'.")
		return
	}

	var targetUserID string
	err = db.QueryRowxContext(r.Context(), `SELECT id FROM users WHERE phone_e164 = $1`, req.PhoneE164).Scan(&targetUserID)
	if err != nil {
		name := req.DisplayName
		if name == "" {
			name = "Team Member (" + req.PhoneE164 + ")"
		}
		err = db.QueryRowxContext(r.Context(), `
			INSERT INTO users (phone_e164, display_name, status, preferred_language)
			VALUES ($1, $2, 'active', 'en')
			RETURNING id
		`, req.PhoneE164, name).Scan(&targetUserID)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to create user account: "+err.Error())
			return
		}
	} else if req.DisplayName != "" {
		_, _ = db.ExecContext(r.Context(), `
			UPDATE users SET display_name = $1 WHERE id = $2 AND (display_name IS NULL OR display_name = '')
		`, req.DisplayName, targetUserID)
	}

	_, _ = db.ExecContext(r.Context(), `
		INSERT INTO user_roles (user_id, role) VALUES ($1, 'merchant') ON CONFLICT DO NOTHING
	`, targetUserID)

	var memberID string
	err = db.QueryRowxContext(r.Context(), `
		INSERT INTO business_members (business_id, user_id, role, status, invited_by, updated_at)
		VALUES ($1, $2, $3, 'active', $4, now())
		ON CONFLICT (business_id, user_id)
		DO UPDATE SET role = EXCLUDED.role, status = 'active', updated_at = now()
		RETURNING id
	`, bizID, targetUserID, req.Role, userID).Scan(&memberID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to assign membership: "+err.Error())
		return
	}

	writeJSON(w, http.StatusCreated, envelope{
		"data": map[string]interface{}{
			"id":           memberID,
			"business_id":  bizID,
			"user_id":      targetUserID,
			"phone_e164":   req.PhoneE164,
			"display_name": req.DisplayName,
			"role":         req.Role,
			"status":       "active",
		},
		"meta": map[string]string{"request_id": "merchant-add-member"},
	})
}

func merchantRevokeMember(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	bizID := r.PathValue("id")
	targetUserID := r.PathValue("userId")
	if targetUserID == "" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "User ID required.")
		return
	}

	bizID, callerRole, err := resolveMerchantBusiness(r.Context(), db, userID, bizID)
	if err != nil || callerRole != "owner" {
		writeError(w, http.StatusForbidden, "FORBIDDEN", "Only store owners can revoke team members.")
		return
	}

	var ownerID string
	err = db.QueryRowxContext(r.Context(), `SELECT owner_user_id FROM businesses WHERE id = $1`, bizID).Scan(&ownerID)
	if err == nil && ownerID == targetUserID {
		writeError(w, http.StatusForbidden, "FORBIDDEN", "Cannot revoke the store owner.")
		return
	}

	res, err := db.ExecContext(r.Context(), `
		UPDATE business_members SET status = 'revoked', updated_at = now()
		WHERE business_id = $1 AND user_id = $2
	`, bizID, targetUserID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to revoke member: "+err.Error())
		return
	}
	rowsAffected, _ := res.RowsAffected()
	if rowsAffected == 0 {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Member not found.")
		return
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]string{
			"status":  "revoked",
			"user_id": targetUserID,
		},
		"meta": map[string]string{"request_id": "merchant-revoke-member"},
	})
}

func merchantListCurrentMembers(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	merchantListMembers(authSvc, db, w, r, userID)
}

func merchantAddCurrentMember(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	merchantAddMember(authSvc, db, w, r, userID)
}

func merchantRevokeCurrentMember(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	merchantRevokeMember(authSvc, db, w, r, userID)
}

// ---------------------------------------------------------------
// Customer Service Requests & Unserved Demand Handlers
// ---------------------------------------------------------------

func handleCreateServiceRequest(notifHub *notifications.Hub) authedHandler {
	return func(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, customerUserID string) {
		bizID := r.PathValue("id")
		if bizID == "" {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Business ID required.")
			return
		}

		// Verify business exists
		var bizName string
		var acceptsReq bool
		err := db.QueryRowxContext(r.Context(), `
			SELECT b.name, COALESCE(pp.accepts_requests, false)
			FROM businesses b
			LEFT JOIN professional_profiles pp ON pp.business_id = b.id
			WHERE b.id = $1 AND b.status = 'approved'
		`, bizID).Scan(&bizName, &acceptsReq)
		if err != nil {
			writeError(w, http.StatusNotFound, "NOT_FOUND", "Business not found or not active.")
			return
		}
		if !acceptsReq {
			writeError(w, http.StatusConflict, "UNAVAILABLE", "This professional is not accepting requests.")
			return
		}

		var req struct {
			ServiceID     *string `json:"service_id"`
			SlotID        *string `json:"slot_id"`
			Description   string  `json:"description"`
			RequestedFor  *string `json:"requested_for"`
			CustomerName  string  `json:"customer_name"`
			CustomerPhone string  `json:"customer_phone"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8<<10)).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Invalid payload.")
			return
		}
		if strings.TrimSpace(req.Description) == "" {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Description is required.")
			return
		}
		if len(req.Description) > 2000 {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Description must be 2000 characters or fewer.")
			return
		}
		if req.RequestedFor != nil && req.SlotID == nil {
			writeError(w, http.StatusBadRequest, "SLOT_REQUIRED", "Scheduled appointments must select a published availability slot.")
			return
		}
		if req.ServiceID != nil {
			var serviceExists bool
			_ = db.QueryRowContext(r.Context(), `SELECT EXISTS(SELECT 1 FROM services WHERE id=$1 AND business_id=$2 AND is_active=true)`, *req.ServiceID, bizID).Scan(&serviceExists)
			if !serviceExists {
				writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Selected service does not belong to this business.")
				return
			}
		}

		// Customer identity comes exclusively from the verified bearer token.
		// Do not accept a caller-supplied phone number or create accounts from a booking request.

		// Reserve an optional persisted slot and insert the request atomically.
		var reqID string
		var createdAt time.Time
		var requestedFor interface{}
		err = db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
			if req.SlotID != nil {
				var startsAt, endsAt time.Time
				var capacity, booked int
				if err := tx.QueryRowx(`SELECT starts_at,ends_at,capacity,booked_count FROM availability_slots WHERE id=$1 AND business_id=$2 AND status='open' FOR UPDATE`, *req.SlotID, bizID).Scan(&startsAt, &endsAt, &capacity, &booked); err != nil {
					return errors.New("selected slot is unavailable")
				}
				if booked >= capacity || startsAt.Before(time.Now().UTC()) || !endsAt.After(startsAt) {
					return errors.New("selected slot is full or expired")
				}
				var closedDate bool
				if err := tx.Get(&closedDate, `SELECT EXISTS(SELECT 1 FROM availability_slots s JOIN businesses b ON b.id=s.business_id JOIN business_availability_exceptions e ON e.business_id=s.business_id AND e.local_date=(s.starts_at AT TIME ZONE b.time_zone)::date WHERE s.id=$1 AND e.is_closed=true)`, *req.SlotID); err != nil {
					return err
				}
				if closedDate {
					return errors.New("selected appointment date is closed")
				}
				result, err := tx.Exec(`UPDATE availability_slots SET booked_count=booked_count+1,updated_at=now() WHERE id=$1 AND business_id=$2 AND status='open' AND booked_count<capacity`, *req.SlotID, bizID)
				if err != nil {
					return err
				}
				if affected, _ := result.RowsAffected(); affected != 1 {
					return errors.New("selected slot is full or unavailable")
				}
				requestedFor = startsAt
			}
			if err := tx.QueryRowx(`INSERT INTO service_requests (customer_user_id,business_id,service_id,slot_id,description,requested_for,status,created_at,updated_at) VALUES($1,$2,$3,$4,$5,$6,'requested',now(),now()) RETURNING id,created_at`, customerUserID, bizID, req.ServiceID, req.SlotID, req.Description, requestedFor).Scan(&reqID, &createdAt); err != nil {
				return err
			}
			_, err := tx.Exec(`INSERT INTO service_request_events(request_id,status,actor_user_id,created_at) VALUES($1,'requested',$2,$3)`, reqID, customerUserID, createdAt)
			return err
		})
		if err != nil {
			writeError(w, http.StatusConflict, "SLOT_UNAVAILABLE", "The requested appointment time is no longer available. Refresh availability and choose another time.")
			return
		}

		// Look up service name if present
		var svcName *string
		if req.ServiceID != nil {
			var sn string
			if err := db.QueryRowxContext(r.Context(), `SELECT name FROM services WHERE id = $1 AND business_id=$2`, *req.ServiceID, bizID).Scan(&sn); err == nil {
				svcName = &sn
			}
		}

		// Publish real-time booking event to SSE subscribers (Merchant workspace & audio alert)
		if notifHub != nil {
			notifHub.Publish(r.Context(), notifications.Event{
				Type:       "service_request.created",
				BusinessID: bizID,
				RequestID:  reqID,
				UserID:     customerUserID,
				Title:      "New Service Booking Request",
				Body:       fmt.Sprintf("New booking requested for %s: %s", bizName, req.Description),
				Payload: map[string]interface{}{
					"request_id":    reqID,
					"business_id":   bizID,
					"business_name": bizName,
					"service_id":    req.ServiceID,
					"service_name":  svcName,
					"description":   req.Description,
					"status":        "requested",
					"requested_for": requestedFor,
					"created_at":    createdAt.Format(time.RFC3339),
				},
			})
		}

		writeJSON(w, http.StatusCreated, envelope{
			"data": map[string]interface{}{
				"id":            reqID,
				"business_id":   bizID,
				"business_name": bizName,
				"service_id":    req.ServiceID,
				"service_name":  svcName,
				"description":   req.Description,
				"requested_for": requestedFor,
				"status":        "requested",
				"created_at":    createdAt.Format(time.RFC3339),
			},
			"meta": map[string]string{"request_id": "create-service-request"},
		})
	}
}

func handleGetServiceRequest(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	reqID := r.PathValue("id")
	if reqID == "" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Request ID required.")
		return
	}

	var id, bizID, bizName, desc, status string
	var svcID, svcName, requestedFor, phone, customerName *string
	var createdAt, updatedAt time.Time

	var customerUserID string
	err := db.QueryRowxContext(r.Context(), `
			SELECT sr.id, sr.business_id, b.name as business_name,
			       sr.service_id, s.name as service_name,
			       sr.description, sr.requested_for, sr.status,
			       u.display_name, u.phone_e164, sr.customer_user_id,
			       sr.created_at, sr.updated_at
			FROM service_requests sr
			JOIN businesses b ON b.id = sr.business_id
			JOIN users u ON u.id = sr.customer_user_id
			LEFT JOIN services s ON s.id = sr.service_id
			WHERE sr.id = $1
		`, reqID).Scan(&id, &bizID, &bizName, &svcID, &svcName, &desc, &requestedFor, &status,
		&customerName, &phone, &customerUserID, &createdAt, &updatedAt)
	if err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Service request not found.")
		return
	}
	if customerUserID != userID && !hasBusinessMembership(r.Context(), db, userID, bizID) {
		writeError(w, http.StatusForbidden, "FORBIDDEN", "You do not have access to this service request.")
		return
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]interface{}{
			"id":             id,
			"business_id":    bizID,
			"business_name":  bizName,
			"service_id":     svcID,
			"service_name":   svcName,
			"description":    desc,
			"requested_for":  requestedFor,
			"status":         status,
			"customer_name":  customerName,
			"customer_phone": phone,
			"created_at":     createdAt.Format(time.RFC3339),
			"updated_at":     updatedAt.Format(time.RFC3339),
		},
		"meta": map[string]string{"request_id": "get-service-request"},
	})
}

func handleCancelServiceRequest(_ *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	tx, err := db.BeginTxx(r.Context(), nil)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Could not cancel request.")
		return
	}
	defer tx.Rollback()
	var slotID *string
	var status, ownerID string
	err = tx.QueryRowxContext(r.Context(), `SELECT customer_user_id, status, slot_id FROM service_requests WHERE id=$1 FOR UPDATE`, r.PathValue("id")).Scan(&ownerID, &status, &slotID)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Service request not found.")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Could not load request.")
		return
	}
	if ownerID != userID {
		writeError(w, http.StatusForbidden, "FORBIDDEN", "You do not have access to this service request.")
		return
	}
	if status != "requested" && status != "accepted" {
		writeError(w, http.StatusConflict, "INVALID_STATE", "Only pending or accepted requests can be cancelled.")
		return
	}
	status = "cancelled"
	if _, err = tx.ExecContext(r.Context(), `UPDATE service_requests SET status='cancelled', updated_at=NOW() WHERE id=$1`, r.PathValue("id")); err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Could not cancel request.")
		return
	}
	if slotID != nil {
		if _, err = tx.ExecContext(r.Context(), `UPDATE availability_slots SET booked_count = GREATEST(booked_count - 1, 0), updated_at = NOW() WHERE id = $1`, *slotID); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Could not release booking slot.")
			return
		}
	}
	if _, err = tx.ExecContext(r.Context(), `INSERT INTO service_request_events (request_id, status) VALUES ($1, 'cancelled')`, r.PathValue("id")); err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Could not record cancellation.")
		return
	}
	if err = tx.Commit(); err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Could not cancel request.")
		return
	}
	writeJSON(w, http.StatusOK, envelope{"data": map[string]interface{}{"id": r.PathValue("id"), "status": status}})
}

func handleListCustomerRequests(_ *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, customerUserID string) {
	type reqItem struct {
		ID           string  `json:"id"`
		BusinessID   string  `json:"business_id"`
		BusinessName string  `json:"business_name"`
		ServiceName  *string `json:"service_name"`
		Description  string  `json:"description"`
		RequestedFor *string `json:"requested_for"`
		Status       string  `json:"status"`
		CreatedAt    string  `json:"created_at"`
	}

	var requests []reqItem
	var rows *sqlx.Rows
	var err error

	rows, err = db.QueryxContext(r.Context(), `
				SELECT sr.id, sr.business_id, b.name as business_name, s.name as service_name,
				       sr.description, sr.requested_for, sr.status, sr.created_at
				FROM service_requests sr
				JOIN businesses b ON b.id = sr.business_id
				LEFT JOIN services s ON s.id = sr.service_id
				WHERE sr.customer_user_id = $1
				ORDER BY sr.created_at DESC
				LIMIT 50
			`, customerUserID)

	if err == nil && rows != nil {
		for rows.Next() {
			var item reqItem
			var createdAt time.Time
			_ = rows.Scan(&item.ID, &item.BusinessID, &item.BusinessName, &item.ServiceName,
				&item.Description, &item.RequestedFor, &item.Status, &createdAt)
			item.CreatedAt = createdAt.Format(time.RFC3339)
			requests = append(requests, item)
		}
		rows.Close()
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]interface{}{
			"requests": requests,
		},
		"meta": map[string]string{"request_id": "customer-requests"},
	})
}

func handleRecordUnservedLocation(authSvc *auth.Service, db *database.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Query             string   `json:"query"`
			Locality          string   `json:"locality"`
			City              string   `json:"city"`
			Latitude          *float64 `json:"latitude"`
			Longitude         *float64 `json:"longitude"`
			NotificationPhone string   `json:"notification_phone"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Invalid payload.")
			return
		}
		if strings.TrimSpace(req.City) == "" {
			req.City = "Odisha"
		}

		var uid *string
		authHdr := r.Header.Get("Authorization")
		token := strings.TrimPrefix(authHdr, "Bearer ")
		if token != "" {
			if claims, err := jwtParse(token, authSvc); err == nil {
				uid = &claims.Subject
			}
		}

		var id string
		err := db.QueryRowxContext(r.Context(), `
			INSERT INTO unserved_location_demand (user_id, query, locality, city, latitude, longitude, notification_phone, created_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7, now())
			RETURNING id
		`, uid, req.Query, req.Locality, req.City, req.Latitude, req.Longitude, req.NotificationPhone).Scan(&id)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to record location demand: "+err.Error())
			return
		}

		writeJSON(w, http.StatusCreated, envelope{
			"data": map[string]interface{}{
				"id":      id,
				"status":  "recorded",
				"message": "We have recorded your location interest. Grepmind Near is expanding here soon!",
			},
			"meta": map[string]string{"request_id": "unserved-location-recorded"},
		})
	}
}

func handleListUnservedLocations(db *database.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		type CityStat struct {
			City         string `json:"city"`
			SearchCount  int    `json:"search_count"`
			LastSearched string `json:"last_searched"`
		}
		var stats []CityStat
		rows, err := db.QueryxContext(r.Context(), `
			SELECT city, COUNT(*) as cnt, MAX(created_at) as last_seen
			FROM unserved_location_demand
			GROUP BY city
			ORDER BY cnt DESC
			LIMIT 20
		`)
		if err == nil {
			for rows.Next() {
				var cs CityStat
				var lastSeen time.Time
				_ = rows.Scan(&cs.City, &cs.SearchCount, &lastSeen)
				cs.LastSearched = lastSeen.Format(time.RFC3339)
				stats = append(stats, cs)
			}
			rows.Close()
		}

		writeJSON(w, http.StatusOK, envelope{
			"data": map[string]interface{}{
				"demand_by_city": stats,
			},
			"meta": map[string]string{"request_id": "admin-unserved-locations"},
		})
	}
}

type authedHandler func(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string)

func hasBusinessMembership(ctx context.Context, db *database.DB, userID, businessID string) bool {
	var allowed bool
	_ = db.QueryRowxContext(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM business_members
			WHERE business_id = $1 AND user_id = $2 AND status = 'active'
			UNION
			SELECT 1 FROM businesses WHERE id = $1 AND owner_user_id = $2 AND status != 'deleted'
		)
	`, businessID, userID).Scan(&allowed)
	return allowed
}

func authorizeNotificationScope(ctx context.Context, db *database.DB, userID, businessID, requestedUserID string) bool {
	if businessID == "" && requestedUserID == "" {
		return true
	}
	if requestedUserID != "" && requestedUserID != userID {
		return false
	}
	return businessID == "" || hasBusinessMembership(ctx, db, userID, businessID)
}

func authorizeEventSubscription(ctx context.Context, db *database.DB, r *http.Request, userID string) bool {
	businessID := r.URL.Query().Get("business_id")
	requestID := r.URL.Query().Get("request_id")
	requestedUserID := r.URL.Query().Get("user_id")
	if requestedUserID != "" && requestedUserID != userID {
		return false
	}
	if businessID != "" && !hasBusinessMembership(ctx, db, userID, businessID) {
		return false
	}
	if requestID != "" {
		var customerID, requestBusinessID string
		err := db.QueryRowxContext(ctx, `SELECT customer_user_id, business_id FROM service_requests WHERE id = $1`, requestID).Scan(&customerID, &requestBusinessID)
		if err != nil || (customerID != userID && !hasBusinessMembership(ctx, db, userID, requestBusinessID)) {
			return false
		}
	}
	return businessID != "" || requestID != "" || requestedUserID != ""
}

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
			writeError(w, http.StatusUnauthorized, "INVALID_TOKEN", "Invalid or expired token: "+err.Error())
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
			writeError(w, http.StatusUnauthorized, "INVALID_TOKEN", "Invalid or expired token: "+err.Error())
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

// requirePrimarySuperadmin protects high-impact platform role changes from
// other administrator accounts while retaining the normal OTP/JWT session.
func requirePrimarySuperadmin(authSvc *auth.Service, next authedHandler) http.HandlerFunc {
	return requireAdmin(authSvc, func(a *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
		var phone string
		if err := db.QueryRowContext(r.Context(), `SELECT phone_e164 FROM users WHERE id=$1 AND status='active'`, userID).Scan(&phone); err != nil || phone != "+910000000000" {
			writeError(w, http.StatusForbidden, "FORBIDDEN", "Primary superadmin access is required to change platform roles.")
			return
		}
		next(a, db, w, r, userID)
	})
}

func jwtParse(token string, authSvc *auth.Service) (*jwt.RegisteredClaims, error) {
	return authSvc.ValidateAccessToken(context.Background(), token)
}

type envelope map[string]interface{}

func writeJSON(w http.ResponseWriter, code int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func nullableStringValue(value sql.NullString) interface{} {
	if !value.Valid {
		return nil
	}
	return value.String
}

func validStockStatus(value string) bool {
	switch value {
	case "unknown", "in_stock", "out_of_stock", "limited":
		return true
	default:
		return false
	}
}

func validProductInput(name string, price *float64, stockStatus string) bool {
	name = strings.TrimSpace(name)
	return len(name) >= 2 && len(name) <= 100 && (price == nil || (*price >= 0 && *price <= 9999999999.99)) && validStockStatus(stockStatus)
}

func validBusinessTime(value string) bool {
	for _, layout := range []string{"15:04", "15:04:05"} {
		if parsed, err := time.Parse(layout, value); err == nil && parsed.Format(layout) == value {
			return true
		}
	}
	return false
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
