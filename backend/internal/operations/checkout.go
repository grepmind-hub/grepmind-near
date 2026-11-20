package operations

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"math"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
)

type checkoutFailure struct {
	status  int
	code    string
	message string
}

func (e *checkoutFailure) Error() string { return e.message }

func checkoutError(status int, code, message string) error {
	return &checkoutFailure{status: status, code: code, message: message}
}

type addressInput struct {
	Label         string   `json:"label"`
	RecipientName string   `json:"recipient_name"`
	AddressLine1  string   `json:"address_line1"`
	Locality      string   `json:"locality"`
	LocalityID    string   `json:"locality_id,omitempty"`
	Landmark      string   `json:"landmark"`
	City          string   `json:"city"`
	State         string   `json:"state"`
	PostalCode    string   `json:"postal_code"`
	ContactPhone  string   `json:"contact_phone"`
	Latitude      *float64 `json:"latitude"`
	Longitude     *float64 `json:"longitude"`
	IsDefault     bool     `json:"is_default"`
}

type customerAddress struct {
	ID                 string          `json:"id" db:"id"`
	Label              string          `json:"label" db:"label"`
	RecipientName      string          `json:"recipient_name" db:"recipient_name"`
	AddressLine1       string          `json:"address_line1" db:"address_line1"`
	Locality           string          `json:"locality" db:"locality"`
	DeliveryLocalityID string          `json:"locality_id,omitempty" db:"delivery_locality_id"`
	Landmark           string          `json:"landmark" db:"landmark"`
	City               string          `json:"city" db:"city"`
	State              string          `json:"state" db:"state"`
	PostalCode         string          `json:"postal_code" db:"postal_code"`
	ContactPhone       string          `json:"contact_phone" db:"contact_phone"`
	Latitude           sql.NullFloat64 `json:"-" db:"latitude"`
	Longitude          sql.NullFloat64 `json:"-" db:"longitude"`
	IsDefault          bool            `json:"is_default" db:"is_default"`
	UpdatedAt          time.Time       `json:"updated_at" db:"updated_at"`
}

func (a customerAddress) public() map[string]interface{} {
	var lat, lng interface{}
	if a.Latitude.Valid && a.Longitude.Valid {
		lat, lng = a.Latitude.Float64, a.Longitude.Float64
	}
	return map[string]interface{}{
		"id": a.ID, "label": a.Label, "recipient_name": a.RecipientName,
		"address_line1": a.AddressLine1, "locality": a.Locality,
		"locality_id": nullableText(a.DeliveryLocalityID),
		"landmark":    a.Landmark, "city": a.City, "state": a.State,
		"postal_code": a.PostalCode, "contact_phone": a.ContactPhone,
		"latitude": lat, "longitude": lng, "is_default": a.IsDefault,
		"updated_at": a.UpdatedAt,
	}
}

func nullableText(value string) interface{} {
	if value == "" {
		return nil
	}
	return value
}

func validateAddressLocality(ctx context.Context, tx *sqlx.Tx, input addressInput) error {
	if strings.TrimSpace(input.LocalityID) == "" {
		return nil
	}
	if _, err := uuid.Parse(input.LocalityID); err != nil {
		return checkoutError(400, "VALIDATION_ERROR", "Select a valid delivery locality.")
	}
	var matches bool
	err := tx.QueryRowxContext(ctx, `SELECT EXISTS(
		SELECT 1 FROM platform_delivery_localities l JOIN platform_districts d ON d.id=l.district_id
		WHERE l.id=$1 AND l.is_active AND d.is_active AND lower(d.name)=lower($2) AND lower(l.name)=lower($3)
	)`, input.LocalityID, input.City, input.Locality).Scan(&matches)
	if err != nil {
		return err
	}
	if !matches {
		return checkoutError(400, "INVALID_LOCALITY", "The selected delivery locality does not belong to this district.")
	}
	return nil
}

const addressSelect = `SELECT a.id::text,a.label,a.recipient_name,a.address_line1,a.locality,COALESCE(a.delivery_locality_id::text,'') AS delivery_locality_id,a.landmark,a.city,a.state,a.postal_code,a.contact_phone,
	ST_Y(a.location::geometry) AS latitude,ST_X(a.location::geometry) AS longitude,a.is_default,a.updated_at
	FROM customer_addresses a`

func (s *Service) ListCustomerAddresses(w http.ResponseWriter, r *http.Request, userID string) {
	if !s.customerCanCheckout(w, r, userID) {
		return
	}
	rows, err := s.db.QueryxContext(r.Context(), addressSelect+` WHERE customer_user_id=$1 ORDER BY is_default DESC, updated_at DESC`, userID)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load saved addresses.")
		return
	}
	defer rows.Close()
	addresses := make([]map[string]interface{}, 0)
	for rows.Next() {
		var address customerAddress
		if err := rows.StructScan(&address); err != nil {
			writeError(w, 500, "INTERNAL_ERROR", "Unable to read saved addresses.")
			return
		}
		addresses = append(addresses, address.public())
	}
	if err := rows.Err(); err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to read saved addresses.")
		return
	}
	writeJSON(w, 200, map[string]interface{}{"data": addresses, "meta": map[string]interface{}{"count": len(addresses)}})
}

func (s *Service) CreateCustomerAddress(w http.ResponseWriter, r *http.Request, userID string) {
	if !s.customerCanCheckout(w, r, userID) {
		return
	}
	var input addressInput
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 12<<10)).Decode(&input); err != nil {
		writeError(w, 400, "VALIDATION_ERROR", "Invalid address payload.")
		return
	}
	input, err := normalizeAddress(input)
	if err != nil {
		writeCheckoutError(w, err)
		return
	}
	id := uuid.NewString()
	err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := lockCustomer(tx, userID); err != nil {
			return err
		}
		var hasAddress bool
		if err := tx.GetContext(r.Context(), &hasAddress, `SELECT EXISTS(SELECT 1 FROM customer_addresses WHERE customer_user_id=$1)`, userID); err != nil {
			return err
		}
		if err := validateAddressLocality(r.Context(), tx, input); err != nil {
			return err
		}
		makeDefault := input.IsDefault || !hasAddress
		if makeDefault {
			if _, err := tx.ExecContext(r.Context(), `UPDATE customer_addresses SET is_default=false,updated_at=now() WHERE customer_user_id=$1 AND is_default`, userID); err != nil {
				return err
			}
		}
		_, err := tx.ExecContext(r.Context(), `INSERT INTO customer_addresses(id,customer_user_id,label,recipient_name,address_line1,locality,delivery_locality_id,landmark,city,state,postal_code,contact_phone,location,is_default)
				VALUES($1,$2,$3,$4,$5,$6,NULLIF($7,'')::uuid,$8,$9,$10,$11,$12,CASE WHEN $13::boolean THEN ST_SetSRID(ST_MakePoint($14,$15),4326)::geography ELSE NULL END,$16)`,
			id, userID, input.Label, input.RecipientName, input.AddressLine1, input.Locality, input.LocalityID, input.Landmark, input.City, input.State, input.PostalCode, input.ContactPhone, input.Latitude != nil, floatValue(input.Longitude), floatValue(input.Latitude), makeDefault)
		return err
	})
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to save the address.")
		return
	}
	s.getCustomerAddress(w, r, userID, id, http.StatusCreated)
}

func (s *Service) UpdateCustomerAddress(w http.ResponseWriter, r *http.Request, userID string) {
	if !s.customerCanCheckout(w, r, userID) {
		return
	}
	var input addressInput
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 12<<10)).Decode(&input); err != nil {
		writeError(w, 400, "VALIDATION_ERROR", "Invalid address payload.")
		return
	}
	input, err := normalizeAddress(input)
	if err != nil {
		writeCheckoutError(w, err)
		return
	}
	id := r.PathValue("id")
	err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := lockCustomer(tx, userID); err != nil {
			return err
		}
		var exists bool
		if err := tx.GetContext(r.Context(), &exists, `SELECT EXISTS(SELECT 1 FROM customer_addresses WHERE id=$1 AND customer_user_id=$2)`, id, userID); err != nil {
			return err
		}
		if !exists {
			return checkoutError(404, "NOT_FOUND", "Saved address not found.")
		}
		if err := validateAddressLocality(r.Context(), tx, input); err != nil {
			return err
		}
		if input.IsDefault {
			if _, err := tx.ExecContext(r.Context(), `UPDATE customer_addresses SET is_default=false,updated_at=now() WHERE customer_user_id=$1 AND is_default`, userID); err != nil {
				return err
			}
		}
		_, err := tx.ExecContext(r.Context(), `UPDATE customer_addresses SET label=$3,recipient_name=$4,address_line1=$5,locality=$6,delivery_locality_id=NULLIF($7,'')::uuid,landmark=$8,city=$9,state=$10,postal_code=$11,contact_phone=$12,
				location=CASE WHEN $13::boolean THEN ST_SetSRID(ST_MakePoint($14,$15),4326)::geography ELSE NULL END,is_default=$16,updated_at=now()
				WHERE id=$1 AND customer_user_id=$2`, id, userID, input.Label, input.RecipientName, input.AddressLine1, input.Locality, input.LocalityID, input.Landmark, input.City, input.State, input.PostalCode, input.ContactPhone, input.Latitude != nil, floatValue(input.Longitude), floatValue(input.Latitude), input.IsDefault)
		return err
	})
	if err != nil {
		writeCheckoutError(w, err)
		return
	}
	s.getCustomerAddress(w, r, userID, id, http.StatusOK)
}

func (s *Service) DeleteCustomerAddress(w http.ResponseWriter, r *http.Request, userID string) {
	if !s.customerCanCheckout(w, r, userID) {
		return
	}
	id := r.PathValue("id")
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := lockCustomer(tx, userID); err != nil {
			return err
		}
		var wasDefault bool
		if err := tx.QueryRowxContext(r.Context(), `DELETE FROM customer_addresses WHERE id=$1 AND customer_user_id=$2 RETURNING is_default`, id, userID).Scan(&wasDefault); err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return checkoutError(404, "NOT_FOUND", "Saved address not found.")
			}
			return err
		}
		if wasDefault {
			_, err := tx.ExecContext(r.Context(), `UPDATE customer_addresses SET is_default=true,updated_at=now()
				WHERE id=(SELECT id FROM customer_addresses WHERE customer_user_id=$1 ORDER BY updated_at DESC,id LIMIT 1)`, userID)
			return err
		}
		return nil
	})
	if err != nil {
		writeCheckoutError(w, err)
		return
	}
	writeJSON(w, 200, map[string]interface{}{"data": map[string]bool{"deleted": true}, "meta": map[string]string{"request_id": "delete-customer-address"}})
}

func (s *Service) getCustomerAddress(w http.ResponseWriter, r *http.Request, userID, addressID string, status int) {
	var address customerAddress
	if err := s.db.GetContext(r.Context(), &address, addressSelect+` WHERE id=$1 AND customer_user_id=$2`, addressID, userID); err != nil {
		writeError(w, 404, "NOT_FOUND", "Saved address not found.")
		return
	}
	writeJSON(w, status, map[string]interface{}{"data": address.public(), "meta": map[string]string{"request_id": "customer-address"}})
}

func (s *Service) customerCanCheckout(w http.ResponseWriter, r *http.Request, userID string) bool {
	var allowed bool
	if err := s.db.QueryRowxContext(r.Context(), `SELECT EXISTS(SELECT 1 FROM user_roles WHERE user_id=$1 AND role='customer')`, userID).Scan(&allowed); err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to validate customer access.")
		return false
	}
	if !allowed {
		writeError(w, 403, "FORBIDDEN", "Customer access is required.")
		return false
	}
	return true
}

func lockCustomer(tx *sqlx.Tx, userID string) error {
	var id string
	err := tx.QueryRowx(`SELECT id::text FROM users WHERE id=$1 FOR UPDATE`, userID).Scan(&id)
	return err
}

var postalCodePattern = regexp.MustCompile(`^[0-9]{6}$`)
var phonePattern = regexp.MustCompile(`^(\+91)?[6-9][0-9]{9}$`)

func normalizeAddress(input addressInput) (addressInput, error) {
	input.Label = strings.TrimSpace(input.Label)
	input.RecipientName = strings.TrimSpace(input.RecipientName)
	input.AddressLine1 = strings.TrimSpace(input.AddressLine1)
	input.Locality = strings.TrimSpace(input.Locality)
	input.LocalityID = strings.TrimSpace(input.LocalityID)
	input.Landmark = strings.TrimSpace(input.Landmark)
	input.State = strings.TrimSpace(input.State)
	input.PostalCode = strings.TrimSpace(input.PostalCode)
	input.ContactPhone = strings.ReplaceAll(strings.TrimSpace(input.ContactPhone), " ", "")
	switch strings.ToLower(strings.TrimSpace(input.City)) {
	case "cuttack":
		input.City = "Cuttack"
	case "jajpur":
		input.City = "Jajpur"
	default:
		return input, checkoutError(400, "VALIDATION_ERROR", "Choose Cuttack or Jajpur.")
	}
	if len(input.Label) < 1 || len(input.Label) > 40 || len(input.RecipientName) < 1 || len(input.RecipientName) > 100 || len(input.AddressLine1) < 3 || len(input.AddressLine1) > 200 || len(input.Locality) < 1 || len(input.Locality) > 100 || len(input.Landmark) > 120 || len(input.State) < 1 || len(input.State) > 80 || !postalCodePattern.MatchString(input.PostalCode) || !phonePattern.MatchString(input.ContactPhone) {
		return input, checkoutError(400, "VALIDATION_ERROR", "Check the required address fields, Indian PIN code, and contact number.")
	}
	if input.LocalityID != "" {
		if _, err := uuid.Parse(input.LocalityID); err != nil {
			return input, checkoutError(400, "VALIDATION_ERROR", "Select a valid delivery locality.")
		}
	}
	if strings.HasPrefix(input.ContactPhone, "+91") {
		input.ContactPhone = strings.TrimPrefix(input.ContactPhone, "+91")
	}
	input.ContactPhone = "+91" + input.ContactPhone
	if (input.Latitude == nil) != (input.Longitude == nil) {
		return input, checkoutError(400, "VALIDATION_ERROR", "Latitude and longitude must be supplied together.")
	}
	if input.Latitude != nil && (math.IsNaN(*input.Latitude) || math.IsInf(*input.Latitude, 0) || math.IsNaN(*input.Longitude) || math.IsInf(*input.Longitude, 0) || *input.Latitude < -90 || *input.Latitude > 90 || *input.Longitude < -180 || *input.Longitude > 180) {
		return input, checkoutError(400, "VALIDATION_ERROR", "Address coordinates are outside valid ranges.")
	}
	return input, nil
}

func floatValue(value *float64) float64 {
	if value == nil {
		return 0
	}
	return *value
}

type quoteRequest struct {
	FulfillmentType string               `json:"fulfillment_type"`
	AddressID       string               `json:"address_id"`
	Items           []cartValidationItem `json:"items"`
}

type checkoutQuoteItem struct {
	ProductID      string `json:"product_id"`
	Name           string `json:"name"`
	Quantity       int    `json:"quantity"`
	UnitPriceMinor int64  `json:"unit_price_minor"`
	DietaryType    string `json:"dietary_type,omitempty"`
}

type quoteBusiness struct {
	Name            string
	Category        string
	City            string
	DeliveryEnabled bool
	DeliveryFee     string
	MinimumOrder    string
	ETA             int
	TimeZone        string
	ServiceRadius   sql.NullInt64
}

func (s *Service) CreateCheckoutQuote(w http.ResponseWriter, r *http.Request, userID string) {
	if !s.customerCanCheckout(w, r, userID) {
		return
	}
	var req quoteRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16<<10)).Decode(&req); err != nil || len(req.Items) == 0 || len(req.Items) > 50 {
		writeError(w, 400, "VALIDATION_ERROR", "Checkout must contain between 1 and 50 items.")
		return
	}
	if req.FulfillmentType != "delivery" && req.FulfillmentType != "takeaway" {
		writeError(w, 400, "VALIDATION_ERROR", "Choose delivery or takeaway.")
		return
	}
	if (req.FulfillmentType == "delivery" && req.AddressID == "") || (req.FulfillmentType == "takeaway" && req.AddressID != "") {
		writeError(w, 400, "VALIDATION_ERROR", "Delivery requires a saved address; takeaway must not include one.")
		return
	}
	quoteID := uuid.NewString()
	var response map[string]interface{}
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		business, err := loadQuoteBusiness(tx, r.PathValue("id"))
		if err != nil {
			return checkoutError(404, "NOT_FOUND", "Orderable business not found.")
		}
		if !business.DeliveryEnabled || (business.Category != "restaurant" && business.Category != "cafe" && business.Category != "grocery" && business.Category != "supermarket" && business.Category != "bakery") {
			return checkoutError(409, "ORDERING_UNAVAILABLE", "This business does not currently support food ordering.")
		}
		open, err := isBusinessOpen(tx, r.PathValue("id"), time.Now())
		if err != nil {
			return err
		}
		if !open {
			return checkoutError(409, "MERCHANT_CLOSED", "This merchant is outside its published operating hours.")
		}
		minimumMinor, ok := decimalToMinor(business.MinimumOrder)
		if !ok {
			return errors.New("merchant minimum order configuration is invalid")
		}
		feeMinor, ok := decimalToMinor(business.DeliveryFee)
		if !ok || feeMinor < 0 {
			return errors.New("merchant delivery fee configuration is invalid")
		}
		var address *customerAddress
		var addressUpdatedAt interface{}
		var serviceabilityMethod interface{}
		if req.FulfillmentType == "delivery" {
			var value customerAddress
			if err := tx.GetContext(r.Context(), &value, addressSelect+` WHERE id=$1 AND customer_user_id=$2`, req.AddressID, userID); err != nil {
				return checkoutError(422, "INVALID_ADDRESS", "Select a saved address that belongs to your account.")
			}
			method, err := deliveryServiceability(tx, r.PathValue("id"), business, value)
			if err != nil {
				return err
			}
			address = &value
			addressUpdatedAt = value.UpdatedAt
			serviceabilityMethod = method
		} else {
			feeMinor = 0
			serviceabilityMethod = "not_required"
		}
		items := make([]checkoutQuoteItem, 0, len(req.Items))
		seen := make(map[string]bool, len(req.Items))
		var subtotal int64
		currency := "INR"
		for _, requested := range req.Items {
			if requested.ProductID == "" || requested.Quantity < 1 || requested.Quantity > 50 || seen[requested.ProductID] {
				return checkoutError(400, "VALIDATION_ERROR", "Product IDs must be unique and quantities must be between 1 and 50.")
			}
			seen[requested.ProductID] = true
			var name, priceText, dietary, stockStatus, inventoryMode, productCurrency string
			var quantity sql.NullInt64
			var published bool
			if err := tx.QueryRowxContext(r.Context(), `SELECT name,price::text,COALESCE(dietary_type,''),stock_status,inventory_mode,available_quantity,is_published,currency
				FROM products WHERE id=$1 AND business_id=$2`, requested.ProductID, r.PathValue("id")).Scan(&name, &priceText, &dietary, &stockStatus, &inventoryMode, &quantity, &published, &productCurrency); err != nil || !published || stockStatus == "out_of_stock" {
				return checkoutError(409, "ITEM_UNAVAILABLE", "One or more cart items are no longer available.")
			}
			price, ok := decimalToMinor(priceText)
			if !ok || strings.TrimSpace(productCurrency) != "INR" {
				return checkoutError(409, "PRICE_UNAVAILABLE", "A cart item has no supported INR price.")
			}
			if inventoryMode == "finite" && (!quantity.Valid || quantity.Int64 < int64(requested.Quantity)) {
				return checkoutError(409, "INSUFFICIENT_STOCK", "Cart quantity exceeds current stock.")
			}
			if inventoryMode != "finite" && inventoryMode != "untracked" {
				return errors.New("product inventory configuration is invalid")
			}
			subtotal += price * int64(requested.Quantity)
			items = append(items, checkoutQuoteItem{ProductID: requested.ProductID, Name: name, Quantity: requested.Quantity, UnitPriceMinor: price, DietaryType: dietary})
		}
		if subtotal < minimumMinor {
			return checkoutError(409, "MINIMUM_ORDER_NOT_MET", "Cart subtotal is below the merchant minimum order.")
		}
		deliveryMinor := int64(0)
		if req.FulfillmentType == "delivery" {
			deliveryMinor = feeMinor
		}
		// No jurisdiction-reviewed tax configuration exists yet. Do not invent a rate;
		// expose that taxes are not separately calculated in this quote.
		taxMinor := int64(0)
		total := subtotal + deliveryMinor + taxMinor
		rawItems, err := json.Marshal(items)
		if err != nil {
			return err
		}
		var expiresAt time.Time
		err = tx.QueryRowxContext(r.Context(), `INSERT INTO checkout_quotes(id,customer_user_id,business_id,fulfillment_type,address_id,address_updated_at,items,item_subtotal_minor,minimum_order_minor,delivery_fee_minor,tax_minor,grand_total_minor,currency,serviceability_method,expires_at)
			VALUES($1,$2,$3,$4,NULLIF($5,'')::uuid,$6,$7::jsonb,$8,$9,$10,$11,$12,$13,$14,now()+interval '5 minutes') RETURNING expires_at`, quoteID, userID, r.PathValue("id"), req.FulfillmentType, req.AddressID, addressUpdatedAt, string(rawItems), subtotal, minimumMinor, deliveryMinor, taxMinor, total, currency, serviceabilityMethod).Scan(&expiresAt)
		if err != nil {
			return err
		}
		var addressData interface{}
		if address != nil {
			addressData = address.public()
		}
		response = map[string]interface{}{
			"quote_id": quoteID, "business_id": r.PathValue("id"), "business_name": business.Name,
			"fulfillment_type": req.FulfillmentType, "address": addressData,
			"items": items, "item_subtotal_minor": subtotal, "discount_minor": 0,
			"delivery_fee_minor": deliveryMinor, "tax_minor": taxMinor,
			"tax_status": "not_configured", "tax_message": "Taxes are not separately calculated in this build; this total excludes any tax not included in listed prices.",
			"grand_total_minor": total, "minimum_order_minor": minimumMinor, "currency": currency,
			"delivery_eta_minutes": business.ETA, "serviceability_method": serviceabilityMethod,
			"expires_at": expiresAt.UTC(), "payment_status": "not_collected",
		}
		return nil
	})
	if err != nil {
		writeCheckoutError(w, err)
		return
	}
	writeJSON(w, 201, map[string]interface{}{"data": response, "meta": map[string]string{"request_id": "checkout-quote"}})
}

func loadQuoteBusiness(tx *sqlx.Tx, id string) (quoteBusiness, error) {
	var business quoteBusiness
	err := tx.QueryRowx(`SELECT b.name,b.category_slug,b.city,b.delivery_enabled,b.delivery_fee::text,b.min_order_amount::text,b.delivery_time_mins,b.time_zone,pp.service_radius_m
		FROM businesses b LEFT JOIN professional_profiles pp ON pp.business_id=b.id
		WHERE b.id=$1 AND b.status='approved'`, id).Scan(&business.Name, &business.Category, &business.City, &business.DeliveryEnabled, &business.DeliveryFee, &business.MinimumOrder, &business.ETA, &business.TimeZone, &business.ServiceRadius)
	return business, err
}

func deliveryServiceability(tx *sqlx.Tx, businessID string, business quoteBusiness, address customerAddress) (string, error) {
	if !business.ServiceRadius.Valid || business.ServiceRadius.Int64 < 100 {
		return "", checkoutError(409, "COVERAGE_NOT_CONFIGURED", "The merchant has not configured an order coverage radius.")
	}
	if address.Latitude.Valid && address.Longitude.Valid {
		var within bool
		err := tx.QueryRowx(`SELECT ST_DWithin(b.location,ST_SetSRID(ST_MakePoint($2,$3),4326)::geography,$4)
			FROM businesses b WHERE b.id=$1 AND b.location IS NOT NULL`, businessID, address.Longitude.Float64, address.Latitude.Float64, business.ServiceRadius.Int64).Scan(&within)
		if err != nil || !within {
			return "", checkoutError(422, "DELIVERY_OUT_OF_COVERAGE", "This saved address is outside the merchant's configured delivery coverage.")
		}
		return "radius", nil
	}
	if !strings.EqualFold(strings.TrimSpace(address.City), strings.TrimSpace(business.City)) {
		return "", checkoutError(422, "DELIVERY_OUT_OF_COVERAGE", "Without a map pin, delivery is available only in the merchant's city.")
	}
	return "city_match", nil
}

func isBusinessOpen(tx *sqlx.Tx, businessID string, now time.Time) (bool, error) {
	var zone string
	var weekdayClosed, hasException, exceptionClosed bool
	var weekdayOpen, weekdayClose, exceptionOpen, exceptionClose sql.NullString
	err := tx.QueryRowx(`SELECT b.time_zone,COALESCE(h.is_closed,true),h.opens_at::text,h.closes_at::text,
		(e.local_date IS NOT NULL),COALESCE(e.is_closed,false),e.opens_at::text,e.closes_at::text
		FROM businesses b
		LEFT JOIN business_hours h ON h.business_id=b.id AND h.weekday=EXTRACT(DOW FROM ($2::timestamptz AT TIME ZONE b.time_zone))::int
		LEFT JOIN business_hour_exceptions e ON e.business_id=b.id AND e.local_date=($2::timestamptz AT TIME ZONE b.time_zone)::date
		WHERE b.id=$1`, businessID, now).Scan(&zone, &weekdayClosed, &weekdayOpen, &weekdayClose, &hasException, &exceptionClosed, &exceptionOpen, &exceptionClose)
	if err != nil {
		return false, err
	}
	location, err := time.LoadLocation(zone)
	if err != nil {
		return false, errors.New("merchant time zone is invalid")
	}
	start, end := weekdayOpen, weekdayClose
	closed := weekdayClosed
	if hasException {
		if exceptionClosed {
			return false, nil
		}
		if exceptionOpen.Valid && exceptionClose.Valid {
			start, end = exceptionOpen, exceptionClose
			closed = false
		}
	}
	if closed || !start.Valid || !end.Valid {
		return false, nil
	}
	parse := func(value string) (time.Duration, error) {
		parsed, err := time.Parse("15:04:05", value)
		if err != nil {
			parsed, err = time.Parse("15:04", value)
		}
		if err != nil {
			return 0, err
		}
		return time.Duration(parsed.Hour())*time.Hour + time.Duration(parsed.Minute())*time.Minute + time.Duration(parsed.Second())*time.Second, nil
	}
	opening, err := parse(start.String)
	if err != nil {
		return false, err
	}
	closing, err := parse(end.String)
	if err != nil {
		return false, err
	}
	local := now.In(location)
	current := time.Duration(local.Hour())*time.Hour + time.Duration(local.Minute())*time.Minute + time.Duration(local.Second())*time.Second
	if closing <= opening {
		return current >= opening || current < closing, nil
	}
	return current >= opening && current < closing, nil
}

func writeCheckoutError(w http.ResponseWriter, err error) {
	var failure *checkoutFailure
	if errors.As(err, &failure) {
		writeError(w, failure.status, failure.code, failure.message)
		return
	}
	writeError(w, 500, "INTERNAL_ERROR", "Unable to complete checkout operation.")
}

func formatAddress(address customerAddress) string {
	parts := []string{address.AddressLine1, address.Locality, address.Landmark, address.City, address.State, address.PostalCode}
	filtered := parts[:0]
	for _, part := range parts {
		if value := strings.TrimSpace(part); value != "" {
			filtered = append(filtered, value)
		}
	}
	return strings.Join(filtered, ", ")
}
