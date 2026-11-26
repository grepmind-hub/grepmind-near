package riders

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"strings"

	"github.com/google/uuid"
)

// FieldExecutiveDirectory returns active Admin-approved Field Executives (AFE-1000 series)
// so onboarding forms can attribute a Rider or Merchant to a Field Executive.
func (s *Service) FieldExecutiveDirectory(w http.ResponseWriter, r *http.Request, _ string) {
	rows, err := queryMaps(
		r.Context(),
		s.db,
		`SELECT id, executive_code, display_name
		 FROM field_executives
		 WHERE is_active = true
		 ORDER BY executive_code ASC`,
	)
	if err != nil {
		fail(w, 500, "Unable to load Field Executives directory.")
		return
	}
	write(w, 200, envelope{"data": rows})
}

// AdminListFieldExecutives lists all Field Executives with onboarded Rider & Merchant counts.
func (s *Service) AdminListFieldExecutives(w http.ResponseWriter, r *http.Request, _ string) {
	rows, err := queryMaps(
		r.Context(),
		s.db,
		`SELECT fe.id,
		        fe.user_id,
		        fe.executive_code,
		        fe.display_name,
		        fe.is_active,
		        fe.granted_at,
		        fe.revoked_at,
		        u.phone_e164,
		        (SELECT COUNT(*) FROM rider_profiles rp WHERE rp.field_executive_id = fe.id) AS onboarded_riders_count,
		        (SELECT COUNT(*) FROM businesses b WHERE b.field_executive_id = fe.id) AS onboarded_merchants_count
		 FROM field_executives fe
		 JOIN users u ON u.id = fe.user_id
		 ORDER BY fe.is_active DESC, fe.executive_code ASC`,
	)
	if err != nil {
		fail(w, 500, "Unable to list Field Executives.")
		return
	}
	write(w, 200, envelope{"data": rows})
}

// AdminGrantFieldExecutive designates an existing user as a Field Executive (AFE-1000 series).
func (s *Service) AdminGrantFieldExecutive(w http.ResponseWriter, r *http.Request, adminID string) {
	var in struct {
		PhoneE164   string `json:"phone_e164"`
		UserID      string `json:"user_id"`
		DisplayName string `json:"display_name"`
	}
	if json.NewDecoder(http.MaxBytesReader(w, r.Body, 16<<10)).Decode(&in) != nil {
		fail(w, 400, "Invalid Field Executive payload.")
		return
	}
	phone := strings.TrimSpace(in.PhoneE164)
	uid := strings.TrimSpace(in.UserID)
	if phone == "" && uid == "" {
		fail(w, 400, "Provide user phone_e164 or user_id.")
		return
	}

	var targetUserID, existingName string
	var err error
	if uid != "" {
		parsed, parseErr := uuid.Parse(uid)
		if parseErr != nil {
			fail(w, 400, "Invalid user_id.")
			return
		}
		err = s.db.QueryRowxContext(
			r.Context(),
			`SELECT id::text, COALESCE(display_name,'') FROM users WHERE id = $1`,
			parsed,
		).Scan(&targetUserID, &existingName)
	} else {
		err = s.db.QueryRowxContext(
			r.Context(),
			`SELECT id::text, COALESCE(display_name,'') FROM users WHERE phone_e164 = $1`,
			phone,
		).Scan(&targetUserID, &existingName)
	}
	if err == sql.ErrNoRows {
		fail(w, 404, "No registered user found for that phone number or ID.")
		return
	}
	if err != nil {
		fail(w, 500, "Unable to look up user.")
		return
	}

	name := strings.TrimSpace(in.DisplayName)
	if name == "" {
		name = strings.TrimSpace(existingName)
	}
	if name == "" {
		name = "Field Executive"
	}
	if len(name) > 120 {
		name = name[:120]
	}

	var row struct {
		ID            string `db:"id" json:"id"`
		ExecutiveCode string `db:"executive_code" json:"executive_code"`
		DisplayName   string `db:"display_name" json:"display_name"`
		IsActive      bool   `db:"is_active" json:"is_active"`
	}
	err = s.db.QueryRowxContext(
		r.Context(),
		`INSERT INTO field_executives (user_id, display_name, is_active, granted_by_user_id, granted_at, revoked_at)
		 VALUES ($1, $2, true, $3, now(), NULL)
		 ON CONFLICT (user_id) DO UPDATE
		 SET display_name = EXCLUDED.display_name,
		     is_active = true,
		     granted_by_user_id = EXCLUDED.granted_by_user_id,
		     granted_at = now(),
		     revoked_at = NULL
		 RETURNING id::text, executive_code, display_name, is_active`,
		targetUserID,
		name,
		adminID,
	).StructScan(&row)
	if err != nil {
		fail(w, 500, "Unable to grant Field Executive designation.")
		return
	}
	write(w, 200, envelope{"data": row})
}

// AdminRevokeFieldExecutive revokes an active Field Executive designation.
func (s *Service) AdminRevokeFieldExecutive(w http.ResponseWriter, r *http.Request, _ string) {
	id := strings.TrimSpace(r.PathValue("id"))
	parsed, err := uuid.Parse(id)
	if err != nil {
		fail(w, 400, "Invalid Field Executive ID.")
		return
	}
	res, err := s.db.ExecContext(
		r.Context(),
		`UPDATE field_executives SET is_active = false, revoked_at = now() WHERE id = $1`,
		parsed,
	)
	if err != nil {
		fail(w, 500, "Unable to revoke Field Executive.")
		return
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		fail(w, 404, "Field Executive not found.")
		return
	}
	write(w, 200, envelope{"data": map[string]any{"id": id, "is_active": false}})
}
