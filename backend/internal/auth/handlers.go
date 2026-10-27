package auth

import (
	"encoding/json"
	"net/http"
	"time"

	"grepmind-near/backend/pkg/database"
)

func (s *Service) RequestOTP(w http.ResponseWriter, r *http.Request) {
	type req struct {
		PhoneE164 string `json:"phone_e164"`
	}
	var body req
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "Unable to parse request body.")
		return
	}
	if body.PhoneE164 == "" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "phone_e164 is required.")
		return
	}

	// Stub OTP delivery in local/dev. In production, invoke an OTP provider.
	_ = s.db
	_ = time.Now

	writeJSON(w, http.StatusAccepted, envelope{
		"data": map[string]string{
			"phone_e164": body.PhoneE164,
			"status":     "otp_requested",
		},
		"meta": map[string]string{"request_id": "otp-req-stub"},
	})
}

func (s *Service) VerifyOTP(w http.ResponseWriter, r *http.Request) {
	type req struct {
		PhoneE164      string `json:"phone_e164"`
		OTPCode        string `json:"otp_code"`
		IdempotencyKey string `json:"idempotency_key"`
	}
	var body req
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "Unable to parse request body.")
		return
	}
	if body.PhoneE164 == "" || body.OTPCode == "" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "phone_e164 and otp_code are required.")
		return
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]interface{}{
			"access_token":  "access-stub",
			"refresh_token": "refresh-stub",
			"user": map[string]interface{}{
				"phone_e164": body.PhoneE164,
				"status":     "active",
			},
		},
		"meta": map[string]string{"request_id": "otp-verify-stub"},
	})
}

func (s *Service) Refresh(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]string{"access_token": "access-stub-rotated"},
		"meta": map[string]string{"request_id": "refresh-stub"},
	})
}

func (s *Service) Logout(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]string{"status": "logged_out"},
		"meta": map[string]string{"request_id": "logout-stub"},
	})
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
			"request_id": "err-stub",
		},
	})
}

var _ = database.ErrNotFound
