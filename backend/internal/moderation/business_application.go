package moderation

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"

	"github.com/google/uuid"
)

// BusinessApplication returns the listing and its private review fields.
func (s *Service) BusinessApplication(w http.ResponseWriter, r *http.Request) {
	id, err := uuid.Parse(r.PathValue("id"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Invalid business ID.")
		return
	}

	var application json.RawMessage
	err = s.db.QueryRowxContext(r.Context(), `
		SELECT jsonb_build_object(
			'id', b.id, 'name', b.name, 'category_slug', b.category_slug,
			'category_name', c.name, 'description', b.description,
			'status', b.status, 'verification_status', b.verification_status,
			'created_at', b.created_at, 'owner_name', u.display_name,
			'owner_phone', u.phone_e164, 'phone_e164', b.phone_e164,
			'whatsapp_e164', b.whatsapp_e164, 'address_text', b.address_text,
			'locality', b.locality, 'city', b.city, 'postal_code', b.postal_code,
			'latitude', ST_Y(b.location::geometry), 'longitude', ST_X(b.location::geometry),
			'time_zone', b.time_zone, 'application', a.details,
			'has_storefront_photo', EXISTS (
				SELECT 1 FROM media_uploads m
				WHERE m.user_id = b.owner_user_id AND m.purpose = 'storefront'
				  AND b.cover_photo_url = '/media/' || m.object_key
			),
			'hours', COALESCE((
				SELECT jsonb_agg(jsonb_build_object(
					'weekday', h.weekday, 'opens_at', left(h.opens_at::text, 5),
					'closes_at', left(h.closes_at::text, 5), 'is_closed', h.is_closed
				) ORDER BY h.weekday) FROM business_hours h WHERE h.business_id = b.id
			), '[]'::jsonb)
		)
		FROM businesses b
		JOIN users u ON u.id = b.owner_user_id
		JOIN categories c ON c.slug = b.category_slug
		LEFT JOIN merchant_application_details a ON a.business_id = b.id
		WHERE b.id = $1
	`, id).Scan(&application)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Business application not found.")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load the business application.")
		return
	}
	w.Header().Set("Cache-Control", "private, no-store")
	writeJSON(w, http.StatusOK, envelope{"data": application, "meta": map[string]string{"request_id": "admin-business-application"}})
}
