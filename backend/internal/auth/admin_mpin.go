package auth

import (
	"database/sql"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/jmoiron/sqlx"
	"golang.org/x/crypto/bcrypt"
)

const (
	adminDeviceCookie    = "__Host-grepmind-admin-device"
	adminMPINLifetime    = 30 * 24 * time.Hour
	adminMPINMaxFailures = 5
)

func adminMPINOrigin() string {
	origin := os.Getenv("ADMIN_MPIN_ORIGIN")
	u, err := url.Parse(origin)
	if err != nil || u.Hostname() == "" || u.User != nil || u.Path != "" || u.ForceQuery || u.RawQuery != "" || u.Fragment != "" {
		return ""
	}
	if u.Scheme == "https" || (u.Scheme == "http" && (u.Hostname() == "localhost" || u.Hostname() == "127.0.0.1")) {
		return origin
	}
	return ""
}

// adminMPINEnrolled checks the current browser credential. A nonempty userID
// restricts the check to the account that has just verified an OTP.
func (s *Service) adminMPINEnrolled(r *http.Request, userID string) (bool, error) {
	device, err := r.Cookie(adminDeviceCookie)
	if err != nil || len(device.Value) != 43 {
		return false, nil
	}
	var enrolled bool
	err = s.db.GetContext(r.Context(), &enrolled, `
		SELECT EXISTS (SELECT 1 FROM admin_mpin_devices d JOIN users u ON u.id=d.user_id
		WHERE d.device_digest=$1 AND d.failed_attempts < $2 AND d.expires_at > $3
		  AND (NULLIF($4,'')::uuid IS NULL OR d.user_id=NULLIF($4,'')::uuid)
		  AND u.status='active' AND EXISTS (SELECT 1 FROM user_roles WHERE user_id=u.id AND role='admin'))
	`, hashToken(device.Value), adminMPINMaxFailures, s.now(), userID)
	return enrolled, err
}

func (s *Service) AdminMPINStatus(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	enabled := adminMPINOrigin() != ""
	enrolled := false
	if enabled && s.db != nil {
		enrolled, _ = s.adminMPINEnrolled(r, "")
	}
	writeJSON(w, http.StatusOK, envelope{"data": envelope{"enabled": enabled, "enrolled": enrolled}})
}

func (s *Service) readAdminMPIN(w http.ResponseWriter, r *http.Request) (string, bool) {
	w.Header().Set("Cache-Control", "no-store")
	origin := adminMPINOrigin()
	if origin == "" || r.Header.Get("Origin") != origin || s.db == nil {
		writeError(w, http.StatusForbidden, "MPIN_UNAVAILABLE", "Admin PIN is unavailable on this portal.")
		return "", false
	}
	var input struct {
		PIN string `json:"pin"`
	}
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 1024))
	if err != nil || json.Unmarshal(body, &input) != nil || !sixDigits(input.PIN) {
		writeError(w, http.StatusBadRequest, "INVALID_PIN", "Enter a six-digit PIN.")
		return "", false
	}
	return input.PIN, true
}

func (s *Service) EnrollAdminMPIN(w http.ResponseWriter, r *http.Request) {
	pin, ok := s.readAdminMPIN(w, r)
	if !ok {
		return
	}
	claims, err := s.parseSessionToken(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "))
	if err != nil || claims.SessionID == "" {
		writeError(w, http.StatusUnauthorized, "OTP_REQUIRED", "Sign in with OTP before setting a PIN.")
		return
	}

	device, err := generateOpaqueRefreshToken()
	if err != nil {
		adminMPINFailure(w)
		return
	}
	ctx := r.Context()
	authorized := false
	err = s.db.Transaction(ctx, func(tx *sqlx.Tx) error {
		var sessionID string
		err := tx.GetContext(ctx, &sessionID, `
			SELECT s.id FROM sessions s JOIN users u ON u.id=s.user_id
			WHERE s.id=$1 AND s.user_id=$2 AND s.revoked_at IS NULL AND s.expires_at > $3
			  AND s.admin_otp_authenticated_at BETWEEN $4 AND $3 AND u.status='active'
			  AND EXISTS (SELECT 1 FROM user_roles WHERE user_id=u.id AND role='admin')
			FOR UPDATE OF s
		`, claims.SessionID, claims.Subject, s.now(), s.now().Add(-5*time.Minute))
		if errors.Is(err, sql.ErrNoRows) {
			return nil
		}
		if err != nil {
			return err
		}
		digest, err := bcrypt.GenerateFromPassword([]byte(device+pin), bcrypt.DefaultCost)
		if err != nil {
			return err
		}
		if _, err = tx.ExecContext(ctx, `
			INSERT INTO admin_mpin_devices (device_digest,user_id,pin_hash,expires_at)
			VALUES ($1,$2,$3,$4)
			ON CONFLICT (user_id) DO UPDATE SET device_digest=EXCLUDED.device_digest,
			    pin_hash=EXCLUDED.pin_hash, expires_at=EXCLUDED.expires_at, failed_attempts=0
		`, hashToken(device), claims.Subject, string(digest), s.now().Add(adminMPINLifetime)); err != nil {
			return err
		}
		_, err = tx.ExecContext(ctx, "UPDATE sessions SET admin_otp_authenticated_at=NULL WHERE id=$1", sessionID)
		if err == nil {
			_, err = tx.ExecContext(ctx, `INSERT INTO audit_logs(actor_user_id,action,target_type,target_id,reason,created_at)
				VALUES($1,'admin_mpin.enrolled','admin_mpin_device',$1,'Browser PIN enrolled or replaced after verified OTP',now())`, claims.Subject)
		}
		authorized = err == nil
		return err
	})
	if err != nil {
		adminMPINFailure(w)
		return
	}
	if !authorized {
		writeError(w, http.StatusUnauthorized, "OTP_REQUIRED", "Sign in with OTP before setting a PIN.")
		return
	}
	http.SetCookie(w, &http.Cookie{
		Name: adminDeviceCookie, Value: device, Path: "/", Secure: true, HttpOnly: true,
		SameSite: http.SameSiteStrictMode, MaxAge: int(adminMPINLifetime.Seconds()),
	})
	w.WriteHeader(http.StatusNoContent)
}

// RemoveAdminMPIN removes the enrolled browser credential. A recent OTP-backed
// session is required so a PIN session cannot remove its own recovery path.
func (s *Service) RemoveAdminMPIN(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	origin := adminMPINOrigin()
	if origin == "" || r.Header.Get("Origin") != origin || s.db == nil {
		writeError(w, http.StatusForbidden, "MPIN_UNAVAILABLE", "Admin PIN is unavailable on this portal.")
		return
	}
	claims, err := s.parseSessionToken(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "))
	if err != nil || claims.SessionID == "" {
		writeError(w, http.StatusUnauthorized, "OTP_REQUIRED", "Sign in with OTP before removing the browser PIN.")
		return
	}
	removed := false
	err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var userID string
		if err := tx.GetContext(r.Context(), &userID, `SELECT s.user_id::text FROM sessions s JOIN users u ON u.id=s.user_id
			WHERE s.id=$1 AND s.user_id=$2 AND s.revoked_at IS NULL AND s.expires_at>$3
			  AND s.admin_otp_authenticated_at BETWEEN $4 AND $3 AND u.status='active'
			  AND EXISTS (SELECT 1 FROM user_roles WHERE user_id=u.id AND role='admin')`,
			claims.SessionID, claims.Subject, s.now(), s.now().Add(-5*time.Minute)); err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return nil
			}
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `DELETE FROM admin_mpin_devices WHERE user_id=$1`, claims.Subject); err != nil {
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO audit_logs(actor_user_id,action,target_type,target_id,reason,created_at)
			VALUES($1,'admin_mpin.removed','admin_mpin_device',$1,'Browser PIN removed after verified OTP',now())`, claims.Subject); err != nil {
			return err
		}
		removed = true
		return nil
	})
	if err != nil {
		adminMPINFailure(w)
		return
	}
	if !removed {
		writeError(w, http.StatusUnauthorized, "OTP_REQUIRED", "Sign in with OTP before removing the browser PIN.")
		return
	}
	http.SetCookie(w, &http.Cookie{Name: adminDeviceCookie, Value: "", Path: "/", Secure: true, HttpOnly: true, SameSite: http.SameSiteStrictMode, MaxAge: -1})
	w.WriteHeader(http.StatusNoContent)
}

func (s *Service) VerifyAdminMPIN(w http.ResponseWriter, r *http.Request) {
	pin, ok := s.readAdminMPIN(w, r)
	if !ok {
		return
	}
	device, err := r.Cookie(adminDeviceCookie)
	var access, refresh string
	if err == nil && len(device.Value) == 43 {
		ctx := r.Context()
		err = s.db.Transaction(ctx, func(tx *sqlx.Tx) error {
			var record struct {
				UserID  string `db:"user_id"`
				PINHash string `db:"pin_hash"`
			}
			err := tx.GetContext(ctx, &record, `
				SELECT d.user_id, d.pin_hash FROM admin_mpin_devices d JOIN users u ON u.id=d.user_id
				WHERE d.device_digest=$1 AND d.failed_attempts < $2 AND d.expires_at > $3 AND u.status='active'
				  AND EXISTS (SELECT 1 FROM user_roles WHERE user_id=u.id AND role='admin')
				FOR UPDATE OF d
			`, hashToken(device.Value), adminMPINMaxFailures, s.now())
			if errors.Is(err, sql.ErrNoRows) {
				return nil
			}
			if err != nil {
				return err
			}
			if bcrypt.CompareHashAndPassword([]byte(record.PINHash), []byte(device.Value+pin)) != nil {
				_, err = tx.ExecContext(ctx, "UPDATE admin_mpin_devices SET failed_attempts=failed_attempts+1 WHERE device_digest=$1", hashToken(device.Value))
				return err
			}
			if _, err = tx.ExecContext(ctx, "UPDATE admin_mpin_devices SET failed_attempts=0 WHERE device_digest=$1", hashToken(device.Value)); err != nil {
				return err
			}
			access, refresh, err = s.issueTokensTx(ctx, tx, record.UserID, r.UserAgent(), remoteIP(r))
			return err
		})
		if err != nil {
			adminMPINFailure(w)
			return
		}
	}
	if access == "" {
		writeError(w, http.StatusUnauthorized, "INVALID_MPIN", "PIN sign-in failed. You can sign in with OTP to set up a new PIN.")
		return
	}
	writeJSON(w, http.StatusOK, envelope{"data": envelope{"access_token": access, "refresh_token": refresh}})
}

func adminMPINFailure(w http.ResponseWriter) {
	writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Admin PIN sign-in could not be completed.")
}
