package merchantanalytics

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"

	"grepmind-near/backend/pkg/database"
)

var (
	ErrForbidden = errors.New("customer view is not permitted")
	ErrNotFound  = errors.New("business not found")
	ErrInvalid   = errors.New("invalid view event")
)

const (
	ViewProfile = "profile"
	ViewCatalog = "catalog"
)

type Service struct {
	db     *database.DB
	secret []byte
	now    func() time.Time
}

func NewService(db *database.DB, secret string) *Service {
	return &Service{db: db, secret: []byte(secret), now: time.Now}
}

// RecordCustomerView records at most one event per signed-in customer, target
// and UTC day. The stored viewer key is an HMAC pseudonym, not a user ID.
func (s *Service) RecordCustomerView(ctx context.Context, userID, businessID, viewType string) error {
	if s.db == nil || len(s.secret) == 0 || uuid.Validate(userID) != nil || uuid.Validate(businessID) != nil || (viewType != ViewProfile && viewType != ViewCatalog) {
		return ErrInvalid
	}
	var eligible bool
	err := s.db.QueryRowxContext(ctx, `
		SELECT EXISTS (SELECT 1 FROM user_roles WHERE user_id = $1 AND role = 'customer')
	`, userID).Scan(&eligible)
	if err != nil {
		return fmt.Errorf("check view eligibility: %w", err)
	}
	var businessEligible, isBusinessMember bool
	if err := s.db.QueryRowxContext(ctx, `
		SELECT EXISTS (
		    SELECT 1 FROM businesses b
		    WHERE b.id = $1 AND b.status = 'approved'
		      AND ($3 <> 'catalog' OR EXISTS (
		          SELECT 1 FROM products p WHERE p.business_id = b.id
		            AND p.is_published = true AND p.stock_status <> 'out_of_stock'
		      ))
		), EXISTS (
		    SELECT 1 FROM businesses b
		    WHERE b.id = $1 AND (
		        b.owner_user_id = $2 OR EXISTS (
		            SELECT 1 FROM business_members bm WHERE bm.business_id = b.id
		              AND bm.user_id = $2 AND bm.status = 'active'
		        )
		    )
		)
	`, businessID, userID, viewType).Scan(&businessEligible, &isBusinessMember); err != nil {
		return fmt.Errorf("check public business: %w", err)
	}
	if !businessEligible {
		return ErrNotFound
	}
	if !eligible || isBusinessMember {
		return ErrForbidden
	}
	day := s.now().UTC().Format("2006-01-02")
	mac := hmac.New(sha256.New, s.secret)
	_, _ = mac.Write([]byte(userID))
	fingerprint := mac.Sum(nil)
	_, err = s.db.ExecContext(ctx, `
		INSERT INTO merchant_view_events (business_id, view_type, view_date, viewer_fingerprint)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (business_id, view_type, view_date, viewer_fingerprint) DO NOTHING
	`, businessID, viewType, day, fingerprint)
	if err != nil {
		return fmt.Errorf("record customer view: %w", err)
	}
	return nil
}

type Summary struct {
	ProfileViews30D int64 `json:"profile_views_30d"`
	CatalogViews30D int64 `json:"product_catalog_views_30d"`
	TotalViews30D   int64 `json:"total_views"`
	PeriodDays      int   `json:"views_period_days"`
}

func (s *Service) Summary(ctx context.Context, businessID string) (Summary, error) {
	if s.db == nil || uuid.Validate(businessID) != nil {
		return Summary{}, ErrInvalid
	}
	var summary Summary
	err := s.db.QueryRowxContext(ctx, `
		SELECT count(*) FILTER (WHERE view_type = 'profile'),
		       count(*) FILTER (WHERE view_type = 'catalog')
		FROM merchant_view_events
		WHERE business_id = $1 AND view_date >= (now() AT TIME ZONE 'UTC')::date - 29
	`, businessID).Scan(&summary.ProfileViews30D, &summary.CatalogViews30D)
	if err != nil {
		return Summary{}, fmt.Errorf("load merchant view summary: %w", err)
	}
	summary.TotalViews30D = summary.ProfileViews30D + summary.CatalogViews30D
	summary.PeriodDays = 30
	return summary, nil
}
