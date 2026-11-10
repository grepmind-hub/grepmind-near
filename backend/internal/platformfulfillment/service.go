package platformfulfillment

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
	"grepmind-near/backend/pkg/database"
)

type Service struct {
	db        *database.DB
	publisher Publisher
}

type Publisher func(ctx context.Context, customerID, businessID, orderID, status, reason string)

func NewService(db *database.DB) *Service { return &Service{db: db} }

func (s *Service) SetPublisher(p Publisher) { s.publisher = p }

type failure struct {
	status  int
	code    string
	message string
}

func (e *failure) Error() string { return e.message }
func fail(status int, code, message string) error {
	return &failure{status: status, code: code, message: message}
}

type item struct {
	Name        string `json:"product_name" db:"product_name"`
	VariantName string `json:"variant_name" db:"variant_name"`
	UnitLabel   string `json:"unit_label" db:"unit_label"`
	Quantity    int    `json:"quantity" db:"quantity"`
}

type statusEvent struct {
	Status    string `json:"status" db:"status"`
	EventKind string `json:"event_kind" db:"event_kind"`
	Reason    string `json:"reason,omitempty" db:"reason"`
	CreatedAt string `json:"created_at" db:"created_at"`
}

type order struct {
	ID                  string        `json:"id" db:"id"`
	BusinessID          string        `json:"business_id" db:"business_id"`
	ReferenceCode       string        `json:"reference_code" db:"reference_code"`
	Status              string        `json:"status" db:"status"`
	Vertical            string        `json:"vertical" db:"platform_vertical"`
	Locality            string        `json:"delivery_locality" db:"delivery_locality"`
	District            string        `json:"delivery_district" db:"delivery_district"`
	SpecialInstructions string        `json:"special_instructions,omitempty" db:"customer_notes"`
	PaymentStatus       string        `json:"payment_status" db:"payment_status"`
	CreatedAt           string        `json:"created_at" db:"created_at"`
	UpdatedAt           string        `json:"updated_at" db:"updated_at"`
	Items               []item        `json:"items" db:"-"`
	StatusEvents        []statusEvent `json:"status_events" db:"-"`
}

const orderColumns = `SELECT o.id::text,o.business_id::text,o.reference_code,o.status,o.platform_vertical,
	COALESCE(l.name,'') AS delivery_locality,COALESCE(d.name,'') AS delivery_district,COALESCE(o.customer_notes,'') AS customer_notes,COALESCE(o.payment_status,'not_collected') AS payment_status,
	o.created_at::text AS created_at,o.updated_at::text AS updated_at
	FROM customer_orders o
	LEFT JOIN platform_delivery_localities l ON l.id=o.delivery_locality_id
	LEFT JOIN platform_districts d ON d.id=l.district_id`

func (s *Service) List(w http.ResponseWriter, r *http.Request, userID string) {
	businessID := r.PathValue("businessId")
	if !validUUID(businessID) {
		writeError(w, 400, "INVALID_ID", "Business ID is invalid.")
		return
	}
	filter := strings.TrimSpace(r.URL.Query().Get("status"))
	if filter != "" && !validStatus(filter) {
		writeError(w, 400, "VALIDATION_ERROR", "Unsupported platform order status.")
		return
	}
	if !s.canAccessBusiness(r.Context(), userID, businessID) {
		writeError(w, 403, "FORBIDDEN", "Active membership in this business is required.")
		return
	}
	limit := 30
	if raw := r.URL.Query().Get("limit"); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed < 1 || parsed > 50 {
			writeError(w, 400, "VALIDATION_ERROR", "limit must be between 1 and 50.")
			return
		}
		limit = parsed
	}
	query := orderColumns + ` WHERE o.business_id=$1 AND o.order_source='platform_catalog'`
	args := []any{businessID}
	if filter != "" {
		query += ` AND o.status=$2`
		args = append(args, filter)
	}
	query += fmt.Sprintf(` ORDER BY o.created_at DESC,o.id DESC LIMIT $%d`, len(args)+1)
	args = append(args, limit)
	rows, err := s.db.QueryxContext(r.Context(), query, args...)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load assigned platform orders.")
		return
	}
	defer rows.Close()
	result := make([]order, 0)
	for rows.Next() {
		var value order
		if err := rows.Scan(&value.ID, &value.BusinessID, &value.ReferenceCode, &value.Status, &value.Vertical, &value.Locality, &value.District, &value.SpecialInstructions, &value.PaymentStatus, &value.CreatedAt, &value.UpdatedAt); err != nil {
			writeError(w, 500, "INTERNAL_ERROR", "Unable to read assigned orders.")
			return
		}
		if err := s.loadOrderParts(r.Context(), &value); err != nil {
			log.Printf("platform fulfillment: load order parts failed: %v", err)
			writeError(w, 500, "INTERNAL_ERROR", "Unable to read order fulfillment details.")
			return
		}
		result = append(result, value)
	}
	if err := rows.Err(); err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to read assigned orders.")
		return
	}
	writeJSON(w, 200, map[string]any{"data": result, "meta": map[string]any{"count": len(result)}})
}

func (s *Service) Get(w http.ResponseWriter, r *http.Request, userID string) {
	businessID, orderID := r.PathValue("businessId"), r.PathValue("orderId")
	if !validUUID(businessID) || !validUUID(orderID) {
		writeError(w, 404, "NOT_FOUND", "Platform order not found.")
		return
	}
	if !s.canAccessBusiness(r.Context(), userID, businessID) {
		writeError(w, 403, "FORBIDDEN", "Active membership in this business is required.")
		return
	}
	value, err := s.load(r.Context(), orderID, businessID)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, 404, "NOT_FOUND", "Platform order not found.")
		return
	}
	if err != nil {
		log.Printf("platform fulfillment: load order %s failed: %v", orderID, err)
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load the platform order.")
		return
	}
	writeJSON(w, 200, map[string]any{"data": value})
}

func (s *Service) Accept(w http.ResponseWriter, r *http.Request, userID string) {
	s.transition(w, r, userID, "accepted", "partner_accepted", "")
}

func (s *Service) Prepare(w http.ResponseWriter, r *http.Request, userID string) {
	s.transition(w, r, userID, "preparing", "preparation_started", "")
}

func (s *Service) Ready(w http.ResponseWriter, r *http.Request, userID string) {
	s.transition(w, r, userID, "ready_for_pickup", "ready_for_pickup", "")
}

func (s *Service) Reject(w http.ResponseWriter, r *http.Request, userID string) {
	var req struct {
		Reason string `json:"reason"`
	}
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 2048))
	decoder.DisallowUnknownFields()
	if decoder.Decode(&req) != nil {
		writeError(w, 400, "VALIDATION_ERROR", "A rejection reason is required.")
		return
	}
	reason := strings.TrimSpace(req.Reason)
	if len([]rune(reason)) < 10 || len([]rune(reason)) > 500 {
		writeError(w, 400, "VALIDATION_ERROR", "Rejection reason must be between 10 and 500 characters.")
		return
	}
	s.transition(w, r, userID, "rejected", "partner_rejected", reason)
}

func (s *Service) transition(w http.ResponseWriter, r *http.Request, userID, target, eventKind, reason string) {
	businessID, orderID := r.PathValue("businessId"), r.PathValue("orderId")
	if !validUUID(businessID) || !validUUID(orderID) {
		writeError(w, 404, "NOT_FOUND", "Platform order not found.")
		return
	}
	var customerID, previous, lockedReference, lockedVertical, lockedLocality, lockedDistrict, lockedNotes, lockedPayment, lockedCreated, lockedUpdated string
	changed := false
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if !lockBusinessAccess(r.Context(), tx, userID, businessID) {
			return fail(403, "FORBIDDEN", "Active membership in this business is required.")
		}
		if err := tx.QueryRowxContext(r.Context(), orderColumns+` WHERE o.id=$1 AND o.business_id=$2 AND o.order_source='platform_catalog' FOR UPDATE OF o`, orderID, businessID).Scan(&orderID, &businessID, &lockedReference, &previous, &lockedVertical, &lockedLocality, &lockedDistrict, &lockedNotes, &lockedPayment, &lockedCreated, &lockedUpdated); err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return fail(404, "NOT_FOUND", "Platform order not found.")
			}
			return err
		}
		if previous == target {
			return nil // idempotent retry: do not append duplicate audit/notification events
		}
		if !transitionAllowed(previous, target) {
			return fail(409, "INVALID_STATE", "This platform order cannot make that fulfillment transition.")
		}
		if err := tx.QueryRowxContext(r.Context(), `SELECT customer_user_id::text FROM customer_orders WHERE id=$1 AND business_id=$2`, orderID, businessID).Scan(&customerID); err != nil {
			return err
		}
		res, err := tx.ExecContext(r.Context(), `UPDATE customer_orders SET status=$1,updated_at=now() WHERE id=$2 AND business_id=$3 AND order_source='platform_catalog' AND status=$4`, target, orderID, businessID, previous)
		if err != nil {
			return err
		}
		count, err := res.RowsAffected()
		if err != nil {
			return err
		}
		if count != 1 {
			return fail(409, "INVALID_STATE", "The order changed while this action was being saved. Refresh and try again.")
		}
		if target == "rejected" {
			if err := releaseInventory(r.Context(), tx, orderID); err != nil {
				return err
			}
		}
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO customer_order_status_events(order_id,status,event_kind,actor_user_id,reason) VALUES($1,$2,$3,$4,NULLIF($5,''))`, orderID, target, eventKind, userID, reason); err != nil {
			return err
		}
		previous = target
		changed = true
		return nil
	})
	if err != nil {
		writeFailure(w, err)
		return
	}
	if changed && s.publisher != nil {
		s.publisher(r.Context(), customerID, businessID, orderID, target, reason)
	}
	value, err := s.load(r.Context(), orderID, businessID)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Order updated but fulfillment details could not be loaded.")
		return
	}
	writeJSON(w, 200, map[string]any{"data": value, "meta": map[string]any{"changed": changed}})
}

func (s *Service) load(ctx context.Context, orderID, businessID string) (*order, error) {
	var value order
	if err := s.db.GetContext(ctx, &value, orderColumns+` WHERE o.id=$1 AND o.business_id=$2 AND o.order_source='platform_catalog'`, orderID, businessID); err != nil {
		return nil, err
	}
	if err := s.loadOrderParts(ctx, &value); err != nil {
		log.Printf("platform fulfillment: load order %s parts failed: %v", orderID, err)
		return nil, err
	}
	return &value, nil
}

func (s *Service) loadOrderParts(ctx context.Context, value *order) error {
	value.Items = make([]item, 0)
	if err := s.db.SelectContext(ctx, &value.Items, `SELECT product_name,variant_name,unit_label,quantity FROM platform_customer_order_items WHERE order_id=$1 ORDER BY product_name,variant_name`, value.ID); err != nil {
		return err
	}
	value.StatusEvents = make([]statusEvent, 0)
	return s.db.SelectContext(ctx, &value.StatusEvents, `SELECT status,event_kind,COALESCE(reason,'') AS reason,created_at::text AS created_at FROM customer_order_status_events WHERE order_id=$1 ORDER BY created_at,id`, value.ID)
}

func (s *Service) canAccessBusiness(ctx context.Context, userID, businessID string) bool {
	var allowed bool
	err := s.db.GetContext(ctx, &allowed, `SELECT EXISTS(
		SELECT 1 FROM businesses b JOIN user_roles ur ON ur.user_id=b.owner_user_id AND ur.role IN ('merchant','professional')
		WHERE b.id=$1 AND b.status!='deleted' AND b.owner_user_id=$2
		UNION ALL
		SELECT 1 FROM business_members m JOIN user_roles ur ON ur.user_id=m.user_id AND ur.role IN ('merchant','professional')
		WHERE m.business_id=$1 AND m.user_id=$2 AND m.status='active' AND m.role IN ('owner','manager','staff')
	)`, businessID, userID)
	return err == nil && allowed
}

func lockBusinessAccess(ctx context.Context, tx *sqlx.Tx, userID, businessID string) bool {
	var role string
	err := tx.GetContext(ctx, &role, `SELECT m.role FROM business_members m WHERE m.business_id=$1 AND m.user_id=$2 AND m.status='active' AND m.role IN ('owner','manager','staff') AND EXISTS(SELECT 1 FROM user_roles ur WHERE ur.user_id=m.user_id AND ur.role IN ('merchant','professional')) FOR SHARE`, businessID, userID)
	if errors.Is(err, sql.ErrNoRows) {
		err = tx.GetContext(ctx, &role, `SELECT 'owner' FROM businesses b WHERE b.id=$1 AND b.owner_user_id=$2 AND b.status!='deleted' AND EXISTS(SELECT 1 FROM user_roles ur WHERE ur.user_id=b.owner_user_id AND ur.role IN ('merchant','professional')) FOR SHARE`, businessID, userID)
	}
	return err == nil && (role == "owner" || role == "manager" || role == "staff")
}

func transitionAllowed(from, to string) bool {
	switch from {
	case "placed":
		return to == "accepted" || to == "rejected"
	case "accepted":
		return to == "preparing"
	case "preparing":
		return to == "ready_for_pickup"
	default:
		return false
	}
}

func validStatus(status string) bool {
	switch status {
	case "placed", "accepted", "preparing", "ready_for_pickup", "rejected", "cancelled":
		return true
	}
	return false
}

func releaseInventory(ctx context.Context, tx *sqlx.Tx, orderID string) error {
	type reservation struct {
		ID        string `db:"id"`
		MappingID string `db:"mapping_id"`
		Quantity  int    `db:"quantity"`
		Mode      string `db:"inventory_mode"`
	}
	rows, err := tx.QueryxContext(ctx, `SELECT id::text,mapping_id::text,quantity,inventory_mode FROM platform_inventory_reservations WHERE order_id=$1 AND status='reserved' ORDER BY mapping_id FOR UPDATE`, orderID)
	if err != nil {
		return err
	}
	items := make([]reservation, 0)
	for rows.Next() {
		var value reservation
		if err := rows.StructScan(&value); err != nil {
			rows.Close()
			return err
		}
		items = append(items, value)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return err
	}
	rows.Close()
	for _, value := range items {
		if value.Mode == "finite" {
			if _, err := tx.ExecContext(ctx, `UPDATE platform_partner_product_mappings SET available_quantity=available_quantity+$2,updated_at=now() WHERE id=$1 AND inventory_mode='finite'`, value.MappingID, value.Quantity); err != nil {
				return err
			}
		}
		if _, err := tx.ExecContext(ctx, `UPDATE platform_inventory_reservations SET status='released',updated_at=now() WHERE id=$1 AND status='reserved'`, value.ID); err != nil {
			return err
		}
	}
	return nil
}

// ReleaseReservedInventory lets other transactional order workflows reuse the
// same idempotent reservation-release logic without creating a second policy.
func ReleaseReservedInventory(ctx context.Context, tx *sqlx.Tx, orderID string) error {
	return releaseInventory(ctx, tx, orderID)
}

func validUUID(value string) bool { _, err := uuid.Parse(value); return err == nil }

func writeFailure(w http.ResponseWriter, err error) {
	var f *failure
	if errors.As(err, &f) {
		writeError(w, f.status, f.code, f.message)
		return
	}
	writeError(w, 500, "INTERNAL_ERROR", "Unable to update partner fulfillment status.")
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, map[string]any{"error": map[string]string{"code": code, "message": message}})
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}
