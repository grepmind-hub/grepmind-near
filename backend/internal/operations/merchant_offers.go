package operations

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"

	"grepmind-near/backend/internal/discovery"
)

type offerInput struct {
	Title           *string    `json:"title"`
	Description     *string    `json:"description"`
	StartsAt        *time.Time `json:"starts_at"`
	EndsAt          *time.Time `json:"ends_at"`
	Terms           *string    `json:"terms"`
	DiscountPercent *int       `json:"discount_percent"`
	ImageURL        *string    `json:"image_url"`
}

func (s *Service) ListMerchantOffers(w http.ResponseWriter, r *http.Request, userID string) {
	businessID := r.PathValue("id")
	if _, err := s.authorizeOfferManager(r, businessID, userID); err != nil {
		writeError(w, http.StatusForbidden, "FORBIDDEN", "You do not have access to manage offers for this business.")
		return
	}
	rows, err := s.db.QueryxContext(r.Context(), `
		SELECT id,business_id,title,COALESCE(description,''),starts_at,ends_at,status,
		       COALESCE(image_url,''),COALESCE(terms,''),discount_percent
		FROM offers WHERE business_id=$1 ORDER BY created_at DESC`, businessID)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load merchant offers.")
		return
	}
	defer rows.Close()
	items := make([]discovery.Offer, 0)
	for rows.Next() {
		var item discovery.Offer
		if err := rows.Scan(&item.ID, &item.BusinessID, &item.Title, &item.Description, &item.StartsAt, &item.EndsAt, &item.Status, &item.ImageURL, &item.Terms, &item.DiscountPct); err != nil {
			writeError(w, 500, "INTERNAL_ERROR", "Unable to read merchant offers.")
			return
		}
		items = append(items, item)
	}
	writeJSON(w, 200, map[string]interface{}{"data": items, "meta": map[string]string{"request_id": "merchant-offers"}})
}

func (s *Service) CreateMerchantOffer(w http.ResponseWriter, r *http.Request, userID string) {
	businessID := r.PathValue("id")
	if _, err := s.authorizeOfferManager(r, businessID, userID); err != nil {
		writeError(w, http.StatusForbidden, "FORBIDDEN", "You do not have access to manage offers for this business.")
		return
	}
	var input offerInput
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16<<10)).Decode(&input); err != nil || input.Title == nil || input.StartsAt == nil || input.EndsAt == nil {
		writeError(w, 400, "VALIDATION_ERROR", "Offer title, start and end times are required.")
		return
	}
	if err := validateOffer(input, true); err != nil {
		writeError(w, 400, "VALIDATION_ERROR", err.Error())
		return
	}
	var item discovery.Offer
	err := s.db.QueryRowxContext(r.Context(), `
		INSERT INTO offers(business_id,title,description,starts_at,ends_at,status,image_url,terms,discount_percent)
		VALUES($1,$2,$3,$4,$5,'pending',$6,$7,$8)
		RETURNING id,business_id,title,COALESCE(description,''),starts_at,ends_at,status,COALESCE(image_url,''),COALESCE(terms,''),discount_percent`,
		businessID, strings.TrimSpace(*input.Title), input.Description, *input.StartsAt, *input.EndsAt, input.ImageURL, input.Terms, input.DiscountPercent).
		Scan(&item.ID, &item.BusinessID, &item.Title, &item.Description, &item.StartsAt, &item.EndsAt, &item.Status, &item.ImageURL, &item.Terms, &item.DiscountPct)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to create offer.")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]interface{}{"data": item, "meta": map[string]string{"request_id": "merchant-create-offer"}})
}

func (s *Service) UpdateMerchantOffer(w http.ResponseWriter, r *http.Request, userID string) {
	offerID := r.PathValue("id")
	var businessID string
	if err := s.db.QueryRowxContext(r.Context(), `SELECT business_id FROM offers WHERE id=$1`, offerID).Scan(&businessID); err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Offer not found.")
		return
	}
	if _, err := s.authorizeOfferManager(r, businessID, userID); err != nil {
		writeError(w, http.StatusForbidden, "FORBIDDEN", "You do not have access to manage offers for this business.")
		return
	}
	var input offerInput
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16<<10)).Decode(&input); err != nil {
		writeError(w, 400, "VALIDATION_ERROR", "Invalid offer payload.")
		return
	}
	if err := validateOffer(input, false); err != nil {
		writeError(w, 400, "VALIDATION_ERROR", err.Error())
		return
	}
	sets := make([]string, 0, 7)
	args := []interface{}{offerID, businessID}
	appendField := func(column string, value interface{}) {
		sets = append(sets, fmt.Sprintf("%s=$%d", column, len(args)+1))
		args = append(args, value)
	}
	if input.Title != nil {
		appendField("title", strings.TrimSpace(*input.Title))
	}
	if input.Description != nil {
		appendField("description", *input.Description)
	}
	if input.StartsAt != nil {
		appendField("starts_at", *input.StartsAt)
	}
	if input.EndsAt != nil {
		appendField("ends_at", *input.EndsAt)
	}
	if input.Terms != nil {
		appendField("terms", *input.Terms)
	}
	if input.DiscountPercent != nil {
		appendField("discount_percent", *input.DiscountPercent)
	}
	if input.ImageURL != nil {
		appendField("image_url", *input.ImageURL)
	}
	if len(sets) == 0 {
		writeError(w, 400, "VALIDATION_ERROR", "No offer fields to update.")
		return
	}
	result, err := s.db.ExecContext(r.Context(), `UPDATE offers SET `+strings.Join(sets, ",")+` WHERE id=$1 AND business_id=$2`, args...)
	if err != nil {
		writeError(w, 400, "VALIDATION_ERROR", "Offer update violates a business rule.")
		return
	}
	if count, _ := result.RowsAffected(); count == 0 {
		writeError(w, 404, "NOT_FOUND", "Offer not found.")
		return
	}
	var item discovery.Offer
	if err := s.db.QueryRowxContext(r.Context(), `
		SELECT id,business_id,title,COALESCE(description,''),starts_at,ends_at,status,
		       COALESCE(image_url,''),COALESCE(terms,''),discount_percent
		FROM offers WHERE id=$1 AND business_id=$2`, offerID, businessID).
		Scan(&item.ID, &item.BusinessID, &item.Title, &item.Description, &item.StartsAt, &item.EndsAt, &item.Status, &item.ImageURL, &item.Terms, &item.DiscountPct); err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Offer was updated but could not be loaded.")
		return
	}
	writeJSON(w, 200, map[string]interface{}{"data": item, "meta": map[string]string{"request_id": "merchant-update-offer"}})
}

func (s *Service) DeleteMerchantOffer(w http.ResponseWriter, r *http.Request, userID string) {
	offerID := r.PathValue("id")
	var businessID string
	if err := s.db.QueryRowxContext(r.Context(), `SELECT business_id FROM offers WHERE id=$1`, offerID).Scan(&businessID); err != nil {
		writeError(w, 404, "NOT_FOUND", "Offer not found.")
		return
	}
	if _, err := s.authorizeOfferManager(r, businessID, userID); err != nil {
		writeError(w, 403, "FORBIDDEN", "You do not have access to manage offers for this business.")
		return
	}
	if _, err := s.db.ExecContext(r.Context(), `DELETE FROM offers WHERE id=$1 AND business_id=$2`, offerID, businessID); err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to delete offer.")
		return
	}
	writeJSON(w, 200, map[string]interface{}{"data": map[string]string{"status": "deleted"}, "meta": map[string]string{"request_id": "merchant-delete-offer"}})
}

func (s *Service) authorizeOfferManager(r *http.Request, businessID, userID string) (string, error) {
	var role string
	err := s.db.QueryRowxContext(r.Context(), `SELECT role FROM business_members WHERE business_id=$1 AND user_id=$2 AND status='active'`, businessID, userID).Scan(&role)
	if err != nil {
		err = s.db.QueryRowxContext(r.Context(), `SELECT 'owner' FROM businesses WHERE id=$1 AND owner_user_id=$2 AND status!='deleted'`, businessID, userID).Scan(&role)
	}
	if err != nil || (role != "owner" && role != "manager") {
		return "", errors.New("not authorized")
	}
	return role, nil
}

func validateOffer(input offerInput, creating bool) error {
	if input.Title != nil && (len(strings.TrimSpace(*input.Title)) < 2 || len(strings.TrimSpace(*input.Title)) > 100) {
		return errors.New("Offer title must be between 2 and 100 characters.")
	}
	if input.Description != nil && len(*input.Description) > 2000 {
		return errors.New("Offer description is too long.")
	}
	if input.Terms != nil && len(*input.Terms) > 1000 {
		return errors.New("Offer terms are too long.")
	}
	if input.DiscountPercent != nil && (*input.DiscountPercent < 0 || *input.DiscountPercent > 100) {
		return errors.New("Discount must be between 0 and 100 percent.")
	}
	if input.ImageURL != nil && *input.ImageURL != "" {
		parsed, err := url.ParseRequestURI(*input.ImageURL)
		if err != nil || parsed.Scheme != "https" || parsed.Host == "" {
			return errors.New("Offer image URL must use HTTPS.")
		}
	}
	if creating && (input.Title == nil || input.StartsAt == nil || input.EndsAt == nil) {
		return errors.New("Offer title, start and end times are required.")
	}
	if input.StartsAt != nil && input.EndsAt != nil && !input.EndsAt.After(*input.StartsAt) {
		return errors.New("Offer end must be after its start.")
	}
	return nil
}
