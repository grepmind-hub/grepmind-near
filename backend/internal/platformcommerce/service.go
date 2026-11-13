package platformcommerce

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
	"grepmind-near/backend/pkg/database"
)

const maxLines = 50

type Service struct {
	db                     *database.DB
	sandboxCODEnabled      bool
	publishOrderAssignment func(ctx context.Context, customerID, businessID, orderID string)
}

func NewService(db *database.DB, sandboxCODEnabled ...bool) *Service {
	s := &Service{db: db}
	if len(sandboxCODEnabled) > 0 {
		s.sandboxCODEnabled = sandboxCODEnabled[0]
	}
	return s
}

func (s *Service) SetOrderAssignmentPublisher(publisher func(ctx context.Context, customerID, businessID, orderID string)) {
	s.publishOrderAssignment = publisher
}

type failure struct {
	status  int
	code    string
	message string
}

func (e *failure) Error() string { return e.message }
func fail(status int, code, message string) error {
	return &failure{status: status, code: code, message: message}
}

func writeError(w http.ResponseWriter, err error) {
	var f *failure
	if errors.As(err, &f) {
		writeJSON(w, f.status, map[string]any{"error": map[string]string{"code": f.code, "message": f.message}})
		return
	}
	writeJSON(w, http.StatusInternalServerError, map[string]any{"error": map[string]string{"code": "INTERNAL_ERROR", "message": "Platform checkout could not be completed."}})
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

type cartLine struct {
	VariantID string `json:"variant_id"`
	Quantity  int    `json:"quantity"`
}

type quoteRequest struct {
	Vertical  string     `json:"vertical"`
	AddressID string     `json:"address_id"`
	Items     []cartLine `json:"items"`
}

type submitRequest struct {
	QuoteID       string `json:"quote_id"`
	Notes         string `json:"notes"`
	PaymentMethod string `json:"payment_method"`
}

func validCheckoutPaymentMethod(method string) bool {
	return method == "upi" || method == "cash_on_delivery"
}

type address struct {
	ID           string    `db:"id"`
	Locality     string    `db:"locality"`
	City         string    `db:"city"`
	State        string    `db:"state"`
	UpdatedAt    time.Time `db:"updated_at"`
	LocalityID   string    `db:"delivery_locality_id"`
	DistrictID   string    `db:"district_id"`
	DistrictName string    `db:"district_name"`
	Enabled      bool      `db:"delivery_enabled"`
	Snapshot     string    `db:"snapshot"`
}

type pricedLine struct {
	ProductID               string        `json:"product_id" db:"product_id"`
	VariantID               string        `json:"variant_id" db:"variant_id"`
	Vertical                string        `json:"vertical" db:"vertical"`
	ProductName             string        `json:"product_name" db:"product_name"`
	VariantName             string        `json:"variant_name" db:"variant_name"`
	UnitLabel               string        `json:"unit_label" db:"unit_label"`
	Quantity                int           `json:"quantity" db:"quantity"`
	UnitPriceMinor          int64         `json:"unit_price_minor" db:"unit_price_minor"`
	PriceRevision           int           `json:"price_revision" db:"price_revision"`
	MappingID               string        `json:"-" db:"mapping_id"`
	InventoryMode           string        `json:"-" db:"inventory_mode"`
	PartnerSupplyPriceMinor sql.NullInt64 `json:"-" db:"partner_supply_price_minor"`
}

type partner struct {
	ID   string `db:"id"`
	Name string `db:"name"`
}

func (s *Service) customerAllowed(ctx context.Context, userID string) bool {
	var ok bool
	return s.db.GetContext(ctx, &ok, `SELECT EXISTS(SELECT 1 FROM user_roles WHERE user_id=$1 AND role='customer')`, userID) == nil && ok
}

func (s *Service) codAvailable(ctx context.Context, tx *sqlx.Tx) bool {
	if !s.sandboxCODEnabled {
		return false
	}
	var enabled bool
	err := tx.GetContext(ctx, &enabled, `SELECT sandbox_cod_enabled AND financial_posting_enabled AND NOT upi_enabled AND NOT cod_enabled AND NOT merchant_settlement_enabled AND NOT real_money_enabled FROM financial_feature_config WHERE singleton=true`)
	return err == nil && enabled
}

func sandboxUPIAvailable(ctx context.Context, tx *sqlx.Tx) bool {
	var enabled bool
	err := tx.GetContext(ctx, &enabled, `SELECT payment_intent_creation_enabled AND payment_attempt_creation_enabled AND sandbox_payment_enabled AND financial_posting_enabled AND NOT upi_enabled AND NOT cod_enabled AND NOT merchant_settlement_enabled AND NOT real_money_enabled FROM financial_feature_config WHERE singleton=true`)
	return err == nil && enabled
}

func decode(w http.ResponseWriter, r *http.Request, dest any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 64<<10)
	d := json.NewDecoder(r.Body)
	d.DisallowUnknownFields()
	if d.Decode(dest) != nil {
		writeJSON(w, 400, map[string]any{"error": map[string]string{"code": "VALIDATION_ERROR", "message": "The checkout request is invalid."}})
		return false
	}
	var extra any
	if d.Decode(&extra) != io.EOF {
		writeJSON(w, 400, map[string]any{"error": map[string]string{"code": "VALIDATION_ERROR", "message": "Only one JSON request is allowed."}})
		return false
	}
	return true
}

func validateCart(req quoteRequest) error {
	if req.Vertical != "food" && req.Vertical != "grocery" {
		return fail(400, "INVALID_VERTICAL", "Choose Food or Grocery.")
	}
	if _, err := uuid.Parse(req.AddressID); err != nil || len(req.Items) == 0 || len(req.Items) > maxLines {
		return fail(400, "VALIDATION_ERROR", "Select a saved delivery address and add 1 to 50 items.")
	}
	seen := map[string]bool{}
	for _, line := range req.Items {
		if _, err := uuid.Parse(line.VariantID); err != nil || line.Quantity < 1 || line.Quantity > 50 || seen[line.VariantID] {
			return fail(400, "VALIDATION_ERROR", "Cart variant IDs must be unique and quantities must be between 1 and 50.")
		}
		seen[line.VariantID] = true
	}
	return nil
}

func loadAddress(ctx context.Context, tx *sqlx.Tx, userID, addressID string, lock bool) (address, error) {
	query := `SELECT a.id::text,a.locality,a.city,a.updated_at,a.delivery_locality_id::text,l.district_id::text,d.name district_name,l.delivery_enabled,
		jsonb_build_object('id',a.id,'label',a.label,'recipient_name',a.recipient_name,'address_line1',a.address_line1,'locality',a.locality,'landmark',a.landmark,'city',a.city,'state',a.state,'postal_code',a.postal_code,'contact_phone',a.contact_phone,'latitude',ST_Y(a.location::geometry),'longitude',ST_X(a.location::geometry),'locality_id',a.delivery_locality_id)::text
		FROM customer_addresses a JOIN platform_delivery_localities l ON l.id=a.delivery_locality_id JOIN platform_districts d ON d.id=l.district_id
		WHERE a.id=$1 AND a.customer_user_id=$2 AND l.is_active AND d.is_active`
	if lock {
		query += ` FOR UPDATE OF a`
	}
	var a address
	err := tx.QueryRowxContext(ctx, query, addressID, userID).Scan(&a.ID, &a.Locality, &a.City, &a.UpdatedAt, &a.LocalityID, &a.DistrictID, &a.DistrictName, &a.Enabled, &a.Snapshot)
	if errors.Is(err, sql.ErrNoRows) {
		return a, fail(422, "INVALID_ADDRESS", "Choose a saved address with a configured delivery locality.")
	}
	if err != nil {
		return a, err
	}
	if !strings.EqualFold(a.City, a.DistrictName) {
		return a, fail(422, "INVALID_ADDRESS", "The saved address district does not match its delivery locality.")
	}
	if !a.Enabled {
		return a, fail(409, "DELIVERY_UNAVAILABLE", "Delivery is not active in this locality yet. Choose Kuanpal or Chhatia when available.")
	}
	return a, nil
}

func loadLines(ctx context.Context, tx *sqlx.Tx, vertical, districtID, localityID string, requested []cartLine, lock bool) ([]pricedLine, int64, error) {
	lines := make([]pricedLine, 0, len(requested))
	var subtotal int64
	for _, item := range requested {
		query := `SELECT p.id::text,v.id::text,c.vertical,p.name,v.name,v.unit_label,v.price_minor,v.price_revision
			FROM platform_catalog_variants v JOIN platform_catalog_products p ON p.id=v.product_id
			JOIN platform_catalog_categories c ON c.id=p.category_id
			JOIN platform_catalog_product_district_visibility dv ON dv.product_id=p.id AND dv.district_id=$2 AND dv.is_active
			JOIN platform_catalog_product_delivery_localities dl ON dl.product_id=p.id AND dl.locality_id=$3 AND dl.is_active
			WHERE v.id=$1 AND c.vertical=$4 AND p.status='active' AND c.is_active AND v.is_active`
		if lock {
			query += ` FOR UPDATE OF p,v`
		}
		var line pricedLine
		line.Quantity = item.Quantity
		if err := tx.QueryRowxContext(ctx, query, item.VariantID, districtID, localityID, vertical).Scan(&line.ProductID, &line.VariantID, &line.Vertical, &line.ProductName, &line.VariantName, &line.UnitLabel, &line.UnitPriceMinor, &line.PriceRevision); err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return nil, 0, fail(409, "ITEM_UNAVAILABLE", "A product is inactive or unavailable in this delivery locality.")
			}
			return nil, 0, err
		}
		if line.UnitPriceMinor < 0 || line.UnitPriceMinor > math.MaxInt64/int64(item.Quantity) {
			return nil, 0, fail(409, "PRICE_UNAVAILABLE", "A product price is outside supported limits.")
		}
		lineTotal := line.UnitPriceMinor * int64(item.Quantity)
		if subtotal > math.MaxInt64-lineTotal {
			return nil, 0, fail(409, "PRICE_UNAVAILABLE", "Cart total is outside supported limits.")
		}
		subtotal += lineTotal
		lines = append(lines, line)
	}
	return lines, subtotal, nil
}

// selectPartner considers only active, approved businesses whose explicit
// approved mappings cover every requested variant in the enabled locality.
// Business UUID order is the stable tie-break so quote results are repeatable.
func selectPartner(ctx context.Context, tx *sqlx.Tx, localityID string, serviceDate time.Time, lines []pricedLine) (partner, []pricedLine, error) {
	args := []any{localityID, serviceDate.Format("2006-01-02")}
	values := make([]string, 0, len(lines))
	for _, line := range lines {
		args = append(args, line.VariantID, line.Quantity)
		values = append(values, fmt.Sprintf("($%d::uuid,$%d::int)", len(args)-1, len(args)))
	}
	query := `WITH requested(variant_id,quantity) AS (VALUES ` + strings.Join(values, ",") + `)
	SELECT b.id::text,b.name
	FROM businesses b
	JOIN platform_partner_delivery_localities dl ON dl.business_id=b.id AND dl.locality_id=$1 AND dl.is_active
	JOIN platform_delivery_localities l ON l.id=dl.locality_id AND l.delivery_enabled AND l.is_active
	WHERE b.status='approved' AND b.verification_status='verified' AND b.delivery_enabled
	AND (SELECT count(*) FROM requested r JOIN platform_partner_product_mappings m ON m.variant_id=r.variant_id AND m.business_id=b.id AND m.status='approved'
	 JOIN platform_catalog_variants v ON v.id=m.variant_id AND v.is_active
	 JOIN platform_catalog_products p ON p.id=v.product_id AND p.status='active'
	 JOIN platform_catalog_categories c ON c.id=p.category_id AND c.is_active
	 JOIN platform_catalog_product_delivery_localities pd ON pd.product_id=p.id AND pd.locality_id=$1 AND pd.is_active
	 WHERE c.vertical=(SELECT vertical FROM platform_catalog_categories c2 JOIN platform_catalog_products p2 ON p2.category_id=c2.id JOIN platform_catalog_variants v2 ON v2.product_id=p2.id WHERE v2.id=r.variant_id)
	 AND (m.inventory_mode='untracked' OR (m.inventory_mode='finite' AND m.available_quantity>=r.quantity) OR (m.inventory_mode='capacity' AND m.capacity_per_day-(SELECT COALESCE(sum(ir.quantity),0) FROM platform_inventory_reservations ir WHERE ir.mapping_id=m.id AND ir.service_date=$2 AND ir.status IN ('reserved','consumed'))>=r.quantity))
	) = (SELECT count(*) FROM requested)
	ORDER BY b.id`
	rows, err := tx.QueryxContext(ctx, query, args...)
	if err != nil {
		return partner{}, nil, err
	}
	defer rows.Close()
	candidates := make([]partner, 0)
	for rows.Next() {
		var p partner
		if err := rows.StructScan(&p); err != nil {
			return partner{}, nil, err
		}
		candidates = append(candidates, p)
	}
	if err := rows.Err(); err != nil {
		return partner{}, nil, err
	}
	for _, candidate := range candidates {
		open, err := businessOpen(ctx, tx, candidate.ID, time.Now())
		if err != nil {
			return partner{}, nil, err
		}
		if !open {
			continue
		}
		partnerLines := make([]pricedLine, len(lines))
		copy(partnerLines, lines)
		all := true
		for i := range partnerLines {
			var mappingID, mode string
			var supplyPrice sql.NullInt64
			query := `SELECT id::text,inventory_mode,supply_price_minor FROM platform_partner_product_mappings WHERE business_id=$1 AND variant_id=$2 AND status='approved'`
			err := tx.QueryRowxContext(ctx, query, candidate.ID, partnerLines[i].VariantID).Scan(&mappingID, &mode, &supplyPrice)
			if err != nil {
				all = false
				break
			}
			partnerLines[i].MappingID = mappingID
			partnerLines[i].InventoryMode = mode
			partnerLines[i].PartnerSupplyPriceMinor = supplyPrice
		}
		if all {
			return candidate, partnerLines, nil
		}
	}
	return partner{}, nil, fail(409, "PARTNER_UNAVAILABLE", "No approved delivery partner can fulfill every item in this locality right now. Remove unavailable items or try again later.")
}

func businessOpen(ctx context.Context, tx *sqlx.Tx, businessID string, now time.Time) (bool, error) {
	var zone string
	var closed, hasException, exceptionClosed bool
	var opens, closes, exceptionOpens, exceptionCloses sql.NullString
	err := tx.QueryRowxContext(ctx, `SELECT b.time_zone,COALESCE(h.is_closed,true),h.opens_at::text,h.closes_at::text,(e.local_date IS NOT NULL),COALESCE(e.is_closed,false),e.opens_at::text,e.closes_at::text
	FROM businesses b LEFT JOIN business_hours h ON h.business_id=b.id AND h.weekday=EXTRACT(DOW FROM ($2::timestamptz AT TIME ZONE b.time_zone))::int
	LEFT JOIN business_hour_exceptions e ON e.business_id=b.id AND e.local_date=($2::timestamptz AT TIME ZONE b.time_zone)::date WHERE b.id=$1`, businessID, now).Scan(&zone, &closed, &opens, &closes, &hasException, &exceptionClosed, &exceptionOpens, &exceptionCloses)
	if err != nil {
		return false, err
	}
	loc, err := time.LoadLocation(zone)
	if err != nil {
		return false, errors.New("partner timezone is invalid")
	}
	start, end := opens, closes
	if hasException {
		if exceptionClosed {
			return false, nil
		}
		if exceptionOpens.Valid && exceptionCloses.Valid {
			start, end = exceptionOpens, exceptionCloses
			closed = false
		}
	}
	if closed || !start.Valid || !end.Valid {
		return false, nil
	}
	parse := func(v string) (time.Duration, error) {
		t, e := time.Parse("15:04:05", v)
		if e != nil {
			t, e = time.Parse("15:04", v)
		}
		if e != nil {
			return 0, e
		}
		return time.Duration(t.Hour())*time.Hour + time.Duration(t.Minute())*time.Minute + time.Duration(t.Second())*time.Second, nil
	}
	a, e := parse(start.String)
	if e != nil {
		return false, e
	}
	b, e := parse(end.String)
	if e != nil {
		return false, e
	}
	local := now.In(loc)
	current := time.Duration(local.Hour())*time.Hour + time.Duration(local.Minute())*time.Minute + time.Duration(local.Second())*time.Second
	if b <= a {
		return current >= a || current < b, nil
	}
	return current >= a && current < b, nil
}

func (s *Service) Quote(w http.ResponseWriter, r *http.Request, userID string) {
	if !s.customerAllowed(r.Context(), userID) {
		writeJSON(w, 403, map[string]any{"error": map[string]string{"code": "FORBIDDEN", "message": "Customer access is required."}})
		return
	}
	var req quoteRequest
	if !decode(w, r, &req) {
		return
	}
	if err := validateCart(req); err != nil {
		writeError(w, err)
		return
	}
	quoteID := uuid.NewString()
	today := time.Now().In(mustLocation("Asia/Kolkata"))
	var result map[string]any
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		a, err := loadAddress(r.Context(), tx, userID, req.AddressID, false)
		if err != nil {
			return err
		}
		lines, subtotal, err := loadLines(r.Context(), tx, req.Vertical, a.DistrictID, a.LocalityID, req.Items, false)
		if err != nil {
			return err
		}
		selected, lines, err := selectPartner(r.Context(), tx, a.LocalityID, today, lines)
		if err != nil {
			return err
		}
		raw, err := json.Marshal(lines)
		if err != nil {
			return err
		}
		var expires time.Time
		if err := tx.QueryRowxContext(r.Context(), `INSERT INTO platform_checkout_quotes(id,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,delivery_fee_minor,tax_minor,grand_total_minor,currency,expires_at)
		VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb,$10,0,0,$10,'INR',now()+interval '5 minutes') RETURNING expires_at`, quoteID, userID, req.Vertical, a.LocalityID, today.Format("2006-01-02"), req.AddressID, a.UpdatedAt, selected.ID, string(raw), subtotal).Scan(&expires); err != nil {
			return err
		}
		codAvailable := s.codAvailable(r.Context(), tx)
		upiAvailable := sandboxUPIAvailable(r.Context(), tx)
		result = map[string]any{"quote_id": quoteID, "vertical": req.Vertical, "locality_id": a.LocalityID, "locality": a.Locality, "district": a.DistrictName, "partner": map[string]string{"business_id": selected.ID, "name": selected.Name}, "address": json.RawMessage(a.Snapshot), "items": lines, "item_subtotal_minor": subtotal, "discount_minor": 0, "delivery_fee_minor": 0, "delivery_fee_status": "not_configured", "tax_minor": 0, "tax_status": "not_configured", "tax_message": "Tax is not separately calculated in this build; the total excludes any tax not included in listed prices.", "grand_total_minor": subtotal, "currency": "INR", "expires_at": expires.UTC(), "payment_status": "not_collected", "upi_sandbox_available": upiAvailable, "cash_on_delivery_available": codAvailable, "payment_mode": "sandbox_only", "cash_on_delivery_mode": "synthetic_qa"}
		return nil
	})
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, 201, map[string]any{"data": result})
}

func (s *Service) Submit(w http.ResponseWriter, r *http.Request, userID string) {
	if !s.customerAllowed(r.Context(), userID) {
		writeJSON(w, 403, map[string]any{"error": map[string]string{"code": "FORBIDDEN", "message": "Customer access is required."}})
		return
	}
	var req submitRequest
	if !decode(w, r, &req) {
		return
	}
	if _, err := uuid.Parse(req.QuoteID); err != nil || len(req.Notes) > 1000 || !validCheckoutPaymentMethod(req.PaymentMethod) {
		writeJSON(w, 400, map[string]any{"error": map[string]string{"code": "VALIDATION_ERROR", "message": "A valid quote, payment method, and short note are required."}})
		return
	}
	idemRaw := r.Header.Get("Idempotency-Key")
	idem, err := uuid.Parse(idemRaw)
	if err != nil {
		writeJSON(w, 400, map[string]any{"error": map[string]string{"code": "IDEMPOTENCY_KEY_REQUIRED", "message": "A valid Idempotency-Key is required."}})
		return
	}
	requestHash := fmt.Sprintf("%s|%s|%s|%s", userID, req.QuoteID, strings.TrimSpace(req.Notes), req.PaymentMethod)
	orderID := uuid.NewString()
	reference := "GN-" + strings.ToUpper(strings.ReplaceAll(orderID[:8], "-", ""))
	replay := false
	selectedPartnerID := ""
	err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var lock string
		if err := tx.QueryRowxContext(r.Context(), `SELECT id::text FROM users WHERE id=$1 FOR UPDATE`, userID).Scan(&lock); err != nil {
			return err
		}
		var existingID, existingHash string
		err := tx.QueryRowxContext(r.Context(), `SELECT id::text,COALESCE(platform_request_hash,'') FROM customer_orders WHERE customer_user_id=$1 AND platform_idempotency_key=$2`, userID, idem.String()).Scan(&existingID, &existingHash)
		if err == nil {
			if existingHash != requestHash {
				return fail(409, "IDEMPOTENCY_CONFLICT", "This request key was used for another checkout.")
			}
			orderID = existingID
			replay = true
			return nil
		}
		if !errors.Is(err, sql.ErrNoRows) {
			return err
		}
		var vertical, localityID, addressID, partnerID, itemsJSON string
		var addressUpdated, expires time.Time
		var serviceDate time.Time
		var subtotal, delivery, tax, total int64
		var consumed sql.NullString
		if err := tx.QueryRowxContext(r.Context(), `SELECT vertical,locality_id::text,address_id::text,address_updated_at,partner_business_id::text,items,item_subtotal_minor,delivery_fee_minor,tax_minor,grand_total_minor,service_date,expires_at,consumed_order_id::text FROM platform_checkout_quotes WHERE id=$1 AND customer_user_id=$2 FOR UPDATE`, req.QuoteID, userID).Scan(&vertical, &localityID, &addressID, &addressUpdated, &partnerID, &itemsJSON, &subtotal, &delivery, &tax, &total, &serviceDate, &expires, &consumed); err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return fail(404, "QUOTE_NOT_FOUND", "Checkout quote not found for this account.")
			}
			return err
		}
		if expires.Before(time.Now()) || consumed.Valid {
			return fail(409, "QUOTE_EXPIRED", "Checkout quote expired or was already submitted. Refresh the quote.")
		}
		if total != subtotal+delivery+tax {
			return fail(409, "QUOTE_STALE", "Checkout totals changed. Refresh the quote.")
		}
		a, err := loadAddress(r.Context(), tx, userID, addressID, true)
		if err != nil {
			return err
		}
		if !a.UpdatedAt.Equal(addressUpdated) || a.LocalityID != localityID {
			return fail(409, "QUOTE_STALE", "Delivery address or locality changed. Refresh the quote.")
		}
		var quoted []pricedLine
		if err := json.Unmarshal([]byte(itemsJSON), &quoted); err != nil || len(quoted) == 0 {
			return fail(409, "QUOTE_STALE", "Quote contents are invalid. Refresh the quote.")
		}
		requested := make([]cartLine, 0, len(quoted))
		for _, line := range quoted {
			requested = append(requested, cartLine{VariantID: line.VariantID, Quantity: line.Quantity})
		}
		currentLines, currentSubtotal, err := loadLines(r.Context(), tx, vertical, a.DistrictID, localityID, requested, true)
		if err != nil {
			return err
		}
		if currentSubtotal != subtotal || !samePrices(quoted, currentLines) {
			return fail(409, "QUOTE_STALE", "A product or price changed. Review a fresh quote.")
		}
		selected, mappedLines, err := selectPartner(r.Context(), tx, localityID, serviceDate, currentLines)
		if err != nil {
			return err
		}
		if selected.ID != partnerID {
			return fail(409, "QUOTE_STALE", "The selected fulfillment partner is no longer available. Review a fresh quote.")
		}
		selectedPartnerID = partnerID
		// Lock every mapped capability in stable order, then validate inventory again
		// while those rows are held until order, stock and reservation commit.
		sort.Slice(mappedLines, func(i, j int) bool { return mappedLines[i].MappingID < mappedLines[j].MappingID })
		for i := range mappedLines {
			var got string
			if err := tx.QueryRowxContext(r.Context(), `SELECT id::text FROM platform_partner_product_mappings WHERE id=$1 FOR UPDATE`, mappedLines[i].MappingID).Scan(&got); err != nil {
				return err
			}
		}
		selectedAgain, lockedLines, err := selectPartner(r.Context(), tx, localityID, serviceDate, currentLines)
		if err != nil {
			return err
		}
		if selectedAgain.ID != partnerID {
			return fail(409, "QUOTE_STALE", "Fulfillment availability changed. Review a fresh quote.")
		}
		byVariant := map[string]pricedLine{}
		for _, line := range mappedLines {
			byVariant[line.VariantID] = line
		}
		for _, line := range lockedLines {
			byVariant[line.VariantID] = line
		}
		for _, line := range currentLines {
			mapped := byVariant[line.VariantID]
			if mapped.InventoryMode == "finite" {
				res, err := tx.ExecContext(r.Context(), `UPDATE platform_partner_product_mappings SET available_quantity=available_quantity-$2,updated_at=now() WHERE id=$1 AND status='approved' AND inventory_mode='finite' AND available_quantity >= $2`, mapped.MappingID, line.Quantity)
				if err != nil {
					return err
				}
				n, _ := res.RowsAffected()
				if n != 1 {
					return fail(409, "OUT_OF_STOCK", "A product sold out. Update your cart and try again.")
				}
			}
		}
		var addressText string
		if err := tx.QueryRowxContext(r.Context(), `SELECT concat_ws(', ',address_line1,locality,landmark,city,state,postal_code) FROM customer_addresses WHERE id=$1 AND customer_user_id=$2`, addressID, userID).Scan(&addressText); err != nil {
			return err
		}
		if req.PaymentMethod == "cash_on_delivery" && !s.codAvailable(r.Context(), tx) {
			return fail(409, "COD_UNAVAILABLE", "Cash on Delivery is unavailable for this order.")
		}
		if req.PaymentMethod == "upi" && !sandboxUPIAvailable(r.Context(), tx) {
			return fail(409, "UPI_UNAVAILABLE", "Sandbox UPI is unavailable for this order.")
		}
		paymentMethod := req.PaymentMethod
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,fulfillment_type,delivery_address,delivery_address_id,delivery_address_snapshot,platform_checkout_quote_id,platform_idempotency_key,platform_request_hash,payment_status,payment_method,customer_notes,item_total,delivery_fee,tax_amount,grand_total,currency,reference_code,order_source,platform_vertical,delivery_locality_id)
				VALUES($1,$2,$3,'platform_order','placed','delivery',$4,$5,$6::jsonb,$7,$8,$9,'not_collected',$10,NULLIF($11,''),$12::numeric/100,$13::numeric/100,$14::numeric/100,$15::numeric/100,'INR',$16,'platform_catalog',$17,$18)`, orderID, userID, partnerID, addressText, addressID, a.Snapshot, req.QuoteID, idem.String(), requestHash, paymentMethod, strings.TrimSpace(req.Notes), subtotal, delivery, tax, total, reference, vertical, localityID); err != nil {
			return err
		}
		if req.PaymentMethod == "cash_on_delivery" {
			if _, err := tx.ExecContext(r.Context(), `INSERT INTO cod_obligations(order_id,customer_user_id,amount_minor,currency,policy_version) VALUES($1,$2,$3,'INR','synthetic-qa-v1')`, orderID, userID, total); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `INSERT INTO cod_audit_events(actor_user_id,obligation_id,event_type,reason,metadata) SELECT $2,id,'obligation_created','Customer selected synthetic QA Cash on Delivery',jsonb_build_object('mode','synthetic_qa','amount_minor',amount_minor) FROM cod_obligations WHERE order_id=$1`, orderID, userID); err != nil {
				return err
			}
		}
		for _, line := range currentLines {
			mapped := byVariant[line.VariantID]
			if _, err := tx.ExecContext(r.Context(), `INSERT INTO platform_inventory_reservations(order_id,mapping_id,quantity,inventory_mode,service_date) VALUES($1,$2,$3,$4,$5)`, orderID, mapped.MappingID, line.Quantity, mapped.InventoryMode, serviceDate.Format("2006-01-02")); err != nil {
				return err
			}
		}
		for _, line := range currentLines {
			mapped := byVariant[line.VariantID]
			if mapped.MappingID == "" {
				return errors.New("selected partner mapping missing for order snapshot")
			}
			var supplyPrice any
			var supplyCurrency any
			if mapped.PartnerSupplyPriceMinor.Valid {
				supplyPrice = mapped.PartnerSupplyPriceMinor.Int64
				supplyCurrency = "INR"
			}
			if _, err := tx.ExecContext(r.Context(), `INSERT INTO platform_customer_order_items(order_id,product_id,variant_id,vertical,product_name,variant_name,unit_label,unit_price_minor,quantity,price_revision,partner_supply_price_minor,partner_supply_currency) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`, orderID, line.ProductID, line.VariantID, line.Vertical, line.ProductName, line.VariantName, line.UnitLabel, line.UnitPriceMinor, line.Quantity, line.PriceRevision, supplyPrice, supplyCurrency); err != nil {
				return err
			}
		}
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO customer_order_status_events(order_id,status,event_kind,actor_user_id) VALUES($1,'placed','status_change',$2)`, orderID, userID); err != nil {
			return err
		}
		res, err := tx.ExecContext(r.Context(), `UPDATE platform_checkout_quotes SET consumed_order_id=$2 WHERE id=$1 AND consumed_order_id IS NULL`, req.QuoteID, orderID)
		if err != nil {
			return err
		}
		n, _ := res.RowsAffected()
		if n != 1 {
			return fail(409, "QUOTE_ALREADY_USED", "This quote has already been submitted. Refresh checkout.")
		}
		return nil
	})
	if err != nil {
		writeError(w, err)
		return
	}
	status := 201
	if replay {
		status = 200
		_ = s.db.GetContext(r.Context(), &reference, `SELECT reference_code FROM customer_orders WHERE id=$1 AND customer_user_id=$2`, orderID, userID)
	} else if s.publishOrderAssignment != nil {
		s.publishOrderAssignment(r.Context(), userID, selectedPartnerID, orderID)
	}
	writeJSON(w, status, map[string]any{"data": map[string]any{"id": orderID, "order_type": "platform_order", "order_source": "platform_catalog", "status": "placed", "payment_status": "not_collected", "payment_method": req.PaymentMethod, "reference_code": reference}, "meta": map[string]any{"idempotent_replay": replay}})
}

func samePrices(a, b []pricedLine) bool {
	if len(a) != len(b) {
		return false
	}
	m := map[string]pricedLine{}
	for _, line := range a {
		m[line.VariantID] = line
	}
	for _, line := range b {
		old, ok := m[line.VariantID]
		if !ok || old.Quantity != line.Quantity || old.PriceRevision != line.PriceRevision || old.UnitPriceMinor != line.UnitPriceMinor || old.ProductName != line.ProductName || old.VariantName != line.VariantName {
			return false
		}
	}
	return true
}

func mustLocation(name string) *time.Location {
	loc, err := time.LoadLocation(name)
	if err != nil {
		return time.UTC
	}
	return loc
}
