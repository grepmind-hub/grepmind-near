package auth

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"
)

type otpRequestBody struct {
	PhoneE164 string `json:"phone_e164"`
}

type otpVerifyBody struct {
	PhoneE164      string `json:"phone_e164"`
	OTPCode        string `json:"otp_code"`
	IdempotencyKey string `json:"idempotency_key"`
}

type refreshBody struct {
	RefreshToken string `json:"refresh_token"`
}

func (s *Service) RequestOTP(w http.ResponseWriter, r *http.Request) {
	// No production SMS adapter exists yet. Fail closed rather than exposing an OTP.
	if !s.cfg.IsLocal() {
		writeError(w, http.StatusServiceUnavailable, "OTP_UNAVAILABLE", "Phone verification is currently unavailable.")
		return
	}
	var body otpRequestBody
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "Unable to parse request body.")
		return
	}
	phone, err := normalizePhone(body.PhoneE164)
	if err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", err.Error())
		return
	}

	var lastCreated time.Time
	err = s.db.GetContext(r.Context(), &lastCreated,
		`SELECT created_at FROM otp_codes WHERE phone_e164 = $1 ORDER BY created_at DESC LIMIT 1`, phone)
	if err == nil && s.now().Sub(lastCreated) < s.cfg.OTPResendCooldown {
		writeError(w, http.StatusTooManyRequests, "RATE_LIMITED", "Please wait before requesting another OTP.")
		return
	}

	code := generateOTP()
	codeHash, err := bcrypt.GenerateFromPassword([]byte(code), bcrypt.DefaultCost)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to generate OTP.")
		return
	}
	_, err = s.db.ExecContext(r.Context(), `
		INSERT INTO otp_codes (phone_e164, code_hash, attempts, max_attempts, expires_at)
		VALUES ($1, $2, 0, $3, $4)
	`, phone, string(codeHash), s.cfg.OTPMaxAttempts, s.now().Add(s.cfg.OTPTTL))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to store OTP.")
		return
	}

	writeJSON(w, http.StatusAccepted, envelope{
		"data": map[string]interface{}{
			"phone_e164": phone,
			"status":     "otp_requested",
			"otp_code":   code,
		},
		"meta": map[string]string{"request_id": "otp-req-" + phone},
	})
}

func (s *Service) VerifyOTP(w http.ResponseWriter, r *http.Request) {
	var body otpVerifyBody
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "Unable to parse request body.")
		return
	}
	phone, err := normalizePhone(body.PhoneE164)
	if err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", err.Error())
		return
	}
	if body.OTPCode == "" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "otp_code is required.")
		return
	}

	var (
		dbID          sql.NullString
		dbCodeHash    sql.NullString
		dbAttempts    sql.NullInt64
		dbMaxAttempts sql.NullInt64
		dbExpiresAt   sql.NullTime
		dbVerifiedAt  sql.NullTime
	)
	err = s.db.QueryRowxContext(r.Context(), `
		SELECT id, code_hash, attempts, max_attempts, expires_at, verified_at
		FROM otp_codes
		WHERE phone_e164 = $1
		ORDER BY created_at DESC
		LIMIT 1
	`, phone).Scan(&dbID, &dbCodeHash, &dbAttempts, &dbMaxAttempts, &dbExpiresAt, &dbVerifiedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusUnauthorized, "INVALID_OTP", "Invalid or expired OTP.")
		} else {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to verify OTP.")
		}
		return
	}

	if dbVerifiedAt.Valid {
		writeError(w, http.StatusBadRequest, "OTP_ALREADY_VERIFIED", "OTP already verified.")
		return
	}
	if dbExpiresAt.Valid && s.now().After(dbExpiresAt.Time) {
		writeError(w, http.StatusUnauthorized, "OTP_EXPIRED", "OTP has expired.")
		return
	}
	if dbAttempts.Valid && int(dbAttempts.Int64) >= int(dbMaxAttempts.Int64) {
		writeError(w, http.StatusUnauthorized, "OTP_MAX_ATTEMPTS", "Maximum OTP attempts exceeded.")
		return
	}

	_, _ = s.db.ExecContext(r.Context(), `
		UPDATE otp_codes SET attempts = attempts + 1 WHERE id = $1
	`, dbID.String)

	if err := bcrypt.CompareHashAndPassword([]byte(dbCodeHash.String), []byte(body.OTPCode)); err != nil {
		writeError(w, http.StatusUnauthorized, "INVALID_OTP", "Invalid OTP code.")
		return
	}

	_, _ = s.db.ExecContext(r.Context(), `
		UPDATE otp_codes SET verified_at = $1 WHERE id = $2
	`, s.now(), dbID.String)

	var userID string
	err = s.db.QueryRowxContext(r.Context(), `
		INSERT INTO users (phone_e164, status, preferred_language)
		VALUES ($1, 'active', 'en')
		ON CONFLICT (phone_e164) DO UPDATE SET updated_at = now()
		RETURNING id
	`, phone).Scan(&userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to create user session.")
		return
	}

	_, _ = s.db.ExecContext(r.Context(), `
		INSERT INTO user_roles (user_id, role)
		VALUES ($1, 'customer')
		ON CONFLICT (user_id, role) DO NOTHING
	`, userID)

	user := AppUser{ID: userID}
	err = s.db.QueryRowContext(r.Context(), `SELECT phone_e164, COALESCE(display_name,''), status, preferred_language FROM users WHERE id=$1`, userID).Scan(&user.PhoneE164, &user.DisplayName, &user.Status, &user.PreferredLanguage)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load account.")
		return
	}
	if user.Status != "active" {
		writeError(w, 403, "FORBIDDEN", "Account is not active.")
		return
	}
	if err = s.db.SelectContext(r.Context(), &user.Roles, `SELECT role FROM user_roles WHERE user_id=$1 ORDER BY role`, userID); err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load account roles.")
		return
	}
	accessToken, refreshToken, err := s.issueTokens(r.Context(), userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to issue session tokens.")
		return
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]interface{}{
			"access_token":  accessToken,
			"refresh_token": refreshToken,
			"user":          user,
		},
		"meta": map[string]string{"request_id": "otp-verify-" + phone},
	})
}

func (s *Service) Refresh(w http.ResponseWriter, r *http.Request) {
	var body refreshBody
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "Unable to parse request body.")
		return
	}
	claims, err := s.validateRefreshToken(r.Context(), body.RefreshToken)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "INVALID_TOKEN", "Invalid or expired refresh token.")
		return
	}

	_, _ = s.db.ExecContext(r.Context(), `UPDATE sessions SET revoked_at = $1 WHERE refresh_token_hash = $2`, s.now(), hashToken(body.RefreshToken))

	accessToken, refreshToken, err := s.issueTokens(r.Context(), claims.Subject)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to rotate tokens.")
		return
	}
	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]interface{}{
			"access_token":  accessToken,
			"refresh_token": refreshToken,
		},
		"meta": map[string]string{"request_id": "refresh-rotated"},
	})
}

func (s *Service) Logout(w http.ResponseWriter, r *http.Request) {
	auth := r.Header.Get("Authorization")
	token := strings.TrimPrefix(auth, "Bearer ")
	if token != "" {
		_, _ = s.db.ExecContext(r.Context(), `UPDATE sessions SET revoked_at = $1 WHERE refresh_token_hash = $2`, s.now(), hashToken(token))
	}
	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]string{"status": "logged_out"},
		"meta": map[string]string{"request_id": "logout"},
	})
}
