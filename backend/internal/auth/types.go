package auth

import (
	"encoding/json"
	"net/http"
)

type AppUser struct {
	ID                string   `json:"id"`
	PhoneE164         string   `json:"phone_e164"`
	DisplayName       string   `json:"display_name,omitempty"`
	Status            string   `json:"status"`
	PreferredLanguage string   `json:"preferred_language"`
	Roles             []string `json:"roles"`
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
