package main

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
	"grepmind-near/backend/internal/auth"
	"grepmind-near/backend/internal/notifications"
	"grepmind-near/backend/pkg/database"
)

type rescheduleRequest struct {
	SlotID string `json:"slot_id"`
}

// merchantRescheduleRequest atomically moves a booking reservation to a new
// available slot and leaves the request awaiting customer confirmation.
func merchantRescheduleRequest(hub *notifications.Hub) authedHandler {
	return func(_ *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
		businessID := r.PathValue("bizId")
		requestID := r.PathValue("id")
		if _, err := uuid.Parse(businessID); err != nil {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "A valid business ID is required.")
			return
		}
		if _, err := uuid.Parse(requestID); err != nil {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "A valid request ID is required.")
			return
		}
		var body rescheduleRequest
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8<<10)).Decode(&body); err != nil {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "A valid replacement slot is required.")
			return
		}
		slotID, err := uuid.Parse(body.SlotID)
		if err != nil {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "A valid replacement slot is required.")
			return
		}

		tx, err := db.BeginTxx(r.Context(), nil)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to reschedule this appointment.")
			return
		}
		defer tx.Rollback()

		var timeZone string
		err = tx.GetContext(r.Context(), &timeZone, `
			SELECT b.time_zone
			FROM businesses b
			WHERE b.id=$1 AND b.status!='deleted'
			  AND (b.owner_user_id=$2 OR EXISTS (
				SELECT 1 FROM business_members bm
				WHERE bm.business_id=b.id AND bm.user_id=$2 AND bm.status='active'
			  ))
			FOR UPDATE OF b
		`, businessID, userID)
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, "NOT_FOUND", "Business not found.")
			return
		}
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to authorize appointment rescheduling.")
			return
		}
		if _, err := time.LoadLocation(timeZone); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Business time zone is invalid.")
			return
		}

		var customerID, currentStatus string
		var currentSlotID *string
		err = tx.QueryRowxContext(r.Context(), `
			SELECT customer_user_id,status,slot_id
			FROM service_requests
			WHERE id=$1 AND business_id=$2
			FOR UPDATE
		`, requestID, businessID).Scan(&customerID, &currentStatus, &currentSlotID)
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, "NOT_FOUND", "Service request not found.")
			return
		}
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load service request.")
			return
		}
		if currentStatus != "accepted" && currentStatus != "rescheduled" {
			writeError(w, http.StatusConflict, "INVALID_STATE", "Only accepted or previously rescheduled appointments can be moved.")
			return
		}
		if currentSlotID != nil && *currentSlotID == slotID.String() {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Choose a different appointment slot.")
			return
		}

		type lockedSlot struct {
			ID       string    `db:"id"`
			StartsAt time.Time `db:"starts_at"`
			EndsAt   time.Time `db:"ends_at"`
			Capacity int       `db:"capacity"`
			Booked   int       `db:"booked_count"`
			Status   string    `db:"status"`
		}
		lockedSlots := make(map[string]lockedSlot, 2)
		var slotRows *sqlx.Rows
		if currentSlotID == nil {
			slotRows, err = tx.QueryxContext(r.Context(), `
				SELECT id,starts_at,ends_at,capacity,booked_count,status
				FROM availability_slots WHERE id=$1 AND business_id=$2 FOR UPDATE
			`, slotID.String(), businessID)
		} else {
			// Every reschedule locks both slot rows in UUID order. That avoids a
			// deadlock when two requests are concurrently moved in opposite
			// directions between the same pair of slots.
			slotRows, err = tx.QueryxContext(r.Context(), `
				SELECT id,starts_at,ends_at,capacity,booked_count,status
				FROM availability_slots
				WHERE business_id=$1 AND id IN ($2,$3)
				ORDER BY id
				FOR UPDATE
			`, businessID, slotID.String(), *currentSlotID)
		}
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to lock appointment slots.")
			return
		}
		for slotRows.Next() {
			var row lockedSlot
			if err := slotRows.StructScan(&row); err != nil {
				_ = slotRows.Close()
				writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load appointment slots.")
				return
			}
			lockedSlots[row.ID] = row
		}
		if err := slotRows.Err(); err != nil {
			_ = slotRows.Close()
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load appointment slots.")
			return
		}
		if err := slotRows.Close(); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to release appointment slot locks.")
			return
		}
		replacement, exists := lockedSlots[slotID.String()]
		if !exists {
			writeError(w, http.StatusNotFound, "NOT_FOUND", "Replacement appointment slot not found.")
			return
		}
		if currentSlotID != nil {
			if _, exists := lockedSlots[*currentSlotID]; !exists {
				writeError(w, http.StatusConflict, "INVALID_STATE", "The current appointment reservation is inconsistent; refresh before rescheduling.")
				return
			}
		}
		startsAt, endsAt := replacement.StartsAt, replacement.EndsAt
		if replacement.Status != "open" || replacement.Booked >= replacement.Capacity || !startsAt.After(time.Now().UTC()) || !endsAt.After(startsAt) {
			writeError(w, http.StatusConflict, "SLOT_UNAVAILABLE", "The replacement appointment slot is no longer available.")
			return
		}
		var closedDate bool
		if err := tx.GetContext(r.Context(), &closedDate, `
			SELECT EXISTS (
				SELECT 1 FROM business_availability_exceptions e
				WHERE e.business_id=$1 AND e.local_date=($2 AT TIME ZONE $3)::date AND e.is_closed=true
			)
		`, businessID, startsAt, timeZone); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to validate replacement appointment date.")
			return
		}
		if closedDate {
			writeError(w, http.StatusConflict, "SLOT_UNAVAILABLE", "The replacement appointment date is closed.")
			return
		}

		result, err := tx.ExecContext(r.Context(), `
			UPDATE availability_slots
			SET booked_count=booked_count+1,updated_at=now()
			WHERE id=$1 AND business_id=$2 AND status='open' AND booked_count<capacity
		`, slotID.String(), businessID)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to reserve replacement appointment slot.")
			return
		}
		if affected, _ := result.RowsAffected(); affected != 1 {
			writeError(w, http.StatusConflict, "SLOT_UNAVAILABLE", "The replacement appointment slot is no longer available.")
			return
		}
		if currentSlotID != nil {
			result, err = tx.ExecContext(r.Context(), `
				UPDATE availability_slots SET booked_count=booked_count-1,updated_at=now()
				WHERE id=$1 AND business_id=$2 AND booked_count>0
			`, *currentSlotID, businessID)
			if err != nil {
				writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to release the previous appointment slot.")
				return
			}
			if affected, _ := result.RowsAffected(); affected != 1 {
				writeError(w, http.StatusConflict, "INVALID_STATE", "The current appointment reservation is inconsistent; refresh before rescheduling.")
				return
			}
		}
		if _, err := tx.ExecContext(r.Context(), `
			UPDATE service_requests SET slot_id=$1,requested_for=$2,status='rescheduled',updated_at=now()
			WHERE id=$3 AND business_id=$4
		`, slotID.String(), startsAt, requestID, businessID); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to update appointment request.")
			return
		}
		if _, err := tx.ExecContext(r.Context(), `
			INSERT INTO service_request_events(request_id,status,actor_user_id,created_at)
			VALUES($1,'rescheduled',$2,now())
		`, requestID, userID); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to record appointment rescheduling.")
			return
		}
		if err := tx.Commit(); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to save appointment rescheduling.")
			return
		}

		if hub != nil {
			hub.Publish(r.Context(), notifications.Event{
				Type: "service_request.rescheduled", BusinessID: businessID, RequestID: requestID, UserID: customerID,
				Title:   "A new appointment time was proposed",
				Body:    "Your service provider proposed a different appointment time. Review it in your request.",
				Payload: map[string]interface{}{"request_id": requestID, "business_id": businessID, "slot_id": slotID.String(), "requested_for": startsAt, "status": "rescheduled"},
			})
		}
		writeJSON(w, http.StatusOK, envelope{"data": map[string]interface{}{"id": requestID, "status": "rescheduled", "slot_id": slotID.String(), "requested_for": startsAt}})
	}
}

// confirmServiceRequestReschedule lets only the customer who owns a request
// accept the merchant's proposed replacement time.
func confirmServiceRequestReschedule(hub *notifications.Hub) authedHandler {
	return func(_ *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
		requestID := r.PathValue("id")
		if _, err := uuid.Parse(requestID); err != nil {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "A valid request ID is required.")
			return
		}
		tx, err := db.BeginTxx(r.Context(), nil)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to confirm the proposed appointment time.")
			return
		}
		defer tx.Rollback()

		var ownerID, businessID, status string
		err = tx.QueryRowxContext(r.Context(), `
			SELECT customer_user_id,business_id,status FROM service_requests WHERE id=$1 FOR UPDATE
		`, requestID).Scan(&ownerID, &businessID, &status)
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, "NOT_FOUND", "Service request not found.")
			return
		}
		if err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load service request.")
			return
		}
		if ownerID != userID {
			writeError(w, http.StatusForbidden, "FORBIDDEN", "You do not have access to this service request.")
			return
		}
		if status != "rescheduled" {
			writeError(w, http.StatusConflict, "INVALID_STATE", "There is no proposed appointment time to confirm.")
			return
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE service_requests SET status='accepted',updated_at=now() WHERE id=$1`, requestID); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to confirm the proposed appointment time.")
			return
		}
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO service_request_events(request_id,status,actor_user_id,created_at) VALUES($1,'accepted',$2,now())`, requestID, userID); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to record appointment confirmation.")
			return
		}
		if err := tx.Commit(); err != nil {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to confirm the proposed appointment time.")
			return
		}
		if hub != nil {
			hub.Publish(r.Context(), notifications.Event{
				Type: "service_request.reschedule_confirmed", BusinessID: businessID, RequestID: requestID,
				Title:   "Customer confirmed the new appointment time",
				Body:    "The customer accepted the proposed appointment time.",
				Payload: map[string]interface{}{"request_id": requestID, "business_id": businessID, "status": "accepted"},
			})
		}
		writeJSON(w, http.StatusOK, envelope{"data": map[string]string{"id": requestID, "status": "accepted"}})
	}
}
