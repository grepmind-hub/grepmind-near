package discovery

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"math"
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

// Odisha businesses use India Standard Time for weekly opening hours. The
// expression accounts for schedules that run past midnight into the next day.
const businessOpenNowSQL = `EXISTS (
	SELECT 1 FROM business_hours bh
	CROSS JOIN LATERAL (SELECT now() AT TIME ZONE 'Asia/Kolkata' AS local_now) clock
	WHERE bh.business_id = b.id AND bh.is_closed = false
	  AND bh.opens_at IS NOT NULL AND bh.closes_at IS NOT NULL
	  AND (
		(bh.weekday = EXTRACT(DOW FROM clock.local_now)::int AND (
			(bh.opens_at < bh.closes_at AND bh.opens_at <= clock.local_now::time AND bh.closes_at > clock.local_now::time)
			OR (bh.opens_at > bh.closes_at AND bh.opens_at <= clock.local_now::time)
		))
		OR (bh.weekday = ((EXTRACT(DOW FROM clock.local_now)::int + 6) % 7)
			AND bh.opens_at > bh.closes_at AND bh.closes_at > clock.local_now::time)
	  )
)`

// ---------- Models ----------

type Category struct {
	Slug        string `json:"slug"`
	Name        string `json:"name"`
	IconName    string `json:"icon_name,omitempty"`
	Description string `json:"description,omitempty"`
	SortOrder   int    `json:"-"`
}

type Business struct {
	ID                  string   `json:"id"`
	Name                string   `json:"name"`
	Slug                string   `json:"slug,omitempty"`
	CategorySlug        string   `json:"category_slug"`
	CategoryName        string   `json:"category_name,omitempty"`
	AddressText         string   `json:"address_text"`
	Locality            string   `json:"locality,omitempty"`
	City                string   `json:"city,omitempty"`
	PostalCode          string   `json:"postal_code,omitempty"`
	Latitude            *float64 `json:"latitude,omitempty"`
	Longitude           *float64 `json:"longitude,omitempty"`
	DistanceM           *float64 `json:"distance_m,omitempty"`
	Status              string   `json:"status"`
	VerificationStatus  string   `json:"verification_status"`
	PhoneE164           string   `json:"phone_e164,omitempty"`
	WhatsappE164        string   `json:"whatsapp_e164,omitempty"`
	IsOpenNow           bool     `json:"is_open_now"`
	AcceptsRequests     bool     `json:"accepts_requests"`
	CoverPhotoURL       string   `json:"cover_photo_url,omitempty"`
	Rating              *float64 `json:"rating,omitempty"`
	ReviewCount         *int     `json:"review_count,omitempty"`
	DeliveryEnabled     bool     `json:"delivery_enabled"`
	DeliveryTimeMins    int      `json:"delivery_time_mins"`
	DeliveryFee         float64  `json:"delivery_fee"`
	MinOrderAmount      float64  `json:"min_order_amount"`
	TableBookingEnabled bool     `json:"table_booking_enabled"`
	RoomBookingEnabled  bool     `json:"room_booking_enabled"`
	Amenities           []string `json:"amenities,omitempty"`
}

type BusinessHour struct {
	Weekday  int     `json:"weekday"`
	OpensAt  *string `json:"opens_at,omitempty"`
	ClosesAt *string `json:"closes_at,omitempty"`
	IsClosed bool    `json:"is_closed"`
}

type Product struct {
	ID                 string   `json:"id"`
	BusinessID         string   `json:"business_id"`
	Name               string   `json:"name"`
	Description        string   `json:"description,omitempty"`
	Price              *float64 `json:"price,omitempty"`
	Currency           string   `json:"currency"`
	StockStatus        string   `json:"stock_status"`
	IsPublished        bool     `json:"is_published"`
	ImageURL           string   `json:"image_url,omitempty"`
	DietaryType        string   `json:"dietary_type,omitempty"`
	FoodCategory       string   `json:"food_category,omitempty"`
	PreparationTimeMin int      `json:"preparation_time_min,omitempty"`
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

// CityOffer is a currently published offer with the approved business context
// required by the public Home feed. Contact details are intentionally omitted.
type CityOffer struct {
	Offer
	BusinessName     string `json:"business_name"`
	BusinessCity     string `json:"business_city"`
	BusinessLocality string `json:"business_locality,omitempty"`
	BusinessPhotoURL string `json:"business_photo_url,omitempty"`
}

// CityCatalogItem is a customer-visible product or service recently
// published by an approved business in a supported city.
type CityCatalogItem struct {
	ID               string    `json:"id"`
	ItemType         string    `json:"item_type"`
	BusinessID       string    `json:"business_id"`
	BusinessName     string    `json:"business_name"`
	BusinessCity     string    `json:"business_city"`
	BusinessLocality string    `json:"business_locality,omitempty"`
	CategoryName     string    `json:"category_name"`
	Name             string    `json:"name"`
	Description      string    `json:"description,omitempty"`
	Price            *float64  `json:"price,omitempty"`
	PriceMax         *float64  `json:"price_max,omitempty"`
	Currency         string    `json:"currency"`
	ImageURL         string    `json:"image_url,omitempty"`
	PublishedAt      time.Time `json:"published_at"`
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
	CompletedJobs      int               `json:"completed_jobs"`
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
	city := strings.TrimSpace(r.URL.Query().Get("city"))
	if len(city) > 120 {
		writeError(w, 400, "VALIDATION_ERROR", "City is too long.")
		return
	}
	openNow := r.URL.Query().Get("open_now") == "true"
	availableNow := r.URL.Query().Get("available_now") == "true"
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
	if city != "" {
		where = append(where, fmt.Sprintf("lower(b.city) = lower($%d)", argIdx))
		args = append(args, city)
		argIdx++
	}
	if q != "" {
		where = append(where, fmt.Sprintf("(b.name ILIKE $%d OR b.description ILIKE $%d)", argIdx, argIdx))
		args = append(args, "%"+q+"%")
		argIdx++
	}

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
		where = append(where, businessOpenNowSQL)
	}
	if availableNow {
		where = append(where, `EXISTS (SELECT 1 FROM professional_profiles pp WHERE pp.business_id = b.id AND pp.accepts_requests = true)`)
	}
	if sort == "recent" {
		orderBy = "b.created_at DESC, b.name ASC"
	}

	query := `
		SELECT b.id, b.name, b.slug, b.category_slug, c.name, b.address_text,
		       b.locality, b.city, b.postal_code, b.status, b.verification_status,
		       b.phone_e164, b.whatsapp_e164,
		       ST_Y(b.location::geometry) AS latitude,
		       ST_X(b.location::geometry) AS longitude,
		       b.cover_photo_url, ` + businessOpenNowSQL + ` AS is_open_now,
		       EXISTS (SELECT 1 FROM professional_profiles pp WHERE pp.business_id = b.id AND pp.accepts_requests = true) AS accepts_requests`
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
		var slug, locality, city, postal, phone, whatsapp, cover sql.NullString
		var dist, lat, lng sql.NullFloat64
		err := rows.Scan(&b.ID, &b.Name, &slug, &b.CategorySlug, &b.CategoryName,
			&b.AddressText, &locality, &city, &postal, &b.Status, &b.VerificationStatus,
			&phone, &whatsapp, &lat, &lng, &cover, &b.IsOpenNow, &b.AcceptsRequests, &dist)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to read results.")
			return
		}
		if cover.Valid {
			b.CoverPhotoURL = cover.String
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
	var slug, locality, city, postal, phone, whatsapp, cover sql.NullString
	var desc sql.NullString
	var lat, lng sql.NullFloat64
	var amenitiesRaw []byte
	err := s.db.QueryRowxContext(r.Context(), `
		SELECT b.id, b.name, b.slug, b.category_slug, c.name, b.address_text,
		       b.locality, b.city, b.postal_code, b.description,
		       b.status, b.verification_status, b.phone_e164, b.whatsapp_e164,
		       ST_Y(b.location::geometry) AS latitude,
		       ST_X(b.location::geometry) AS longitude,
		       b.cover_photo_url,
	       `+businessOpenNowSQL+` AS is_open_now,
		       COALESCE(b.delivery_enabled, false),
		       COALESCE(b.delivery_time_mins, 30),
		       COALESCE(b.delivery_fee, 30.0),
		       COALESCE(b.min_order_amount, 0.0),
		       COALESCE(b.table_booking_enabled, false),
		       COALESCE(b.room_booking_enabled, false),
		       COALESCE(b.amenities, '[]'::jsonb)
		FROM businesses b
		LEFT JOIN categories c ON c.slug = b.category_slug
		WHERE b.id = $1
	`, id).Scan(&b.ID, &b.Name, &slug, &b.CategorySlug, &b.CategoryName,
		&b.AddressText, &locality, &city, &postal, &desc,
		&b.Status, &b.VerificationStatus, &phone, &whatsapp, &lat, &lng, &cover, &b.IsOpenNow,
		&b.DeliveryEnabled, &b.DeliveryTimeMins, &b.DeliveryFee, &b.MinOrderAmount,
		&b.TableBookingEnabled, &b.RoomBookingEnabled, &amenitiesRaw)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, "NOT_FOUND", "Business not found.")
		} else {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load business.")
		}
		return
	}
	if len(amenitiesRaw) > 0 {
		_ = json.Unmarshal(amenitiesRaw, &b.Amenities)
	}
	if cover.Valid {
		b.CoverPhotoURL = cover.String
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
	var radius, experience sql.NullInt64
	var serviceDescription sql.NullString
	var acceptsRequests sql.NullBool
	if err := s.db.QueryRowContext(r.Context(), `SELECT service_radius_m,experience_years,service_description,accepts_requests FROM professional_profiles WHERE business_id=$1`, id).
		Scan(&radius, &experience, &serviceDescription, &acceptsRequests); err == nil {
		if radius.Valid {
			value := int(radius.Int64)
			b.ServiceRadiusM = &value
		}
		if experience.Valid {
			value := int(experience.Int64)
			b.ExperienceYears = &value
		}
		if serviceDescription.Valid {
			b.ServiceDescription = serviceDescription.String
		}
		if acceptsRequests.Valid {
			b.AcceptsRequests = acceptsRequests.Bool
		}
	}
	_ = s.db.QueryRowContext(r.Context(), `SELECT count(*) FROM service_requests WHERE business_id=$1 AND status='completed'`, id).Scan(&b.CompletedJobs)
	hourRows, hourErr := s.db.QueryxContext(r.Context(), `SELECT weekday,opens_at,closes_at,is_closed FROM business_hours WHERE business_id=$1 ORDER BY weekday`, id)
	if hourErr == nil {
		defer hourRows.Close()
		for hourRows.Next() {
			var h BusinessHour
			var open, close sql.NullString
			if hourRows.Scan(&h.Weekday, &open, &close, &h.IsClosed) == nil {
				if open.Valid {
					h.OpensAt = &open.String
				}
				if close.Valid {
					h.ClosesAt = &close.String
				}
				b.BusinessHours = append(b.BusinessHours, h)
			}
		}
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": b,
		"meta": map[string]string{"request_id": "business"},
	})
}

func (s *Service) ListProducts(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	rows, err := s.db.QueryxContext(r.Context(), `
		SELECT id, business_id, name, description, price, currency, stock_status, is_published, image_url, updated_at,
		       COALESCE(dietary_type, ''), COALESCE(food_category, ''), COALESCE(preparation_time_min, 20)
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
		var dietary, foodCategory string
		var prepTime int
		if err := rows.Scan(&p.ID, &p.BusinessID, &p.Name, &desc, &price, &p.Currency,
			&p.StockStatus, &p.IsPublished, &image, &updated,
			&dietary, &foodCategory, &prepTime); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to read products.")
			return
		}
		p.DietaryType = dietary
		p.FoodCategory = foodCategory
		p.PreparationTimeMin = prepTime
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

func (s *Service) ListCityOffers(w http.ResponseWriter, r *http.Request) {
	city := strings.TrimSpace(r.URL.Query().Get("city"))
	if !isSupportedOfferCity(city) {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "City must be Cuttack or Jajpur.")
		return
	}
	limit, _ := parsePagination(r)
	now := time.Now()
	rows, err := s.db.QueryxContext(r.Context(), `
		SELECT o.id, o.business_id, o.title, o.description, o.starts_at, o.ends_at,
		       o.status, o.image_url, o.terms, o.discount_percent,
		       b.name, b.city, b.locality, b.cover_photo_url
		FROM offers o
		JOIN businesses b ON b.id = o.business_id
		WHERE lower(b.city) = lower($1)
		  AND b.status = 'approved'
		  AND o.status = 'published'
		  AND o.starts_at <= $2 AND o.ends_at >= $2
		ORDER BY o.starts_at DESC, o.created_at DESC
		LIMIT $3
	`, city, now, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load current offers.")
		return
	}
	defer rows.Close()

	offers := make([]CityOffer, 0)
	for rows.Next() {
		var item CityOffer
		var desc, terms, image, locality, businessPhoto sql.NullString
		var discount sql.NullInt64
		if err := rows.Scan(&item.ID, &item.BusinessID, &item.Title, &desc, &item.StartsAt, &item.EndsAt,
			&item.Status, &image, &terms, &discount, &item.BusinessName, &item.BusinessCity, &locality, &businessPhoto); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to read current offers.")
			return
		}
		if desc.Valid {
			item.Description = desc.String
		}
		if terms.Valid {
			item.Terms = terms.String
		}
		if image.Valid {
			item.ImageURL = image.String
		}
		if discount.Valid {
			value := int(discount.Int64)
			item.DiscountPct = &value
		}
		if locality.Valid {
			item.BusinessLocality = locality.String
		}
		if businessPhoto.Valid {
			item.BusinessPhotoURL = businessPhoto.String
		}
		offers = append(offers, item)
	}
	if err := rows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to read current offers.")
		return
	}
	writeJSON(w, http.StatusOK, envelope{
		"data": offers,
		"meta": map[string]string{"request_id": "city-offers"},
	})
}

func (s *Service) ListNewCatalogItems(w http.ResponseWriter, r *http.Request) {
	city := strings.TrimSpace(r.URL.Query().Get("city"))
	if !isSupportedOfferCity(city) {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "City must be Cuttack or Jajpur.")
		return
	}
	kind := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("type")))
	if kind == "" {
		kind = "all"
	}
	if kind != "all" && kind != "products" && kind != "services" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Type must be all, products, or services.")
		return
	}
	limit := 8
	if value := r.URL.Query().Get("limit"); value != "" {
		parsed, err := strconv.Atoi(value)
		if err != nil || parsed < 1 || parsed > 50 {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", errLimitOutOfRange.Error())
			return
		}
		limit = parsed
	}
	offset := 0
	if value := r.URL.Query().Get("offset"); value != "" {
		parsed, err := strconv.Atoi(value)
		if err != nil || parsed < 0 || parsed > 10000 {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Offset must be between 0 and 10000.")
			return
		}
		offset = parsed
	}
	query := `
		SELECT item_id, item_type, business_id, business_name, business_city,
		       business_locality, category_name, name, description, price, price_max,
		       currency, image_url, published_at
		FROM (
			SELECT p.id AS item_id, 'product'::text AS item_type, b.id AS business_id,
			       b.name AS business_name, b.city AS business_city, COALESCE(b.locality, '') AS business_locality,
			       COALESCE(c.name, b.category_slug) AS category_name, p.name,
			       COALESCE(p.description, '') AS description, p.price, NULL::numeric AS price_max,
			       p.currency, COALESCE(p.image_url, b.cover_photo_url, '') AS image_url, p.published_at
			FROM products p
			JOIN businesses b ON b.id = p.business_id
			LEFT JOIN categories c ON c.slug = b.category_slug
			WHERE lower(b.city) = lower($1) AND b.status = 'approved'
			  AND p.is_published = true AND p.stock_status <> 'out_of_stock'
			  AND p.published_at IS NOT NULL AND $2 IN ('all', 'products')
			UNION ALL
			SELECT s.id AS item_id, 'service'::text AS item_type, b.id AS business_id,
			       b.name AS business_name, b.city AS business_city, COALESCE(b.locality, '') AS business_locality,
			       COALESCE(c.name, b.category_slug) AS category_name, s.name,
			       COALESCE(s.description, '') AS description, s.indicative_price_min AS price,
			       s.indicative_price_max AS price_max, s.currency, COALESCE(b.cover_photo_url, '') AS image_url, s.activated_at AS published_at
			FROM services s
			JOIN businesses b ON b.id = s.business_id
			LEFT JOIN categories c ON c.slug = b.category_slug
			WHERE lower(b.city) = lower($1) AND b.status = 'approved'
			  AND s.is_active = true AND s.activated_at IS NOT NULL AND $2 IN ('all', 'services')
		) catalog
		ORDER BY published_at DESC, item_id DESC
		LIMIT $3 OFFSET $4`
	rows, err := s.db.QueryxContext(r.Context(), query, city, kind, limit+1, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load new local products and services.")
		return
	}
	defer rows.Close()
	items := make([]CityCatalogItem, 0, limit)
	for rows.Next() {
		var item CityCatalogItem
		var desc, locality, image sql.NullString
		var price, priceMax sql.NullFloat64
		if err := rows.Scan(&item.ID, &item.ItemType, &item.BusinessID, &item.BusinessName,
			&item.BusinessCity, &locality, &item.CategoryName, &item.Name, &desc, &price,
			&priceMax, &item.Currency, &image, &item.PublishedAt); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to read new local products and services.")
			return
		}
		if locality.Valid {
			item.BusinessLocality = locality.String
		}
		if desc.Valid {
			item.Description = desc.String
		}
		if price.Valid {
			value := price.Float64
			item.Price = &value
		}
		if priceMax.Valid {
			value := priceMax.Float64
			item.PriceMax = &value
		}
		if image.Valid {
			item.ImageURL = image.String
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to read new local products and services.")
		return
	}
	hasMore := len(items) > limit
	if hasMore {
		items = items[:limit]
	}
	writeJSON(w, http.StatusOK, envelope{
		"data": items,
		"meta": map[string]interface{}{"request_id": "new-catalog-items", "limit": limit, "offset": offset, "has_more": hasMore},
	})
}

func isSupportedOfferCity(city string) bool {
	switch strings.ToLower(strings.TrimSpace(city)) {
	case "cuttack", "jajpur":
		return true
	default:
		return false
	}
}

func (s *Service) Nearby(w http.ResponseWriter, r *http.Request) {
	city := strings.TrimSpace(r.URL.Query().Get("city"))
	category := strings.TrimSpace(r.URL.Query().Get("category_slug"))
	if len(city) > 120 || len(category) > 100 {
		writeError(w, 400, "VALIDATION_ERROR", "Invalid city or category filter.")
		return
	}
	latStr := r.URL.Query().Get("lat")
	lngStr := r.URL.Query().Get("lng")
	lat, err := strconv.ParseFloat(latStr, 64)
	lng, err2 := strconv.ParseFloat(lngStr, 64)
	if err != nil || err2 != nil || math.IsNaN(lat) || math.IsNaN(lng) || math.IsInf(lat, 0) || math.IsInf(lng, 0) || lat < -90 || lat > 90 || lng < -180 || lng > 180 {
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
		       b.cover_photo_url,
	       `+businessOpenNowSQL+` AS is_open_now,
		       ST_Distance(b.location, ST_SetSRID(ST_MakePoint($1, $2)::geography, 4326)) AS distance_m
		FROM businesses b
		LEFT JOIN categories c ON c.slug = b.category_slug
		WHERE b.status = 'approved'
		  AND lower(b.city) IN ('cuttack','jajpur')
		  AND ($5::text = '' OR lower(b.city) = lower($5))
		  AND ($6::text = '' OR b.category_slug = $6)
		  AND ST_DWithin(b.location, ST_SetSRID(ST_MakePoint($1, $2)::geography, 4326), $3)
		ORDER BY distance_m ASC, b.name ASC
		LIMIT $4
	`, lng, lat, radiusM, limit, city, category)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load nearby businesses.")
		return
	}
	defer rows.Close()

	var results []Business
	for rows.Next() {
		var b Business
		var slug, locality, city, phone, whatsapp, cover sql.NullString
		var dist, latitude, longitude sql.NullFloat64
		if err := rows.Scan(&b.ID, &b.Name, &slug, &b.CategorySlug, &b.CategoryName,
			&b.AddressText, &locality, &city, &b.Status, &b.VerificationStatus,
			&phone, &whatsapp, &latitude, &longitude, &cover, &b.IsOpenNow, &dist); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to read results.")
			return
		}
		if cover.Valid {
			b.CoverPhotoURL = cover.String
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
