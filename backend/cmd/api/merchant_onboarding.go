package main

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"regexp"
	"strings"

	"github.com/google/uuid"
	"grepmind-near/backend/pkg/database"
)

type createMerchantBusinessRequest struct {
	Name          string               `json:"name"`
	Description   string               `json:"description"`
	CategorySlug  string               `json:"category_slug"`
	PhoneE164     string               `json:"phone_e164"`
	WhatsAppE164  string               `json:"whatsapp_e164"`
	AddressText   string               `json:"address_text"`
	Locality      string               `json:"locality"`
	City          string               `json:"city"`
	PostalCode    string               `json:"postal_code"`
	Latitude      float64              `json:"latitude"`
	Longitude     float64              `json:"longitude"`
	CoverPhotoURL string               `json:"cover_photo_url"`
	Hours         []createBusinessHour `json:"hours"`
}

type createBusinessHour struct {
	Weekday  int     `json:"weekday"`
	OpensAt  *string `json:"opens_at"`
	ClosesAt *string `json:"closes_at"`
	IsClosed bool    `json:"is_closed"`
}

// registerMerchantBusiness is intentionally limited to pending listings in the
// two supported launch cities. The authenticated user becomes the owner in the
// same transaction; verification/status are never accepted from the client.
func createMerchantBusiness(db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	r.Body = http.MaxBytesReader(w, r.Body, 32<<10)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	var req createMerchantBusinessRequest
	if err := decoder.Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Invalid business details.")
		return
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Invalid business details.")
		return
	}
	trim := func(s string) string { return strings.TrimSpace(s) }
	req.Name, req.Description, req.CategorySlug = trim(req.Name), trim(req.Description), trim(req.CategorySlug)
	req.AddressText, req.Locality = trim(req.AddressText), trim(req.Locality)
	req.City, req.PostalCode = trim(req.City), trim(req.PostalCode)
	req.PhoneE164, req.WhatsAppE164 = trim(req.PhoneE164), trim(req.WhatsAppE164)
	req.CoverPhotoURL = trim(req.CoverPhotoURL)
	if len([]rune(req.Name)) < 2 || len([]rune(req.Name)) > 100 || len([]rune(req.Description)) > 2000 ||
		req.CategorySlug == "" || len(req.CategorySlug) > 100 || len([]rune(req.AddressText)) < 5 || len([]rune(req.AddressText)) > 240 ||
		len([]rune(req.Locality)) < 2 || len([]rune(req.Locality)) > 100 || len(req.PostalCode) != 6 || !digitsOnly(req.PostalCode) ||
		!validOptionalIndianMobile(req.PhoneE164) || !validOptionalIndianMobile(req.WhatsAppE164) ||
		math.IsNaN(req.Latitude) || math.IsInf(req.Latitude, 0) || req.Latitude < -90 || req.Latitude > 90 ||
		math.IsNaN(req.Longitude) || math.IsInf(req.Longitude, 0) || req.Longitude < -180 || req.Longitude > 180 {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Review the required business name, category, contact, address, PIN and location fields.")
		return
	}
	city := strings.ToLower(req.City)
	if city != "cuttack" && city != "jajpur" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Only Cuttack and Jajpur are supported.")
		return
	}
	var centerLat, centerLng float64
	var cityListingCount int
	if err := db.QueryRowxContext(r.Context(), `
		SELECT count(*), COALESCE(avg(ST_Y(location::geometry)),0), COALESCE(avg(ST_X(location::geometry)),0)
		FROM businesses WHERE lower(city)=lower($1) AND status='approved' AND location IS NOT NULL
	`, req.City).Scan(&cityListingCount, &centerLat, &centerLng); err != nil || cityListingCount == 0 {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "This city has no active location coverage yet.")
		return
	}
	var locationInCity bool
	if err := db.QueryRowxContext(r.Context(), `
		SELECT ST_DWithin(
			ST_SetSRID(ST_MakePoint($1,$2),4326)::geography,
			ST_SetSRID(ST_MakePoint($3,$4),4326)::geography,
			30000
		)
	`, req.Longitude, req.Latitude, centerLng, centerLat).Scan(&locationInCity); err != nil || !locationInCity {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "The business pin must be within 30 km of the selected city center.")
		return
	}
	if len(req.Hours) != 7 {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Provide an operating-hours choice for all seven days.")
		return
	}
	seenDays := make(map[int]bool, 7)
	for _, hour := range req.Hours {
		if hour.Weekday < 0 || hour.Weekday > 6 || seenDays[hour.Weekday] {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Operating days must be unique weekdays from zero through six.")
			return
		}
		seenDays[hour.Weekday] = true
		if !hour.IsClosed && (hour.OpensAt == nil || hour.ClosesAt == nil || !validBusinessTime(*hour.OpensAt) || !validBusinessTime(*hour.ClosesAt) || *hour.OpensAt == *hour.ClosesAt) {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Open days require valid opening and closing times.")
			return
		}
	}
	if req.CoverPhotoURL != "" {
		var owned bool
		if err := db.QueryRowxContext(r.Context(), `SELECT EXISTS(SELECT 1 FROM media_uploads WHERE user_id=$1 AND purpose='storefront' AND object_key=$2)`, userID, strings.TrimPrefix(req.CoverPhotoURL, "/media/")).Scan(&owned); err != nil || !owned {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Upload the storefront photo using this account before saving it.")
			return
		}
	}
	var businessID, categoryName, phone string
	tx, err := db.BeginTxx(r.Context(), nil)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to start business registration.")
		return
	}
	defer tx.Rollback()
	if err = tx.GetContext(r.Context(), &categoryName, `SELECT name FROM categories WHERE slug=$1 AND is_active=true`, req.CategorySlug); errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Choose an active business category.")
		return
	} else if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to validate the category.")
		return
	}
	if err = tx.GetContext(r.Context(), &phone, `SELECT phone_e164 FROM users WHERE id=$1 AND status='active'`, userID); err != nil {
		writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "Sign in again to register your business.")
		return
	}
	if req.PhoneE164 == "" {
		req.PhoneE164 = phone
	}
	if req.WhatsAppE164 == "" {
		req.WhatsAppE164 = req.PhoneE164
	}
	if !validIndianMobile(req.PhoneE164) || !validIndianMobile(req.WhatsAppE164) {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Use a valid Indian mobile number.")
		return
	}
	id := uuid.NewString()
	slugBase := slugify(req.Name)
	slug := fmt.Sprintf("%s-%s", slugBase, strings.ReplaceAll(id[:8], "-", ""))
	err = tx.QueryRowxContext(r.Context(), `
		INSERT INTO businesses (id,owner_user_id,name,slug,description,category_slug,phone_e164,whatsapp_e164,address_text,locality,city,postal_code,location,status,verification_status,time_zone,cover_photo_url)
		VALUES ($1,$2,$3,$4,NULLIF($5,''),$6,$7,$8,$9,$10,$11,$12,ST_SetSRID(ST_MakePoint($13,$14),4326)::geography,'pending','pending','Asia/Kolkata',NULLIF($15,''))
		RETURNING id::text
	`, id, userID, req.Name, slug, req.Description, req.CategorySlug, req.PhoneE164, req.WhatsAppE164, req.AddressText, req.Locality, req.City, req.PostalCode, req.Longitude, req.Latitude, req.CoverPhotoURL).Scan(&businessID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to save the business listing.")
		return
	}
	if _, err = tx.ExecContext(r.Context(), `INSERT INTO user_roles(user_id,role) VALUES($1,'merchant') ON CONFLICT DO NOTHING`, userID); err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to activate merchant access.")
		return
	}
	for _, hour := range req.Hours {
		var opensAt, closesAt interface{}
		if hour.OpensAt != nil && *hour.OpensAt != "" {
			opensAt = *hour.OpensAt
		}
		if hour.ClosesAt != nil && *hour.ClosesAt != "" {
			closesAt = *hour.ClosesAt
		}
		if _, err = tx.ExecContext(r.Context(), `INSERT INTO business_hours(business_id,weekday,opens_at,closes_at,is_closed) VALUES($1,$2,$3,$4,$5)`, businessID, hour.Weekday, opensAt, closesAt, hour.IsClosed); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to save operating hours.")
			return
		}
	}
	if err = tx.Commit(); err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to complete business registration.")
		return
	}
	writeJSON(w, http.StatusCreated, envelope{"data": map[string]interface{}{
		"id": businessID, "name": req.Name, "slug": slug, "category_slug": req.CategorySlug,
		"category_name": categoryName, "address_text": req.AddressText, "locality": req.Locality,
		"city": req.City, "postal_code": req.PostalCode, "phone_e164": req.PhoneE164,
		"whatsapp_e164": req.WhatsAppE164, "cover_photo_url": req.CoverPhotoURL,
		"latitude": req.Latitude, "longitude": req.Longitude, "status": "pending", "verification_status": "pending",
	}, "meta": map[string]string{"request_id": "merchant-business-created"}})
}

var (
	digitsPattern       = regexp.MustCompile(`^[0-9]+$`)
	indianMobilePattern = regexp.MustCompile(`^\+91[6-9][0-9]{9}$`)
)

func digitsOnly(value string) bool                { return digitsPattern.MatchString(value) }
func validIndianMobile(value string) bool         { return indianMobilePattern.MatchString(value) }
func validOptionalIndianMobile(value string) bool { return value == "" || validIndianMobile(value) }

func slugify(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	var b strings.Builder
	lastDash := false
	for _, r := range value {
		if r >= 'a' && r <= 'z' || r >= '0' && r <= '9' {
			b.WriteRune(r)
			lastDash = false
		} else if !lastDash && b.Len() > 0 {
			b.WriteByte('-')
			lastDash = true
		}
	}
	return strings.Trim(b.String(), "-")
}
