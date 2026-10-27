package discovery

import (
	"encoding/json"
	"net/http"
	"strconv"

	"grepmind-near/backend/pkg/database"
)

func (s *Service) ListCategories(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, envelope{
		"data": []map[string]interface{}{
			{"slug": "grocery", "name": "Grocery", "icon_name": "store"},
			{"slug": "hardware", "name": "Hardware", "icon_name": "build"},
			{"slug": "medical", "name": "Medical & Pharmacy", "icon_name": "local_pharmacy"},
			{"slug": "restaurant", "name": "Restaurant & Food", "icon_name": "restaurant"},
			{"slug": "salon", "name": "Salon & Beauty", "icon_name": "face"},
			{"slug": "plumber", "name": "Plumber", "icon_name": "plumbing"},
			{"slug": "electrician", "name": "Electrician", "icon_name": "electrical_services"},
			{"slug": "carpenter", "name": "Carpenter", "icon_name": "carpenter"},
		},
		"meta": map[string]string{"request_id": "cats-stub"},
	})
}

func (s *Service) SearchBusinesses(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query().Get("q")
	lat := r.URL.Query().Get("lat")
	lng := r.URL.Query().Get("lng")
	radius := r.URL.Query().Get("radius_m")

	_ = q
	_ = lat
	_ = lng
	_ = radius

	// Validate pagination
	limit := 20
	if v := r.URL.Query().Get("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 && n <= 50 {
			limit = n
		}
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": []map[string]interface{}{},
		"meta": map[string]interface{}{
			"request_id": "search-stub",
			"limit":      limit,
			"count":      0,
		},
	})
}

func (s *Service) GetBusiness(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	_ = id
	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]interface{}{
			"id":                  id,
			"name":                "Sample Business",
			"status":              "approved",
			"verification_status": "verified",
			"is_open_now":         true,
		},
		"meta": map[string]string{"request_id": "biz-stub"},
	})
}

func (s *Service) ListProducts(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, envelope{
		"data": []map[string]interface{}{},
		"meta": map[string]string{"request_id": "products-stub"},
	})
}

func (s *Service) ListServices(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, envelope{
		"data": []map[string]interface{}{},
		"meta": map[string]string{"request_id": "services-stub"},
	})
}

func (s *Service) ListOffers(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, envelope{
		"data": []map[string]interface{}{},
		"meta": map[string]string{"request_id": "offers-stub"},
	})
}

func (s *Service) Nearby(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, envelope{
		"data": []map[string]interface{}{},
		"meta": map[string]string{"request_id": "nearby-stub"},
	})
}

type envelope map[string]interface{}

func writeJSON(w http.ResponseWriter, code int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

var _ = database.ErrNotFound
var _ = strconv.Atoi
