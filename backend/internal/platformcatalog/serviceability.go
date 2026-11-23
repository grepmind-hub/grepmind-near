package platformcatalog

import (
	"database/sql"
	"encoding/json"
	"math"
	"net/http"
	"strings"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
	"github.com/lib/pq"
)

type ServiceLocationItem struct {
	ID                       string    `json:"id"`
	DistrictID               string    `json:"district_id"`
	DistrictName             string    `json:"district_name"`
	Name                     string    `json:"name"`
	Slug                     string    `json:"slug"`
	PinCodes                 []string  `json:"pin_codes"`
	Latitude                 *float64  `json:"latitude"`
	Longitude                *float64  `json:"longitude"`
	ServiceRadiusKm          float64   `json:"service_radius_km"`
	DeliveryEnabled          bool      `json:"delivery_enabled"`
	IsActive                 bool      `json:"is_active"`
	FoodDeliveryEnabled      bool      `json:"food_delivery_enabled"`
	GroceryDeliveryEnabled   bool      `json:"grocery_delivery_enabled"`
	MedicinesDeliveryEnabled bool      `json:"medicines_delivery_enabled"`
	LocalServicesEnabled     bool      `json:"local_services_enabled"`
	TransportEnabled         bool      `json:"transport_enabled"`
	MerchantDiscoveryEnabled bool      `json:"merchant_discovery_enabled"`
	CreatedAt                string    `json:"created_at"`
}

type ServiceLocationInput struct {
	District                 string   `json:"district"`
	Name                     string   `json:"name"`
	PinCodes                 []string `json:"pin_codes"`
	Latitude                 *float64 `json:"latitude"`
	Longitude                *float64 `json:"longitude"`
	ServiceRadiusKm          float64  `json:"service_radius_km"`
	DeliveryEnabled          bool     `json:"delivery_enabled"`
	IsActive                 bool     `json:"is_active"`
	FoodDeliveryEnabled      bool     `json:"food_delivery_enabled"`
	GroceryDeliveryEnabled   bool     `json:"grocery_delivery_enabled"`
	MedicinesDeliveryEnabled bool     `json:"medicines_delivery_enabled"`
	LocalServicesEnabled     bool     `json:"local_services_enabled"`
	TransportEnabled         bool     `json:"transport_enabled"`
	MerchantDiscoveryEnabled bool     `json:"merchant_discovery_enabled"`
}

type ServiceabilityCheckRequest struct {
	PinCode   string   `json:"pin_code"`
	Latitude  *float64 `json:"latitude"`
	Longitude *float64 `json:"longitude"`
}

type ServiceabilityCapabilities struct {
	FoodDelivery      bool `json:"food_delivery"`
	GroceryDelivery   bool `json:"grocery_delivery"`
	MedicinesDelivery bool `json:"medicines_delivery"`
	LocalServices     bool `json:"local_services"`
	Transport         bool `json:"transport"`
	MerchantDiscovery bool `json:"merchant_discovery"`
}

type ServiceabilityCheckResponse struct {
	Serviceable  bool                        `json:"serviceable"`
	Status       string                      `json:"status"` // "active", "coming_soon", "outside_service_area"
	LocalityID   string                      `json:"locality_id,omitempty"`
	LocalityName string                      `json:"locality_name,omitempty"`
	DistrictName string                      `json:"district_name,omitempty"`
	PinCode      string                      `json:"pin_code,omitempty"`
	DistanceKm   *float64                    `json:"distance_km,omitempty"`
	Message      string                      `json:"message"`
	Capabilities *ServiceabilityCapabilities `json:"capabilities,omitempty"`
}

type NotifyInterestRequest struct {
	PinCode           string   `json:"pin_code"`
	LocalityName      string   `json:"locality_name"`
	City              string   `json:"city"`
	NotificationPhone string   `json:"notification_phone"`
	Latitude          *float64 `json:"latitude"`
	Longitude         *float64 `json:"longitude"`
}

// AdminListServiceLocations lists all configured service areas with their PIN codes,
// geographic coordinates, and capability flags.
func (s *Service) AdminListServiceLocations(w http.ResponseWriter, r *http.Request, _ string) {
	query := `
		SELECT 
			l.id::text,
			d.id::text AS district_id,
			d.name AS district_name,
			l.name,
			l.slug,
			COALESCE(to_json(l.pin_codes), '[]'::json) AS pin_codes_json,
			l.latitude,
			l.longitude,
			COALESCE(l.service_radius_km, 10.0) AS service_radius_km,
			l.delivery_enabled,
			l.is_active,
			COALESCE(l.food_delivery_enabled, true) AS food_delivery_enabled,
			COALESCE(l.grocery_delivery_enabled, true) AS grocery_delivery_enabled,
			COALESCE(l.medicines_delivery_enabled, true) AS medicines_delivery_enabled,
			COALESCE(l.local_services_enabled, true) AS local_services_enabled,
			COALESCE(l.transport_enabled, true) AS transport_enabled,
			COALESCE(l.merchant_discovery_enabled, true) AS merchant_discovery_enabled,
			l.created_at::text
		FROM platform_delivery_localities l
		JOIN platform_districts d ON d.id = l.district_id
		ORDER BY d.name, l.name
	`

	rows, err := s.db.QueryContext(r.Context(), query)
	if err != nil {
		responseFailure(w, err)
		return
	}
	defer rows.Close()

	items := make([]ServiceLocationItem, 0)
	for rows.Next() {
		var item ServiceLocationItem
		var pinCodesJSON []byte
		var lat, lng sql.NullFloat64

		if err := rows.Scan(
			&item.ID,
			&item.DistrictID,
			&item.DistrictName,
			&item.Name,
			&item.Slug,
			&pinCodesJSON,
			&lat,
			&lng,
			&item.ServiceRadiusKm,
			&item.DeliveryEnabled,
			&item.IsActive,
			&item.FoodDeliveryEnabled,
			&item.GroceryDeliveryEnabled,
			&item.MedicinesDeliveryEnabled,
			&item.LocalServicesEnabled,
			&item.TransportEnabled,
			&item.MerchantDiscoveryEnabled,
			&item.CreatedAt,
		); err != nil {
			responseFailure(w, err)
			return
		}

		if lat.Valid {
			item.Latitude = &lat.Float64
		}
		if lng.Valid {
			item.Longitude = &lng.Float64
		}

		item.PinCodes = make([]string, 0)
		if len(pinCodesJSON) > 0 {
			_ = json.Unmarshal(pinCodesJSON, &item.PinCodes)
		}

		items = append(items, item)
	}

	if err := rows.Err(); err != nil {
		responseFailure(w, err)
		return
	}

	writeJSON(w, http.StatusOK, apiEnvelope{
		Data: items,
		Meta: map[string]any{
			"count": len(items),
		},
	})
}

// AdminCreateServiceLocation allows administrators to add a new serviceability area.
func (s *Service) AdminCreateServiceLocation(w http.ResponseWriter, r *http.Request, adminID string) {
	var input ServiceLocationInput
	if !decodeJSON(w, r, &input) {
		return
	}

	districtName := strings.TrimSpace(input.District)
	localityName := strings.TrimSpace(input.Name)
	if districtName == "" || localityName == "" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "District and Locality name are required.")
		return
	}

	if input.ServiceRadiusKm <= 0 {
		input.ServiceRadiusKm = 10.0
	}

	cleanedPins := make([]string, 0, len(input.PinCodes))
	for _, p := range input.PinCodes {
		p = strings.TrimSpace(p)
		if p != "" {
			cleanedPins = append(cleanedPins, p)
		}
	}

	slug := strings.ToLower(strings.ReplaceAll(localityName, " ", "-"))

	var createdID string
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var districtID string
		err := tx.GetContext(r.Context(), &districtID, `SELECT id::text FROM platform_districts WHERE lower(name) = lower($1) LIMIT 1`, districtName)
		if err == sql.ErrNoRows {
			districtID = uuid.NewString()
			districtSlug := strings.ToLower(strings.ReplaceAll(districtName, " ", "-"))
			if _, insertErr := tx.ExecContext(r.Context(), `
				INSERT INTO platform_districts (id, state_code, name, slug, is_active)
				VALUES ($1, 'OD', $2, $3, true)
			`, districtID, districtName, districtSlug); insertErr != nil {
				return insertErr
			}
		} else if err != nil {
			return err
		}

		createdID = uuid.NewString()
		_, insertLocErr := tx.ExecContext(r.Context(), `
			INSERT INTO platform_delivery_localities (
				id, district_id, name, slug, pin_codes, latitude, longitude,
				service_radius_km, delivery_enabled, is_active,
				food_delivery_enabled, grocery_delivery_enabled, medicines_delivery_enabled,
				local_services_enabled, transport_enabled, merchant_discovery_enabled
			) VALUES (
				$1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16
			)
		`,
			createdID, districtID, localityName, slug, pq.Array(cleanedPins),
			input.Latitude, input.Longitude, input.ServiceRadiusKm,
			input.DeliveryEnabled, input.IsActive,
			input.FoodDeliveryEnabled, input.GroceryDeliveryEnabled, input.MedicinesDeliveryEnabled,
			input.LocalServicesEnabled, input.TransportEnabled, input.MerchantDiscoveryEnabled,
		)
		if insertLocErr != nil {
			return insertLocErr
		}

		return s.logAudit(r.Context(), tx, adminID, "platform_catalog.service_location.create", "platform_delivery_locality", createdID)
	})

	if err != nil {
		if isUniqueViolation(err) {
			writeError(w, http.StatusConflict, "LOCATION_EXISTS", "A locality with this name or slug already exists in this district.")
			return
		}
		responseFailure(w, err)
		return
	}

	writeJSON(w, http.StatusCreated, apiEnvelope{
		Data: map[string]string{
			"id":      createdID,
			"message": "Service location created successfully.",
		},
	})
}

// AdminUpdateServiceLocation allows administrators to update serviceability rules,
// coordinates, PIN codes, or toggle delivery / active states.
func (s *Service) AdminUpdateServiceLocation(w http.ResponseWriter, r *http.Request, adminID string) {
	id := r.PathValue("id")
	if !validateUUID(id) {
		writeError(w, http.StatusBadRequest, "INVALID_ID", "Service location ID is invalid.")
		return
	}

	var input ServiceLocationInput
	if !decodeJSON(w, r, &input) {
		return
	}

	cleanedPins := make([]string, 0, len(input.PinCodes))
	for _, p := range input.PinCodes {
		p = strings.TrimSpace(p)
		if p != "" {
			cleanedPins = append(cleanedPins, p)
		}
	}

	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		query := `
			UPDATE platform_delivery_localities SET
				delivery_enabled = $2,
				is_active = $3,
				pin_codes = $4,
				latitude = $5,
				longitude = $6,
				service_radius_km = $7,
				food_delivery_enabled = $8,
				grocery_delivery_enabled = $9,
				medicines_delivery_enabled = $10,
				local_services_enabled = $11,
				transport_enabled = $12,
				merchant_discovery_enabled = $13
			WHERE id = $1
		`
		res, execErr := tx.ExecContext(r.Context(), query,
			id, input.DeliveryEnabled, input.IsActive, pq.Array(cleanedPins),
			input.Latitude, input.Longitude, input.ServiceRadiusKm,
			input.FoodDeliveryEnabled, input.GroceryDeliveryEnabled, input.MedicinesDeliveryEnabled,
			input.LocalServicesEnabled, input.TransportEnabled, input.MerchantDiscoveryEnabled,
		)
		if execErr != nil {
			return execErr
		}
		rowsAff, _ := res.RowsAffected()
		if rowsAff == 0 {
			return sql.ErrNoRows
		}

		return s.logAudit(r.Context(), tx, adminID, "platform_catalog.service_location.update", "platform_delivery_locality", id)
	})

	if err != nil {
		if err == sql.ErrNoRows {
			writeError(w, http.StatusNotFound, "NOT_FOUND", "Service location not found.")
			return
		}
		responseFailure(w, err)
		return
	}

	writeJSON(w, http.StatusOK, apiEnvelope{
		Data: map[string]string{
			"id":      id,
			"message": "Service location updated successfully.",
		},
	})
}

// PublicCheckServiceability checks if a given PIN code or GPS coordinates are serviceable,
// returning active capabilities and status.
func (s *Service) PublicCheckServiceability(w http.ResponseWriter, r *http.Request) {
	var req ServiceabilityCheckRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	req.PinCode = strings.TrimSpace(req.PinCode)

	type localityMatch struct {
		ID                       string          `db:"id"`
		Name                     string          `db:"name"`
		DistrictName             string          `db:"district_name"`
		PinCodesJSON             json.RawMessage `db:"pin_codes_json"`
		Latitude                 sql.NullFloat64 `db:"latitude"`
		Longitude                sql.NullFloat64 `db:"longitude"`
		ServiceRadiusKm          float64         `db:"service_radius_km"`
		DeliveryEnabled          bool            `db:"delivery_enabled"`
		IsActive                 bool            `db:"is_active"`
		FoodDeliveryEnabled      bool            `db:"food_delivery_enabled"`
		GroceryDeliveryEnabled   bool            `db:"grocery_delivery_enabled"`
		MedicinesDeliveryEnabled bool            `db:"medicines_delivery_enabled"`
		LocalServicesEnabled     bool            `db:"local_services_enabled"`
		TransportEnabled         bool            `db:"transport_enabled"`
		MerchantDiscoveryEnabled bool            `db:"merchant_discovery_enabled"`
	}

	var match localityMatch
	var found bool

	// 1. Check exact PIN code match
	if req.PinCode != "" {
		err := s.db.GetContext(r.Context(), &match, `
			SELECT 
				l.id::text, l.name, d.name AS district_name,
				COALESCE(to_json(l.pin_codes), '[]'::json) AS pin_codes_json,
				l.latitude, l.longitude,
				COALESCE(l.service_radius_km, 10.0) AS service_radius_km,
				l.delivery_enabled, l.is_active,
				COALESCE(l.food_delivery_enabled, true) AS food_delivery_enabled,
				COALESCE(l.grocery_delivery_enabled, true) AS grocery_delivery_enabled,
				COALESCE(l.medicines_delivery_enabled, true) AS medicines_delivery_enabled,
				COALESCE(l.local_services_enabled, true) AS local_services_enabled,
				COALESCE(l.transport_enabled, true) AS transport_enabled,
				COALESCE(l.merchant_discovery_enabled, true) AS merchant_discovery_enabled
			FROM platform_delivery_localities l
			JOIN platform_districts d ON d.id = l.district_id
			WHERE $1 = ANY(l.pin_codes) AND l.is_active = true
			ORDER BY l.delivery_enabled DESC
			LIMIT 1
		`, req.PinCode)
		if err == nil {
			found = true
		}
	}

	// 2. Fall back to nearest GPS coordinates within radius
	if !found && req.Latitude != nil && req.Longitude != nil {
		var allActive []localityMatch
		err := s.db.SelectContext(r.Context(), &allActive, `
			SELECT 
				l.id::text, l.name, d.name AS district_name,
				COALESCE(to_json(l.pin_codes), '[]'::json) AS pin_codes_json,
				l.latitude, l.longitude,
				COALESCE(l.service_radius_km, 10.0) AS service_radius_km,
				l.delivery_enabled, l.is_active,
				COALESCE(l.food_delivery_enabled, true) AS food_delivery_enabled,
				COALESCE(l.grocery_delivery_enabled, true) AS grocery_delivery_enabled,
				COALESCE(l.medicines_delivery_enabled, true) AS medicines_delivery_enabled,
				COALESCE(l.local_services_enabled, true) AS local_services_enabled,
				COALESCE(l.transport_enabled, true) AS transport_enabled,
				COALESCE(l.merchant_discovery_enabled, true) AS merchant_discovery_enabled
			FROM platform_delivery_localities l
			JOIN platform_districts d ON d.id = l.district_id
			WHERE l.is_active = true AND l.latitude IS NOT NULL AND l.longitude IS NOT NULL
		`)
		if err == nil {
			var minDistance = math.MaxFloat64
			for _, loc := range allActive {
				dist := haversineDistance(*req.Latitude, *req.Longitude, loc.Latitude.Float64, loc.Longitude.Float64)
				if dist <= loc.ServiceRadiusKm && dist < minDistance {
					minDistance = dist
					match = loc
					found = true
				}
			}
		}
	}

	if !found {
		writeJSON(w, http.StatusOK, apiEnvelope{
			Data: ServiceabilityCheckResponse{
				Serviceable: false,
				Status:      "outside_service_area",
				PinCode:     req.PinCode,
				Message:     "We're not in your area just yet. Abashyaka is expanding neighbourhood by neighbourhood.",
			},
		})
		return
	}

	var status = "active"
	var message = "Service is fully active in this area."
	if !match.DeliveryEnabled {
		status = "coming_soon"
		message = "Delivery is coming soon to this area. You can browse local businesses and explore services."
	}

	var distKm *float64
	if req.Latitude != nil && req.Longitude != nil && match.Latitude.Valid && match.Longitude.Valid {
		d := haversineDistance(*req.Latitude, *req.Longitude, match.Latitude.Float64, match.Longitude.Float64)
		distKm = &d
	}

	writeJSON(w, http.StatusOK, apiEnvelope{
		Data: ServiceabilityCheckResponse{
			Serviceable:  true,
			Status:       status,
			LocalityID:   match.ID,
			LocalityName: match.Name,
			DistrictName: match.DistrictName,
			PinCode:      req.PinCode,
			DistanceKm:   distKm,
			Message:      message,
			Capabilities: &ServiceabilityCapabilities{
				FoodDelivery:      match.FoodDeliveryEnabled,
				GroceryDelivery:   match.GroceryDeliveryEnabled,
				MedicinesDelivery: match.MedicinesDeliveryEnabled,
				LocalServices:     match.LocalServicesEnabled,
				Transport:         match.TransportEnabled,
				MerchantDiscovery: match.MerchantDiscoveryEnabled,
			},
		},
	})
}

// PublicNotifyInterest records customer interest when outside the service area.
func (s *Service) PublicNotifyInterest(w http.ResponseWriter, r *http.Request) {
	var req NotifyInterestRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	var id string
	err := s.db.QueryRowxContext(r.Context(), `
		INSERT INTO location_interest_leads (pin_code, locality_name, phone, latitude, longitude)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id::text
	`, req.PinCode, req.LocalityName, req.NotificationPhone, req.Latitude, req.Longitude).Scan(&id)
	if err != nil {
		responseFailure(w, err)
		return
	}

	// Also record in unserved_location_demand for admin graphical demand analytics
	city := req.City
	if strings.TrimSpace(city) == "" {
		city = "Odisha"
	}
	_, _ = s.db.ExecContext(r.Context(), `
		INSERT INTO unserved_location_demand (query, locality, city, latitude, longitude, notification_phone)
		VALUES ($1, $2, $3, $4, $5, $6)
	`, req.PinCode, req.LocalityName, city, req.Latitude, req.Longitude, req.NotificationPhone)

	writeJSON(w, http.StatusCreated, apiEnvelope{
		Data: map[string]string{
			"id":      id,
			"status":  "recorded",
			"message": "Thank you! We will notify you as soon as Abashyaka launches in your area.",
		},
	})
}

func haversineDistance(lat1, lon1, lat2, lon2 float64) float64 {
	const earthRadiusKm = 6371.0
	dLat := (lat2 - lat1) * (math.Pi / 180.0)
	dLon := (lon2 - lon1) * (math.Pi / 180.0)

	rLat1 := lat1 * (math.Pi / 180.0)
	rLat2 := lat2 * (math.Pi / 180.0)

	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Sin(dLon/2)*math.Sin(dLon/2)*math.Cos(rLat1)*math.Cos(rLat2)
	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))

	return earthRadiusKm * c
}
