package discovery

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"grepmind-near/backend/internal/auth"
	"grepmind-near/backend/pkg/config"
	"grepmind-near/backend/pkg/database"
)

var (
	errInvalidCoordinates = errors.New("invalid coordinates")
	errRadiusOutOfRange   = errors.New("radius must be between 100 and 50000 meters")
	errLimitOutOfRange    = errors.New("limit must be between 1 and 50")
)

// ---------- Models ----------

type Category struct {
	Slug        string `json:"slug"`
	Name        string `json:"name"`
	IconName    string `json:"icon_name,omitempty"`
	Description string `json:"description,omitempty"`
	SortOrder   int    `json:"-"`
}

type Business struct {
	ID                 string   `json:"id"`
	Name               string   `json:"name"`
	Slug               string   `json:"slug,omitempty"`
	CategorySlug       string   `json:"category_slug"`
	CategoryName       string   `json:"category_name,omitempty"`
	AddressText        string   `json:"address_text"`
	Locality           string   `json:"locality,omitempty"`
	City               string   `json:"city,omitempty"`
	PostalCode         string   `json:"postal_code,omitempty"`
	Latitude           *float64 `json:"latitude,omitempty"`
	Longitude          *float64 `json:"longitude,omitempty"`
	DistanceM          *float64 `json:"distance_m,omitempty"`
	Status             string   `json:"status"`
	VerificationStatus string   `json:"verification_status"`
	PhoneE164          string   `json:"phone_e164,omitempty"`
	WhatsappE164       string   `json:"whatsapp_e164,omitempty"`
	IsOpenNow          bool     `json:"is_open_now"`
	AcceptsRequests    bool     `json:"accepts_requests"`
	CoverPhotoURL      string   `json:"cover_photo_url,omitempty"`
	Rating             *float64 `json:"rating,omitempty"`
	ReviewCount        *int     `json:"review_count,omitempty"`
}

type BusinessHour struct {
	Weekday  int     `json:"weekday"`
	OpensAt  *string `json:"opens_at,omitempty"`
	ClosesAt *string `json:"closes_at,omitempty"`
	IsClosed bool    `json:"is_closed"`
}

type Product struct {
	ID          string   `json:"id"`
	BusinessID  string   `json:"business_id"`
	Name        string   `json:"name"`
	Description string   `json:"description,omitempty"`
	Price       *float64 `json:"price,omitempty"`
	Currency    string   `json:"currency"`
	StockStatus string   `json:"stock_status"`
	IsPublished bool     `json:"is_published"`
	ImageURL    string   `json:"image_url,omitempty"`
}

type Offer struct {
	ID          string    `json:"id"`
	BusinessID  string    `json:"business_id"`
	Title       string    `json:"title"`
	Description string    `json:"description,omitempty"`
	StartsAt    time.Time `json:"starts_at"`
	EndsAt      time.Time `json:"ends_at"`
	Status      string    `json:"status"`
	ImageURL    string    `json:"image_url,omitempty"`
	Terms       string    `json:"terms,omitempty"`
	DiscountPct *int      `json:"discount_percent,omitempty"`
}

type ServiceOffering struct {
	ID          string   `json:"id"`
	BusinessID  string   `json:"business_id"`
	Name        string   `json:"name"`
	Description string   `json:"description,omitempty"`
	PriceMin    *float64 `json:"indicative_price_min,omitempty"`
	PriceMax    *float64 `json:"indicative_price_max,omitempty"`
	Currency    string   `json:"currency"`
	IsActive    bool     `json:"is_active"`
}

type BusinessDetail struct {
	Business
	Description        string            `json:"description,omitempty"`
	BusinessHours      []BusinessHour    `json:"business_hours,omitempty"`
	Products           []Product         `json:"products,omitempty"`
	Offers             []Offer           `json:"offers,omitempty"`
	Services           []ServiceOffering `json:"services,omitempty"`
	ServiceRadiusM     *int              `json:"service_radius_m,omitempty"`
	ExperienceYears    *int              `json:"experience_years,omitempty"`
	ServiceDescription string            `json:"service_description,omitempty"`
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

// ---------- Service ----------

type Service struct {
	db  *database.DB
	cfg *config.Config
}

func NewService(db *database.DB, cfg *config.Config) *Service {
	return &Service{db: db, cfg: cfg}
}

// ---------- Handlers ----------

func (s *Service) ListCategories(w http.ResponseWriter, r *http.Request) {
	rows, err := s.db.QueryxContext(r.Context(), `
		SELECT slug, name, icon_name, description, sort_order
		FROM categories
		WHERE is_active = true
		ORDER BY sort_order ASC, name ASC
	`)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load categories.")
		return
	}
	defer rows.Close()

	var cats []Category
	for rows.Next() {
		var c Category
		var icon, desc sql.NullString
		if err := rows.Scan(&c.Slug, &c.Name, &icon, &desc, &c.SortOrder); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to read categories.")
			return
		}
		if icon.Valid {
			c.IconName = icon.String
		}
		if desc.Valid {
			c.Description = desc.String
		}
		cats = append(cats, c)
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": cats,
		"meta": map[string]string{"request_id": "categories"},
	})
}

func parsePagination(r *http.Request) (limit int, cursor string) {
	limit = 20
	if v := r.URL.Query().Get("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= 1 && n <= 50 {
			limit = n
		}
	}
	cursor = r.URL.Query().Get("cursor")
	return
}

func (s *Service) SearchBusinesses(w http.ResponseWriter, r *http.Request) {
	q := strings.TrimSpace(r.URL.Query().Get("q"))
	latStr := r.URL.Query().Get("lat")
	lngStr := r.URL.Query().Get("lng")
	radiusM := 5000
	if v := r.URL.Query().Get("radius_m"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= 100 && n <= 50000 {
			radiusM = n
		} else {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", errRadiusOutOfRange.Error())
			return
		}
	}
	categorySlug := strings.TrimSpace(r.URL.Query().Get("category_slug"))
	openNow := r.URL.Query().Get("open_now") == "true"
	sort := r.URL.Query().Get("sort")
	if sort == "" {
		sort = "relevance"
	}
	limit, _ := parsePagination(r)

	var lat, lng float64
	hasLoc := false
	if latStr != "" && lngStr != "" {
		var err1, err2 error
		lat, err1 = strconv.ParseFloat(latStr, 64)
		lng, err2 = strconv.ParseFloat(lngStr, 64)
		if err1 != nil || err2 != nil || lat < -90 || lat > 90 || lng < -180 || lng > 180 {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", errInvalidCoordinates.Error())
			return
		}
		hasLoc = true
	}

	args := []interface{}{}
	argIdx := 1
	where := []string{"b.status = 'approved'"}
	orderBy := "distance_m ASC NULLS LAST, b.name ASC"

	if hasLoc {
		where = append(where, fmt.Sprintf(
			`ST_DWithin(b.location, ST_SetSRID(ST_MakePoint($%d, $%d)::geography, 4326), $%d)`,
			argIdx, argIdx+1, argIdx+2,
		))
		args = append(args, lng, lat, radiusM)
		argIdx += 3
	}
	if categorySlug != "" {
		where = append(where, fmt.Sprintf("b.category_slug = $%d", argIdx))
		args = append(args, categorySlug)
		argIdx++
	}
	if openNow {
		where = append(where, `EXISTS (
			SELECT 1 FROM business_hours bh
			WHERE bh.business_id = b.id
			AND bh.weekday = EXTRACT(DOW FROM now() AT TIME ZONE 'UTC')
			AND bh.is_closed = false
			AND bh.opens_at IS NOT NULL AND bh.closes_at IS NOT NULL
		)`)
	}

	query := `
		SELECT b.id, b.name, b.slug, b.category_slug, c.name, b.address_text,
		       b.locality, b.city, b.postal_code, b.status, b.verification_status,
		       b.phone_e164, b.whatsapp_e164,
		       ST_Y(b.location::geometry) AS latitude,
		       ST_X(b.location::geometry) AS longitude`
	if hasLoc {
		query += fmt.Sprintf(`, ST_Distance(b.location, ST_SetSRID(ST_MakePoint($%d, $%d)::geography, 4326)) AS distance_m`,
			argIdx, argIdx+1)
		args = append(args, lng, lat)
		argIdx += 2
	} else {
		query += `, NULL AS distance_m`
	}

	query += `
		FROM businesses b
		LEFT JOIN categories c ON c.slug = b.category_slug
		WHERE ` + strings.Join(where, " AND ")

	if sort == "relevance" && q != "" {
		orderBy = fmt.Sprintf("(CASE WHEN b.name ILIKE $%d THEN 0 ELSE 1 END), distance_m ASC NULLS LAST, b.name ASC", argIdx)
		args = append(args, "%"+q+"%")
		argIdx++
	}
	query += ` ORDER BY ` + orderBy + `
		LIMIT $` + strconv.Itoa(argIdx)
	args = append(args, limit)

	rows, err := s.db.QueryxContext(r.Context(), query, args...)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to search businesses.")
		return
	}
	defer rows.Close()

	var results []Business
	for rows.Next() {
		var b Business
		var slug, locality, city, postal, phone, whatsapp sql.NullString
		var dist, lat, lng sql.NullFloat64
		err := rows.Scan(&b.ID, &b.Name, &slug, &b.CategorySlug, &b.CategoryName,
			&b.AddressText, &locality, &city, &postal, &b.Status, &b.VerificationStatus,
			&phone, &whatsapp, &lat, &lng, &dist)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to read results.")
			return
		}
		if slug.Valid {
			b.Slug = slug.String
		}
		if locality.Valid {
			b.Locality = locality.String
		}
		if city.Valid {
			b.City = city.String
		}
		if postal.Valid {
			b.PostalCode = postal.String
		}
		if phone.Valid {
			b.PhoneE164 = phone.String
		}
		if whatsapp.Valid {
			b.WhatsappE164 = whatsapp.String
		}
		if lat.Valid {
			b.Latitude = &lat.Float64
		}
		if lng.Valid {
			b.Longitude = &lng.Float64
		}
		if dist.Valid {
			b.DistanceM = &dist.Float64
		}
		results = append(results, b)
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": results,
		"meta": map[string]interface{}{
			"request_id": "search",
			"limit":      limit,
			"count":      len(results),
		},
	})
}

func (s *Service) GetBusiness(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var b BusinessDetail
		var slug, locality, city, postal, phone, whatsapp sql.NullString
		var desc sql.NullString
		var lat, lng sql.NullFloat64
		err := s.db.QueryRowxContext(r.Context(), `
		SELECT b.id, b.name, b.slug, b.category_slug, c.name, b.address_text,
		       b.locality, b.city, b.postal_code, b.description,
		       b.status, b.verification_status, b.phone_e164, b.whatsapp_e164,
		       ST_Y(b.location::geometry) AS latitude,
		       ST_X(b.location::geometry) AS longitude
		FROM businesses b
		LEFT JOIN categories c ON c.slug = b.category_slug
		WHERE b.id = $1
	`, id).Scan(&b.ID, &b.Name, &slug, &b.CategorySlug, &b.CategoryName,
		&b.AddressText, &locality, &city, &postal, &desc,
		&b.Status, &b.VerificationStatus, &phone, &whatsapp, &lat, &lng)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, "NOT_FOUND", "Business not found.")
		} else {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load business.")
		}
		return
	}
	if slug.Valid {
		b.Slug = slug.String
	}
	if locality.Valid {
		b.Locality = locality.String
	}
	if city.Valid {
		b.City = city.String
	}
	if postal.Valid {
		b.PostalCode = postal.String
	}
	if desc.Valid {
		b.Description = desc.String
	}
	if phone.Valid {
		b.PhoneE164 = phone.String
	}
	if whatsapp.Valid {
		b.WhatsappE164 = whatsapp.String
	}
	if lat.Valid {
		b.Latitude = &lat.Float64
	}
	if lng.Valid {
		b.Longitude = &lng.Float64
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": b,
		"meta": map[string]string{"request_id": "business"},
	})
}

func (s *Service) ListProducts(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	rows, err := s.db.QueryxContext(r.Context(), `
		SELECT id, business_id, name, description, price, currency, stock_status, is_published, image_url, updated_at
		FROM products
		WHERE business_id = $1 AND is_published = true
		ORDER BY updated_at DESC
	`, id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load products.")
		return
	}
	defer rows.Close()

	var products []Product
	for rows.Next() {
		var p Product
		var price sql.NullFloat64
		var desc, image sql.NullString
		var updated sql.NullTime
		if err := rows.Scan(&p.ID, &p.BusinessID, &p.Name, &desc, &price, &p.Currency,
			&p.StockStatus, &p.IsPublished, &image, &updated); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to read products.")
			return
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
		"meta": map[string]string{"request_id": "products"},
	})
}

func (s *Service) ListServices(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	rows, err := s.db.QueryxContext(r.Context(), `
		SELECT id, business_id, name, description, indicative_price_min, indicative_price_max, currency, is_active
		FROM services
		WHERE business_id = $1 AND is_active = true
		ORDER BY name ASC
	`, id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load services.")
		return
	}
	defer rows.Close()

	var services []ServiceOffering
	for rows.Next() {
		var srv ServiceOffering
		var desc sql.NullString
		var pmin, pmax sql.NullFloat64
		if err := rows.Scan(&srv.ID, &srv.BusinessID, &srv.Name, &desc, &pmin, &pmax, &srv.Currency, &srv.IsActive); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to read services.")
			return
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
		"meta": map[string]string{"request_id": "services"},
	})
}

func (s *Service) ListOffers(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	now := time.Now()
	rows, err := s.db.QueryxContext(r.Context(), `
		SELECT id, business_id, title, description, starts_at, ends_at, status, image_url, terms, discount_percent
		FROM offers
		WHERE business_id = $1 AND status = 'published' AND starts_at <= $2 AND ends_at >= $2
		ORDER BY starts_at DESC
	`, id, now)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load offers.")
		return
	}
	defer rows.Close()

	var offers []Offer
	for rows.Next() {
		var o Offer
		var desc, terms, image sql.NullString
		var disc sql.NullInt64
		if err := rows.Scan(&o.ID, &o.BusinessID, &o.Title, &desc, &o.StartsAt, &o.EndsAt,
			&o.Status, &image, &terms, &disc); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to read offers.")
			return
		}
		if desc.Valid {
			o.Description = desc.String
		}
		if terms.Valid {
			o.Terms = terms.String
		}
		if image.Valid {
			o.ImageURL = image.String
		}
		if disc.Valid {
			d := int(disc.Int64)
			o.DiscountPct = &d
		}
		offers = append(offers, o)
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": offers,
		"meta": map[string]string{"request_id": "offers"},
	})
}

func (s *Service) Nearby(w http.ResponseWriter, r *http.Request) {
	latStr := r.URL.Query().Get("lat")
	lngStr := r.URL.Query().Get("lng")
	lat, err := strconv.ParseFloat(latStr, 64)
	lng, err2 := strconv.ParseFloat(lngStr, 64)
	if err != nil || err2 != nil || lat < -90 || lat > 90 || lng < -180 || lng > 180 {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", errInvalidCoordinates.Error())
		return
	}
	radiusM := 5000
	if v := r.URL.Query().Get("radius_m"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= 100 && n <= 50000 {
			radiusM = n
		} else {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", errRadiusOutOfRange.Error())
			return
		}
	}
	limit, _ := parsePagination(r)

	rows, err := s.db.QueryxContext(r.Context(), `
		SELECT b.id, b.name, b.slug, b.category_slug, c.name, b.address_text,
		       b.locality, b.city, b.status, b.verification_status, b.phone_e164,
		       b.whatsapp_e164,
		       ST_Y(b.location::geometry) AS latitude,
		       ST_X(b.location::geometry) AS longitude,
		       ST_Distance(b.location, ST_SetSRID(ST_MakePoint($1, $2)::geography, 4326)) AS distance_m
		FROM businesses b
		LEFT JOIN categories c ON c.slug = b.category_slug
		WHERE b.status = 'approved'
		  AND ST_DWithin(b.location, ST_SetSRID(ST_MakePoint($1, $2)::geography, 4326), $3)
		ORDER BY distance_m ASC, b.name ASC
		LIMIT $4
	`, lng, lat, radiusM, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load nearby businesses.")
		return
	}
	defer rows.Close()

	var results []Business
	for rows.Next() {
		var b Business
		var slug, locality, city, phone, whatsapp sql.NullString
		var dist, latitude, longitude sql.NullFloat64
		if err := rows.Scan(&b.ID, &b.Name, &slug, &b.CategorySlug, &b.CategoryName,
			&b.AddressText, &locality, &city, &b.Status, &b.VerificationStatus,
			&phone, &whatsapp, &latitude, &longitude, &dist); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to read results.")
			return
		}
		if slug.Valid {
			b.Slug = slug.String
		}
		if locality.Valid {
			b.Locality = locality.String
		}
		if city.Valid {
			b.City = city.String
		}
		if phone.Valid {
			b.PhoneE164 = phone.String
		}
		if whatsapp.Valid {
			b.WhatsappE164 = whatsapp.String
		}
		if latitude.Valid {
			b.Latitude = &latitude.Float64
		}
		if longitude.Valid {
			b.Longitude = &longitude.Float64
		}
		if dist.Valid {
			b.DistanceM = &dist.Float64
		}
		results = append(results, b)
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": results,
		"meta": map[string]interface{}{
			"request_id": "nearby",
			"limit":      limit,
			"count":      len(results),
		},
	})
}

// ---------- Favorites ----------

func (s *Service) ListFavorites(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	limit := 20
	if v := r.URL.Query().Get("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= 1 && n <= 50 {
			limit = n
		}
	}
	where := "f.user_id = $1 AND b.status = 'approved'"
	args := []interface{}{userID}
	argIdx := 2

	query := `
		SELECT b.id, b.name, b.slug, b.category_slug, c.name, b.address_text,
		       b.locality, b.city, b.postal_code, b.status, b.verification_status,
		       b.phone_e164, b.whatsapp_e164,
		       ST_Y(b.location::geometry) AS latitude,
		       ST_X(b.location::geometry) AS longitude,
		       f.created_at as favorited_at
		FROM favorites f
		JOIN businesses b ON b.id = f.business_id
		LEFT JOIN categories c ON c.slug = b.category_slug
		WHERE ` + where + `
		ORDER BY f.created_at DESC
		LIMIT $` + strconv.Itoa(argIdx)
	args = append(args, limit)

	rows, err := s.db.QueryxContext(r.Context(), query, args...)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load favorites.")
		return
	}
	defer rows.Close()

	var results []Business
	for rows.Next() {
		var b Business
		var slug, locality, city, postal, phone, whatsapp sql.NullString
		var lat, lng sql.NullFloat64
		var favoritedAt sql.NullTime
		err := rows.Scan(&b.ID, &b.Name, &slug, &b.CategorySlug, &b.CategoryName,
			&b.AddressText, &locality, &city, &postal, &b.Status, &b.VerificationStatus,
			&phone, &whatsapp, &lat, &lng, &favoritedAt)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to read results.")
			return
		}
		if slug.Valid {
			b.Slug = slug.String
		}
		if locality.Valid {
			b.Locality = locality.String
		}
		if city.Valid {
			b.City = city.String
		}
		if postal.Valid {
			b.PostalCode = postal.String
		}
		if phone.Valid {
			b.PhoneE164 = phone.String
		}
		if whatsapp.Valid {
			b.WhatsappE164 = whatsapp.String
		}
		if lat.Valid {
			b.Latitude = &lat.Float64
		}
		if lng.Valid {
			b.Longitude = &lng.Float64
		}
		results = append(results, b)
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": results,
		"meta": map[string]interface{}{
			"request_id": "favorites",
			"limit":      limit,
			"count":      len(results),
		},
	})
}

func (s *Service) ToggleFavorite(authSvc *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	id := r.PathValue("id")
	if id == "" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Business ID required.")
		return
	}

	// Check if already favorited
	var exists bool
	err := s.db.QueryRowContext(r.Context(), `
		SELECT EXISTS(SELECT 1 FROM favorites WHERE user_id = $1 AND business_id = $2)
	`, userID, id).Scan(&exists)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to check favorite.")
		return
	}

	if exists {
		// Remove favorite
		_, err = s.db.ExecContext(r.Context(), `
			DELETE FROM favorites WHERE user_id = $1 AND business_id = $2
		`, userID, id)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to remove favorite.")
			return
		}
		writeJSON(w, http.StatusOK, envelope{
			"data": map[string]bool{"favorited": false},
			"meta": map[string]string{"request_id": "favorite-toggle"},
		})
	} else {
		// Add favorite
		_, err = s.db.ExecContext(r.Context(), `
			INSERT INTO favorites (user_id, business_id) VALUES ($1, $2)
			ON CONFLICT (user_id, business_id) DO NOTHING
		`, userID, id)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to add favorite.")
			return
		}
		writeJSON(w, http.StatusOK, envelope{
			"data": map[string]bool{"favorited": true},
			"meta": map[string]string{"request_id": "favorite-toggle"},
		})
	}
}

func (s *Service) cfgNow() time.Time {
	return time.Now()
}

var _ = errors.Is
