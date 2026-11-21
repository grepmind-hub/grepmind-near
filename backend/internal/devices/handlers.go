package devices

import (
	"encoding/json"
	"net/http"

	"grepmind-near/backend/internal/fcm"
)

type registerResponse struct {
	ID                     string `json:"id"`
	InstallationID         string `json:"installation_id"`
	Platform               string `json:"platform"`
	Environment            string `json:"environment"`
	NotificationPermission bool   `json:"notification_permission"`
	Active                 bool   `json:"active"`
}

func (s *Service) HandleRegister(w http.ResponseWriter, r *http.Request, userID string) {
	var req registerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "Unable to parse request body.")
		return
	}

	reg, err := s.Register(r.Context(), &userID, req)
	if err != nil {
		switch {
		case err == errInvalidPlatform:
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", err.Error())
		case err == errInvalidEnvironment:
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", err.Error())
		default:
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to register device.")
		}
		return
	}

	writeJSON(w, http.StatusCreated, envelope{
		"data": registerResponse{
			ID:                     reg.ID,
			InstallationID:         reg.InstallationID,
			Platform:               reg.Platform,
			Environment:            reg.Environment,
			NotificationPermission: reg.NotificationPermission,
			Active:                 reg.Active,
		},
		"meta": map[string]string{"request_id": "device-registered"},
	})
}

func (s *Service) HandleRevoke(w http.ResponseWriter, r *http.Request, userID string) {
	var req revokeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "Unable to parse request body.")
		return
	}

	if err := s.Revoke(r.Context(), userID, req); err != nil {
		if err == errDeviceNotFound {
			writeError(w, http.StatusNotFound, "NOT_FOUND", "Device registration not found.")
			return
		}
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to revoke device.")
		return
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]string{"status": "revoked"},
		"meta": map[string]string{"request_id": "device-revoked"},
	})
}

func (s *Service) HandleList(w http.ResponseWriter, r *http.Request, userID string) {
	regs, err := s.ListActive(r.Context(), userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to list devices.")
		return
	}

	items := make([]map[string]interface{}, 0, len(regs))
	for _, reg := range regs {
		items = append(items, map[string]interface{}{
			"id":                      reg.ID,
			"installation_id":         reg.InstallationID,
			"platform":                reg.Platform,
			"environment":             reg.Environment,
			"notification_permission": reg.NotificationPermission,
			"last_seen":               reg.LastSeen,
			"active":                  reg.Active,
		})
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": items,
		"meta": map[string]interface{}{"count": len(items)},
	})
}

// HandlePreLoginRegister registers a device installation without authentication.
// Used for pre-login test installation registration where the user may not
// exist yet. user_id is left nil and bound later via AssociateUser after
// successful authentication.
//
// This endpoint is only enabled when the server is running in a QA or staging
// environment (APP_ENV=qa). The registration is scoped to the QA environment
// only; FCM tokens submitted here are used for test OTP delivery exclusively
// and do not establish phone ownership.
func (s *Service) HandlePreLoginRegister(w http.ResponseWriter, r *http.Request) {
	// Enforce QA-only access. The environment is validated at service
	// construction time; we double-check here to fail closed on misconfiguration.
	if !s.IsQAEnvironment() {
		writeError(w, http.StatusForbidden, "DEVICE_REGISTRATION_UNAVAILABLE", "Pre-login device registration requires a QA environment.")
		return
	}
	var req registerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "Unable to parse request body.")
		return
	}

	reg, err := s.Register(r.Context(), nil, req)
	if err != nil {
		switch {
		case err == errInvalidPlatform:
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", err.Error())
		case err == errInvalidEnvironment:
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", err.Error())
		default:
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to register device.")
		}
		return
	}

	writeJSON(w, http.StatusCreated, envelope{
		"data": registerResponse{
			ID:                     reg.ID,
			InstallationID:         reg.InstallationID,
			Platform:               reg.Platform,
			Environment:            reg.Environment,
			NotificationPermission: reg.NotificationPermission,
			Active:                 reg.Active,
		},
		"meta": map[string]string{"request_id": "device-registered-prelogin"},
	})
}

var _ = fcm.IsInvalidToken
