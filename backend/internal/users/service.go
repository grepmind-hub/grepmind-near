package users

import (
	"encoding/json"
	"net/http"

	"grepmind-near/backend/pkg/database"
)

type Service struct {
	db *database.DB
}

func NewService(db *database.DB) *Service {
	return &Service{db: db}
}

func (s *Service) GetMe(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]interface{}{
			"id":                 "me-stub",
			"phone_e164":         "+910000000000",
			"display_name":       "Platform Admin",
			"status":             "active",
			"preferred_language": "en",
			"roles":              []string{"admin"},
		},
		"meta": map[string]string{"request_id": "me-stub"},
	})
}

func (s *Service) UpdateMe(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]interface{}{"status": "updated"},
		"meta": map[string]string{"request_id": "me-update-stub"},
	})
}

type envelope map[string]interface{}

func writeJSON(w http.ResponseWriter, code int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

var _ = database.ErrNotFound
