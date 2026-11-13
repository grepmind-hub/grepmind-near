package deliverydispatch

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jmoiron/sqlx"
	"grepmind-near/backend/internal/notifications"
	"grepmind-near/backend/pkg/config"
	"grepmind-near/backend/pkg/database"
)

const defaultOfferTimeout = 60 * time.Second
const defaultAvailabilityLease = 90 * time.Second

type Service struct {
	db                    *database.DB
	hub                   *notifications.Hub
	enabled               bool
	offerTimeout          time.Duration
	availabilityLease     time.Duration
	verificationKey       [32]byte
	completionRecorder    func(context.Context, *sqlx.Tx, string, string) error
	codCollectionRecorder func(context.Context, *sqlx.Tx, string, string) error
	// beforeHeartbeatLeaseUpdate is a nil-by-default synchronization hook used
	// only by package integration tests to control the lease-expiry boundary.
	beforeHeartbeatLeaseUpdate func()
	beforeProcessExpiredOffers func()
}

func (s *Service) SetCODCollectionRecorder(recorder func(context.Context, *sqlx.Tx, string, string) error) {
	s.codCollectionRecorder = recorder
}

func NewService(db *database.DB, hub *notifications.Hub, cfg *config.Config, completionRecorder ...func(context.Context, *sqlx.Tx, string, string) error) *Service {
	offerTimeout, lease := defaultOfferTimeout, defaultAvailabilityLease
	enabled := false
	if cfg != nil {
		enabled = cfg.RiderDispatchEnabled
		if cfg.RiderOfferTimeout >= 10*time.Second && cfg.RiderOfferTimeout <= 10*time.Minute {
			offerTimeout = cfg.RiderOfferTimeout
		}
		if cfg.RiderAvailabilityLease >= 30*time.Second && cfg.RiderAvailabilityLease <= 5*time.Minute {
			lease = cfg.RiderAvailabilityLease
		}
	}
	key := sha256.Sum256([]byte("grepmind-near/delivery-verification/v1:" + configSecret(cfg)))
	s := &Service{db: db, hub: hub, enabled: enabled, offerTimeout: offerTimeout, availabilityLease: lease, verificationKey: key}
	if len(completionRecorder) > 0 {
		s.completionRecorder = completionRecorder[0]
	}
	return s
}

func configSecret(cfg *config.Config) string {
	if cfg == nil {
		return ""
	}
	return cfg.JWTSecret
}

type apiFailure struct {
	status  int
	code    string
	message string
}

func (e *apiFailure) Error() string { return e.message }
func failure(status int, code, message string) error {
	return &apiFailure{status: status, code: code, message: message}
}

type riderItem struct {
	ProductName string `json:"product_name" db:"product_name"`
	VariantName string `json:"variant_name" db:"variant_name"`
	UnitLabel   string `json:"unit_label" db:"unit_label"`
	Quantity    int    `json:"quantity" db:"quantity"`
}

type offer struct {
	ID                  string      `json:"id" db:"id"`
	JobID               string      `json:"job_id" db:"job_id"`
	OrderID             string      `json:"order_id" db:"order_id"`
	ReferenceCode       string      `json:"reference_code" db:"reference_code"`
	Vertical            string      `json:"vertical" db:"platform_vertical"`
	PickupBusiness      string      `json:"pickup_business" db:"pickup_business"`
	PickupAddress       string      `json:"pickup_address" db:"pickup_address"`
	PickupLocality      string      `json:"pickup_locality" db:"pickup_locality"`
	DestinationLocality string      `json:"destination_locality" db:"destination_locality"`
	DestinationDistrict string      `json:"destination_district" db:"destination_district"`
	PaymentMethod       string      `json:"payment_method" db:"payment_method"`
	PaymentStatus       string      `json:"payment_status" db:"payment_status"`
	CODAmountMinor      int64       `json:"cod_amount_minor" db:"cod_amount_minor"`
	CODCollectionState  string      `json:"cod_collection_state" db:"cod_collection_state"`
	ExpiresAt           string      `json:"expires_at" db:"expires_at"`
	Items               []riderItem `json:"items" db:"-"`
}

type assignment struct {
	JobID               string      `json:"job_id" db:"job_id"`
	OrderID             string      `json:"order_id" db:"order_id"`
	ReferenceCode       string      `json:"reference_code" db:"reference_code"`
	Vertical            string      `json:"vertical" db:"platform_vertical"`
	PickupBusiness      string      `json:"pickup_business" db:"pickup_business"`
	PickupAddress       string      `json:"pickup_address" db:"pickup_address"`
	PickupLocality      string      `json:"pickup_locality" db:"pickup_locality"`
	DestinationLocality string      `json:"destination_locality" db:"destination_locality"`
	DestinationDistrict string      `json:"destination_district" db:"destination_district"`
	AssignedAt          string      `json:"assigned_at" db:"assigned_at"`
	ExecutionState      string      `json:"execution_state" db:"execution_state"`
	PaymentMethod       string      `json:"payment_method" db:"payment_method"`
	PaymentStatus       string      `json:"payment_status" db:"payment_status"`
	CODAmountMinor      int64       `json:"cod_amount_minor" db:"cod_amount_minor"`
	CODCollectionState  string      `json:"cod_collection_state" db:"cod_collection_state"`
	DestinationAddress  string      `json:"destination_address,omitempty" db:"destination_address"`
	RecipientName       string      `json:"recipient_name,omitempty" db:"recipient_name"`
	ContactPhone        string      `json:"contact_phone,omitempty" db:"contact_phone"`
	Items               []riderItem `json:"items" db:"-"`
}

type eligibleRider struct {
	UserID          string  `json:"user_id" db:"user_id"`
	DisplayName     string  `json:"display_name" db:"display_name"`
	VehicleType     string  `json:"vehicle_type" db:"vehicle_type"`
	Locality        string  `json:"locality" db:"locality"`
	AssignmentCount int     `json:"assignment_count" db:"assignment_count"`
	LastAssignedAt  *string `json:"last_assigned_at,omitempty" db:"last_assigned_at"`
}

func (s *Service) Enabled() bool { return s != nil && s.enabled }

// Start runs the PostgreSQL-backed offer/lease sweeper. Delivery records remain
// authoritative in SQL, so another API process can safely run the same loop.
func (s *Service) Start(ctx context.Context) {
	if s == nil || !s.enabled {
		return
	}
	go func() {
		ticker := time.NewTicker(2 * time.Second)
		defer ticker.Stop()
		for {
			if err := s.Process(ctx); err != nil {
				var hasSchema bool
				if schemaErr := s.db.GetContext(ctx, &hasSchema, `SELECT to_regclass('delivery_jobs') IS NOT NULL`); schemaErr == nil && hasSchema {
					log.Printf("delivery dispatch cycle failed: %v", err)
				}
			}
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
			}
		}
	}()
}

func (s *Service) requireEnabled(w http.ResponseWriter) bool {
	if s == nil || !s.enabled {
		writeError(w, http.StatusServiceUnavailable, "DISPATCH_DISABLED", "Rider dispatch is disabled in this environment.")
		return false
	}
	return true
}

func (s *Service) Process(ctx context.Context) error {
	var expired []string
	if _, err := s.db.ExecContext(ctx, `WITH expired AS (
		UPDATE rider_availability_sessions SET is_online=false,updated_at=now()
		WHERE is_online AND lease_expires_at<=now() RETURNING rider_user_id
	) INSERT INTO rider_availability_events(rider_user_id,event_type)
	SELECT rider_user_id,'lease_expired' FROM expired`); err != nil {
		return err
	}
	if err := s.recordStaleAssignments(ctx); err != nil {
		return err
	}
	if s.beforeProcessExpiredOffers != nil {
		s.beforeProcessExpiredOffers()
	}
	if err := s.db.SelectContext(ctx, &expired, `SELECT DISTINCT job_id::text FROM delivery_offers WHERE state='offered' AND expires_at<=now() ORDER BY job_id LIMIT 100`); err != nil {
		return err
	}
	var pending []string
	if err := s.db.SelectContext(ctx, &pending, `SELECT id::text FROM delivery_jobs WHERE state='pending_dispatch' ORDER BY created_at,id LIMIT 100`); err != nil {
		return err
	}
	// A job that exhausted its rider pool must be reconsidered when eligible
	// capacity returns. Limit this recovery scan to the oldest job that has at
	// least one currently eligible rider; otherwise every sweep would create a
	// new exhausted dispatch run while no rider is available.
	var newlyEligible []string
	if err := s.db.SelectContext(ctx, &newlyEligible, eligibleNoRiderJobsSQL); err != nil {
		return err
	}
	seen := make(map[string]bool, len(expired)+len(pending)+len(newlyEligible))
	for _, id := range expired {
		seen[id] = true
	}
	for _, id := range pending {
		seen[id] = true
	}
	for _, id := range newlyEligible {
		seen[id] = true
	}
	for id := range seen {
		if err := s.advanceJob(ctx, id); err != nil && !errors.Is(err, sql.ErrNoRows) {
			return err
		}
	}
	return nil
}

func (s *Service) advanceJob(ctx context.Context, jobID string) error {
	var newOffer *offer
	var customerID, businessID string
	var newOfferRider string
	var dispatchStarted, dispatchExhausted, expiredOffer bool
	err := s.db.Transaction(ctx, func(tx *sqlx.Tx) error {
		var state, orderID, localityID, orderSource, paymentMethod, paymentStatus string
		var hasCODObligation bool
		if err := tx.QueryRowxContext(ctx, `SELECT j.state,j.order_id::text,j.locality_id::text,COALESCE(o.order_source,''),COALESCE(o.payment_method,''),COALESCE(o.payment_status,''),EXISTS(SELECT 1 FROM cod_obligations c WHERE c.order_id=o.id) FROM delivery_jobs j JOIN customer_orders o ON o.id=j.order_id WHERE j.id=$1 FOR UPDATE OF j,o`, jobID).Scan(&state, &orderID, &localityID, &orderSource, &paymentMethod, &paymentStatus, &hasCODObligation); err != nil {
			return err
		}
		if !dispatchPaymentEligible(orderSource, paymentMethod, paymentStatus, hasCODObligation) {
			return nil
		}
		if err := tx.QueryRowxContext(ctx, `SELECT customer_user_id::text,business_id::text FROM customer_orders WHERE id=$1`, orderID).Scan(&customerID, &businessID); err != nil {
			return err
		}
		if state == "assigned" || state == "cancelled" {
			return nil
		}
		var activeOfferID, activeRider string
		var expires time.Time
		err := tx.QueryRowxContext(ctx, `SELECT id::text,rider_user_id::text,expires_at FROM delivery_offers WHERE job_id=$1 AND state='offered' FOR UPDATE`, jobID).Scan(&activeOfferID, &activeRider, &expires)
		if err == nil {
			if expires.After(time.Now().UTC()) {
				return nil
			}
			if _, err := tx.ExecContext(ctx, `UPDATE delivery_offers SET state='expired',responded_at=now() WHERE id=$1 AND state='offered'`, activeOfferID); err != nil {
				return err
			}
			if _, err := tx.ExecContext(ctx, `INSERT INTO delivery_events(job_id,event_type,offer_id,metadata) VALUES($1,'offer_expired',$2,'{}')`, jobID, activeOfferID); err != nil {
				return err
			}
			expiredOffer = true
		} else if !errors.Is(err, sql.ErrNoRows) {
			return err
		}

		var runID string
		var runNumber int
		err = tx.QueryRowxContext(ctx, `SELECT id::text,run_number FROM delivery_dispatch_runs WHERE job_id=$1 AND state='searching' FOR UPDATE`, jobID).Scan(&runID, &runNumber)
		if errors.Is(err, sql.ErrNoRows) {
			if _, err := tx.ExecContext(ctx, `UPDATE delivery_jobs SET state='pending_dispatch',updated_at=now() WHERE id=$1`, jobID); err != nil {
				return err
			}
			if err := tx.QueryRowxContext(ctx, `INSERT INTO delivery_dispatch_runs(job_id,run_number) VALUES($1,COALESCE((SELECT max(run_number)+1 FROM delivery_dispatch_runs WHERE job_id=$1),1)) RETURNING id::text,run_number`, jobID).Scan(&runID, &runNumber); err != nil {
				return err
			}
			if _, err := tx.ExecContext(ctx, `INSERT INTO delivery_events(job_id,event_type) VALUES($1,'dispatch_started')`, jobID); err != nil {
				return err
			}
			dispatchStarted = true
		} else if err != nil {
			return err
		}

		var candidate eligibleRider
		err = tx.QueryRowxContext(ctx, `SELECT p.user_id::text,p.display_name,p.vehicle_type,l.name,
			(SELECT count(*)::int FROM delivery_assignments a WHERE a.rider_user_id=p.user_id),
			(SELECT max(a.assigned_at)::text FROM delivery_assignments a WHERE a.rider_user_id=p.user_id)
			FROM rider_profiles p
			JOIN users u ON u.id=p.user_id AND u.status='active'
			JOIN user_roles ur ON ur.user_id=p.user_id AND ur.role='rider'
			JOIN rider_profile_localities rl ON rl.rider_profile_id=p.id AND rl.locality_id=$1 AND rl.status='approved'
			JOIN platform_delivery_localities l ON l.id=rl.locality_id AND l.is_active AND l.delivery_enabled
			JOIN rider_availability_sessions av ON av.rider_user_id=p.user_id AND av.is_online AND av.lease_expires_at>now()
			WHERE p.status='approved'
			AND NOT EXISTS (SELECT 1 FROM delivery_assignments a WHERE a.rider_user_id=p.user_id AND a.state='active')
			AND NOT EXISTS (SELECT 1 FROM delivery_offers x WHERE x.rider_user_id=p.user_id AND x.state='offered')
			AND NOT EXISTS (SELECT 1 FROM delivery_offers x WHERE x.dispatch_run_id=$2 AND x.rider_user_id=p.user_id)
			AND NOT EXISTS (SELECT 1 FROM rider_document_requirements q WHERE q.is_active AND q.is_required AND q.vehicle_type IN ('any',p.vehicle_type)
				AND NOT EXISTS (SELECT 1 FROM rider_documents d WHERE d.rider_profile_id=p.id AND d.requirement_id=q.id AND d.review_status='accepted'))
			ORDER BY (SELECT count(*) FROM delivery_assignments a WHERE a.rider_user_id=p.user_id),
				(SELECT max(a.assigned_at) FROM delivery_assignments a WHERE a.rider_user_id=p.user_id) ASC NULLS FIRST,p.user_id
			LIMIT 1 FOR UPDATE OF p,av,u,ur SKIP LOCKED`, localityID, runID).Scan(&candidate.UserID, &candidate.DisplayName, &candidate.VehicleType, &candidate.Locality, &candidate.AssignmentCount, &candidate.LastAssignedAt)
		if errors.Is(err, sql.ErrNoRows) {
			if _, err := tx.ExecContext(ctx, `UPDATE delivery_dispatch_runs SET state='no_rider_available',completed_at=now() WHERE id=$1 AND state='searching'`, runID); err != nil {
				return err
			}
			if _, err := tx.ExecContext(ctx, `UPDATE delivery_jobs SET state='no_rider_available',updated_at=now() WHERE id=$1`, jobID); err != nil {
				return err
			}
			_, err = tx.ExecContext(ctx, `INSERT INTO delivery_events(job_id,event_type,metadata) VALUES($1,'dispatch_exhausted',jsonb_build_object('run_number',$2::integer))`, jobID, runNumber)
			dispatchExhausted = true
			return err
		}
		if err != nil {
			return err
		}
		var candidateOfferID, candidateOfferExpiry string
		var offerSequence int
		if err := tx.QueryRowxContext(ctx, `INSERT INTO delivery_offers(job_id,dispatch_run_id,rider_user_id,sequence,expires_at)
			VALUES($1,$2,$3,COALESCE((SELECT max(sequence)+1 FROM delivery_offers WHERE dispatch_run_id=$2),1),now()+($4 * interval '1 second'))
			RETURNING id::text,expires_at::text,sequence`, jobID, runID, candidate.UserID, int(s.offerTimeout.Seconds())).Scan(&candidateOfferID, &candidateOfferExpiry, &offerSequence); err != nil {
			return err
		}
		newOffer = &offer{ID: candidateOfferID, JobID: jobID, OrderID: orderID, ExpiresAt: candidateOfferExpiry}
		if _, err := tx.ExecContext(ctx, `UPDATE delivery_jobs SET state='offered',updated_at=now() WHERE id=$1`, jobID); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO delivery_events(job_id,event_type,offer_id,metadata) VALUES($1,'offer_issued',$2,jsonb_build_object('run_number',$3::int,'sequence',$4::int))`, jobID, newOffer.ID, runNumber, offerSequence); err != nil {
			return err
		}
		newOffer.Items = nil
		newOfferRider = candidate.UserID
		return nil
	})
	if err != nil {
		// Another API worker may have claimed the same rider for a different job.
		// The unique active-offer index resolves that race; a later cycle retries.
		if strings.Contains(strings.ToLower(err.Error()), "unique") {
			return nil
		}
		return err
	}
	if dispatchStarted {
		s.publishScoped(ctx, customerID, businessID, jobID, "delivery.job_created", "Delivery dispatch started", "Your partner started preparing this order; Grepmind is checking rider availability.")
	}
	if expiredOffer {
		s.publishScoped(ctx, customerID, businessID, jobID, "delivery.offer_expired", "Rider offer expired", "A rider did not respond before the offer expired.")
	}
	if newOffer != nil && s.hub != nil {
		s.hub.Publish(ctx, notifications.Event{Type: "delivery.offer", UserID: newOfferRider, Title: "Delivery offer available", Body: "A delivery offer is waiting for your response.", Payload: map[string]any{"offer_id": newOffer.ID, "job_id": jobID, "expires_at": newOffer.ExpiresAt}})
		s.publishScoped(ctx, customerID, businessID, jobID, "delivery.dispatch", "Rider dispatch update", "A rider offer has been issued.")
	}
	if dispatchExhausted {
		s.publishScoped(ctx, customerID, businessID, jobID, "delivery.exception", "No rider available yet", "No approved rider is currently available for this locality.")
	}
	return nil
}

// NOTE: These are set per advance call only after the database transaction
// writes the offer. They are local variables declared below through closures.

func (s *Service) SetAvailability(w http.ResponseWriter, r *http.Request, riderID string) {
	if !s.requireEnabled(w) {
		return
	}
	var in struct {
		Online bool `json:"online"`
	}
	if decodeBody(w, r, &in, 2048) != nil {
		writeError(w, 400, "VALIDATION_ERROR", "Provide an online boolean.")
		return
	}
	var jobs []string
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := requireActiveRider(r.Context(), tx, riderID, ""); err != nil {
			return err
		}
		if in.Online {
			if err := riderEligibleForAvailability(r.Context(), tx, riderID); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `INSERT INTO rider_availability_sessions(rider_user_id,is_online,lease_expires_at,last_heartbeat_at)
				VALUES($1,true,now()+($2 * interval '1 second'),now()) ON CONFLICT(rider_user_id) DO UPDATE SET is_online=true,lease_expires_at=EXCLUDED.lease_expires_at,last_heartbeat_at=now(),updated_at=now()`, riderID, int(s.availabilityLease.Seconds())); err != nil {
				return err
			}
			_, err := tx.ExecContext(r.Context(), `INSERT INTO rider_availability_events(rider_user_id,event_type) VALUES($1,'online')`, riderID)
			return err
		}
		if err := tx.SelectContext(r.Context(), &jobs, `SELECT job_id::text FROM delivery_offers WHERE rider_user_id=$1 AND state='offered' FOR UPDATE`, riderID); err != nil {
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `WITH changed AS (
			UPDATE delivery_offers SET state='declined',responded_at=now() WHERE rider_user_id=$1 AND state='offered' RETURNING id,job_id
		) INSERT INTO delivery_events(job_id,event_type,offer_id,actor_user_id,reason)
		SELECT job_id,'offer_declined',id,$1,'Rider went offline' FROM changed`, riderID); err != nil {
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE rider_availability_sessions SET is_online=false,updated_at=now() WHERE rider_user_id=$1`, riderID); err != nil {
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO rider_availability_sessions(rider_user_id,is_online) VALUES($1,false) ON CONFLICT(rider_user_id) DO NOTHING`, riderID); err != nil {
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO rider_availability_events(rider_user_id,event_type) VALUES($1,'offline')`, riderID); err != nil {
			return err
		}
		return nil
	})
	if err != nil {
		writeFailure(w, err)
		return
	}
	if in.Online {
		// Reconcile immediately so a rider who just came online can receive an
		// offer without waiting for the next background sweep.
		if err := s.Process(r.Context()); err != nil {
			writeError(w, 500, "INTERNAL_ERROR", "Availability changed, but dispatch could not be advanced.")
			return
		}
	}
	for _, jobID := range jobs {
		if err := s.advanceJob(r.Context(), jobID); err != nil {
			writeError(w, 500, "INTERNAL_ERROR", "Availability changed, but dispatch could not be advanced.")
			return
		}
	}
	writeJSON(w, 200, map[string]any{"data": map[string]any{"online": in.Online, "lease_seconds": int(s.availabilityLease.Seconds())}})
}

func (s *Service) Heartbeat(w http.ResponseWriter, r *http.Request, riderID string) {
	if !s.requireEnabled(w) {
		return
	}
	var active bool
	err := s.db.GetContext(r.Context(), &active, `SELECT EXISTS(SELECT 1 FROM rider_availability_sessions WHERE rider_user_id=$1 AND is_online AND lease_expires_at>now())`, riderID)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to refresh rider availability.")
		return
	}
	if !active {
		writeError(w, 409, "AVAILABILITY_EXPIRED", "Your online session expired. Go online again to receive offers.")
		return
	}
	if err := riderCanMaintainAvailabilityDB(r.Context(), s.db, riderID); err != nil {
		writeFailure(w, err)
		return
	}
	if s.beforeHeartbeatLeaseUpdate != nil {
		s.beforeHeartbeatLeaseUpdate()
	}
	res, err := s.db.ExecContext(r.Context(), `UPDATE rider_availability_sessions SET lease_expires_at=now()+($2 * interval '1 second'),last_heartbeat_at=now(),updated_at=now() WHERE rider_user_id=$1 AND is_online AND lease_expires_at>now()`, riderID, int(s.availabilityLease.Seconds()))
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to refresh rider availability.")
		return
	}
	updated, err := res.RowsAffected()
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to confirm rider availability.")
		return
	}
	if updated != 1 {
		writeError(w, 409, "AVAILABILITY_EXPIRED", "Your online session expired. Go online again to receive offers.")
		return
	}
	writeJSON(w, 200, map[string]any{"data": map[string]any{"online": true, "lease_seconds": int(s.availabilityLease.Seconds())}})
}

func (s *Service) Availability(w http.ResponseWriter, r *http.Request, riderID string) {
	if !s.requireEnabled(w) {
		return
	}
	var out struct {
		Online         bool    `db:"online" json:"online"`
		LeaseExpiresAt *string `db:"lease_expires_at" json:"lease_expires_at"`
	}
	err := s.db.GetContext(r.Context(), &out, `SELECT COALESCE(is_online AND lease_expires_at>now(),false) online,CASE WHEN is_online AND lease_expires_at>now() THEN lease_expires_at::text END lease_expires_at FROM rider_availability_sessions WHERE rider_user_id=$1`, riderID)
	if errors.Is(err, sql.ErrNoRows) {
		writeJSON(w, 200, map[string]any{"data": map[string]any{"online": false}})
		return
	}
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load availability.")
		return
	}
	writeJSON(w, 200, map[string]any{"data": out})
}

func (s *Service) Offers(w http.ResponseWriter, r *http.Request, riderID string) {
	if !s.requireEnabled(w) {
		return
	}
	if err := s.Process(r.Context()); err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to refresh rider offers.")
		return
	}
	rows, err := s.db.QueryxContext(r.Context(), offerSelect+` WHERE x.rider_user_id=$1 AND x.state='offered' AND x.expires_at>now() ORDER BY x.expires_at`, riderID)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load rider offers.")
		return
	}
	defer rows.Close()
	result := make([]offer, 0)
	for rows.Next() {
		var value offer
		if err := rows.StructScan(&value); err != nil {
			writeError(w, 500, "INTERNAL_ERROR", "Unable to read rider offers.")
			return
		}
		if err := s.loadOfferItems(r.Context(), &value); err != nil {
			writeError(w, 500, "INTERNAL_ERROR", "Unable to read offer items.")
			return
		}
		result = append(result, value)
	}
	if err := rows.Err(); err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to read rider offers.")
		return
	}
	writeJSON(w, 200, map[string]any{"data": result})
}

const offerSelect = `SELECT x.id::text id,j.id::text job_id,o.id::text order_id,o.reference_code,o.platform_vertical,
	b.name pickup_business,b.address_text pickup_address,COALESCE(b.locality,b.city,'') pickup_locality,dl.name destination_locality,d.name destination_district,
	COALESCE(o.payment_method,'') payment_method,COALESCE(o.payment_status,'') payment_status,
	COALESCE((SELECT ob.amount_minor FROM cod_obligations ob WHERE ob.order_id=o.id),0) cod_amount_minor,
	CASE WHEN EXISTS(SELECT 1 FROM cod_collections c WHERE c.order_id=o.id) THEN 'collected' WHEN EXISTS(SELECT 1 FROM cod_obligations ob WHERE ob.order_id=o.id) THEN 'due' ELSE 'not_applicable' END cod_collection_state,
	x.expires_at::text expires_at
	FROM delivery_offers x JOIN delivery_jobs j ON j.id=x.job_id JOIN customer_orders o ON o.id=j.order_id
	JOIN businesses b ON b.id=j.business_id JOIN platform_delivery_localities l ON l.id=j.locality_id JOIN platform_districts d ON d.id=l.district_id
	JOIN platform_delivery_localities dl ON dl.id=j.locality_id`

func (s *Service) GetOffer(w http.ResponseWriter, r *http.Request, riderID string) {
	if !s.requireEnabled(w) {
		return
	}
	var value offer
	err := s.db.GetContext(r.Context(), &value, offerSelect+` WHERE x.id=$1 AND x.rider_user_id=$2`, r.PathValue("offerId"), riderID)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, 404, "NOT_FOUND", "Rider offer not found.")
		return
	}
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load rider offer.")
		return
	}
	if err := s.loadOfferItems(r.Context(), &value); err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load rider offer items.")
		return
	}
	writeJSON(w, 200, map[string]any{"data": value})
}

func (s *Service) loadOfferItems(ctx context.Context, value *offer) error {
	value.Items = make([]riderItem, 0)
	return s.db.SelectContext(ctx, &value.Items, `SELECT product_name,variant_name,unit_label,quantity FROM platform_customer_order_items WHERE order_id=$1 ORDER BY product_name,variant_name`, value.OrderID)
}

func (s *Service) RespondOffer(w http.ResponseWriter, r *http.Request, riderID, decision string) {
	if !s.requireEnabled(w) {
		return
	}
	offerID := r.PathValue("offerId")
	var in struct {
		Reason string `json:"reason"`
	}
	if decision == "decline" && r.Body != nil && r.ContentLength != 0 {
		if decodeBody(w, r, &in, 2048) != nil {
			writeError(w, 400, "VALIDATION_ERROR", "Invalid decline reason.")
			return
		}
		in.Reason = strings.TrimSpace(in.Reason)
		if in.Reason != "" && (len([]rune(in.Reason)) < 10 || len([]rune(in.Reason)) > 500) {
			writeError(w, 400, "VALIDATION_ERROR", "Decline reason must be between 10 and 500 characters.")
			return
		}
	}
	var jobID, customerID, businessID string
	var expired bool
	var alreadyAccepted bool
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		// Match advanceJob's job-then-offer lock order. Expiry processing holds
		// the job row before the offer row; locking the offer first here can
		// deadlock when the expiry event's foreign key needs a key-share lock on
		// that job.
		if err := tx.GetContext(r.Context(), &jobID, `SELECT job_id::text FROM delivery_offers WHERE id=$1 AND rider_user_id=$2`, offerID, riderID); errors.Is(err, sql.ErrNoRows) {
			return failure(404, "NOT_FOUND", "Rider offer not found.")
		} else if err != nil {
			return err
		}
		var lockedJobID string
		if err := tx.GetContext(r.Context(), &lockedJobID, `SELECT id::text FROM delivery_jobs WHERE id=$1 FOR UPDATE`, jobID); err != nil {
			return err
		}
		var state string
		var exp time.Time
		err := tx.QueryRowxContext(r.Context(), `SELECT x.state,x.expires_at,x.job_id::text,o.customer_user_id::text,o.business_id::text FROM delivery_offers x JOIN customer_orders o ON o.id=(SELECT order_id FROM delivery_jobs WHERE id=x.job_id) WHERE x.id=$1 AND x.rider_user_id=$2 FOR UPDATE OF x`, offerID, riderID).Scan(&state, &exp, &jobID, &customerID, &businessID)
		if errors.Is(err, sql.ErrNoRows) {
			return failure(404, "NOT_FOUND", "Rider offer not found.")
		}
		if err != nil {
			return err
		}
		if state == "accepted" && decision == "accept" {
			alreadyAccepted = true
			return nil
		}
		if state != "offered" {
			return failure(409, "OFFER_CLOSED", "This offer is no longer active.")
		}
		if !exp.After(time.Now().UTC()) {
			expired = true
			if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_offers SET state='expired',responded_at=now() WHERE id=$1 AND state='offered'`, offerID); err != nil {
				return err
			}
			_, err := tx.ExecContext(r.Context(), `INSERT INTO delivery_events(job_id,event_type,offer_id) VALUES($1,'offer_expired',$2)`, jobID, offerID)
			return err
		}
		if err := requireActiveRider(r.Context(), tx, riderID, ""); err != nil {
			return err
		}
		if decision == "accept" {
			var orderSource, paymentMethod, paymentStatus string
			var hasCODObligation bool
			if err := tx.QueryRowxContext(r.Context(), `SELECT COALESCE(o.order_source,''),COALESCE(o.payment_method,''),COALESCE(o.payment_status,''),EXISTS(SELECT 1 FROM cod_obligations c WHERE c.order_id=o.id) FROM customer_orders o JOIN delivery_jobs j ON j.order_id=o.id WHERE j.id=$1 FOR UPDATE OF o`, jobID).Scan(&orderSource, &paymentMethod, &paymentStatus, &hasCODObligation); err != nil {
				return err
			}
			if !dispatchPaymentEligible(orderSource, paymentMethod, paymentStatus, hasCODObligation) {
				return failure(409, "PAYMENT_NOT_VERIFIED", "This delivery offer cannot be accepted until the order payment is eligible and verified.")
			}
			if err := riderEligibleForAcceptance(r.Context(), tx, riderID, offerID); err != nil {
				return err
			}
			var locality string
			if err := tx.GetContext(r.Context(), &locality, `SELECT locality_id::text FROM delivery_jobs WHERE id=$1`, jobID); err != nil {
				return err
			}
			if err := checkRiderLocality(r.Context(), tx, riderID, locality); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_offers SET state='accepted',responded_at=now() WHERE id=$1 AND state='offered'`, offerID); err != nil {
				return err
			}
			var assignmentID string
			if err := tx.QueryRowxContext(r.Context(), `INSERT INTO delivery_assignments(job_id,rider_user_id,offer_id) VALUES($1,$2,$3) RETURNING id::text`, jobID, riderID, offerID).Scan(&assignmentID); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_dispatch_runs SET state='assigned',completed_at=now() WHERE id=(SELECT dispatch_run_id FROM delivery_offers WHERE id=$1)`, offerID); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_jobs SET state='assigned',updated_at=now() WHERE id=$1`, jobID); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `INSERT INTO delivery_events(job_id,event_type,offer_id,assignment_id,actor_user_id) VALUES($1,'offer_accepted',$2,$3,$4),($1,'rider_assigned',$2,$3,$4)`, jobID, offerID, assignmentID, riderID); err != nil {
				return err
			}
			_, err := tx.ExecContext(r.Context(), `INSERT INTO audit_logs(actor_user_id,action,target_type,target_id) VALUES($1,'delivery.rider_accepted','delivery_job',$2)`, riderID, jobID)
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_offers SET state='declined',responded_at=now() WHERE id=$1`, offerID); err != nil {
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO delivery_events(job_id,event_type,offer_id,actor_user_id,reason) VALUES($1,'offer_declined',$2,$3,NULLIF($4,''))`, jobID, offerID, riderID, in.Reason); err != nil {
			return err
		}
		_, err = tx.ExecContext(r.Context(), `UPDATE delivery_jobs SET state='pending_dispatch',updated_at=now() WHERE id=$1 AND state='offered'`, jobID)
		return err
	})
	if err != nil {
		writeFailure(w, err)
		return
	}
	if alreadyAccepted {
		writeJSON(w, 200, map[string]any{"data": map[string]any{"offer_id": offerID, "decision": decision, "idempotent": true}})
		return
	}
	if expired {
		s.publishScoped(r.Context(), customerID, businessID, jobID, "delivery.offer_expired", "Rider offer expired", "A rider did not respond before the offer expired.")
		if err := s.advanceJob(r.Context(), jobID); err != nil {
			writeError(w, 500, "INTERNAL_ERROR", "The offer expired, but dispatch could not be advanced.")
			return
		}
		writeError(w, 409, "OFFER_EXPIRED", "This offer has expired and cannot be accepted.")
		return
	}
	if decision == "decline" {
		s.publishScoped(r.Context(), customerID, businessID, jobID, "delivery.offer_declined", "Rider declined offer", "The rider declined; Grepmind is checking the next eligible rider.")
		if err := s.advanceJob(r.Context(), jobID); err != nil {
			writeError(w, 500, "INTERNAL_ERROR", "The offer was declined, but dispatch could not be advanced.")
			return
		}
	} else {
		s.publishAssignment(r.Context(), customerID, businessID, jobID)
	}
	writeJSON(w, 200, map[string]any{"data": map[string]any{"offer_id": offerID, "decision": decision}})
}

func (s *Service) ActiveAssignment(w http.ResponseWriter, r *http.Request, riderID string) {
	if !s.requireEnabled(w) {
		return
	}
	var value assignment
	err := s.db.GetContext(r.Context(), &value, assignmentSelect+` WHERE a.rider_user_id=$1 AND a.state='active'`, riderID)
	if errors.Is(err, sql.ErrNoRows) {
		writeJSON(w, 200, map[string]any{"data": nil})
		return
	}
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load active rider assignment.")
		return
	}
	value.Items = make([]riderItem, 0)
	if err := s.db.SelectContext(r.Context(), &value.Items, `SELECT product_name,variant_name,unit_label,quantity FROM platform_customer_order_items WHERE order_id=$1 ORDER BY product_name,variant_name`, value.OrderID); err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load assignment items.")
		return
	}
	writeJSON(w, 200, map[string]any{"data": value})
}

const assignmentSelect = `SELECT j.id::text job_id,o.id::text order_id,o.reference_code,o.platform_vertical,b.name pickup_business,b.address_text pickup_address,
	COALESCE(b.locality,b.city,'') pickup_locality,l.name destination_locality,d.name destination_district,a.assigned_at::text assigned_at,j.execution_state,
	concat_ws(', ',o.delivery_address_snapshot->>'address_line1',o.delivery_address_snapshot->>'locality',o.delivery_address_snapshot->>'landmark',o.delivery_address_snapshot->>'city',o.delivery_address_snapshot->>'state',o.delivery_address_snapshot->>'postal_code') destination_address,
	COALESCE(o.delivery_address_snapshot->>'recipient_name','') recipient_name,COALESCE(o.delivery_address_snapshot->>'contact_phone','') contact_phone,
	COALESCE(o.payment_method,'') payment_method,COALESCE(o.payment_status,'') payment_status,COALESCE((SELECT ob.amount_minor FROM cod_obligations ob WHERE ob.order_id=o.id),0) cod_amount_minor,
	CASE WHEN EXISTS(SELECT 1 FROM cod_collections c WHERE c.order_id=o.id) THEN 'collected' WHEN EXISTS(SELECT 1 FROM cod_obligations ob WHERE ob.order_id=o.id) THEN 'due' ELSE 'not_applicable' END cod_collection_state
	FROM delivery_assignments a JOIN delivery_jobs j ON j.id=a.job_id JOIN customer_orders o ON o.id=j.order_id JOIN businesses b ON b.id=j.business_id
	JOIN platform_delivery_localities l ON l.id=j.locality_id JOIN platform_districts d ON d.id=l.district_id`

func (s *Service) AdminBoard(w http.ResponseWriter, r *http.Request, _ string) {
	if !s.requireEnabled(w) {
		return
	}
	if err := s.Process(r.Context()); err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to refresh dispatch state.")
		return
	}
	rows, err := queryMaps(r.Context(), s.db, `SELECT j.id::text id,j.order_id::text order_id,o.reference_code,o.customer_user_id::text customer_user_id,j.business_id::text business_id,b.name business_name,
		j.locality_id::text locality_id,l.name locality,d.name district,j.state delivery_state,j.execution_state,o.status fulfillment_status,
		COALESCE(o.payment_method,'') payment_method,COALESCE(o.payment_status,'not_collected') payment_status,
		CASE WHEN EXISTS(SELECT 1 FROM cod_collections c WHERE c.order_id=o.id) THEN 'collected' WHEN EXISTS(SELECT 1 FROM cod_obligations ob WHERE ob.order_id=o.id) THEN 'due' ELSE 'not_applicable' END cod_collection_state,
		x.id::text active_offer_id,ox.display_name offered_rider_name,x.expires_at::text offer_expires_at,
		a.id::text assignment_id,ar.display_name assigned_rider_name,a.rider_user_id::text assigned_rider_user_id,j.created_at::text created_at
		FROM delivery_jobs j JOIN customer_orders o ON o.id=j.order_id JOIN businesses b ON b.id=j.business_id
		JOIN platform_delivery_localities l ON l.id=j.locality_id JOIN platform_districts d ON d.id=l.district_id
		LEFT JOIN delivery_offers x ON x.job_id=j.id AND x.state='offered' LEFT JOIN rider_profiles ox ON ox.user_id=x.rider_user_id
		LEFT JOIN LATERAL (
			SELECT da.id,da.rider_user_id FROM delivery_assignments da
			WHERE da.job_id=j.id ORDER BY da.assigned_at DESC,da.id DESC LIMIT 1
		) a ON true LEFT JOIN rider_profiles ar ON ar.user_id=a.rider_user_id
		ORDER BY CASE j.state WHEN 'no_rider_available' THEN 0 WHEN 'pending_dispatch' THEN 1 WHEN 'offered' THEN 2 WHEN 'assigned' THEN 3 ELSE 4 END,j.created_at DESC LIMIT 200`)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load dispatch board.")
		return
	}
	writeJSON(w, 200, map[string]any{"data": rows})
}

func (s *Service) EligibleRiders(w http.ResponseWriter, r *http.Request, _ string) {
	if !s.requireEnabled(w) {
		return
	}
	jobID := r.PathValue("jobId")
	var locality string
	err := s.db.GetContext(r.Context(), &locality, `SELECT locality_id::text FROM delivery_jobs WHERE id=$1`, jobID)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, 404, "NOT_FOUND", "Delivery job not found.")
		return
	}
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to inspect delivery job.")
		return
	}
	rows := make([]eligibleRider, 0)
	err = s.db.SelectContext(r.Context(), &rows, eligibleRidersSQL, locality)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to inspect eligible riders.")
		return
	}
	writeJSON(w, 200, map[string]any{"data": rows})
}

func (s *Service) AdminEvents(w http.ResponseWriter, r *http.Request, _ string) {
	if !s.requireEnabled(w) {
		return
	}
	jobID := r.PathValue("jobId")
	var exists bool
	if err := s.db.GetContext(r.Context(), &exists, `SELECT EXISTS(SELECT 1 FROM delivery_jobs WHERE id=$1)`, jobID); err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to inspect delivery job.")
		return
	}
	if !exists {
		writeError(w, 404, "NOT_FOUND", "Delivery job not found.")
		return
	}
	rows, err := queryMaps(r.Context(), s.db, `SELECT e.id::text id,e.event_type,e.actor_user_id::text actor_user_id,COALESCE(u.display_name,'System') actor_name,e.reason,e.metadata,e.created_at::text created_at
		FROM delivery_events e LEFT JOIN users u ON u.id=e.actor_user_id WHERE e.job_id=$1 ORDER BY e.created_at,e.id LIMIT 500`, jobID)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load delivery event history.")
		return
	}
	writeJSON(w, 200, map[string]any{"data": rows})
}

func (s *Service) Retry(w http.ResponseWriter, r *http.Request, adminID string) {
	if !s.requireEnabled(w) {
		return
	}
	var in struct {
		Reason string `json:"reason"`
	}
	if decodeBody(w, r, &in, 2048) != nil || len([]rune(strings.TrimSpace(in.Reason))) < 10 || len([]rune(in.Reason)) > 500 {
		writeError(w, 400, "VALIDATION_ERROR", "A retry reason of 10 to 500 characters is required.")
		return
	}
	jobID := r.PathValue("jobId")
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var state string
		if err := tx.QueryRowxContext(r.Context(), `SELECT state FROM delivery_jobs WHERE id=$1 FOR UPDATE`, jobID).Scan(&state); errors.Is(err, sql.ErrNoRows) {
			return failure(404, "NOT_FOUND", "Delivery job not found.")
		} else if err != nil {
			return err
		}
		if state == "assigned" || state == "cancelled" {
			return failure(409, "INVALID_STATE", "This delivery job cannot be retried.")
		}
		var active bool
		if err := tx.GetContext(r.Context(), &active, `SELECT EXISTS(SELECT 1 FROM delivery_offers WHERE job_id=$1 AND state='offered')`, jobID); err != nil {
			return err
		}
		if active {
			return failure(409, "ACTIVE_OFFER", "Cancel or resolve the active offer before retrying dispatch.")
		}
		if state != "no_rider_available" {
			return failure(409, "INVALID_STATE", "Only a no-rider exception can be retried by Admin.")
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_jobs SET state='pending_dispatch',updated_at=now() WHERE id=$1`, jobID); err != nil {
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_dispatch_runs SET state='cancelled',completed_at=now() WHERE job_id=$1 AND state='no_rider_available'`, jobID); err != nil {
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO delivery_events(job_id,event_type,actor_user_id,reason) VALUES($1,'dispatch_retried',$2,$3)`, jobID, adminID, strings.TrimSpace(in.Reason)); err != nil {
			return err
		}
		_, err := tx.ExecContext(r.Context(), `INSERT INTO audit_logs(actor_user_id,action,target_type,target_id,reason) VALUES($1,'delivery.dispatch_retried','delivery_job',$2,$3)`, adminID, jobID, strings.TrimSpace(in.Reason))
		return err
	})
	if err != nil {
		writeFailure(w, err)
		return
	}
	if err := s.advanceJob(r.Context(), jobID); err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Dispatch retry was saved but could not issue an offer.")
		return
	}
	writeJSON(w, 200, map[string]any{"data": map[string]string{"job_id": jobID, "state": "retrying"}})
}

func (s *Service) ManualAssign(w http.ResponseWriter, r *http.Request, adminID string) {
	if !s.requireEnabled(w) {
		return
	}
	var in struct {
		RiderUserID string `json:"rider_user_id"`
		Reason      string `json:"reason"`
	}
	if decodeBody(w, r, &in, 4096) != nil || !validUUID(in.RiderUserID) || len([]rune(strings.TrimSpace(in.Reason))) < 10 || len([]rune(in.Reason)) > 500 {
		writeError(w, 400, "VALIDATION_ERROR", "Provide an eligible rider and a reason of 10 to 500 characters.")
		return
	}
	jobID := r.PathValue("jobId")
	var assignmentID, customerID, businessID string
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var state, locality string
		if err := tx.QueryRowxContext(r.Context(), `SELECT state,locality_id::text FROM delivery_jobs WHERE id=$1 FOR UPDATE`, jobID).Scan(&state, &locality); errors.Is(err, sql.ErrNoRows) {
			return failure(404, "NOT_FOUND", "Delivery job not found.")
		} else if err != nil {
			return err
		}
		if state == "assigned" || state == "cancelled" {
			return failure(409, "INVALID_STATE", "This delivery job cannot be manually assigned.")
		}
		var orderSource, paymentMethod, paymentStatus string
		var hasCODObligation bool
		if err := tx.QueryRowxContext(r.Context(), `SELECT COALESCE(o.order_source,''),COALESCE(o.payment_method,''),COALESCE(o.payment_status,''),EXISTS(SELECT 1 FROM cod_obligations c WHERE c.order_id=o.id) FROM customer_orders o JOIN delivery_jobs j ON j.order_id=o.id WHERE j.id=$1 FOR UPDATE OF o`, jobID).Scan(&orderSource, &paymentMethod, &paymentStatus, &hasCODObligation); err != nil {
			return err
		}
		if !dispatchPaymentEligible(orderSource, paymentMethod, paymentStatus, hasCODObligation) {
			return failure(409, "PAYMENT_NOT_VERIFIED", "This delivery cannot be assigned until the order payment is eligible and verified.")
		}
		if err := requireActiveRider(r.Context(), tx, in.RiderUserID, ""); err != nil {
			return err
		}
		if err := riderEligibleForAvailability(r.Context(), tx, in.RiderUserID); err != nil {
			return err
		}
		var online bool
		if err := tx.GetContext(r.Context(), &online, `SELECT EXISTS(SELECT 1 FROM rider_availability_sessions WHERE rider_user_id=$1 AND is_online AND lease_expires_at>now())`, in.RiderUserID); err != nil {
			return err
		}
		if !online {
			return failure(409, "RIDER_UNAVAILABLE", "Admin assignment requires a rider with a current online session.")
		}
		if err := checkRiderLocality(r.Context(), tx, in.RiderUserID, locality); err != nil {
			return err
		}
		var active string
		if err := tx.GetContext(r.Context(), &active, `SELECT id::text FROM delivery_offers WHERE job_id=$1 AND state='offered' FOR UPDATE`, jobID); err == nil {
			if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_offers SET state='cancelled',responded_at=now() WHERE id=$1`, active); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `INSERT INTO delivery_events(job_id,event_type,offer_id,actor_user_id,reason) VALUES($1,'offer_cancelled',$2,$3,'Replaced by audited Admin assignment')`, jobID, active, adminID); err != nil {
				return err
			}
		} else if !errors.Is(err, sql.ErrNoRows) {
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_dispatch_runs SET state='cancelled',completed_at=now() WHERE job_id=$1 AND state='searching'`, jobID); err != nil {
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO delivery_dispatch_runs(job_id,run_number,state,started_by,reason,completed_at) VALUES($1,COALESCE((SELECT max(run_number)+1 FROM delivery_dispatch_runs WHERE job_id=$1),1),'assigned',$2,$3,now())`, jobID, adminID, strings.TrimSpace(in.Reason)); err != nil {
			return err
		}
		if err := tx.QueryRowxContext(r.Context(), `INSERT INTO delivery_assignments(job_id,rider_user_id,assigned_by,assignment_reason) VALUES($1,$2,$3,$4) RETURNING id::text`, jobID, in.RiderUserID, adminID, strings.TrimSpace(in.Reason)).Scan(&assignmentID); err != nil {
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_jobs SET state='assigned',updated_at=now() WHERE id=$1`, jobID); err != nil {
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO delivery_events(job_id,event_type,actor_user_id,assignment_id,reason) VALUES($1,'manual_assignment',$2,$3,$4)`, jobID, adminID, assignmentID, strings.TrimSpace(in.Reason)); err != nil {
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO audit_logs(actor_user_id,action,target_type,target_id,reason) VALUES($1,'delivery.manual_assignment','delivery_job',$2,$3)`, adminID, jobID, strings.TrimSpace(in.Reason)); err != nil {
			return err
		}
		return tx.QueryRowxContext(r.Context(), `SELECT o.customer_user_id::text,o.business_id::text FROM delivery_jobs j JOIN customer_orders o ON o.id=j.order_id WHERE j.id=$1`, jobID).Scan(&customerID, &businessID)
	})
	if err != nil {
		writeFailure(w, err)
		return
	}
	s.publishAssignment(r.Context(), customerID, businessID, jobID)
	writeJSON(w, 200, map[string]any{"data": map[string]string{"job_id": jobID, "assignment_id": assignmentID, "state": "assigned"}})
}

func (s *Service) CancelOffer(w http.ResponseWriter, r *http.Request, adminID string) {
	if !s.requireEnabled(w) {
		return
	}
	var in struct {
		Reason string `json:"reason"`
	}
	if decodeBody(w, r, &in, 2048) != nil || len([]rune(strings.TrimSpace(in.Reason))) < 10 || len([]rune(in.Reason)) > 500 {
		writeError(w, 400, "VALIDATION_ERROR", "A cancellation reason of 10 to 500 characters is required.")
		return
	}
	var jobID, customerID, businessID string
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		offerID := r.PathValue("offerId")
		var state string
		if err := tx.QueryRowxContext(r.Context(), `SELECT x.state,x.job_id::text,o.customer_user_id::text,o.business_id::text FROM delivery_offers x JOIN delivery_jobs j ON j.id=x.job_id JOIN customer_orders o ON o.id=j.order_id WHERE x.id=$1 FOR UPDATE OF x,j`, offerID).Scan(&state, &jobID, &customerID, &businessID); errors.Is(err, sql.ErrNoRows) {
			return failure(404, "NOT_FOUND", "Offer not found.")
		} else if err != nil {
			return err
		}
		if state != "offered" {
			return failure(409, "OFFER_CLOSED", "Only an active offer can be cancelled.")
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_offers SET state='cancelled',responded_at=now() WHERE id=$1`, offerID); err != nil {
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_jobs SET state='pending_dispatch',updated_at=now() WHERE id=$1 AND state='offered'`, jobID); err != nil {
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO delivery_events(job_id,event_type,offer_id,actor_user_id,reason) VALUES($1,'offer_cancelled',$2,$3,$4)`, jobID, offerID, adminID, strings.TrimSpace(in.Reason)); err != nil {
			return err
		}
		_, err := tx.ExecContext(r.Context(), `INSERT INTO audit_logs(actor_user_id,action,target_type,target_id,reason) VALUES($1,'delivery.offer_cancelled','delivery_job',$2,$3)`, adminID, jobID, strings.TrimSpace(in.Reason))
		return err
	})
	if err != nil {
		writeFailure(w, err)
		return
	}
	s.publishScoped(r.Context(), customerID, businessID, jobID, "delivery.offer_cancelled", "Rider offer cancelled", "An active rider offer was cancelled by Grepmind Admin.")
	if err := s.advanceJob(r.Context(), jobID); err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "The offer was cancelled, but dispatch could not be advanced.")
		return
	}
	writeJSON(w, 200, map[string]any{"data": map[string]string{"offer_id": r.PathValue("offerId"), "state": "cancelled"}})
}

func (s *Service) MerchantSummary(w http.ResponseWriter, r *http.Request, userID string) {
	if !s.requireEnabled(w) {
		return
	}
	businessID := r.PathValue("businessId")
	var allowed bool
	if err := s.db.GetContext(r.Context(), &allowed, `SELECT EXISTS(SELECT 1 FROM businesses b WHERE b.id=$1 AND b.owner_user_id=$2 AND b.status<>'deleted' UNION ALL SELECT 1 FROM business_members m WHERE m.business_id=$1 AND m.user_id=$2 AND m.status='active' AND m.role IN ('owner','manager','staff'))`, businessID, userID); err != nil || !allowed {
		writeError(w, 403, "FORBIDDEN", "Active membership in this business is required.")
		return
	}
	rows, err := queryMaps(r.Context(), s.db, `SELECT j.id::text job_id,j.order_id::text order_id,j.state delivery_state,j.execution_state,COALESCE(a.state='active',false) rider_assigned,a.id::text assignment_id,
		CASE WHEN a.state='active' THEN 'assigned' WHEN j.state='no_rider_available' THEN 'no_rider_available' ELSE j.state END dispatch_status,
		rp.display_name rider_name,
		EXISTS(SELECT 1 FROM delivery_recovery_partner_confirmations pc WHERE pc.job_id=j.id AND pc.assignment_id=a.id AND pc.confirmation='goods_not_handed_over') partner_confirmed_no_handover,
		COALESCE(rr.inventory_disposition,'') inventory_disposition,rr.received_at::text return_received_at,rr.finalized_at::text return_finalized_at,
		(SELECT created_at::text FROM delivery_execution_events e WHERE e.job_id=j.id AND e.to_state='arriving_at_pickup' ORDER BY created_at DESC LIMIT 1) rider_arriving_at,
		(SELECT created_at::text FROM delivery_execution_events e WHERE e.job_id=j.id AND e.event_type='pickup_verified' ORDER BY created_at DESC LIMIT 1) pickup_verified_at,
		(SELECT created_at::text FROM delivery_execution_events e WHERE e.job_id=j.id AND e.to_state='picked_up' ORDER BY created_at DESC LIMIT 1) picked_up_at,
		(SELECT created_at::text FROM delivery_execution_events e WHERE e.job_id=j.id AND e.to_state='en_route' ORDER BY created_at DESC LIMIT 1) en_route_at,
		(SELECT created_at::text FROM delivery_execution_events e WHERE e.job_id=j.id AND e.to_state='delivered' ORDER BY created_at DESC LIMIT 1) delivered_at,
		(SELECT exception_type FROM delivery_exceptions x WHERE x.job_id=j.id AND x.state='open' ORDER BY x.created_at DESC LIMIT 1) open_exception_type,
		(SELECT reason FROM delivery_exceptions x WHERE x.job_id=j.id AND x.state='open' ORDER BY x.created_at DESC LIMIT 1) open_exception_reason
		FROM delivery_jobs j LEFT JOIN LATERAL (SELECT id,rider_user_id,state FROM delivery_assignments WHERE job_id=j.id ORDER BY assigned_at DESC LIMIT 1) a ON true LEFT JOIN rider_profiles rp ON rp.user_id=a.rider_user_id
		LEFT JOIN delivery_return_receipts rr ON rr.job_id=j.id
		WHERE j.business_id=$1 ORDER BY j.created_at DESC LIMIT 100`, businessID)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load dispatch summaries.")
		return
	}
	writeJSON(w, 200, map[string]any{"data": rows})
}

func (s *Service) CustomerSummary(w http.ResponseWriter, r *http.Request, userID string) {
	if !s.requireEnabled(w) {
		return
	}
	orderID := r.PathValue("id")
	var row struct {
		JobID          string `db:"job_id" json:"job_id"`
		State          string `db:"state" json:"delivery_state"`
		Assigned       bool   `db:"assigned" json:"rider_assigned"`
		Updated        string `db:"updated" json:"updated_at"`
		ExecutionState string `db:"execution_state" json:"execution_state"`
	}
	err := s.db.GetContext(r.Context(), &row, `SELECT COALESCE(j.id::text,'') AS job_id,COALESCE(j.state,'not_dispatched') AS state,(a.id IS NOT NULL) AS assigned,COALESCE(j.updated_at,o.updated_at)::text AS updated,CASE WHEN a.id IS NOT NULL THEN COALESCE(j.execution_state,'assigned') WHEN j.execution_state IN ('delivered','returned','cancelled') THEN j.execution_state ELSE 'not_started' END AS execution_state FROM customer_orders o LEFT JOIN delivery_jobs j ON j.order_id=o.id LEFT JOIN delivery_assignments a ON a.job_id=j.id AND a.state='active' WHERE o.id=$1 AND o.customer_user_id=$2`, orderID, userID)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, 404, "NOT_FOUND", "Order delivery status not found.")
		return
	}
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load delivery status.")
		return
	}
	writeJSON(w, 200, map[string]any{"data": row})
}

func (s *Service) publishAssignment(ctx context.Context, customerID, businessID, jobID string) {
	if s.hub == nil {
		return
	}
	payload := s.customerOrderEventPayload(ctx, jobID)
	payload["delivery_state"] = "assigned"
	payload["rider_assigned"] = true
	s.hub.Publish(ctx, notifications.Event{Type: "delivery.status", UserID: customerID, Title: "Rider assigned", Body: "A rider has been assigned to your order.", Payload: payload})
	s.hub.Publish(ctx, notifications.Event{Type: "delivery.dispatch", BusinessID: businessID, Title: "Rider assigned", Body: "A rider has accepted this delivery job.", Payload: payload})
}

func (s *Service) publishScoped(ctx context.Context, customerID, businessID, jobID, eventType, title, body string) {
	if s.hub == nil {
		return
	}
	payload := s.customerOrderEventPayload(ctx, jobID)
	if customerID != "" {
		s.hub.Publish(ctx, notifications.Event{Type: eventType, UserID: customerID, Title: title, Body: body, Payload: payload})
	}
	if businessID != "" {
		s.hub.Publish(ctx, notifications.Event{Type: eventType, BusinessID: businessID, Title: title, Body: body, Payload: payload})
	}
	// The rider receives only events for the delivery job to which they were
	// assigned; no address, phone number, or verification code is broadcast.
	var riderID string
	if err := s.db.GetContext(ctx, &riderID, `SELECT rider_user_id::text FROM delivery_assignments WHERE job_id=$1 ORDER BY assigned_at DESC LIMIT 1`, jobID); err == nil && riderID != "" {
		s.hub.Publish(ctx, notifications.Event{Type: eventType, UserID: riderID, Title: title, Body: body, Payload: payload})
	}
}

func (s *Service) customerOrderEventPayload(ctx context.Context, jobID string) map[string]any {
	payload := map[string]any{"job_id": jobID}
	var orderID string
	if s.db != nil && s.db.GetContext(ctx, &orderID, `SELECT order_id::text FROM delivery_jobs WHERE id=$1`, jobID) == nil {
		payload["order_id"] = orderID
	}
	return payload
}

const eligibleRidersSQL = `SELECT p.user_id::text,p.display_name,p.vehicle_type,l.name locality,
	(SELECT count(*)::int FROM delivery_assignments a WHERE a.rider_user_id=p.user_id) assignment_count,
	(SELECT max(a.assigned_at)::text FROM delivery_assignments a WHERE a.rider_user_id=p.user_id) last_assigned_at
	FROM rider_profiles p JOIN users u ON u.id=p.user_id AND u.status='active' JOIN user_roles ur ON ur.user_id=p.user_id AND ur.role='rider'
	JOIN rider_profile_localities rl ON rl.rider_profile_id=p.id AND rl.locality_id=$1 AND rl.status='approved'
	JOIN platform_delivery_localities l ON l.id=rl.locality_id AND l.is_active AND l.delivery_enabled
	JOIN rider_availability_sessions av ON av.rider_user_id=p.user_id AND av.is_online AND av.lease_expires_at>now()
	WHERE p.status='approved' AND NOT EXISTS(SELECT 1 FROM delivery_assignments a WHERE a.rider_user_id=p.user_id AND a.state='active')
	AND NOT EXISTS(SELECT 1 FROM delivery_offers x WHERE x.rider_user_id=p.user_id AND x.state='offered')
	AND NOT EXISTS(SELECT 1 FROM rider_document_requirements q WHERE q.is_active AND q.is_required AND q.vehicle_type IN ('any',p.vehicle_type)
		AND NOT EXISTS(SELECT 1 FROM rider_documents d WHERE d.rider_profile_id=p.id AND d.requirement_id=q.id AND d.review_status='accepted'))
	ORDER BY (SELECT count(*) FROM delivery_assignments a WHERE a.rider_user_id=p.user_id),(SELECT max(a.assigned_at) FROM delivery_assignments a WHERE a.rider_user_id=p.user_id) ASC NULLS FIRST,p.user_id`

// eligibleNoRiderJobsSQL reopens only the oldest exhausted job when capacity
// has actually returned for its locality. It mirrors the offer eligibility
// predicates so idle/no-rider jobs do not churn through dispatch runs.
const eligibleNoRiderJobsSQL = `SELECT j.id::text
	FROM delivery_jobs j
	WHERE j.state='no_rider_available'
	AND EXISTS (
		SELECT 1 FROM rider_profiles p
		JOIN users u ON u.id=p.user_id AND u.status='active'
		JOIN user_roles ur ON ur.user_id=p.user_id AND ur.role='rider'
		JOIN rider_profile_localities rl ON rl.rider_profile_id=p.id AND rl.locality_id=j.locality_id AND rl.status='approved'
		JOIN platform_delivery_localities l ON l.id=rl.locality_id AND l.is_active AND l.delivery_enabled
		JOIN rider_availability_sessions av ON av.rider_user_id=p.user_id AND av.is_online AND av.lease_expires_at>now()
		WHERE p.status='approved'
		AND NOT EXISTS (SELECT 1 FROM delivery_assignments a WHERE a.rider_user_id=p.user_id AND a.state='active')
		AND NOT EXISTS (SELECT 1 FROM delivery_offers x WHERE x.rider_user_id=p.user_id AND x.state='offered')
		AND NOT EXISTS (SELECT 1 FROM rider_document_requirements q WHERE q.is_active AND q.is_required AND q.vehicle_type IN ('any',p.vehicle_type)
			AND NOT EXISTS (SELECT 1 FROM rider_documents d WHERE d.rider_profile_id=p.id AND d.requirement_id=q.id AND d.review_status='accepted'))
	)
	ORDER BY j.created_at,j.id
	LIMIT 1`

func requireActiveRider(ctx context.Context, tx *sqlx.Tx, riderID, localityID string) error {
	var confirmed string
	err := tx.GetContext(ctx, &confirmed, `SELECT u.id::text FROM users u JOIN user_roles ur ON ur.user_id=u.id AND ur.role='rider' JOIN rider_profiles p ON p.user_id=u.id AND p.status='approved' WHERE u.id=$1 AND u.status='active' FOR UPDATE OF u,ur,p`, riderID)
	if errors.Is(err, sql.ErrNoRows) {
		return failure(403, "RIDER_NOT_APPROVED", "Approved active rider access is required.")
	}
	if err != nil {
		return err
	}
	if localityID != "" {
		return checkRiderLocality(ctx, tx, riderID, localityID)
	}
	return nil
}

func dispatchPaymentEligible(orderSource, method, paymentStatus string, hasCODObligation bool) bool {
	if orderSource != "platform_catalog" {
		return true
	}
	switch method {
	case "": // Existing pre-payment-contract orders retain their historical workflow.
		return true
	case "upi":
		return paymentStatus == "paid"
	case "cash_on_delivery":
		return hasCODObligation
	default:
		return false
	}
}

func requireDispatchPaymentEligibility(ctx context.Context, tx *sqlx.Tx, jobID string) error {
	var source, method, status string
	var hasCOD bool
	if err := tx.QueryRowxContext(ctx, `SELECT COALESCE(o.order_source,''),COALESCE(o.payment_method,''),COALESCE(o.payment_status,''),EXISTS(SELECT 1 FROM cod_obligations c WHERE c.order_id=o.id) FROM customer_orders o JOIN delivery_jobs j ON j.order_id=o.id WHERE j.id=$1 FOR UPDATE OF o`, jobID).Scan(&source, &method, &status, &hasCOD); err != nil {
		return err
	}
	if !dispatchPaymentEligible(source, method, status, hasCOD) {
		return failure(409, "PAYMENT_NOT_VERIFIED", "This delivery cannot proceed until the order payment is eligible and verified.")
	}
	return nil
}

func riderEligibleForAvailability(ctx context.Context, tx *sqlx.Tx, riderID string) error {
	var reason string
	err := tx.GetContext(ctx, &reason, `SELECT CASE WHEN EXISTS(SELECT 1 FROM delivery_assignments a WHERE a.rider_user_id=$1 AND a.state='active') THEN 'An active delivery is already assigned to this rider.'
	WHEN EXISTS(SELECT 1 FROM delivery_offers x WHERE x.rider_user_id=$1 AND x.state='offered') THEN 'Resolve the current rider offer before going online.'
	WHEN EXISTS(SELECT 1 FROM rider_document_requirements q JOIN rider_profiles p ON p.user_id=$1 AND p.status='approved' WHERE q.is_active AND q.is_required AND q.vehicle_type IN ('any',p.vehicle_type) AND NOT EXISTS(SELECT 1 FROM rider_documents d WHERE d.rider_profile_id=p.id AND d.requirement_id=q.id AND d.review_status='accepted')) THEN 'Required rider verification is not current.'
	ELSE '' END`, riderID)
	if err != nil {
		return err
	}
	if reason != "" {
		return failure(409, "RIDER_UNAVAILABLE", reason)
	}
	return nil
}

func riderEligibleForAcceptance(ctx context.Context, tx *sqlx.Tx, riderID, offerID string) error {
	var reason string
	err := tx.GetContext(ctx, &reason, `SELECT CASE WHEN EXISTS(SELECT 1 FROM delivery_assignments a WHERE a.rider_user_id=$1 AND a.state='active') THEN 'An active delivery is already assigned to this rider.'
	WHEN EXISTS(SELECT 1 FROM delivery_offers x WHERE x.rider_user_id=$1 AND x.state='offered' AND x.id<>$2) THEN 'Another active rider offer must be resolved first.'
	WHEN EXISTS(SELECT 1 FROM rider_document_requirements q JOIN rider_profiles p ON p.user_id=$1 AND p.status='approved' WHERE q.is_active AND q.is_required AND q.vehicle_type IN ('any',p.vehicle_type) AND NOT EXISTS(SELECT 1 FROM rider_documents d WHERE d.rider_profile_id=p.id AND d.requirement_id=q.id AND d.review_status='accepted')) THEN 'Required rider verification is not current.'
	ELSE '' END`, riderID, offerID)
	if err != nil {
		return err
	}
	if reason != "" {
		return failure(409, "RIDER_UNAVAILABLE", reason)
	}
	return nil
}
func riderEligibleForAvailabilityDB(ctx context.Context, db *database.DB, riderID string) error {
	var tx *sqlx.Tx
	t, err := db.BeginTxx(ctx, nil)
	if err != nil {
		return err
	}
	tx = t
	defer tx.Rollback()
	if err := requireActiveRider(ctx, tx, riderID, ""); err != nil {
		return err
	}
	return riderEligibleForAvailability(ctx, tx, riderID)
}

func riderCanMaintainAvailabilityDB(ctx context.Context, db *database.DB, riderID string) error {
	tx, err := db.BeginTxx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err := requireActiveRider(ctx, tx, riderID, ""); err != nil {
		return err
	}
	var blocked bool
	// An active assignment excludes this rider from new offers, but must not
	// prevent heartbeat renewal. Otherwise delivery work expires its own lease.
	if err := tx.GetContext(ctx, &blocked, `SELECT EXISTS(SELECT 1 FROM rider_document_requirements q JOIN rider_profiles p ON p.user_id=$1 AND p.status='approved' WHERE q.is_active AND q.is_required AND q.vehicle_type IN ('any',p.vehicle_type) AND NOT EXISTS(SELECT 1 FROM rider_documents d WHERE d.rider_profile_id=p.id AND d.requirement_id=q.id AND d.review_status='accepted'))`, riderID); err != nil {
		return err
	}
	if blocked {
		return failure(409, "RIDER_UNAVAILABLE", "Availability cannot be renewed while required rider verification is incomplete.")
	}
	return nil
}

func checkRiderLocality(ctx context.Context, tx *sqlx.Tx, riderID, localityID string) error {
	var ok bool
	err := tx.GetContext(ctx, &ok, `SELECT EXISTS(SELECT 1 FROM rider_profiles p JOIN rider_profile_localities rl ON rl.rider_profile_id=p.id AND rl.status='approved' AND rl.locality_id=$2 JOIN platform_delivery_localities l ON l.id=rl.locality_id AND l.is_active AND l.delivery_enabled WHERE p.user_id=$1 AND p.status='approved')`, riderID, localityID)
	if err != nil {
		return err
	}
	if !ok {
		return failure(403, "LOCALITY_NOT_APPROVED", "This rider is not approved for the delivery locality.")
	}
	return nil
}

func decodeBody(w http.ResponseWriter, r *http.Request, out any, max int64) error {
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, max))
	dec.DisallowUnknownFields()
	if err := dec.Decode(out); err != nil {
		return err
	}
	var extra any
	if err := dec.Decode(&extra); err != io.EOF {
		return fmt.Errorf("invalid trailing JSON")
	}
	return nil
}

func validUUID(v string) bool { _, err := uuid.Parse(v); return err == nil }

func queryMaps(ctx context.Context, db *database.DB, query string, args ...any) ([]map[string]any, error) {
	rows, err := db.QueryxContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]map[string]any, 0)
	for rows.Next() {
		row := make(map[string]any)
		if err := rows.MapScan(row); err != nil {
			return nil, err
		}
		for key, value := range row {
			if b, ok := value.([]byte); ok {
				row[key] = string(b)
			}
		}
		out = append(out, row)
	}
	return out, rows.Err()
}

func writeFailure(w http.ResponseWriter, err error) {
	var f *apiFailure
	if errors.As(err, &f) {
		writeError(w, f.status, f.code, f.message)
		return
	}
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" {
		writeError(w, 409, "DISPATCH_CONFLICT", "Rider or job availability changed. Refresh dispatch state and retry.")
		return
	}
	writeError(w, 500, "INTERNAL_ERROR", "Unable to process delivery dispatch request.")
}
func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, map[string]any{"error": map[string]string{"code": code, "message": message}})
}
func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}
