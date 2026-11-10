package operations

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"

	"grepmind-near/backend/pkg/database"
)

type OrderStatusPublisher func(ctx context.Context, customerID, businessID, orderID, status string)

type Service struct {
	db                 *database.DB
	publishOrderStatus OrderStatusPublisher
}

func NewService(db *database.DB) *Service { return &Service{db: db} }

func (s *Service) SetOrderStatusPublisher(publisher OrderStatusPublisher) {
	s.publishOrderStatus = publisher
}

type cartValidationItem struct {
	ProductID string `json:"product_id"`
	Quantity  int    `json:"quantity"`
}

// ValidateCart returns a server-priced, read-only validation snapshot. It does
// not reserve stock; order creation repeats checks under row locks.
func (s *Service) ValidateCart(w http.ResponseWriter, r *http.Request, userID string) {
	var roleExists bool
	if err := s.db.QueryRowxContext(r.Context(), `SELECT EXISTS (SELECT 1 FROM user_roles WHERE user_id=$1 AND role='customer')`, userID).Scan(&roleExists); err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to validate customer access.")
		return
	}
	if !roleExists {
		writeError(w, http.StatusForbidden, "FORBIDDEN", "Customer access is required.")
		return
	}
	var req struct {
		Items []cartValidationItem `json:"items"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16<<10)).Decode(&req); err != nil || len(req.Items) == 0 || len(req.Items) > 50 {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Cart must contain 1 to 50 items.")
		return
	}
	businessID := r.PathValue("id")
	var businessName, category string
	var enabled bool
	var minimumText string
	if err := s.db.QueryRowxContext(r.Context(), `SELECT name,category_slug,delivery_enabled,min_order_amount::text FROM businesses WHERE id=$1 AND status='approved'`, businessID).Scan(&businessName, &category, &enabled, &minimumText); err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Orderable business not found.")
		return
	}
	// This first cart release supports the already-established food workflow.
	// Category names do not implicitly grant commerce capability.
	if !enabled || (category != "restaurant" && category != "cafe") {
		writeError(w, http.StatusConflict, "ORDERING_UNAVAILABLE", "This business does not currently support product ordering.")
		return
	}
	minimumMinor, ok := decimalToMinor(minimumText)
	if !ok {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Business minimum order is invalid.")
		return
	}
	seen := make(map[string]bool, len(req.Items))
	items := make([]map[string]interface{}, 0, len(req.Items))
	var subtotalMinor int64
	valid := true
	for _, requested := range req.Items {
		if requested.ProductID == "" || requested.Quantity < 1 || requested.Quantity > 50 || seen[requested.ProductID] {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Cart item IDs must be unique and quantities must be between 1 and 50.")
			return
		}
		seen[requested.ProductID] = true
		var name, currency, stockStatus, inventoryMode string
		var priceText sql.NullString
		var published bool
		var quantity sql.NullInt64
		err := s.db.QueryRowxContext(r.Context(), `SELECT name,currency,price::text,stock_status,inventory_mode,available_quantity,is_published FROM products WHERE id=$1 AND business_id=$2`, requested.ProductID, businessID).Scan(&name, &currency, &priceText, &stockStatus, &inventoryMode, &quantity, &published)
		item := map[string]interface{}{"product_id": requested.ProductID, "quantity": requested.Quantity, "available": false, "reason": "unavailable"}
		if err == nil && published && priceText.Valid && stockStatus != "out_of_stock" {
			minor, validPrice := decimalToMinor(priceText.String)
			stockOK := inventoryMode == "untracked" || (inventoryMode == "finite" && quantity.Valid && quantity.Int64 >= int64(requested.Quantity))
			if validPrice && stockOK {
				lineTotal := minor * int64(requested.Quantity)
				subtotalMinor += lineTotal
				item = map[string]interface{}{"product_id": requested.ProductID, "quantity": requested.Quantity, "name": name, "currency": strings.TrimSpace(currency), "unit_price_minor": minor, "line_total_minor": lineTotal, "inventory_mode": inventoryMode, "available_quantity": nullableInt(quantity), "available": true}
			} else if !stockOK {
				item["reason"] = "insufficient_stock"
			}
		}
		if item["available"] != true {
			valid = false
		}
		items = append(items, item)
	}
	if subtotalMinor < minimumMinor {
		valid = false
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"data": map[string]interface{}{"business_id": businessID, "business_name": businessName, "items": items, "item_subtotal_minor": subtotalMinor, "minimum_order_minor": minimumMinor, "currency": "INR", "valid": valid, "minimum_met": subtotalMinor >= minimumMinor}, "meta": map[string]interface{}{"request_id": "cart-validation"}})
}

func nullableInt(value sql.NullInt64) interface{} {
	if value.Valid {
		return value.Int64
	}
	return nil
}

func decimalToMinor(value string) (int64, bool) {
	value = strings.TrimSpace(value)
	if value == "" {
		return 0, false
	}
	parts := strings.Split(value, ".")
	if len(parts) > 2 {
		return 0, false
	}
	whole := parts[0]
	if whole == "" || whole == "+" {
		whole = "0"
	}
	negative := strings.HasPrefix(whole, "-")
	if negative {
		whole = strings.TrimPrefix(whole, "-")
	} else {
		whole = strings.TrimPrefix(whole, "+")
	}
	if whole == "" {
		return 0, false
	}
	frac := "00"
	if len(parts) == 2 {
		frac = parts[1]
		if len(frac) > 2 {
			return 0, false
		}
		for len(frac) < 2 {
			frac += "0"
		}
	}
	for _, digit := range whole + frac {
		if digit < '0' || digit > '9' {
			return 0, false
		}
	}
	minor, err := strconv.ParseInt(whole+frac, 10, 64)
	if err != nil {
		return 0, false
	}
	if negative {
		minor = -minor
	}
	return minor, true
}

func minorToDecimal(value int64) string {
	negative := value < 0
	if negative {
		value = -value
	}
	formatted := fmt.Sprintf("%d.%02d", value/100, value%100)
	if negative {
		return "-" + formatted
	}
	return formatted
}

type createItem struct {
	ProductID string `json:"product_id"`
	Quantity  int    `json:"quantity"`
}

type createOrderRequest struct {
	OrderType       string       `json:"order_type"`
	CheckoutQuoteID string       `json:"checkout_quote_id"`
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
	ProductID         string  `json:"id" db:"product_id"`
	Name              string  `json:"name" db:"product_name"`
	Price             float64 `json:"price" db:"unit_price"`
	Quantity          int     `json:"quantity" db:"quantity"`
	DietaryType       string  `json:"dietary_type,omitempty" db:"dietary_type"`
	PlatformProductID string  `json:"platform_product_id,omitempty" db:"platform_product_id"`
	VariantID         string  `json:"variant_id,omitempty" db:"variant_id"`
	VariantName       string  `json:"variant_name,omitempty" db:"variant_name"`
	UnitLabel         string  `json:"unit_label,omitempty" db:"unit_label"`
	Vertical          string  `json:"vertical,omitempty" db:"vertical"`
}

type orderResponse struct {
	ID                         string             `json:"id" db:"id"`
	BusinessID                 string             `json:"business_id" db:"business_id"`
	BusinessName               string             `json:"business_name" db:"business_name"`
	BusinessLocality           string             `json:"business_locality,omitempty" db:"business_locality"`
	BusinessPhone              string             `json:"business_phone,omitempty" db:"business_phone"`
	BusinessCoverURL           string             `json:"business_cover_url,omitempty" db:"business_cover_url"`
	OrderType                  string             `json:"order_type" db:"order_type"`
	OrderSource                string             `json:"order_source" db:"order_source"`
	PlatformVertical           string             `json:"platform_vertical,omitempty" db:"platform_vertical"`
	DeliveryLocalityID         string             `json:"delivery_locality_id,omitempty" db:"delivery_locality_id"`
	Status                     string             `json:"status" db:"status"`
	FulfillmentType            string             `json:"fulfillment_type,omitempty" db:"fulfillment_type"`
	DeliveryAddress            string             `json:"delivery_address,omitempty" db:"delivery_address"`
	DeliveryAddressID          string             `json:"delivery_address_id,omitempty" db:"delivery_address_id"`
	DeliveryAddressSnapshot    json.RawMessage    `json:"delivery_address_snapshot,omitempty" db:"-"`
	DeliveryAddressSnapshotRaw string             `json:"-" db:"delivery_address_snapshot"`
	Notes                      string             `json:"special_instructions,omitempty" db:"customer_notes"`
	ItemTotal                  float64            `json:"item_total" db:"item_total"`
	DeliveryFee                float64            `json:"delivery_fee" db:"delivery_fee"`
	TaxAmount                  float64            `json:"tax" db:"tax_amount"`
	GrandTotal                 float64            `json:"grand_total" db:"grand_total"`
	Currency                   string             `json:"currency" db:"currency"`
	PaymentStatus              string             `json:"payment_status" db:"payment_status"`
	ETAMinutes                 *int               `json:"eta_minutes,omitempty" db:"eta_minutes"`
	ReservationAt              *time.Time         `json:"reservation_at,omitempty" db:"reservation_at"`
	ReservationEnd             *time.Time         `json:"reservation_end_at,omitempty" db:"reservation_end_at"`
	GuestCount                 *int               `json:"guest_count,omitempty" db:"guest_count"`
	SeatingArea                string             `json:"seating_area,omitempty" db:"seating_area"`
	RoomProductID              string             `json:"room_product_id,omitempty" db:"room_product_id"`
	ReferenceCode              string             `json:"voucher_code" db:"reference_code"`
	CreatedAt                  time.Time          `json:"created_at" db:"created_at"`
	UpdatedAt                  time.Time          `json:"updated_at" db:"updated_at"`
	Items                      []orderItem        `json:"items" db:"-"`
	StatusEvents               []orderStatusEvent `json:"status_events,omitempty" db:"-"`
}

type orderStatusEvent struct {
	Status    string    `json:"status" db:"status"`
	EventKind string    `json:"event_kind" db:"event_kind"`
	Reason    string    `json:"reason,omitempty" db:"reason"`
	CreatedAt time.Time `json:"created_at" db:"created_at"`
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
		SELECT s.id, s.starts_at, s.ends_at, s.capacity, s.booked_count, b.time_zone
		FROM availability_slots s
		JOIN businesses b ON b.id=s.business_id
		WHERE s.business_id=$1 AND s.status='open' AND s.starts_at >= $2 AND s.starts_at < $3
		  AND s.booked_count < s.capacity
		  AND NOT EXISTS (
			SELECT 1 FROM business_availability_exceptions e
			WHERE e.business_id=s.business_id AND e.local_date=(s.starts_at AT TIME ZONE b.time_zone)::date AND e.is_closed=true
		  )
		ORDER BY s.starts_at`, businessID, from, to)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load availability.")
		return
	}
	defer rows.Close()
	items := make([]map[string]interface{}, 0)
	for rows.Next() {
		var id, zone string
		var starts, ends time.Time
		var capacity, booked int
		if err := rows.Scan(&id, &starts, &ends, &capacity, &booked, &zone); err != nil {
			writeError(w, 500, "INTERNAL_ERROR", "Unable to read availability.")
			return
		}
		location, err := time.LoadLocation(zone)
		if err != nil {
			writeError(w, 500, "INTERNAL_ERROR", "Business time zone is invalid.")
			return
		}
		items = append(items, map[string]interface{}{
			"id": id, "starts_at": starts, "ends_at": ends,
			"local_date":         starts.In(location).Format("2006-01-02"),
			"local_starts_at":    starts.In(location).Format("15:04"),
			"local_ends_at":      ends.In(location).Format("15:04"),
			"remaining_capacity": capacity - booked, "time_zone": zone,
		})
	}
	writeJSON(w, 200, map[string]interface{}{"data": items, "meta": map[string]interface{}{"count": len(items)}})
}

func (s *Service) CreateOrder(w http.ResponseWriter, r *http.Request, userID string) {
	var customerRole bool
	if err := s.db.QueryRowxContext(r.Context(), `SELECT EXISTS(SELECT 1 FROM user_roles WHERE user_id=$1 AND role='customer')`, userID).Scan(&customerRole); err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to validate customer access.")
		return
	}
	if !customerRole {
		writeError(w, http.StatusForbidden, "FORBIDDEN", "Customer access is required.")
		return
	}
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
	idempotencyKey := strings.TrimSpace(r.Header.Get("Idempotency-Key"))
	requestHash := ""
	if req.OrderType == "food_delivery" {
		if _, err := uuid.Parse(req.CheckoutQuoteID); err != nil {
			writeError(w, 400, "QUOTE_REQUIRED", "Refresh checkout and submit a valid server quote.")
			return
		}
		if _, err := uuid.Parse(idempotencyKey); err != nil {
			writeError(w, 400, "IDEMPOTENCY_KEY_REQUIRED", "A valid Idempotency-Key is required for food checkout.")
			return
		}
		sum := sha256.Sum256([]byte(userID + "|" + businessID + "|" + req.CheckoutQuoteID))
		requestHash = hex.EncodeToString(sum[:])
	}
	orderID := uuid.NewString()
	reference := "GN-" + strings.ToUpper(strings.ReplaceAll(orderID[:8], "-", ""))
	replayed := false
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if req.OrderType == "food_delivery" {
			if err := lockCustomer(tx, userID); err != nil {
				return err
			}
			var existingID, existingHash string
			err := tx.QueryRowxContext(r.Context(), `SELECT id::text,COALESCE(checkout_request_hash,'') FROM customer_orders WHERE customer_user_id=$1 AND checkout_idempotency_key=$2`, userID, idempotencyKey).Scan(&existingID, &existingHash)
			if err == nil {
				if existingHash != requestHash {
					return checkoutError(409, "IDEMPOTENCY_CONFLICT", "This idempotency key was already used for a different checkout.")
				}
				orderID = existingID
				replayed = true
				return nil
			}
			if !errors.Is(err, sql.ErrNoRows) {
				return err
			}
		}
		var name string
		var delivery, tableBooking, roomBooking bool
		var feeText, minimumText string
		var eta int
		if err := tx.QueryRowx(`SELECT name,delivery_enabled,table_booking_enabled,room_booking_enabled,delivery_fee::text,min_order_amount::text,delivery_time_mins FROM businesses WHERE id=$1 AND status='approved'`, businessID).
			Scan(&name, &delivery, &tableBooking, &roomBooking, &feeText, &minimumText, &eta); err != nil {
			return err
		}
		var itemTotal, deliveryFee float64
		var foodSubtotalMinor, deliveryFeeMinor, foodTaxMinor int64
		status := "placed"
		var reservationAt, reservationEnd interface{}
		var guestCount interface{}
		var roomProduct interface{}
		var addressID, addressSnapshot interface{}
		var consumedQuoteID interface{}
		switch req.OrderType {
		case "food_delivery":
			var quoteFulfillment string
			var quoteAddressID, quoteConsumedOrder sql.NullString
			var quoteAddressUpdated sql.NullTime
			var quoteItemsJSON []byte
			var quoteSubtotal, quoteMinimum, quoteDelivery, quoteTax, quoteGrand int64
			var quoteCurrency string
			var quoteExpiry time.Time
			if err := tx.QueryRowxContext(r.Context(), `SELECT fulfillment_type,address_id::text,address_updated_at,items,item_subtotal_minor,minimum_order_minor,delivery_fee_minor,tax_minor,grand_total_minor,currency,expires_at,consumed_order_id::text
				FROM checkout_quotes WHERE id=$1 AND customer_user_id=$2 AND business_id=$3 FOR UPDATE`, req.CheckoutQuoteID, userID, businessID).
				Scan(&quoteFulfillment, &quoteAddressID, &quoteAddressUpdated, &quoteItemsJSON, &quoteSubtotal, &quoteMinimum, &quoteDelivery, &quoteTax, &quoteGrand, &quoteCurrency, &quoteExpiry, &quoteConsumedOrder); err != nil {
				return checkoutError(404, "QUOTE_NOT_FOUND", "Checkout quote not found for this customer and merchant.")
			}
			if quoteExpiry.Before(time.Now()) {
				return checkoutError(409, "QUOTE_EXPIRED", "Checkout quote expired. Refresh prices and availability.")
			}
			if quoteConsumedOrder.Valid {
				return checkoutError(409, "QUOTE_ALREADY_USED", "This checkout quote has already been submitted. Retry with its original idempotency key.")
			}
			if quoteFulfillment != req.FulfillmentType || (quoteFulfillment != "delivery" && quoteFulfillment != "takeaway") {
				return checkoutError(409, "QUOTE_MISMATCH", "Checkout fulfillment changed. Refresh the quote.")
			}
			business, err := loadQuoteBusiness(tx, businessID)
			if err != nil || !business.DeliveryEnabled || (business.Category != "restaurant" && business.Category != "cafe") {
				return checkoutError(409, "ORDERING_UNAVAILABLE", "This business does not currently support food ordering.")
			}
			open, err := isBusinessOpen(tx, businessID, time.Now())
			if err != nil {
				return err
			}
			if !open {
				return checkoutError(409, "MERCHANT_CLOSED", "This merchant is outside its published operating hours.")
			}
			currentMinimum, ok := decimalToMinor(business.MinimumOrder)
			if !ok || currentMinimum != quoteMinimum {
				return checkoutError(409, "QUOTE_STALE", "Merchant minimum changed. Refresh the checkout quote.")
			}
			currentFee, ok := decimalToMinor(business.DeliveryFee)
			if !ok || (quoteFulfillment == "delivery" && currentFee != quoteDelivery) || (quoteFulfillment == "takeaway" && quoteDelivery != 0) {
				return checkoutError(409, "QUOTE_STALE", "Delivery charges changed. Refresh the checkout quote.")
			}
			if quoteFulfillment == "delivery" {
				var value customerAddress
				if err := tx.GetContext(r.Context(), &value, addressSelect+` WHERE id=$1 AND customer_user_id=$2`, quoteAddressID.String, userID); err != nil || !quoteAddressUpdated.Valid || !value.UpdatedAt.Equal(quoteAddressUpdated.Time) {
					return checkoutError(422, "INVALID_ADDRESS", "Delivery address changed or was removed. Select it and refresh the quote.")
				}
				if _, err := deliveryServiceability(tx, businessID, business, value); err != nil {
					return err
				}
				addressID = quoteAddressID.String
				snapshot, err := json.Marshal(value.public())
				if err != nil {
					return err
				}
				addressSnapshot = string(snapshot)
				req.DeliveryAddress = formatAddress(value)
			} else if quoteAddressID.Valid {
				return checkoutError(409, "QUOTE_MISMATCH", "Takeaway checkout cannot contain a delivery address.")
			}
			if quoteCurrency != "INR" || quoteTax < 0 || quoteGrand != quoteSubtotal+quoteDelivery+quoteTax {
				return checkoutError(409, "QUOTE_STALE", "Checkout quote totals are invalid. Refresh the quote.")
			}
			var quotedItems []checkoutQuoteItem
			if err := json.Unmarshal(quoteItemsJSON, &quotedItems); err != nil || len(quotedItems) == 0 || len(quotedItems) > 50 {
				return checkoutError(409, "QUOTE_STALE", "Checkout quote contents are invalid. Refresh the quote.")
			}
			req.Items = make([]createItem, 0, len(quotedItems))
			quotedByID := make(map[string]checkoutQuoteItem, len(quotedItems))
			for _, item := range quotedItems {
				req.Items = append(req.Items, createItem{ProductID: item.ProductID, Quantity: item.Quantity})
				quotedByID[item.ProductID] = item
			}
			if len(req.Items) == 0 || len(req.Items) > 50 {
				return checkoutError(409, "QUOTE_STALE", "Checkout quote contents are invalid. Refresh the quote.")
			}
			minimumMinor, validMinimum := decimalToMinor(minimumText)
			if !validMinimum || minimumMinor != quoteMinimum {
				return checkoutError(409, "QUOTE_STALE", "Merchant minimum changed. Refresh the checkout quote.")
			}
			configuredFeeMinor, validFee := decimalToMinor(feeText)
			if !validFee {
				return errors.New("delivery fee is invalid")
			}
			seenProducts := make(map[string]bool, len(req.Items))
			for _, requested := range req.Items {
				if requested.Quantity < 1 || requested.Quantity > 50 {
					return errors.New("invalid item quantity")
				}
				if seenProducts[requested.ProductID] {
					return errors.New("duplicate order item")
				}
				seenProducts[requested.ProductID] = true
				var productName, dietary, priceText, inventoryMode, stockStatus string
				var available sql.NullInt64
				err := tx.QueryRowx(`SELECT name,price::text,COALESCE(dietary_type,''),inventory_mode,available_quantity,stock_status FROM products WHERE id=$1 AND business_id=$2 AND is_published=true FOR UPDATE`, requested.ProductID, businessID).Scan(&productName, &priceText, &dietary, &inventoryMode, &available, &stockStatus)
				if errors.Is(err, sql.ErrNoRows) || (err == nil && stockStatus == "out_of_stock") {
					return checkoutError(409, "ITEM_UNAVAILABLE", "A cart item is no longer available. Refresh the cart.")
				}
				if err != nil {
					return err
				}
				priceMinor, validPrice := decimalToMinor(priceText)
				if !validPrice {
					return errors.New("product price is invalid")
				}
				quoted, exists := quotedByID[requested.ProductID]
				if !exists || quoted.Quantity != requested.Quantity || quoted.UnitPriceMinor != priceMinor || quoted.Name != productName {
					return checkoutError(409, "QUOTE_STALE", "A product price or detail changed. Refresh the checkout quote.")
				}
				if inventoryMode == "finite" {
					if !available.Valid || available.Int64 < int64(requested.Quantity) {
						return checkoutError(409, "INSUFFICIENT_STOCK", "Cart quantity exceeds current stock. Refresh the cart.")
					}
					remaining := available.Int64 - int64(requested.Quantity)
					newStatus := "in_stock"
					if remaining == 0 {
						newStatus = "out_of_stock"
					}
					if _, err := tx.Exec(`UPDATE products SET available_quantity=$2,stock_status=$3,updated_at=now() WHERE id=$1`, requested.ProductID, remaining, newStatus); err != nil {
						return err
					}
				} else if inventoryMode != "untracked" {
					return errors.New("product inventory mode is invalid")
				}
				foodSubtotalMinor += priceMinor * int64(requested.Quantity)
				if _, err := tx.Exec(`INSERT INTO customer_order_items(order_id,product_id,product_name,unit_price,quantity,dietary_type) VALUES($1,$2,$3,$4,$5,$6)`, orderID, requested.ProductID, productName, fmt.Sprintf("%d.%02d", priceMinor/100, priceMinor%100), requested.Quantity, dietary); err != nil {
					return err
				}
			}
			if foodSubtotalMinor < minimumMinor {
				return fmt.Errorf("minimum order is %s", minorToDecimal(minimumMinor))
			}
			itemTotal = float64(foodSubtotalMinor) / 100
			if req.FulfillmentType == "delivery" {
				deliveryFeeMinor = configuredFeeMinor
				deliveryFee = float64(deliveryFeeMinor) / 100
			}
			if foodSubtotalMinor != quoteSubtotal || foodSubtotalMinor < quoteMinimum || deliveryFeeMinor != quoteDelivery || foodSubtotalMinor+deliveryFeeMinor+quoteTax != quoteGrand {
				return checkoutError(409, "QUOTE_STALE", "Cart availability or checkout pricing changed. Refresh the quote.")
			}
			foodTaxMinor = quoteTax
			consumedQuoteID = req.CheckoutQuoteID
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
		var itemTotalValue, deliveryFeeValue, grandTotalValue interface{} = itemTotal, deliveryFee, itemTotal + deliveryFee
		if req.OrderType == "food_delivery" {
			itemTotalValue = minorToDecimal(foodSubtotalMinor)
			deliveryFeeValue = minorToDecimal(deliveryFeeMinor)
			grandTotalValue = minorToDecimal(foodSubtotalMinor + deliveryFeeMinor + foodTaxMinor)
		}
		var idempotencyValue, requestHashValue interface{}
		if req.OrderType == "food_delivery" {
			idempotencyValue, requestHashValue = idempotencyKey, requestHash
		}
		_, err := tx.Exec(`INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,fulfillment_type,delivery_address,delivery_address_id,delivery_address_snapshot,checkout_quote_id,checkout_idempotency_key,checkout_request_hash,payment_status,customer_notes,item_total,delivery_fee,tax_amount,grand_total,eta_minutes,reservation_at,reservation_end_at,guest_count,seating_area,room_product_id,reference_code) VALUES($1,$2,$3,$4,$5,NULLIF($6,''),NULLIF($7,''),NULLIF($8,'')::uuid,$9::jsonb,NULLIF($10,'')::uuid,NULLIF($11,'')::uuid,NULLIF($12,''),'not_collected',NULLIF($13,''),$14,$15,$16,$17,$18,$19,$20,$21,NULLIF($22,''),$23,$24)`, orderID, userID, businessID, req.OrderType, status, req.FulfillmentType, strings.TrimSpace(req.DeliveryAddress), addressID, addressSnapshot, consumedQuoteID, idempotencyValue, requestHashValue, strings.TrimSpace(req.Notes), itemTotalValue, deliveryFeeValue, minorToDecimal(foodTaxMinor), grandTotalValue, eta, reservationAt, reservationEnd, guestCount, strings.TrimSpace(req.SeatingArea), roomProduct, reference)
		if err != nil {
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO customer_order_status_events(order_id,status,event_kind,actor_user_id) VALUES($1,$2,'status_change',$3)`, orderID, status, userID); err != nil {
			return err
		}
		if req.OrderType == "food_delivery" {
			if _, err := tx.Exec(`UPDATE checkout_quotes SET consumed_order_id=$2 WHERE id=$1 AND consumed_order_id IS NULL`, req.CheckoutQuoteID, orderID); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		var failure *checkoutFailure
		if errors.As(err, &failure) {
			writeError(w, failure.status, failure.code, failure.message)
		} else {
			writeError(w, 400, "ORDER_REJECTED", err.Error())
		}
		return
	}
	order, err := s.loadOrder(r.Context(), orderID, userID, false)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Order created but could not be loaded.")
		return
	}
	if !replayed {
		s.publishStatus(r.Context(), userID, businessID, orderID, order.Status)
	}
	status := http.StatusCreated
	meta := map[string]interface{}{"request_id": "create-order", "idempotent_replay": false}
	if replayed {
		status = http.StatusOK
		meta["idempotent_replay"] = true
	}
	writeJSON(w, status, map[string]interface{}{"data": order, "meta": meta})
}

func (s *Service) ListOrders(w http.ResponseWriter, r *http.Request, userID string) {
	limit := 20
	if raw := r.URL.Query().Get("limit"); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed < 1 || parsed > 50 {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "limit must be between 1 and 50.")
			return
		}
		limit = parsed
	}
	statusFilter := r.URL.Query().Get("status")
	if statusFilter != "" && !validOrderStatus(statusFilter) {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Unsupported order status filter.")
		return
	}
	typeFilter := r.URL.Query().Get("order_type")
	if typeFilter != "" && typeFilter != "food_delivery" && typeFilter != "table_reservation" && typeFilter != "hotel_booking" && typeFilter != "platform_order" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Unsupported order type filter.")
		return
	}
	query := orderSelect + ` WHERE o.customer_user_id=$1`
	args := []interface{}{userID}
	if statusFilter != "" {
		args = append(args, statusFilter)
		query += fmt.Sprintf(" AND o.status=$%d", len(args))
	}
	if typeFilter != "" {
		args = append(args, typeFilter)
		query += fmt.Sprintf(" AND o.order_type=$%d", len(args))
	}
	if raw := r.URL.Query().Get("before"); raw != "" {
		cursorTime, cursorID, ok := decodeOrderCursor(raw)
		if !ok {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Invalid order page cursor.")
			return
		}
		args = append(args, cursorTime, cursorID)
		query += fmt.Sprintf(" AND (o.created_at,o.id) < ($%d,$%d::uuid)", len(args)-1, len(args))
	}
	args = append(args, limit+1)
	query += fmt.Sprintf(" ORDER BY o.created_at DESC,o.id DESC LIMIT $%d", len(args))
	rows, err := s.db.QueryxContext(r.Context(), query, args...)
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
		o.populateAddressSnapshot()
		o.Items = s.loadItems(r.Context(), o.ID)
		items = append(items, o)
	}
	if err := rows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to read orders.")
		return
	}
	hasMore := len(items) > limit
	if hasMore {
		items = items[:limit]
	}
	meta := map[string]interface{}{"count": len(items), "has_more": hasMore}
	if hasMore && len(items) > 0 {
		last := items[len(items)-1]
		meta["next_cursor"] = encodeOrderCursor(last.CreatedAt, last.ID)
	}
	writeJSON(w, 200, map[string]interface{}{"data": items, "meta": meta})
}

func (s *Service) GetOrder(w http.ResponseWriter, r *http.Request, userID string) {
	o, err := s.loadOrder(r.Context(), r.PathValue("id"), userID, false)
	if err != nil {
		writeError(w, 404, "NOT_FOUND", "Order not found.")
		return
	}
	writeJSON(w, 200, map[string]interface{}{"data": o})
}

func (s *Service) CreateOrderSupportReport(w http.ResponseWriter, r *http.Request, userID string) {
	orderID := r.PathValue("id")
	var req struct {
		Reason string `json:"reason"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8<<10)).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "A valid support reason is required.")
		return
	}
	reason := strings.TrimSpace(req.Reason)
	if len(reason) < 10 || len(reason) > 1000 {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Support details must be between 10 and 1000 characters.")
		return
	}
	var reportID string
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if _, err := tx.ExecContext(r.Context(), `SELECT pg_advisory_xact_lock(hashtextextended($1 || ':' || $2, 0))`, userID, orderID); err != nil {
			return err
		}
		var exists bool
		if err := tx.QueryRowxContext(r.Context(), `SELECT EXISTS(SELECT 1 FROM customer_orders WHERE id=$1 AND customer_user_id=$2)`, orderID, userID).Scan(&exists); err != nil {
			return err
		}
		if !exists {
			return sql.ErrNoRows
		}
		// Return the user's already-open order report on repeat taps/retries.
		err := tx.QueryRowxContext(r.Context(), `SELECT id::text FROM reports WHERE reporter_user_id=$1 AND target_type='order' AND target_id=$2 AND status='open' ORDER BY created_at DESC LIMIT 1`, userID, orderID).Scan(&reportID)
		if err == nil {
			return nil
		}
		if !errors.Is(err, sql.ErrNoRows) {
			return err
		}
		return tx.QueryRowxContext(r.Context(), `INSERT INTO reports(reporter_user_id,target_type,target_id,reason) VALUES($1,'order',$2,$3) RETURNING id::text`, userID, orderID, reason).Scan(&reportID)
	})
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Order not found.")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to submit order support request.")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]interface{}{"data": map[string]string{"report_id": reportID, "status": "open"}})
}

func (s *Service) CancelOrder(w http.ResponseWriter, r *http.Request, userID string) {
	var cancelled bool
	var alreadyCancelled bool
	orderID := r.PathValue("id")
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var kind string
		if err := tx.QueryRowx(`UPDATE customer_orders SET status='cancelled',cancelled_at=now(),updated_at=now() WHERE id=$1 AND customer_user_id=$2 AND status IN ('placed','accepted','confirmed') RETURNING order_type`, orderID, userID).Scan(&kind); err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				var currentStatus string
				if err := tx.QueryRowx(`SELECT status FROM customer_orders WHERE id=$1 AND customer_user_id=$2 FOR UPDATE`, orderID, userID).Scan(&currentStatus); errors.Is(err, sql.ErrNoRows) {
					return nil
				} else if err != nil {
					return err
				} else if currentStatus == "cancelled" {
					cancelled, alreadyCancelled = true, true
				}
				return nil
			}
			return err
		}
		cancelled = true
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO customer_order_status_events(order_id,status,event_kind,actor_user_id) VALUES($1,'cancelled','status_change',$2)`, orderID, userID); err != nil {
			return err
		}
		if kind == "food_delivery" || kind == "platform_order" {
			return restoreOrderInventory(tx, orderID)
		}
		return nil
	})
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to cancel order.")
		return
	}
	if !cancelled {
		var owned bool
		if err := s.db.GetContext(r.Context(), &owned, `SELECT EXISTS(SELECT 1 FROM customer_orders WHERE id=$1 AND customer_user_id=$2)`, r.PathValue("id"), userID); err != nil {
			writeError(w, 500, "INTERNAL_ERROR", "Unable to check order state.")
			return
		}
		if !owned {
			writeError(w, 404, "NOT_FOUND", "Order not found.")
			return
		}
		writeError(w, 409, "INVALID_STATE", "Only a new order or reservation can be cancelled.")
		return
	}
	if !alreadyCancelled {
		var businessID string
		_ = s.db.QueryRowxContext(r.Context(), `SELECT business_id::text FROM customer_orders WHERE id=$1 AND customer_user_id=$2`, orderID, userID).Scan(&businessID)
		s.publishStatus(r.Context(), userID, businessID, orderID, "cancelled")
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
	var current, kind, businessID, customerID, source string
	if err := s.db.QueryRowContext(r.Context(), `SELECT status,order_type,business_id,customer_user_id,order_source FROM customer_orders WHERE id=$1`, r.PathValue("id")).Scan(&current, &kind, &businessID, &customerID, &source); err != nil {
		writeError(w, 404, "NOT_FOUND", "Order not found.")
		return
	}
	if source == "platform_catalog" {
		writeError(w, 409, "INVALID_STATE", "Use the assigned partner fulfillment actions for this Grepmind order.")
		return
	}
	if !s.hasMembership(r.Context(), userID, businessID) {
		writeError(w, 403, "FORBIDDEN", "Order belongs to another business.")
		return
	}
	foodOrder := kind == "food_delivery" || kind == "platform_order"
	allowed := map[string]map[string]bool{"placed": {"confirmed": true, "preparing": true, "cancelled": true}, "confirmed": {"preparing": foodOrder, "completed": !foodOrder, "cancelled": true}, "preparing": {"out_for_delivery": true, "completed": true, "cancelled": true}, "out_for_delivery": {"delivered": true}, "delivered": {"completed": true}}
	if !allowed[current][body.Status] {
		writeError(w, 409, "INVALID_STATE", "Invalid order status transition.")
		return
	}
	var affected int64
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		result, err := tx.ExecContext(r.Context(), `
		UPDATE customer_orders o SET status=$1,updated_at=now()
		WHERE o.id=$2 AND o.business_id=$3 AND o.status=$4 AND EXISTS (
			SELECT 1 FROM business_members bm WHERE bm.business_id=o.business_id AND bm.user_id=$5 AND bm.status='active'
			UNION SELECT 1 FROM businesses b WHERE b.id=o.business_id AND b.owner_user_id=$5 AND b.status!='deleted'
		)
	`, body.Status, r.PathValue("id"), businessID, current, userID)
		if err != nil {
			return err
		}
		affected, err = result.RowsAffected()
		if err != nil || affected == 0 {
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO customer_order_status_events(order_id,status,event_kind,actor_user_id) VALUES($1,$2,'status_change',$3)`, r.PathValue("id"), body.Status, userID); err != nil {
			return err
		}
		if body.Status == "cancelled" && (kind == "food_delivery" || kind == "platform_order") {
			return restoreOrderInventory(tx, r.PathValue("id"))
		}
		return nil
	})
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to update order.")
		return
	}
	if affected == 0 {
		if !s.hasMembership(r.Context(), userID, businessID) {
			writeError(w, 403, "FORBIDDEN", "Order belongs to another business.")
			return
		}
		writeError(w, 409, "INVALID_STATE", "Order status changed; reload before retrying.")
		return
	}
	s.publishStatus(r.Context(), customerID, businessID, r.PathValue("id"), body.Status)
	o, err := s.loadOrder(r.Context(), r.PathValue("id"), userID, true)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load updated order.")
		return
	}
	writeJSON(w, 200, map[string]interface{}{"data": o})
}

func restoreOrderInventory(tx *sqlx.Tx, orderID string) error {
	rows, err := tx.Queryx(`SELECT p.id,i.quantity FROM customer_order_items i JOIN products p ON p.id=i.product_id WHERE i.order_id=$1 AND p.inventory_mode='finite' FOR UPDATE OF p`, orderID)
	if err != nil {
		return err
	}
	type stockLine struct {
		ProductID string `db:"id"`
		Quantity  int    `db:"quantity"`
	}
	var lines []stockLine
	for rows.Next() {
		var line stockLine
		if err := rows.StructScan(&line); err != nil {
			rows.Close()
			return err
		}
		lines = append(lines, line)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return err
	}
	rows.Close()
	for _, line := range lines {
		if _, err := tx.Exec(`UPDATE products SET available_quantity=available_quantity+$2,stock_status='in_stock',updated_at=now() WHERE id=$1 AND inventory_mode='finite'`, line.ProductID, line.Quantity); err != nil {
			return err
		}
	}
	reservations, err := tx.Queryx(`SELECT id::text,mapping_id::text,quantity,inventory_mode FROM platform_inventory_reservations WHERE order_id=$1 AND status='reserved' ORDER BY mapping_id FOR UPDATE`, orderID)
	if err != nil {
		return err
	}
	type reservation struct {
		ID        string `db:"id"`
		MappingID string `db:"mapping_id"`
		Quantity  int    `db:"quantity"`
		Mode      string `db:"inventory_mode"`
	}
	var held []reservation
	for reservations.Next() {
		var item reservation
		if err := reservations.StructScan(&item); err != nil {
			reservations.Close()
			return err
		}
		held = append(held, item)
	}
	if err := reservations.Err(); err != nil {
		reservations.Close()
		return err
	}
	reservations.Close()
	for _, item := range held {
		if item.Mode == "finite" {
			if _, err := tx.Exec(`UPDATE platform_partner_product_mappings SET available_quantity=available_quantity+$2,updated_at=now() WHERE id=$1 AND inventory_mode='finite'`, item.MappingID, item.Quantity); err != nil {
				return err
			}
		}
		if _, err := tx.Exec(`UPDATE platform_inventory_reservations SET status='released',updated_at=now() WHERE id=$1 AND status='reserved'`, item.ID); err != nil {
			return err
		}
	}
	return nil
}

const orderSelect = `SELECT o.id,o.business_id,b.name business_name,COALESCE(b.locality,'') business_locality,COALESCE(b.phone_e164,'') business_phone,COALESCE(b.cover_photo_url,'') business_cover_url,o.order_type,o.order_source,COALESCE(o.platform_vertical,'') platform_vertical,COALESCE(o.delivery_locality_id::text,'') delivery_locality_id,o.status,COALESCE(o.fulfillment_type,'') fulfillment_type,COALESCE(o.delivery_address,'') delivery_address,COALESCE(o.delivery_address_id::text,'') delivery_address_id,COALESCE(o.delivery_address_snapshot::text,'') delivery_address_snapshot,COALESCE(o.customer_notes,'') customer_notes,o.item_total,o.delivery_fee,o.tax_amount,o.grand_total,o.currency,COALESCE(o.payment_status,'not_collected') payment_status,o.eta_minutes,o.reservation_at,o.reservation_end_at,o.guest_count,COALESCE(o.seating_area,'') seating_area,COALESCE(o.room_product_id::text,'') room_product_id,o.reference_code,o.created_at,o.updated_at FROM customer_orders o JOIN businesses b ON b.id=o.business_id`

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
	o.populateAddressSnapshot()
	o.Items = s.loadItems(ctx, id)
	o.StatusEvents = make([]orderStatusEvent, 0)
	if err := s.db.SelectContext(ctx, &o.StatusEvents, `SELECT status,event_kind,COALESCE(reason,'') reason,created_at FROM customer_order_status_events WHERE order_id=$1 ORDER BY created_at,id`, id); err != nil {
		return nil, err
	}
	return &o, nil
}

func validOrderStatus(status string) bool {
	switch status {
	case "placed", "accepted", "confirmed", "preparing", "ready_for_pickup", "rejected", "out_for_delivery", "delivered", "completed", "cancelled":
		return true
	default:
		return false
	}
}

func encodeOrderCursor(createdAt time.Time, id string) string {
	return base64.RawURLEncoding.EncodeToString([]byte(createdAt.UTC().Format(time.RFC3339Nano) + "|" + id))
}

func decodeOrderCursor(raw string) (time.Time, string, bool) {
	decoded, err := base64.RawURLEncoding.DecodeString(raw)
	if err != nil {
		return time.Time{}, "", false
	}
	parts := strings.Split(string(decoded), "|")
	if len(parts) != 2 {
		return time.Time{}, "", false
	}
	createdAt, err := time.Parse(time.RFC3339Nano, parts[0])
	if err != nil {
		return time.Time{}, "", false
	}
	if _, err := uuid.Parse(parts[1]); err != nil {
		return time.Time{}, "", false
	}
	return createdAt, parts[1], true
}

func (s *Service) publishStatus(ctx context.Context, customerID, businessID, orderID, status string) {
	if s.publishOrderStatus != nil {
		s.publishOrderStatus(ctx, customerID, businessID, orderID, status)
	}
}

func (o *orderResponse) populateAddressSnapshot() {
	if o.DeliveryAddressSnapshotRaw != "" {
		o.DeliveryAddressSnapshot = json.RawMessage(o.DeliveryAddressSnapshotRaw)
	}
}
func (s *Service) loadItems(ctx context.Context, id string) []orderItem {
	items := make([]orderItem, 0)
	_ = s.db.SelectContext(ctx, &items, `SELECT product_id::text,product_name,unit_price,quantity,COALESCE(dietary_type,'') dietary_type,'' platform_product_id,'' variant_id,'' variant_name,'' unit_label,'' vertical FROM customer_order_items WHERE order_id=$1
		UNION ALL
		SELECT variant_id::text,product_name,unit_price_minor::numeric/100,quantity,'' dietary_type,product_id::text,variant_id::text,variant_name,unit_label,vertical FROM platform_customer_order_items WHERE order_id=$1
		ORDER BY product_name`, id)
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
