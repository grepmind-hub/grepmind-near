package main

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/mail"
	"regexp"
	"strings"

	"github.com/google/uuid"
	"grepmind-near/backend/internal/platformcatalog"
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
	CoverPhotoURL      string               `json:"cover_photo_url"`
	OnboardingSource   string               `json:"onboarding_source,omitempty"`
	FieldExecutiveCode string               `json:"field_executive_code,omitempty"`
	Hours              []createBusinessHour `json:"hours"`
	Application   *merchantApplication `json:"application"`
}

type merchantApplication struct {
	OwnerName     string `json:"owner_name"`
	Email         string `json:"email,omitempty"`
	TaxID         string `json:"tax_id,omitempty"`
	NoGST         bool   `json:"no_gst"`
	Enterprise    string `json:"enterprise_type"`
	OperatingMode string `json:"operating_mode"`
	RadiusKM      int    `json:"service_radius_km"`
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
	var applicationJSON []byte
	if application := req.Application; application != nil {
		application.OwnerName, application.Email, application.TaxID = trim(application.OwnerName), trim(application.Email), trim(application.TaxID)
		if application.NoGST {
			application.TaxID = ""
		}
		email, emailErr := mail.ParseAddress(application.Email)
		if application.OwnerName == "" || len([]rune(application.OwnerName)) > 100 ||
			len(application.Email) > 254 || (application.Email != "" && (emailErr != nil || email.Address != application.Email)) ||
			len(application.TaxID) > 40 || application.RadiusKM < 1 || application.RadiusKM > 20 ||
			(application.OperatingMode != "store_only" && application.OperatingMode != "home_only" && application.OperatingMode != "both") ||
			(application.Enterprise != "retail" && application.Enterprise != "service_pro" && application.Enterprise != "food" && application.Enterprise != "wellness") {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Review the owner name, email, registration ID and operating details.")
			return
		}
		var err error
		applicationJSON, err = json.Marshal(application)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to prepare the application details.")
			return
		}
	}
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
	covered, err := platformcatalog.MerchantRegistrationCovered(r.Context(), tx, req.City, req.Locality, req.PostalCode, req.Latitude, req.Longitude)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to verify business location coverage.")
		return
	}
	if !covered {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Enter the approved locality and its PIN code, and place the GPS pin within that service area.")
		return
	}
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
	onboardingSource := strings.TrimSpace(req.OnboardingSource)
	if onboardingSource == "" {
		onboardingSource = "self"
	}
	if onboardingSource != "self" && onboardingSource != "field_executive" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Unsupported onboarding source.")
		return
	}
	var fieldExecID *string
	if onboardingSource == "field_executive" {
		code := strings.ToUpper(strings.TrimSpace(req.FieldExecutiveCode))
		if code == "" {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Select or enter a valid Field Executive ID (AFE-1000).")
			return
		}
		var feID string
		if err := db.GetContext(r.Context(), &feID, `SELECT id::text FROM field_executives WHERE UPPER(executive_code)=$1 AND is_active=true`, code); err != nil {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Active Field Executive ID not found.")
			return
		}
		fieldExecID = &feID
	}
	err = tx.QueryRowxContext(r.Context(), `
		INSERT INTO businesses (id,owner_user_id,name,slug,description,category_slug,phone_e164,whatsapp_e164,address_text,locality,city,postal_code,location,status,verification_status,time_zone,cover_photo_url,onboarding_source,field_executive_id)
		VALUES ($1,$2,$3,$4,NULLIF($5,''),$6,$7,$8,$9,$10,$11,$12,ST_SetSRID(ST_MakePoint($13,$14),4326)::geography,'pending','pending','Asia/Kolkata',NULLIF($15,''),$16,$17)
		RETURNING id::text
	`, id, userID, req.Name, slug, req.Description, req.CategorySlug, req.PhoneE164, req.WhatsAppE164, req.AddressText, req.Locality, req.City, req.PostalCode, req.Longitude, req.Latitude, req.CoverPhotoURL, onboardingSource, fieldExecID).Scan(&businessID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to save the business listing.")
		return
	}
	if _, err = tx.ExecContext(r.Context(), `INSERT INTO user_roles(user_id,role) VALUES($1,'merchant') ON CONFLICT DO NOTHING`, userID); err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to activate merchant access.")
		return
	}
	if applicationJSON != nil {
		if _, err = tx.ExecContext(r.Context(), `INSERT INTO merchant_application_details (business_id, details) VALUES ($1, $2::jsonb)`, businessID, string(applicationJSON)); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to save application details.")
			return
		}
	}
	if _, err = tx.ExecContext(r.Context(), `INSERT INTO business_members(business_id,user_id,role,status) VALUES($1,$2,'owner','active')`, businessID, userID); err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to link the owner to the new business.")
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
	if _, err = tx.ExecContext(r.Context(), `
		INSERT INTO audit_logs(actor_user_id,action,target_type,target_id,reason,created_at)
		VALUES($1,'create_business','business',$2,'New listing submitted through merchant onboarding',now())
	`, userID, businessID); err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to record listing activity.")
		return
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
