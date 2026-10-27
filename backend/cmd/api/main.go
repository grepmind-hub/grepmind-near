package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"grepmind-near/backend/internal/auth"
	"grepmind-near/backend/internal/discovery"
	"grepmind-near/backend/internal/users"
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
	userSvc := users.NewService(db)
	discSvc := discovery.NewService(db, cfg)

	mux := setupRouter(authSvc, userSvc, discSvc)

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

func setupRouter(authSvc *auth.Service, userSvc *users.Service, discSvc *discovery.Service) *http.ServeMux {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, envelope{"status": "ok"})
	})

	mux.HandleFunc("POST /api/v1/auth/otp/request", authSvc.RequestOTP)
	mux.HandleFunc("POST /api/v1/auth/otp/verify", authSvc.VerifyOTP)
	mux.HandleFunc("POST /api/v1/auth/refresh", authSvc.Refresh)
	mux.HandleFunc("POST /api/v1/auth/logout", authSvc.Logout)

	mux.HandleFunc("GET /api/v1/me", requireAuth(userSvc.GetMe))
	mux.HandleFunc("PATCH /api/v1/me", requireAuth(userSvc.UpdateMe))

	mux.HandleFunc("GET /api/v1/categories", discSvc.ListCategories)
	mux.HandleFunc("GET /api/v1/businesses", discSvc.SearchBusinesses)
	mux.HandleFunc("GET /api/v1/businesses/{id}", discSvc.GetBusiness)
	mux.HandleFunc("GET /api/v1/businesses/{id}/products", discSvc.ListProducts)
	mux.HandleFunc("GET /api/v1/businesses/{id}/services", discSvc.ListServices)
	mux.HandleFunc("GET /api/v1/businesses/{id}/offers", discSvc.ListOffers)
	mux.HandleFunc("GET /api/v1/nearby", discSvc.Nearby)

	return mux
}

func requireAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, envelope{"status": "auth required"})
	}
}

type envelope map[string]interface{}

func writeJSON(w http.ResponseWriter, code int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = v
}

var _ = slog.New
var _ = os.Getenv
