package operations

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"

	"grepmind-near/backend/pkg/database"
)

type Service struct{ db *database.DB }

func NewService(db *database.DB) *Service { return &Service{db: db} }

type createItem struct {
	ProductID string `json:"product_id"`
	Quantity  int    `json:"quantity"`
}

type createOrderRequest struct {
	OrderType       string       `json:"order_type"`
	FulfillmentType string       `json:"fulfillment_type"`
	DeliveryAddress string       `json:"delivery_address"`
	Notes           string       `json:"notes"`
	Items           []createItem `json:"items"`
	ReservationAt   *time.Time   `json:"reservation_at"`
	ReservationEnd  *time.Time   `json:"reservation_end_at"`
	GuestCount      *int         `json:"guest_count"`
	SeatingArea     string       `json:"seating_area"`
	RoomProductID   string       `json:"room_product_id"`
}

type orderItem struct {
	ProductID   string  `json:"id" db:"product_id"`
	Name        string  `json:"name" db:"product_name"`
	Price       float64 `json:"price" db:"unit_price"`
	Quantity    int     `json:"quantity" db:"quantity"`
	DietaryType string  `json:"dietary_type,omitempty" db:"dietary_type"`
}

type orderResponse struct {
	ID               string      `json:"id" db:"id"`
	BusinessID       string      `json:"business_id" db:"business_id"`
	BusinessName     string      `json:"business_name" db:"business_name"`
	BusinessLocality string      `json:"business_locality,omitempty" db:"business_locality"`
	BusinessPhone    string      `json:"business_phone,omitempty" db:"business_phone"`
	BusinessCoverURL string      `json:"business_cover_url,omitempty" db:"business_cover_url"`
	OrderType        string      `json:"order_type" db:"order_type"`
	Status           string      `json:"status" db:"status"`
	FulfillmentType  string      `json:"fulfillment_type,omitempty" db:"fulfillment_type"`
	DeliveryAddress  string      `json:"delivery_address,omitempty" db:"delivery_address"`
	Notes            string      `json:"special_instructions,omitempty" db:"customer_notes"`
	ItemTotal        float64     `json:"item_total" db:"item_total"`
	DeliveryFee      float64     `json:"delivery_fee" db:"delivery_fee"`
	TaxAmount        float64     `json:"tax" db:"tax_amount"`
	GrandTotal       float64     `json:"grand_total" db:"grand_total"`
	Currency         string      `json:"currency" db:"currency"`
	ETAMinutes       *int        `json:"eta_minutes,omitempty" db:"eta_minutes"`
	ReservationAt    *time.Time  `json:"reservation_at,omitempty" db:"reservation_at"`
	ReservationEnd   *time.Time  `json:"reservation_end_at,omitempty" db:"reservation_end_at"`
	GuestCount       *int        `json:"guest_count,omitempty" db:"guest_count"`
	SeatingArea      string      `json:"seating_area,omitempty" db:"seating_area"`
	RoomProductID    string      `json:"room_product_id,omitempty" db:"room_product_id"`
	ReferenceCode    string      `json:"voucher_code" db:"reference_code"`
	CreatedAt        time.Time   `json:"created_at" db:"created_at"`
	UpdatedAt        time.Time   `json:"updated_at" db:"updated_at"`
	Items            []orderItem `json:"items"`
}

func (s *Service) Availability(w http.ResponseWriter, r *http.Request) {
	businessID := r.PathValue("id")
	from := time.Now().UTC()
	to := from.Add(14 * 24 * time.Hour)
	if raw := r.URL.Query().Get("from"); raw != "" {
		parsed, err := time.Parse(time.RFC3339, raw)
		if err != nil {
			writeError(w, 400, "VALIDATION_ERROR", "Invalid availability start.")
			return
		}
		from = parsed
	}
	if raw := r.URL.Query().Get("to"); raw != "" {
		parsed, err := time.Parse(time.RFC3339, raw)
		if err != nil {
			writeError(w, 400, "VALIDATION_ERROR", "Invalid availability end.")
			return
		}
		to = parsed
	}
	if !to.After(from) || to.Sub(from) > 31*24*time.Hour {
		writeError(w, 400, "VALIDATION_ERROR", "Availability range must be between one instant and 31 days.")
		return
	}
	rows, err := s.db.QueryxContext(r.Context(), `
		SELECT id, starts_at, ends_at, capacity, booked_count
		FROM availability_slots
		WHERE business_id=$1 AND status='open' AND starts_at >= $2 AND starts_at < $3 AND booked_count < capacity
		ORDER BY starts_at`, businessID, from, to)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load availability.")
		return
	}
	defer rows.Close()
	items := make([]map[string]interface{}, 0)
	for rows.Next() {
		var id string
		var starts, ends time.Time
		var capacity, booked int
		if err := rows.Scan(&id, &starts, &ends, &capacity, &booked); err != nil {
			writeError(w, 500, "INTERNAL_ERROR", "Unable to read availability.")
			return
		}
		items = append(items, map[string]interface{}{"id": id, "starts_at": starts, "ends_at": ends, "remaining_capacity": capacity - booked})
	}
	writeJSON(w, 200, map[string]interface{}{"data": items, "meta": map[string]interface{}{"count": len(items)}})
}

func (s *Service) CreateOrder(w http.ResponseWriter, r *http.Request, userID string) {
	var req createOrderRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&req); err != nil {
		writeError(w, 400, "VALIDATION_ERROR", "Invalid order payload.")
		return
	}
	req.OrderType = strings.TrimSpace(req.OrderType)
	if req.OrderType != "food_delivery" && req.OrderType != "table_reservation" && req.OrderType != "hotel_booking" {
		writeError(w, 400, "VALIDATION_ERROR", "Unsupported order type.")
		return
	}
	businessID := r.PathValue("id")
	orderID := uuid.NewString()
	reference := "GN-" + strings.ToUpper(strings.ReplaceAll(orderID[:8], "-", ""))
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var name string
		var delivery, tableBooking, roomBooking bool
		var fee, minimum float64
		var eta int
		if err := tx.QueryRowx(`SELECT name,delivery_enabled,table_booking_enabled,room_booking_enabled,delivery_fee,min_order_amount,delivery_time_mins FROM businesses WHERE id=$1 AND status='approved'`, businessID).
			Scan(&name, &delivery, &tableBooking, &roomBooking, &fee, &minimum, &eta); err != nil {
			return err
		}
		var itemTotal, deliveryFee float64
		status := "placed"
		var reservationAt, reservationEnd interface{}
		var guestCount interface{}
		var roomProduct interface{}
		switch req.OrderType {
		case "food_delivery":
			if !delivery || (req.FulfillmentType != "delivery" && req.FulfillmentType != "takeaway") {
				return errors.New("food ordering is unavailable")
			}
			if len(req.Items) == 0 || len(req.Items) > 50 {
				return errors.New("order must contain 1 to 50 items")
			}
			for _, requested := range req.Items {
				if requested.Quantity < 1 || requested.Quantity > 50 {
					return errors.New("invalid item quantity")
				}
				var productName, dietary string
				var price float64
				if err := tx.QueryRowx(`SELECT name,price,COALESCE(dietary_type,'') FROM products WHERE id=$1 AND business_id=$2 AND is_published=true AND stock_status!='out_of_stock' FOR SHARE`, requested.ProductID, businessID).Scan(&productName, &price, &dietary); err != nil {
					return errors.New("product unavailable")
				}
				itemTotal += price * float64(requested.Quantity)
				if _, err := tx.Exec(`INSERT INTO customer_order_items(order_id,product_id,product_name,unit_price,quantity,dietary_type) VALUES($1,$2,$3,$4,$5,$6)`, orderID, requested.ProductID, productName, price, requested.Quantity, dietary); err != nil {
					return err
				}
			}
			if itemTotal < minimum {
				return fmt.Errorf("minimum order is %.2f", minimum)
			}
			if req.FulfillmentType == "delivery" {
				if strings.TrimSpace(req.DeliveryAddress) == "" {
					return errors.New("delivery address required")
				}
				deliveryFee = fee
			}
		case "table_reservation":
			if !tableBooking || req.ReservationAt == nil || req.GuestCount == nil || *req.GuestCount < 1 || *req.GuestCount > 20 {
				return errors.New("invalid or unavailable table reservation")
			}
			if req.ReservationAt.Before(time.Now().Add(30 * time.Minute)) {
				return errors.New("reservation must be in the future")
			}
			status = "confirmed"
			reservationAt = *req.ReservationAt
			guestCount = *req.GuestCount
		case "hotel_booking":
			if !roomBooking || req.ReservationAt == nil || req.ReservationEnd == nil || req.GuestCount == nil || req.RoomProductID == "" {
				return errors.New("invalid or unavailable room booking")
			}
			if !req.ReservationEnd.After(*req.ReservationAt) || req.ReservationAt.Before(time.Now()) {
				return errors.New("invalid stay dates")
			}
			nights := int(req.ReservationEnd.Sub(*req.ReservationAt).Hours() / 24)
			if nights < 1 || nights > 30 {
				return errors.New("stay must be 1 to 30 nights")
			}
			var productName string
			var price float64
			if err := tx.QueryRowx(`SELECT name,price FROM products WHERE id=$1 AND business_id=$2 AND is_published=true AND stock_status!='out_of_stock' FOR SHARE`, req.RoomProductID, businessID).Scan(&productName, &price); err != nil {
				return errors.New("room unavailable")
			}
			itemTotal = price * float64(nights)
			status = "confirmed"
			reservationAt = *req.ReservationAt
			reservationEnd = *req.ReservationEnd
			guestCount = *req.GuestCount
			roomProduct = req.RoomProductID
			if _, err := tx.Exec(`INSERT INTO customer_order_items(order_id,product_id,product_name,unit_price,quantity) VALUES($1,$2,$3,$4,$5)`, orderID, req.RoomProductID, productName, price, nights); err != nil {
				return err
			}
		}
		_, err := tx.Exec(`INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,fulfillment_type,delivery_address,customer_notes,item_total,delivery_fee,tax_amount,grand_total,eta_minutes,reservation_at,reservation_end_at,guest_count,seating_area,room_product_id,reference_code) VALUES($1,$2,$3,$4,$5,NULLIF($6,''),NULLIF($7,''),NULLIF($8,''),$9,$10,0,$11,$12,$13,$14,$15,NULLIF($16,''),$17,$18)`, orderID, userID, businessID, req.OrderType, status, req.FulfillmentType, strings.TrimSpace(req.DeliveryAddress), strings.TrimSpace(req.Notes), itemTotal, deliveryFee, itemTotal+deliveryFee, eta, reservationAt, reservationEnd, guestCount, strings.TrimSpace(req.SeatingArea), roomProduct, reference)
		return err
	})
	if err != nil {
		writeError(w, 400, "ORDER_REJECTED", err.Error())
		return
	}
	order, err := s.loadOrder(r.Context(), orderID, userID, false)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Order created but could not be loaded.")
		return
	}
	writeJSON(w, 201, map[string]interface{}{"data": order, "meta": map[string]string{"request_id": "create-order"}})
}

func (s *Service) ListOrders(w http.ResponseWriter, r *http.Request, userID string) {
	rows, err := s.db.QueryxContext(r.Context(), orderSelect+` WHERE o.customer_user_id=$1 ORDER BY o.created_at DESC LIMIT 100`, userID)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load orders.")
		return
	}
	defer rows.Close()
	items := make([]orderResponse, 0)
	for rows.Next() {
		var o orderResponse
		if err := rows.StructScan(&o); err != nil {
			writeError(w, 500, "INTERNAL_ERROR", "Unable to read orders.")
			return
		}
		o.Items = s.loadItems(r.Context(), o.ID)
		items = append(items, o)
	}
	writeJSON(w, 200, map[string]interface{}{"data": items, "meta": map[string]interface{}{"count": len(items)}})
}

func (s *Service) GetOrder(w http.ResponseWriter, r *http.Request, userID string) {
	o, err := s.loadOrder(r.Context(), r.PathValue("id"), userID, false)
	if err != nil {
		writeError(w, 404, "NOT_FOUND", "Order not found.")
		return
	}
	writeJSON(w, 200, map[string]interface{}{"data": o})
}

func (s *Service) CancelOrder(w http.ResponseWriter, r *http.Request, userID string) {
	res, err := s.db.ExecContext(r.Context(), `UPDATE customer_orders SET status='cancelled',cancelled_at=now(),updated_at=now() WHERE id=$1 AND customer_user_id=$2 AND status IN ('placed','confirmed')`, r.PathValue("id"), userID)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to cancel order.")
		return
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		writeError(w, 409, "INVALID_STATE", "Only a new order or reservation can be cancelled.")
		return
	}
	s.GetOrder(w, r, userID)
}

func (s *Service) UpdateOrderStatus(w http.ResponseWriter, r *http.Request, userID string) {
	var body struct {
		Status string `json:"status"`
	}
	if json.NewDecoder(r.Body).Decode(&body) != nil {
		writeError(w, 400, "VALIDATION_ERROR", "Invalid status payload.")
		return
	}
	var current, kind, businessID string
	if err := s.db.QueryRowContext(r.Context(), `SELECT status,order_type,business_id FROM customer_orders WHERE id=$1`, r.PathValue("id")).Scan(&current, &kind, &businessID); err != nil {
		writeError(w, 404, "NOT_FOUND", "Order not found.")
		return
	}
	if !s.hasMembership(r.Context(), userID, businessID) {
		writeError(w, 403, "FORBIDDEN", "Order belongs to another business.")
		return
	}
	allowed := map[string]map[string]bool{"placed": {"confirmed": true, "preparing": true, "cancelled": true}, "confirmed": {"preparing": kind == "food_delivery", "completed": kind != "food_delivery", "cancelled": true}, "preparing": {"out_for_delivery": true, "completed": true, "cancelled": true}, "out_for_delivery": {"delivered": true}, "delivered": {"completed": true}}
	if !allowed[current][body.Status] {
		writeError(w, 409, "INVALID_STATE", "Invalid order status transition.")
		return
	}
	if _, err := s.db.ExecContext(r.Context(), `UPDATE customer_orders SET status=$1,updated_at=now() WHERE id=$2`, body.Status, r.PathValue("id")); err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to update order.")
		return
	}
	o, err := s.loadOrder(r.Context(), r.PathValue("id"), userID, true)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load updated order.")
		return
	}
	writeJSON(w, 200, map[string]interface{}{"data": o})
}

const orderSelect = `SELECT o.id,o.business_id,b.name business_name,COALESCE(b.locality,'') business_locality,COALESCE(b.phone_e164,'') business_phone,COALESCE(b.cover_photo_url,'') business_cover_url,o.order_type,o.status,COALESCE(o.fulfillment_type,'') fulfillment_type,COALESCE(o.delivery_address,'') delivery_address,COALESCE(o.customer_notes,'') customer_notes,o.item_total,o.delivery_fee,o.tax_amount,o.grand_total,o.currency,o.eta_minutes,o.reservation_at,o.reservation_end_at,o.guest_count,COALESCE(o.seating_area,'') seating_area,COALESCE(o.room_product_id::text,'') room_product_id,o.reference_code,o.created_at,o.updated_at FROM customer_orders o JOIN businesses b ON b.id=o.business_id`

func (s *Service) loadOrder(ctx context.Context, id, userID string, merchant bool) (*orderResponse, error) {
	q := orderSelect + ` WHERE o.id=$1 AND o.customer_user_id=$2`
	args := []interface{}{id, userID}
	if merchant {
		q = orderSelect + ` WHERE o.id=$1`
		args = []interface{}{id}
	}
	var o orderResponse
	if err := s.db.GetContext(ctx, &o, q, args...); err != nil {
		return nil, err
	}
	o.Items = s.loadItems(ctx, id)
	return &o, nil
}
func (s *Service) loadItems(ctx context.Context, id string) []orderItem {
	items := make([]orderItem, 0)
	_ = s.db.SelectContext(ctx, &items, `SELECT product_id,product_name,unit_price,quantity,COALESCE(dietary_type,'') dietary_type FROM customer_order_items WHERE order_id=$1 ORDER BY product_name`, id)
	return items
}
func (s *Service) hasMembership(ctx context.Context, userID, businessID string) bool {
	var ok bool
	_ = s.db.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM business_members WHERE business_id=$1 AND user_id=$2 AND status='active' UNION SELECT 1 FROM businesses WHERE id=$1 AND owner_user_id=$2)`, businessID, userID).Scan(&ok)
	return ok
}

func writeJSON(w http.ResponseWriter, status int, value interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, map[string]interface{}{"error": map[string]string{"code": code, "message": message, "request_id": "err"}})
}
