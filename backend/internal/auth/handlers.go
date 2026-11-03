package auth

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/jmoiron/sqlx"
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
	if s == nil || s.cfg == nil || s.otpProvider == nil {
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
	if !s.allowOTPRequest(phone, remoteIP(r)) {
		writeError(w, http.StatusTooManyRequests, "RATE_LIMITED", "Please wait before requesting another OTP.")
		return
	}
	if s.db == nil {
		writeError(w, http.StatusServiceUnavailable, "OTP_UNAVAILABLE", "Phone verification is currently unavailable.")
		return
	}
	var code, otpID string
	err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		// Serialize request checks by phone across API processes without a new
		// service or table. The lock is held only through OTP row creation.
		if _, lockErr := tx.ExecContext(r.Context(), `SELECT pg_advisory_xact_lock(hashtextextended($1, 0))`, phone); lockErr != nil {
			return lockErr
		}
		var count int
		if queryErr := tx.GetContext(r.Context(), &count, `
			SELECT count(*) FROM otp_codes WHERE phone_e164 = $1 AND created_at > $2
		`, phone, s.now().Add(-time.Hour)); queryErr != nil {
			return queryErr
		}
		if count >= 5 {
			return errOTPRequestLimited
		}
		var lastCreated time.Time
		queryErr := tx.GetContext(r.Context(), &lastCreated,
			`SELECT created_at FROM otp_codes WHERE phone_e164 = $1 ORDER BY created_at DESC LIMIT 1`, phone)
		if queryErr == nil && s.now().Sub(lastCreated) < s.cfg.OTPResendCooldown {
			return errOTPRequestLimited
		}
		if queryErr != nil && !errors.Is(queryErr, sql.ErrNoRows) {
			return queryErr
		}
		code, queryErr = generateOTP()
		if queryErr != nil {
			return queryErr
		}
		codeHash, hashErr := bcrypt.GenerateFromPassword([]byte(code), bcrypt.DefaultCost)
		if hashErr != nil {
			return hashErr
		}
		return tx.QueryRowxContext(r.Context(), `
			INSERT INTO otp_codes (phone_e164, code_hash, attempts, max_attempts, expires_at)
			VALUES ($1, $2, 0, $3, $4) RETURNING id::text
		`, phone, string(codeHash), s.cfg.OTPMaxAttempts, s.now().Add(s.cfg.OTPTTL)).Scan(&otpID)
	})
	if errors.Is(err, errOTPRequestLimited) {
		writeError(w, http.StatusTooManyRequests, "RATE_LIMITED", "Please wait before requesting another OTP.")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to store OTP.")
		return
	}
	if err := s.otpProvider.SendOTP(r.Context(), phone, code); err != nil {
		_, _ = s.db.ExecContext(r.Context(), `DELETE FROM otp_codes WHERE id = $1`, otpID)
		writeError(w, http.StatusServiceUnavailable, "OTP_UNAVAILABLE", "Phone verification is currently unavailable.")
		return
	}

	data := otpRequestResponseData(phone, code, s.cfg.IsLocal())
	writeJSON(w, http.StatusAccepted, envelope{
		"data": data,
		"meta": map[string]string{"request_id": "otp-requested"},
	})
}

func otpRequestResponseData(phone, code string, local bool) map[string]interface{} {
	data := map[string]interface{}{"phone_e164": phone, "status": "otp_requested"}
	// OTP echo is a local-only development affordance. Non-local environments
	// never include it, even if a provider implementation is injected.
	if local {
		data["otp_code"] = code
	}
	return data
}

func (s *Service) allowOTPRequest(phone, ip string) bool {
	if s.otpLimits == nil {
		s.otpLimits = newOTPRateLimiter()
	}
	now := s.now()
	return s.otpLimits.allow("request-ip", ip, now, 20, time.Minute) &&
		s.otpLimits.allow("request-phone", phone, now, 5, time.Hour)
}

func (s *Service) allowOTPVerify(phone, ip string) bool {
	if s.otpLimits == nil {
		s.otpLimits = newOTPRateLimiter()
	}
	now := s.now()
	return s.otpLimits.allow("verify-ip", ip, now, 30, 10*time.Minute) &&
		s.otpLimits.allow("verify-phone", phone, now, 10, 10*time.Minute)
}

func remoteIP(r *http.Request) string {
	peer, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		peer = r.RemoteAddr
	}
	peerIP := net.ParseIP(peer)
	if peerIP != nil && (peerIP.IsPrivate() || peerIP.IsLoopback()) {
		if forwarded := net.ParseIP(strings.TrimSpace(r.Header.Get("X-Real-IP"))); forwarded != nil {
			return forwarded.String()
		}
	}
	return peer
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
	if body.OTPCode == "" || len(body.OTPCode) != 6 {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "otp_code must contain six digits.")
		return
	}
	if !s.allowOTPVerify(phone, remoteIP(r)) {
		writeError(w, http.StatusTooManyRequests, "RATE_LIMITED", "Too many verification attempts. Please try later.")
		return
	}
	if s.db == nil {
		writeError(w, http.StatusServiceUnavailable, "AUTH_UNAVAILABLE", "Phone verification is currently unavailable.")
		return
	}

	var userID string
	invalidOTP := false
	err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var id, codeHash string
		var attempts, maxAttempts int
		var expiresAt time.Time
		var verifiedAt sql.NullTime
		queryErr := tx.QueryRowxContext(r.Context(), `
			SELECT id::text, code_hash, attempts, max_attempts, expires_at, verified_at
			FROM otp_codes WHERE phone_e164 = $1 ORDER BY created_at DESC LIMIT 1 FOR UPDATE
		`, phone).Scan(&id, &codeHash, &attempts, &maxAttempts, &expiresAt, &verifiedAt)
		if errors.Is(queryErr, sql.ErrNoRows) {
			invalidOTP = true
			return nil
		}
		if queryErr != nil {
			return queryErr
		}
		if verifiedAt.Valid || !expiresAt.After(s.now()) || attempts >= maxAttempts {
			invalidOTP = true
			return nil
		}
		if _, queryErr = tx.ExecContext(r.Context(), `UPDATE otp_codes SET attempts = attempts + 1 WHERE id = $1`, id); queryErr != nil {
			return queryErr
		}
		if compareErr := bcrypt.CompareHashAndPassword([]byte(codeHash), []byte(body.OTPCode)); compareErr != nil {
			invalidOTP = true
			return nil
		}
		if _, queryErr = tx.ExecContext(r.Context(), `UPDATE otp_codes SET verified_at = $1 WHERE id = $2 AND verified_at IS NULL`, s.now(), id); queryErr != nil {
			return queryErr
		}
		if queryErr = tx.QueryRowxContext(r.Context(), `
			INSERT INTO users (phone_e164, status, preferred_language)
			VALUES ($1, 'active', 'en')
			ON CONFLICT (phone_e164) DO UPDATE SET updated_at = now()
			RETURNING id::text
		`, phone).Scan(&userID); queryErr != nil {
			return queryErr
		}
		_, queryErr = tx.ExecContext(r.Context(), `
			INSERT INTO user_roles (user_id, role) VALUES ($1, 'customer')
			ON CONFLICT (user_id, role) DO NOTHING
		`, userID)
		return queryErr
	})
	if invalidOTP {
		writeError(w, http.StatusUnauthorized, "INVALID_OTP", "Invalid or expired OTP.")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to verify phone number.")
		return
	}

	var user AppUser
	err = s.db.QueryRowContext(r.Context(), `
		SELECT phone_e164, COALESCE(display_name,''), status, preferred_language FROM users WHERE id=$1
	`, userID).Scan(&user.PhoneE164, &user.DisplayName, &user.Status, &user.PreferredLanguage)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load account.")
		return
	}
	user.ID = userID
	if user.Status != "active" {
		writeError(w, http.StatusForbidden, "FORBIDDEN", "Account is not active.")
		return
	}
	if err = s.db.SelectContext(r.Context(), &user.Roles, `SELECT role FROM user_roles WHERE user_id=$1 ORDER BY role`, userID); err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load account roles.")
		return
	}
	accessToken, refreshToken, err := s.issueTokens(r.Context(), userID, r.UserAgent(), remoteIP(r))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to issue session tokens.")
		return
	}
	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]interface{}{"access_token": accessToken, "refresh_token": refreshToken, "user": user},
		"meta": map[string]string{"request_id": "otp-verified"},
	})
}

func (s *Service) Refresh(w http.ResponseWriter, r *http.Request) {
	var body refreshBody
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "Unable to parse request body.")
		return
	}
	if body.RefreshToken == "" {
		writeError(w, http.StatusUnauthorized, "INVALID_TOKEN", "Invalid or expired refresh token.")
		return
	}
	accessToken, refreshToken, err := s.rotateRefreshToken(r.Context(), body.RefreshToken, r.UserAgent(), remoteIP(r))
	if err != nil {
		if errors.Is(err, errInvalidToken) {
			writeError(w, http.StatusUnauthorized, "INVALID_TOKEN", "Invalid or expired refresh token.")
		} else {
			writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to rotate session tokens.")
		}
		return
	}
	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]interface{}{"access_token": accessToken, "refresh_token": refreshToken},
		"meta": map[string]string{"request_id": "refresh-rotated"},
	})
}

func (s *Service) Logout(w http.ResponseWriter, r *http.Request) {
	token := strings.TrimSpace(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "))
	if token != "" {
		if err := s.revokeAccessToken(r.Context(), token); err != nil {
			writeError(w, http.StatusUnauthorized, "INVALID_TOKEN", "Invalid or expired access token.")
			return
		}
	}
	writeJSON(w, http.StatusOK, envelope{
		"data": map[string]string{"status": "logged_out"},
		"meta": map[string]string{"request_id": "logout"},
	})
}
