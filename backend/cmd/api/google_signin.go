package main

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"google.golang.org/api/idtoken"

	"grepmind-near/backend/internal/auth"
	"grepmind-near/backend/internal/devices"
)

type googleVerifyRequest struct {
	IDToken       string `json:"id_token"`
	InstallationID string `json:"installation_id,omitempty"`
	FCMToken      string `json:"fcm_token,omitempty"`
	Platform      string `json:"platform,omitempty"`
	Environment   string `json:"environment,omitempty"`
}

type googleVerifyResponse struct {
	AccessToken  string                 `json:"access_token"`
	RefreshToken string                 `json:"refresh_token"`
	User         map[string]interface{} `json:"user"`
	IsNewUser    bool                   `json:"is_new_user"`
}

// handleGoogleSignIn verifies a Google ID token and issues Abashyaka session tokens.
// It does not use Firebase Authentication as a second identity system.
func handleGoogleSignIn(w http.ResponseWriter, r *http.Request, authSvc *auth.Service, deviceSvc *devices.Service, expectedAudience string) {
	if expectedAudience == "" {
		writeJSON(w, http.StatusInternalServerError, envelope{
			"error": map[string]interface{}{"code": "CONFIGURATION_ERROR", "message": "Google OAuth client ID is not configured.", "request_id": "err-stub"},
		})
		return
	}

	var body googleVerifyRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "Unable to parse request body.")
		return
	}
	if body.IDToken == "" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "id_token is required.")
		return
	}

	// Verify the Google ID token: signature, audience, issuer, expiry.
	payload, err := idtoken.Validate(r.Context(), body.IDToken, expectedAudience)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "INVALID_TOKEN", "Google ID token verification failed.")
		return
	}

	// Validate issuer.
	if payload.Issuer != "accounts.google.com" && payload.Issuer != "https://accounts.google.com" {
		writeError(w, http.StatusUnauthorized, "INVALID_TOKEN", "Invalid token issuer.")
		return
	}

	// Stable Google subject identifier for identity association.
	googleSub := payload.Subject
	if googleSub == "" {
		writeError(w, http.StatusUnauthorized, "INVALID_TOKEN", "Google token missing subject identifier.")
		return
	}

	email, _ := payload.Claims["email"].(string)
	_ = email // Email is not used for automatic account linking.

	db := authSvc.DB()

	// Check for an existing Google-linked account.
	var existingUserID string
	err = db.QueryRowContext(r.Context(), `
		SELECT user_id FROM google_identities WHERE google_subject = $1
	`, googleSub).Scan(&existingUserID)
	if err == nil && existingUserID != "" {
		// Existing Google-linked account: issue tokens.
		userID := existingUserID
		accessToken, refreshToken, err := authSvc.IssueTokensForUser(r.Context(), userID, r.UserAgent(), remoteIPMain(r))
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to issue session tokens.")
			return
		}
		// Update device registration if provided.
		if body.InstallationID != "" && deviceSvc != nil {
			_ = deviceSvc.AssociateUser(r.Context(), body.InstallationID, userID)
			if body.FCMToken != "" {
				_ = deviceSvc.UpdateLastSeen(r.Context(), userID, body.InstallationID)
			}
		}
		writeJSON(w, http.StatusOK, envelope{
			"data": googleVerifyResponse{
				AccessToken:  accessToken,
				RefreshToken: refreshToken,
				User:         map[string]interface{}{"id": userID, "phone_e164": "", "roles": []string{"customer"}},
				IsNewUser:    false,
			},
			"meta": map[string]string{"request_id": "google-verified"},
		})
		return
	}

	// New user: register with Google subject. Phone is not required for
	// Google Sign-In accounts; a compatible identity/phone-onboarding
	// migration is needed before Google-first accounts can complete login.
	// For now, create a minimal user record.
	newUserID := uuid.NewString()
	_, err = db.ExecContext(r.Context(), `
		INSERT INTO users (id, phone_e164, status, preferred_language)
		VALUES ($1, '', 'active', 'en')
		ON CONFLICT (id) DO NOTHING
	`, newUserID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to create account.")
		return
	}
	_, err = db.ExecContext(r.Context(), `
		INSERT INTO user_roles (user_id, role) VALUES ($1, 'customer')
		ON CONFLICT (user_id, role) DO NOTHING
	`, newUserID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to assign role.")
		return
	}
	_, err = db.ExecContext(r.Context(), `
		INSERT INTO google_identities (user_id, google_subject, email, created_at)
		VALUES ($1, $2, $3, now())
		ON CONFLICT (google_subject) DO NOTHING
	`, newUserID, googleSub, email)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to link Google identity.")
		return
	}

	accessToken, refreshToken, err := authSvc.IssueTokensForUser(r.Context(), newUserID, r.UserAgent(), remoteIPMain(r))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to issue session tokens.")
		return
	}
	// Associate device registration with the new user.
	if body.InstallationID != "" && deviceSvc != nil {
		_ = deviceSvc.AssociateUser(r.Context(), body.InstallationID, newUserID)
		if body.FCMToken != "" {
			_ = deviceSvc.UpdateLastSeen(r.Context(), newUserID, body.InstallationID)
		}
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": googleVerifyResponse{
			AccessToken:  accessToken,
			RefreshToken: refreshToken,
			User:         map[string]interface{}{"id": newUserID, "phone_e164": "", "roles": []string{"customer"}},
			IsNewUser:    true,
		},
		"meta": map[string]string{"request_id": "google-verified"},
	})
}

// remoteIPMain extracts the client IP from the request for local use in package main.
func remoteIPMain(r *http.Request) string {
	peer, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		peer = r.RemoteAddr
	}
	peerIP := net.ParseIP(peer)
	if peerIP != nil && (peerIP.IsPrivate() || peerIP.IsLoopback()) {
		if forwarded := net.ParseIP(strings.TrimSpace(r.Header.Get("X-Real-IP"))); forwarded != nil {
			return forwarded.String()
		}
	}
	return peer
}

// ensure imports are used
var _ = context.Background
var _ = errors.New
var _ = time.Now
