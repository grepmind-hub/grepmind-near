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

	mux := setupRouter(authSvc, discSvc)

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

func setupRouter(authSvc *auth.Service, discSvc *discovery.Service) *http.ServeMux {
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
