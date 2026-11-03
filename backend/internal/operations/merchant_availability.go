package operations

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
)

var localClockPattern = regexp.MustCompile(`^([01][0-9]|2[0-3]):([0-5][0-9])$`)

type merchantBusiness struct {
	ID       string `db:"id"`
	TimeZone string `db:"time_zone"`
}

type slotMutation struct {
	Date     string `json:"date"`
	StartsAt string `json:"starts_at"`
	EndsAt   string `json:"ends_at"`
	Capacity int    `json:"capacity"`
	Status   string `json:"status"`
}

type exceptionMutation struct {
	Date     string  `json:"date"`
	IsClosed bool    `json:"is_closed"`
	OpensAt  *string `json:"opens_at"`
	ClosesAt *string `json:"closes_at"`
	Note     string  `json:"note"`
}

type availabilityException struct {
	ID       string  `json:"id" db:"id"`
	Date     string  `json:"date" db:"local_date"`
	IsClosed bool    `json:"is_closed" db:"is_closed"`
	OpensAt  *string `json:"opens_at" db:"opens_at"`
	ClosesAt *string `json:"closes_at" db:"closes_at"`
	Note     string  `json:"note" db:"note"`
}

// MerchantAvailability returns time-zone aware slot inventory and date exceptions.
func (s *Service) MerchantAvailability(w http.ResponseWriter, r *http.Request, userID string) {
	businessID := r.PathValue("id")
	from, to, ok := localDateRange(r, w)
	if !ok {
		return
	}
	var business merchantBusiness
	if !s.loadAuthorizedBusiness(r, businessID, userID, &business) {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Business not found.")
		return
	}
	loc, err := time.LoadLocation(business.TimeZone)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Business time zone is invalid.")
		return
	}
	start := time.Date(from.Year(), from.Month(), from.Day(), 0, 0, 0, 0, loc)
	end := time.Date(to.Year(), to.Month(), to.Day(), 0, 0, 0, 0, loc).AddDate(0, 0, 1)
	rows, err := s.db.QueryxContext(r.Context(), `
		SELECT id, starts_at, ends_at, capacity, booked_count, status
		FROM availability_slots
		WHERE business_id=$1 AND starts_at >= $2 AND starts_at < $3
		ORDER BY starts_at`, businessID, start.UTC(), end.UTC())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load appointment slots.")
		return
	}
	slots := make([]map[string]interface{}, 0)
	for rows.Next() {
		var id, status string
		var starts, ends time.Time
		var capacity, booked int
		if err := rows.Scan(&id, &starts, &ends, &capacity, &booked, &status); err != nil {
			rows.Close()
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to read appointment slots.")
			return
		}
		slots = append(slots, map[string]interface{}{
			"id": id, "starts_at": starts, "ends_at": ends, "local_date": starts.In(loc).Format("2006-01-02"),
			"local_starts_at": starts.In(loc).Format("15:04"), "local_ends_at": ends.In(loc).Format("15:04"),
			"capacity": capacity, "booked_count": booked, "remaining_capacity": capacity - booked, "status": status,
		})
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to read appointment slots.")
		return
	}
	rows.Close()
	exceptions := make([]availabilityException, 0)
	if err := s.db.SelectContext(r.Context(), &exceptions, `
		SELECT id, local_date::text, is_closed, opens_at::text, closes_at::text, note
		FROM business_availability_exceptions WHERE business_id=$1 AND local_date BETWEEN $2 AND $3
		ORDER BY local_date`, businessID, from, to); err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load date exceptions.")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"data": map[string]interface{}{"time_zone": business.TimeZone, "slots": slots, "exceptions": exceptions},
		"meta": map[string]interface{}{"count": len(slots)},
	})
}

// CreateAvailabilitySlot persists one merchant-defined interval in the business's local time zone.
func (s *Service) CreateAvailabilitySlot(w http.ResponseWriter, r *http.Request, userID string) {
	var req slotMutation
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8<<10)).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Invalid slot payload.")
		return
	}
	if req.Capacity < 1 || req.Capacity > 20 || req.Status != "" && req.Status != "open" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Capacity must be 1 through 20 and new slots must be open.")
		return
	}
	var id string
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		business, err := lockAuthorizedBusiness(tx, r, r.PathValue("id"), userID)
		if err != nil {
			return err
		}
		starts, ends, localDate, err := validateSlotWindow(req, business.TimeZone)
		if err != nil {
			return err
		}
		if err := validateOpenDate(tx, r, business.ID, localDate, req.StartsAt, req.EndsAt); err != nil {
			return err
		}
		if starts.Before(time.Now().UTC().Add(time.Minute)) {
			return errors.New("slot must start at least one minute in the future")
		}
		var conflict bool
		if err := tx.GetContext(r.Context(), &conflict, `SELECT EXISTS(SELECT 1 FROM availability_slots WHERE business_id=$1 AND status='open' AND starts_at < $3 AND ends_at > $2)`, business.ID, starts, ends); err != nil {
			return err
		}
		if conflict {
			return errors.New("slot overlaps an existing open appointment")
		}
		id = uuid.NewString()
		_, err = tx.ExecContext(r.Context(), `INSERT INTO availability_slots(id,business_id,starts_at,ends_at,capacity,booked_count,status,updated_at) VALUES($1,$2,$3,$4,$5,0,'open',now())`, id, business.ID, starts, ends, req.Capacity)
		return err
	})
	if err != nil {
		writeAvailabilityMutationError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]interface{}{"data": map[string]string{"id": id, "status": "open"}})
}

// UpdateAvailabilitySlot edits or closes only future, unbooked slots belonging to the requested business.
func (s *Service) UpdateAvailabilitySlot(w http.ResponseWriter, r *http.Request, userID string) {
	var req slotMutation
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8<<10)).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Invalid slot payload.")
		return
	}
	if req.Status != "" && req.Status != "open" && req.Status != "closed" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Slot status must be open or closed.")
		return
	}
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		business, err := lockAuthorizedBusiness(tx, r, r.PathValue("id"), userID)
		if err != nil {
			return err
		}
		var startsAt, endsAt time.Time
		var capacity, booked int
		var status string
		if err := tx.QueryRowxContext(r.Context(), `SELECT starts_at,ends_at,capacity,booked_count,status FROM availability_slots WHERE id=$1 AND business_id=$2 FOR UPDATE`, r.PathValue("slotId"), business.ID).Scan(&startsAt, &endsAt, &capacity, &booked, &status); err != nil {
			return errSlotNotFound
		}
		if startsAt.Before(time.Now().UTC()) {
			return errors.New("past slots cannot be changed")
		}
		if booked != 0 {
			return errors.New("booked slots cannot be edited or closed")
		}
		if req.Capacity != 0 {
			if req.Capacity < 1 || req.Capacity > 20 {
				return errors.New("capacity must be 1 through 20")
			}
			capacity = req.Capacity
		}
		if req.Date != "" || req.StartsAt != "" || req.EndsAt != "" {
			if req.Date == "" || req.StartsAt == "" || req.EndsAt == "" {
				return errors.New("date, start time and end time must be supplied together")
			}
			newStart, newEnd, localDate, err := validateSlotWindow(req, business.TimeZone)
			if err != nil {
				return err
			}
			if newStart.Before(time.Now().UTC().Add(time.Minute)) {
				return errors.New("slot must start at least one minute in the future")
			}
			if err := validateOpenDate(tx, r, business.ID, localDate, req.StartsAt, req.EndsAt); err != nil {
				return err
			}
			startsAt, endsAt = newStart, newEnd
		}
		newStatus := status
		if req.Status != "" {
			newStatus = req.Status
		}
		if newStatus == "open" {
			var conflict bool
			if err := tx.GetContext(r.Context(), &conflict, `SELECT EXISTS(SELECT 1 FROM availability_slots WHERE business_id=$1 AND id<>$2 AND status='open' AND starts_at < $4 AND ends_at > $3)`, business.ID, r.PathValue("slotId"), startsAt, endsAt); err != nil {
				return err
			}
			if conflict {
				return errors.New("slot overlaps an existing open appointment")
			}
			local := startsAt.In(mustLoadLocation(business.TimeZone))
			if err := validateOpenDate(tx, r, business.ID, local, local.Format("15:04"), endsAt.In(local.Location()).Format("15:04")); err != nil {
				return err
			}
		}
		_, err = tx.ExecContext(r.Context(), `UPDATE availability_slots SET starts_at=$1,ends_at=$2,capacity=$3,status=$4,updated_at=now() WHERE id=$5 AND business_id=$6`, startsAt, endsAt, capacity, newStatus, r.PathValue("slotId"), business.ID)
		return err
	})
	if err != nil {
		writeAvailabilityMutationError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

// UpsertAvailabilityException closes or customizes one local calendar date.
func (s *Service) UpsertAvailabilityException(w http.ResponseWriter, r *http.Request, userID string) {
	var req exceptionMutation
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8<<10)).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Invalid date exception payload.")
		return
	}
	date, err := time.Parse("2006-01-02", req.Date)
	if err != nil || len(req.Note) > 240 {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "A valid date and note up to 240 characters are required.")
		return
	}
	if req.IsClosed {
		req.OpensAt, req.ClosesAt = nil, nil
	} else if (req.OpensAt == nil) != (req.ClosesAt == nil) || req.OpensAt != nil && (!localClockPattern.MatchString(*req.OpensAt) || !localClockPattern.MatchString(*req.ClosesAt) || *req.OpensAt >= *req.ClosesAt) {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Custom hours must be a valid same-day start and end time.")
		return
	}
	err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		business, err := lockAuthorizedBusiness(tx, r, r.PathValue("id"), userID)
		if err != nil {
			return err
		}
		loc, err := time.LoadLocation(business.TimeZone)
		if err != nil {
			return err
		}
		localDate := time.Date(date.Year(), date.Month(), date.Day(), 0, 0, 0, 0, loc)
		dayStart := localDate.UTC()
		dayEnd := localDate.AddDate(0, 0, 1).UTC()
		nowLocal := time.Now().In(loc)
		today := time.Date(nowLocal.Year(), nowLocal.Month(), nowLocal.Day(), 0, 0, 0, 0, loc)
		if localDate.Before(today) {
			return errors.New("past dates cannot be changed")
		}
		if req.IsClosed {
			var booked bool
			if err := tx.GetContext(r.Context(), &booked, `SELECT EXISTS(SELECT 1 FROM availability_slots WHERE business_id=$1 AND starts_at < $3 AND ends_at > $2 AND booked_count > 0 AND status='open')`, business.ID, dayStart, dayEnd); err != nil {
				return err
			}
			if booked {
				return errors.New("date has confirmed appointments and cannot be closed")
			}
			if _, err := tx.ExecContext(r.Context(), `UPDATE availability_slots SET status='closed',updated_at=now() WHERE business_id=$1 AND starts_at < $3 AND ends_at > $2 AND status='open'`, business.ID, dayStart, dayEnd); err != nil {
				return err
			}
		}
		_, err = tx.ExecContext(r.Context(), `INSERT INTO business_availability_exceptions(business_id,local_date,is_closed,opens_at,closes_at,note,updated_at) VALUES($1,$2,$3,$4,$5,$6,now()) ON CONFLICT(business_id,local_date) DO UPDATE SET is_closed=EXCLUDED.is_closed,opens_at=EXCLUDED.opens_at,closes_at=EXCLUDED.closes_at,note=EXCLUDED.note,updated_at=now()`, business.ID, date.Format("2006-01-02"), req.IsClosed, req.OpensAt, req.ClosesAt, strings.TrimSpace(req.Note))
		return err
	})
	if err != nil {
		writeAvailabilityMutationError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

var errSlotNotFound = errors.New("slot not found")

func localDateRange(r *http.Request, w http.ResponseWriter) (time.Time, time.Time, bool) {
	from, errFrom := time.Parse("2006-01-02", r.URL.Query().Get("from"))
	to, errTo := time.Parse("2006-01-02", r.URL.Query().Get("to"))
	if errFrom != nil || errTo != nil || to.Before(from) || to.Sub(from) > 62*24*time.Hour {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Provide a date range no longer than 62 days.")
		return time.Time{}, time.Time{}, false
	}
	return from, to, true
}

func (s *Service) loadAuthorizedBusiness(r *http.Request, businessID, userID string, business *merchantBusiness) bool {
	err := s.db.GetContext(r.Context(), business, `SELECT b.id,b.time_zone FROM businesses b WHERE b.id=$1 AND b.status!='deleted' AND (b.owner_user_id=$2 OR EXISTS(SELECT 1 FROM business_members bm WHERE bm.business_id=b.id AND bm.user_id=$2 AND bm.status='active'))`, businessID, userID)
	return err == nil
}

func lockAuthorizedBusiness(tx *sqlx.Tx, r *http.Request, businessID, userID string) (merchantBusiness, error) {
	var business merchantBusiness
	err := tx.GetContext(r.Context(), &business, `SELECT b.id,b.time_zone FROM businesses b WHERE b.id=$1 AND b.status!='deleted' AND (b.owner_user_id=$2 OR EXISTS(SELECT 1 FROM business_members bm WHERE bm.business_id=b.id AND bm.user_id=$2 AND bm.status='active')) FOR UPDATE`, businessID, userID)
	if err != nil {
		return merchantBusiness{}, errSlotNotFound
	}
	if _, err := time.LoadLocation(business.TimeZone); err != nil {
		return merchantBusiness{}, errors.New("business has an invalid time zone")
	}
	return business, nil
}

func validateSlotWindow(req slotMutation, zone string) (time.Time, time.Time, time.Time, error) {
	date, err := time.Parse("2006-01-02", req.Date)
	if err != nil || !localClockPattern.MatchString(req.StartsAt) || !localClockPattern.MatchString(req.EndsAt) || req.StartsAt >= req.EndsAt {
		return time.Time{}, time.Time{}, time.Time{}, errors.New("provide a valid local date and same-day start/end times")
	}
	loc, err := time.LoadLocation(zone)
	if err != nil {
		return time.Time{}, time.Time{}, time.Time{}, errors.New("business has an invalid time zone")
	}
	start, err := localWallTime(date, req.StartsAt, loc)
	if err != nil {
		return time.Time{}, time.Time{}, time.Time{}, errors.New("start time is invalid or ambiguous in the business time zone")
	}
	end, err := localWallTime(date, req.EndsAt, loc)
	if err != nil || end.Sub(start) <= 0 || end.Sub(start) > 12*time.Hour {
		return time.Time{}, time.Time{}, time.Time{}, errors.New("end time must be later than start and within 12 hours")
	}
	localToday := time.Now().In(loc)
	if date.Before(time.Date(localToday.Year(), localToday.Month(), localToday.Day(), 0, 0, 0, 0, loc)) || date.After(time.Date(localToday.Year(), localToday.Month(), localToday.Day(), 0, 0, 0, 0, loc).AddDate(0, 0, 180)) {
		return time.Time{}, time.Time{}, time.Time{}, errors.New("slot date must be within the next 180 days")
	}
	return start.UTC(), end.UTC(), date, nil
}

func localWallTime(date time.Time, clock string, loc *time.Location) (time.Time, error) {
	parsed, err := time.ParseInLocation("2006-01-02 15:04", date.Format("2006-01-02")+" "+clock, loc)
	if err != nil || parsed.In(loc).Format("2006-01-02 15:04") != date.Format("2006-01-02")+" "+clock {
		return time.Time{}, errors.New("invalid local time")
	}
	matches := 0
	for delta := -3 * time.Hour; delta <= 3*time.Hour; delta += time.Minute {
		candidate := parsed.Add(delta)
		if candidate.In(loc).Format("2006-01-02 15:04") == date.Format("2006-01-02")+" "+clock {
			matches++
		}
	}
	if matches != 1 {
		return time.Time{}, errors.New("ambiguous local time")
	}
	return parsed, nil
}

func validateOpenDate(tx *sqlx.Tx, r *http.Request, businessID string, date time.Time, starts, ends string) error {
	var isClosed bool
	var opens, closes *string
	err := tx.QueryRowxContext(r.Context(), `SELECT is_closed,opens_at::text,closes_at::text FROM business_availability_exceptions WHERE business_id=$1 AND local_date=$2`, businessID, date.Format("2006-01-02")).Scan(&isClosed, &opens, &closes)
	if err == nil {
		if isClosed {
			return errors.New("date is marked closed")
		}
		if opens != nil {
			openMinute, closeMinute := clockMinutes(*opens), clockMinutes(*closes)
			startMinute, endMinute := clockMinutes(starts), clockMinutes(ends)
			if openMinute < 0 || closeMinute < 0 || startMinute < openMinute || endMinute > closeMinute {
				return errors.New("slot falls outside the date's custom hours")
			}
		}
		return nil
	}
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return err
	}
	var weekdayClosed bool
	var weekdayOpens, weekdayCloses *string
	weekday := int(date.Weekday())
	err = tx.QueryRowxContext(r.Context(), `SELECT is_closed,opens_at::text,closes_at::text FROM business_hours WHERE business_id=$1 AND weekday=$2`, businessID, weekday).Scan(&weekdayClosed, &weekdayOpens, &weekdayCloses)
	if errors.Is(err, sql.ErrNoRows) {
		return errors.New("configure weekly operating hours or add a date-specific open exception first")
	}
	if err != nil {
		return err
	}
	if weekdayClosed || weekdayOpens == nil || weekdayCloses == nil {
		return errors.New("business is closed on this weekday; add a date-specific open exception first")
	}
	if clockMinutes(starts) < clockMinutes(*weekdayOpens) || clockMinutes(ends) > clockMinutes(*weekdayCloses) {
		return errors.New("slot falls outside weekly operating hours")
	}
	return nil
}

func clockMinutes(value string) int {
	parsed, err := time.Parse("15:04:05", value)
	if err != nil {
		parsed, err = time.Parse("15:04", value)
	}
	if err != nil {
		return -1
	}
	return parsed.Hour()*60 + parsed.Minute()
}

func writeAvailabilityMutationError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, errSlotNotFound):
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Business or appointment slot not found.")
	case strings.Contains(err.Error(), "overlap"), strings.Contains(err.Error(), "booked"), strings.Contains(err.Error(), "closed"), strings.Contains(err.Error(), "future"), strings.Contains(err.Error(), "past"), strings.Contains(err.Error(), "outside"), strings.Contains(err.Error(), "configure"), strings.Contains(err.Error(), "capacity"), strings.Contains(err.Error(), "date's"), strings.Contains(err.Error(), "confirmed"):
		writeError(w, http.StatusConflict, "AVAILABILITY_CONFLICT", err.Error())
	case strings.Contains(err.Error(), "valid"), strings.Contains(err.Error(), "provide"), strings.Contains(err.Error(), "ambiguous"), strings.Contains(err.Error(), "within"):
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", err.Error())
	default:
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to update appointment availability.")
	}
}

func mustLoadLocation(name string) *time.Location {
	loc, err := time.LoadLocation(name)
	if err != nil {
		return time.UTC
	}
	return loc
}
