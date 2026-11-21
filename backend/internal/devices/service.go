package devices

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"

	"grepmind-near/backend/internal/fcm"
)

var (
	errDeviceNotFound   = errors.New("device registration not found")
	errDeviceMismatch   = errors.New("device registration does not belong to the authenticated user")
	errInvalidPlatform  = errors.New("invalid platform")
	errInvalidEnvironment = errors.New("invalid environment")
)

type Registration struct {
	ID                        string     `json:"id" db:"id"`
	UserID                    *string    `json:"user_id,omitempty" db:"user_id"`
	InstallationID            string     `json:"installation_id" db:"installation_id"`
	FCMToken                  string     `json:"-" db:"fcm_token"`
	Platform                  string     `json:"platform" db:"platform"`
	Environment               string     `json:"environment" db:"environment"`
	NotificationPermission    bool       `json:"notification_permission" db:"notification_permission"`
	LastSeen                  time.Time  `json:"last_seen" db:"last_seen"`
	Active                    bool       `json:"active" db:"active"`
	RevokedAt                 *time.Time `json:"revoked_at,omitempty" db:"revoked_at"`
	CreatedAt                 time.Time  `json:"created_at" db:"created_at"`
	UpdatedAt                 time.Time  `json:"updated_at" db:"updated_at"`
}

type registerRequest struct {
	InstallationID            string `json:"installation_id"`
	FCMToken                  string `json:"fcm_token"`
	Platform                  string `json:"platform"`
	Environment               string `json:"environment"`
	NotificationPermission    bool   `json:"notification_permission"`
}

type revokeRequest struct {
	InstallationID string `json:"installation_id"`
	FCMToken       string `json:"fcm_token,omitempty"`
}

type Service struct {
	db  *sqlx.DB
	fcm *fcm.Service
	env string
}

func NewService(db *sqlx.DB, fcmSvc *fcm.Service) *Service {
	return &Service{db: db, fcm: fcmSvc}
}

// SetEnvironment configures the environment for this service, used to gate
// QA-only endpoints such as pre-login device registration.
func (s *Service) SetEnvironment(env string) {
	s.env = env
}

// IsQAEnvironment returns true when the server is running in a QA or staging
// environment. Pre-login device registration is restricted to QA environments
// to prevent accidental exposure in production.
func (s *Service) IsQAEnvironment() bool {
	return strings.EqualFold(s.env, "qa") || strings.EqualFold(s.env, "staging")
}

// Register stores or updates a device registration. user_id may be nil for
// pre-login installations. Account isolation is enforced: an installation can
// only be claimed by one user at a time. FCM tokens are never treated as proof
// of phone ownership.
func (s *Service) Register(ctx context.Context, userID *string, req registerRequest) (*Registration, error) {
	if req.InstallationID == "" {
		return nil, errors.New("installation_id is required")
	}
	if req.FCMToken == "" {
		return nil, errors.New("fcm_token is required")
	}
	if !validPlatform(req.Platform) {
		return nil, errInvalidPlatform
	}
	if !validEnvironment(req.Environment) {
		return nil, errInvalidEnvironment
	}

	var uID *uuid.UUID
	if userID != nil && *userID != "" {
		parsed, err := uuid.Parse(*userID)
		if err != nil {
			return nil, errors.New("invalid user ID")
		}
		uID = &parsed
	}

	reg := &Registration{
		UserID:                 ptrString(userID),
		InstallationID:         req.InstallationID,
		FCMToken:               req.FCMToken,
		Platform:               req.Platform,
		Environment:            req.Environment,
		NotificationPermission: req.NotificationPermission,
		Active:                 true,
	}

	tx, err := s.db.BeginTxx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	// Revoke any previous active registration for this installation
	// so the same installation cannot be bound to multiple accounts.
	if _, err := tx.ExecContext(ctx, `
		UPDATE device_registrations
		SET active = false, revoked_at = $1, updated_at = $1
		WHERE installation_id = $2 AND active = true AND revoked_at IS NULL
	`, time.Now().UTC(), req.InstallationID); err != nil {
		return nil, err
	}

	// Revoke any other active registration using the same FCM token
	// to prevent token reuse across installations.
	if _, err := tx.ExecContext(ctx, `
		UPDATE device_registrations
		SET active = false, revoked_at = $1, updated_at = $1
		WHERE fcm_token = $2 AND active = true AND revoked_at IS NULL
	`, time.Now().UTC(), req.FCMToken); err != nil {
		return nil, err
	}

	query := `
		INSERT INTO device_registrations
			(user_id, installation_id, fcm_token, platform, environment,
			 notification_permission, last_seen, active, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, true, now(), now())
		RETURNING id::text, user_id, installation_id, fcm_token, platform,
			environment, notification_permission, last_seen, active, created_at, updated_at
	`
	if err := tx.QueryRowxContext(ctx, query,
		uID, req.InstallationID, req.FCMToken, req.Platform, req.Environment,
		req.NotificationPermission, time.Now().UTC()).Scan(
		&reg.ID, &reg.UserID, &reg.InstallationID, &reg.FCMToken, &reg.Platform,
		&reg.Environment, &reg.NotificationPermission, &reg.LastSeen,
		&reg.Active, &reg.CreatedAt, &reg.UpdatedAt,
	); err != nil {
		return nil, err
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}

	return reg, nil
}

// AssociateUser binds a pre-login installation to an authenticated user.
// Enforces account isolation: only the installation's current state is changed.
func (s *Service) AssociateUser(ctx context.Context, installationID, userID string) error {
	uID, err := uuid.Parse(userID)
	if err != nil {
		return errors.New("invalid user ID")
	}
	result, err := s.db.ExecContext(ctx, `
		UPDATE device_registrations
		SET user_id = $1, updated_at = now()
		WHERE installation_id = $2 AND active = true AND revoked_at IS NULL
			AND (user_id IS NULL OR user_id = $1)
	`, uID, installationID)
	if err != nil {
		return err
	}
	count, _ := result.RowsAffected()
	if count == 0 {
		return errDeviceNotFound
	}
	return nil
}

// Revoke deactivates a device registration. When userID is provided, only
// registrations belonging to that user can be revoked (account isolation).
func (s *Service) Revoke(ctx context.Context, userID string, req revokeRequest) error {
	uID, err := uuid.Parse(userID)
	if err != nil {
		return errors.New("invalid user ID")
	}

	result, err := s.db.ExecContext(ctx, `
		UPDATE device_registrations
		SET active = false, revoked_at = $1, updated_at = $1
		WHERE active = true AND revoked_at IS NULL
			AND (user_id = $2 OR user_id IS NULL)
			AND ($3 = '' OR installation_id = $3)
			AND ($4 = '' OR fcm_token = $4)
	`, time.Now().UTC(), uID, req.InstallationID, req.FCMToken)
	if err != nil {
		return err
	}
	count, _ := result.RowsAffected()
	if count == 0 {
		return errDeviceNotFound
	}
	return nil
}

// GetByInstallationID returns an active registration by installation ID.
// Used for pre-login FCM delivery where the user may not exist yet.
func (s *Service) GetByInstallationID(ctx context.Context, installationID string) (*Registration, error) {
	var reg Registration
	err := s.db.QueryRowxContext(ctx, `
		SELECT id::text, user_id, installation_id, fcm_token, platform,
			environment, notification_permission, last_seen, active, created_at, updated_at
		FROM device_registrations
		WHERE installation_id = $1 AND active = true AND revoked_at IS NULL
	`, installationID).Scan(
		&reg.ID, &reg.UserID, &reg.InstallationID, &reg.FCMToken, &reg.Platform,
		&reg.Environment, &reg.NotificationPermission, &reg.LastSeen,
		&reg.Active, &reg.CreatedAt, &reg.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, errDeviceNotFound
		}
		return nil, err
	}
	return &reg, nil
}

// ListActive returns active device registrations for the authenticated user.
func (s *Service) ListActive(ctx context.Context, userID string) ([]Registration, error) {
	uID, err := uuid.Parse(userID)
	if err != nil {
		return nil, errors.New("invalid user ID")
	}

	var regs []Registration
	err = s.db.SelectContext(ctx, &regs, `
		SELECT id::text, user_id, installation_id, fcm_token, platform,
			environment, notification_permission, last_seen, active, created_at, updated_at
		FROM device_registrations
		WHERE user_id = $1 AND active = true AND revoked_at IS NULL
		ORDER BY last_seen DESC
	`, uID)
	if err != nil {
		return nil, err
	}
	if regs == nil {
		regs = []Registration{}
	}
	return regs, nil
}

// MarkTokenInvalid revokes a registration whose FCM token is no longer valid.
// Called when FCM returns an InvalidRegistration / NotRegistered error.
func (s *Service) MarkTokenInvalid(ctx context.Context, fcmToken string) error {
	if fcmToken == "" {
		return errors.New("fcm_token is required")
	}
	_, err := s.db.ExecContext(ctx, `
		UPDATE device_registrations
		SET active = false, revoked_at = $1, updated_at = $1
		WHERE fcm_token = $2 AND active = true AND revoked_at IS NULL
	`, time.Now().UTC(), fcmToken)
	return err
}

// UpdateLastSeen refreshes the last_seen timestamp for an active registration.
func (s *Service) UpdateLastSeen(ctx context.Context, userID, installationID string) error {
	uID, err := uuid.Parse(userID)
	if err != nil {
		return errors.New("invalid user ID")
	}
	_, err = s.db.ExecContext(ctx, `
		UPDATE device_registrations
		SET last_seen = $1, updated_at = $1
		WHERE user_id = $2 AND installation_id = $3 AND active = true AND revoked_at IS NULL
	`, time.Now().UTC(), uID, installationID)
	return err
}

// validPlatform checks that the platform value is accepted.
func validPlatform(p string) bool {
	switch strings.ToLower(p) {
	case "android", "ios", "web":
		return true
	}
	return false
}

// validEnvironment checks that the environment value is accepted.
func validEnvironment(e string) bool {
	switch strings.ToLower(e) {
	case "qa", "production":
		return true
	}
	return false
}

func ptrString(s *string) *string {
	if s == nil {
		return nil
	}
	return s
}
