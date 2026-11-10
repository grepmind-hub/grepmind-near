package platformcatalog

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"path"
	"regexp"
	"strconv"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jmoiron/sqlx"
	"grepmind-near/backend/pkg/database"
	"grepmind-near/backend/pkg/logger"
)

const (
	VerticalFood    = "food"
	VerticalGrocery = "grocery"
	maxPageSize     = 100
	maxPageOffset   = 10000
)

var (
	slugPattern = regexp.MustCompile(`^[a-z0-9]+(?:[-_][a-z0-9]+)*$`)
	skuPattern  = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._/-]{0,79}$`)
)

type Service struct{ db *database.DB }

func NewService(db *database.DB) *Service { return &Service{db: db} }

type apiEnvelope struct {
	Data any            `json:"data"`
	Meta map[string]any `json:"meta,omitempty"`
}

type apiError struct {
	Error map[string]any `json:"error"`
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, apiError{Error: map[string]any{"code": code, "message": message}})
}

func decodeJSON(w http.ResponseWriter, r *http.Request, dest any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 64<<10)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(dest); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_BODY", "The request body is invalid or too large.")
		return false
	}
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		writeError(w, http.StatusBadRequest, "INVALID_BODY", "Only one JSON value is allowed.")
		return false
	}
	return true
}

func validVertical(value string) bool { return value == VerticalFood || value == VerticalGrocery }

func normalizeCity(value string) (string, bool) {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "cuttack":
		return "Cuttack", true
	case "jajpur":
		return "Jajpur", true
	default:
		return "", false
	}
}

func parsePage(r *http.Request) (limit, offset int, ok bool) {
	limit = 20
	offset = 0
	var err error
	if raw := r.URL.Query().Get("limit"); raw != "" {
		limit, err = strconv.Atoi(raw)
		if err != nil || limit < 1 || limit > maxPageSize {
			return 0, 0, false
		}
	}
	if raw := r.URL.Query().Get("offset"); raw != "" {
		offset, err = strconv.Atoi(raw)
		if err != nil || offset < 0 || offset > maxPageOffset {
			return 0, 0, false
		}
	}
	return limit, offset, true
}

func validateUUID(value string) bool { _, err := uuid.Parse(value); return err == nil }

func validSKU(value string) bool { return skuPattern.MatchString(strings.TrimSpace(value)) }

func validImageURLs(values []string) bool {
	if len(values) > 8 {
		return false
	}
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value == "" || len(value) > 2048 {
			return false
		}
		if strings.HasPrefix(value, "/media/") {
			parsed, err := url.ParseRequestURI(value)
			if err != nil || parsed.IsAbs() || parsed.RawQuery != "" || parsed.Fragment != "" || strings.Contains(parsed.Path, `\`) || path.Clean(parsed.Path) != parsed.Path {
				return false
			}
			continue
		}
		parsed, err := url.ParseRequestURI(value)
		if err != nil || parsed.Scheme != "https" || parsed.Host == "" {
			return false
		}
	}
	return true
}

func responseFailure(w http.ResponseWriter, err error) {
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "The requested catalog resource was not found.")
		return
	}
	logger.Log.Error().Err(err).Msg("platform catalog request failed")
	writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "The catalog request could not be completed.")
}

type Category struct {
	ID        string  `json:"id"`
	Vertical  string  `json:"vertical"`
	Slug      string  `json:"slug"`
	Name      string  `json:"name"`
	ParentID  *string `json:"parent_id"`
	IsActive  bool    `json:"is_active"`
	IsSystem  bool    `json:"is_system"`
	SortOrder int     `json:"sort_order"`
}

type Area struct {
	City       string  `json:"city"`
	Locality   *string `json:"locality,omitempty"`
	DistrictID string  `json:"district_id,omitempty"`
	LocalityID string  `json:"locality_id,omitempty"`
}

type DeliveryDistrict struct {
	ID         string             `json:"id"`
	Name       string             `json:"name"`
	Localities []DeliveryLocality `json:"localities"`
}
type DeliveryLocality struct {
	ID              string `json:"id"`
	Name            string `json:"name"`
	DeliveryEnabled bool   `json:"delivery_enabled"`
}

// ListDeliveryLocations exposes the configured location hierarchy and rollout
// status. IDs, not locality labels, are used for catalog delivery filtering.
func (s *Service) ListDeliveryLocations(w http.ResponseWriter, r *http.Request) {
	rows, err := s.db.QueryxContext(r.Context(), `
		SELECT d.id::text,d.name,l.id::text,l.name,l.delivery_enabled
		FROM platform_districts d LEFT JOIN platform_delivery_localities l
		  ON l.district_id=d.id AND l.is_active
		WHERE d.state_code='OD' AND d.is_active
		ORDER BY d.name,l.name`)
	if err != nil {
		responseFailure(w, err)
		return
	}
	defer rows.Close()
	byID := map[string]int{}
	items := make([]DeliveryDistrict, 0)
	for rows.Next() {
		var districtID, districtName string
		var localityID, localityName sql.NullString
		var enabled sql.NullBool
		if err := rows.Scan(&districtID, &districtName, &localityID, &localityName, &enabled); err != nil {
			responseFailure(w, err)
			return
		}
		index, ok := byID[districtID]
		if !ok {
			index = len(items)
			byID[districtID] = index
			items = append(items, DeliveryDistrict{ID: districtID, Name: districtName, Localities: []DeliveryLocality{}})
		}
		if localityID.Valid {
			items[index].Localities = append(items[index].Localities, DeliveryLocality{ID: localityID.String, Name: localityName.String, DeliveryEnabled: enabled.Bool})
		}
	}
	if err := rows.Err(); err != nil {
		responseFailure(w, err)
		return
	}
	writeJSON(w, http.StatusOK, apiEnvelope{Data: items, Meta: map[string]any{"count": len(items)}})
}

func validateCatalogLocation(ctx context.Context, db *database.DB, district, localityID string) (bool, bool) {
	var districtOK bool
	if db.GetContext(ctx, &districtOK, `SELECT EXISTS(SELECT 1 FROM platform_districts WHERE lower(name)=lower($1) AND state_code='OD' AND is_active)`, district) != nil || !districtOK {
		return false, false
	}
	if localityID == "" {
		return true, true
	}
	var enabled bool
	err := db.GetContext(ctx, &enabled, `SELECT l.delivery_enabled FROM platform_delivery_localities l JOIN platform_districts d ON d.id=l.district_id WHERE l.id=$1 AND lower(d.name)=lower($2) AND l.is_active AND d.is_active`, localityID, district)
	if err != nil {
		return false, false
	}
	return true, enabled
}

type Variant struct {
	ID            string `json:"id"`
	ProductID     string `json:"product_id"`
	SKU           string `json:"sku"`
	Name          string `json:"name"`
	UnitLabel     string `json:"unit_label"`
	PriceMinor    int64  `json:"price_minor"`
	Currency      string `json:"currency"`
	PriceRevision int    `json:"price_revision"`
	IsActive      bool   `json:"is_active"`
}

type Product struct {
	ID                string    `json:"id"`
	SKU               string    `json:"sku"`
	CategoryID        string    `json:"category_id"`
	CategorySlug      string    `json:"category_slug"`
	CategoryName      string    `json:"category_name"`
	Vertical          string    `json:"vertical"`
	Name              string    `json:"name"`
	Description       string    `json:"description"`
	ImageURLs         []string  `json:"image_urls"`
	TaxClassification *string   `json:"tax_classification,omitempty"`
	Status            string    `json:"status"`
	Variants          []Variant `json:"variants"`
	Areas             []Area    `json:"areas"`
	CreatedAt         string    `json:"created_at"`
	UpdatedAt         string    `json:"updated_at"`
}

type productRow struct {
	ID                string         `db:"id"`
	SKU               string         `db:"sku"`
	CategoryID        string         `db:"category_id"`
	CategorySlug      string         `db:"category_slug"`
	CategoryName      string         `db:"category_name"`
	Vertical          string         `db:"vertical"`
	Name              string         `db:"name"`
	Description       string         `db:"description"`
	ImageURLsJSON     []byte         `db:"image_urls_json"`
	TaxClassification sql.NullString `db:"tax_classification"`
	Status            string         `db:"status"`
	CreatedAt         string         `db:"created_at"`
	UpdatedAt         string         `db:"updated_at"`
	VariantsJSON      []byte         `db:"variants_json"`
	AreasJSON         []byte         `db:"areas_json"`
}

const productSelect = `
	SELECT p.id::text, p.sku, p.category_id::text, c.slug AS category_slug,
	       c.name AS category_name, c.vertical, p.name, p.description,
	       to_json(p.image_urls) AS image_urls_json, p.tax_classification, p.status,
	       p.created_at::text, p.updated_at::text,
	       COALESCE((SELECT jsonb_agg(jsonb_build_object(
	           'id', v.id::text, 'product_id', v.product_id::text, 'sku', v.sku,
	           'name', v.name, 'unit_label', v.unit_label, 'price_minor', v.price_minor,
	           'currency', v.currency, 'price_revision', v.price_revision, 'is_active', v.is_active
	       ) ORDER BY v.name) FROM platform_catalog_variants v WHERE v.product_id=p.id AND ($1::boolean OR v.is_active)), '[]'::jsonb) AS variants_json,
	       COALESCE((SELECT jsonb_agg(jsonb_build_object('city', a.city, 'locality', a.locality) ORDER BY a.city, a.locality)
	         FROM platform_catalog_product_areas a WHERE a.product_id=p.id AND ($1::boolean OR a.is_active)), '[]'::jsonb) AS areas_json
	FROM platform_catalog_products p
	JOIN platform_catalog_categories c ON c.id=p.category_id
`

func scanProduct(row *sqlx.Row) (Product, error) {
	var dbRow productRow
	if err := row.StructScan(&dbRow); err != nil {
		return Product{}, err
	}
	return finishProduct(dbRow)
}

func finishProduct(row productRow) (Product, error) {
	product := Product{ID: row.ID, SKU: row.SKU, CategoryID: row.CategoryID, CategorySlug: row.CategorySlug, CategoryName: row.CategoryName, Vertical: row.Vertical, Name: row.Name, Description: row.Description, Status: row.Status, CreatedAt: row.CreatedAt, UpdatedAt: row.UpdatedAt}
	if err := json.Unmarshal(row.ImageURLsJSON, &product.ImageURLs); err != nil {
		return Product{}, err
	}
	if row.TaxClassification.Valid {
		product.TaxClassification = &row.TaxClassification.String
	}
	if product.ImageURLs == nil {
		product.ImageURLs = []string{}
	}
	if err := json.Unmarshal(row.VariantsJSON, &product.Variants); err != nil {
		return Product{}, err
	}
	if err := json.Unmarshal(row.AreasJSON, &product.Areas); err != nil {
		return Product{}, err
	}
	if product.Variants == nil {
		product.Variants = []Variant{}
	}
	if product.Areas == nil {
		product.Areas = []Area{}
	}
	return product, nil
}

func (s *Service) ListPublicCategories(w http.ResponseWriter, r *http.Request) {
	vertical := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("vertical")))
	city, cityOK := normalizeCity(r.URL.Query().Get("city"))
	localityID := strings.TrimSpace(r.URL.Query().Get("locality_id"))
	if !validVertical(vertical) || !cityOK || (localityID != "" && !validateUUID(localityID)) {
		writeError(w, http.StatusBadRequest, "INVALID_FILTER", "A supported vertical, district, and valid locality ID are required.")
		return
	}
	locationOK, deliveryEnabled := validateCatalogLocation(r.Context(), s.db, city, localityID)
	if !locationOK {
		writeError(w, http.StatusBadRequest, "UNSUPPORTED_LOCATION", "The locality does not belong to the selected district.")
		return
	}
	if !deliveryEnabled {
		writeJSON(w, http.StatusOK, apiEnvelope{Data: []Category{}, Meta: map[string]any{"count": 0, "delivery_available": false}})
		return
	}
	rows, err := s.db.QueryContext(r.Context(), `
		SELECT c.id::text, c.vertical, c.slug, c.name, c.parent_id::text, c.is_active, c.is_system, c.sort_order
		FROM platform_catalog_categories c
		WHERE c.vertical=$1 AND c.is_active
		  AND (c.is_system OR EXISTS (
			SELECT 1 FROM platform_catalog_products p
			JOIN platform_catalog_product_district_visibility a ON a.product_id=p.id AND a.district_id=(SELECT id FROM platform_districts WHERE name=$2) AND a.is_active
			JOIN platform_catalog_variants v ON v.product_id=p.id AND v.is_active
			WHERE p.category_id=c.id AND p.status='active'
			  AND ($3='' OR EXISTS(SELECT 1 FROM platform_catalog_product_delivery_localities pa WHERE pa.product_id=p.id AND pa.locality_id=$3::uuid AND pa.is_active))
		  ))
		ORDER BY c.sort_order, c.name
	`, vertical, city, localityID)
	if err != nil {
		responseFailure(w, err)
		return
	}
	defer rows.Close()
	items := make([]Category, 0)
	for rows.Next() {
		var item Category
		var parent sql.NullString
		if err := rows.Scan(&item.ID, &item.Vertical, &item.Slug, &item.Name, &parent, &item.IsActive, &item.IsSystem, &item.SortOrder); err != nil {
			responseFailure(w, err)
			return
		}
		if parent.Valid {
			item.ParentID = &parent.String
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		responseFailure(w, err)
		return
	}
	writeJSON(w, http.StatusOK, apiEnvelope{Data: items, Meta: map[string]any{"count": len(items)}})
}

func (s *Service) ListPublicProducts(w http.ResponseWriter, r *http.Request) {
	vertical := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("vertical")))
	city, cityOK := normalizeCity(r.URL.Query().Get("city"))
	localityID := strings.TrimSpace(r.URL.Query().Get("locality_id"))
	limit, offset, pageOK := parsePage(r)
	query := strings.TrimSpace(r.URL.Query().Get("q"))
	categoryID := strings.TrimSpace(r.URL.Query().Get("category_id"))
	if !validVertical(vertical) || !cityOK || !pageOK || len(query) > 100 || (localityID != "" && !validateUUID(localityID)) || (categoryID != "" && !validateUUID(categoryID)) {
		writeError(w, http.StatusBadRequest, "INVALID_FILTER", "The catalog filters are invalid or outside supported limits.")
		return
	}
	locationOK, deliveryEnabled := validateCatalogLocation(r.Context(), s.db, city, localityID)
	if !locationOK {
		writeError(w, http.StatusBadRequest, "UNSUPPORTED_LOCATION", "The locality does not belong to the selected district.")
		return
	}
	if !deliveryEnabled {
		writeJSON(w, http.StatusOK, apiEnvelope{Data: []Product{}, Meta: map[string]any{"count": 0, "limit": limit, "offset": offset, "has_more": false, "delivery_available": false}})
		return
	}
	args := []any{false, vertical, city, localityID, query, categoryID, limit + 1, offset}
	rows, err := s.db.QueryxContext(r.Context(), productSelect+`
		WHERE p.status='active' AND c.is_active AND c.vertical=$2
		  AND EXISTS (SELECT 1 FROM platform_catalog_product_district_visibility a WHERE a.product_id=p.id AND a.district_id=(SELECT id FROM platform_districts WHERE name=$3) AND a.is_active)
		  AND ($4='' OR EXISTS (SELECT 1 FROM platform_catalog_product_delivery_localities a JOIN platform_delivery_localities l ON l.id=a.locality_id WHERE a.product_id=p.id AND a.locality_id=$4::uuid AND a.is_active AND l.delivery_enabled AND l.is_active))
		  AND ($5='' OR to_tsvector('simple',p.name || ' ' || p.description) @@ plainto_tsquery('simple',$5))
		  AND ($6='' OR p.category_id=$6::uuid)
		  AND EXISTS (SELECT 1 FROM platform_catalog_variants v WHERE v.product_id=p.id AND v.is_active)
		ORDER BY p.created_at DESC, p.id
		LIMIT $7 OFFSET $8`, args...)
	if err != nil {
		responseFailure(w, err)
		return
	}
	defer rows.Close()
	items := make([]Product, 0, limit)
	for rows.Next() {
		var dbRow productRow
		if err := rows.StructScan(&dbRow); err != nil {
			responseFailure(w, err)
			return
		}
		item, err := finishProduct(dbRow)
		if err != nil {
			responseFailure(w, err)
			return
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		responseFailure(w, err)
		return
	}
	hasMore := len(items) > limit
	if hasMore {
		items = items[:limit]
	}
	writeJSON(w, http.StatusOK, apiEnvelope{Data: items, Meta: map[string]any{"count": len(items), "limit": limit, "offset": offset, "has_more": hasMore}})
}

func (s *Service) GetPublicProduct(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	vertical := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("vertical")))
	city, cityOK := normalizeCity(r.URL.Query().Get("city"))
	localityID := strings.TrimSpace(r.URL.Query().Get("locality_id"))
	if !validateUUID(id) || !validVertical(vertical) || !cityOK || (localityID != "" && !validateUUID(localityID)) {
		writeError(w, http.StatusBadRequest, "INVALID_FILTER", "The product ID or location filters are invalid.")
		return
	}
	locationOK, deliveryEnabled := validateCatalogLocation(r.Context(), s.db, city, localityID)
	if !locationOK {
		writeError(w, http.StatusBadRequest, "UNSUPPORTED_LOCATION", "The locality does not belong to the selected district.")
		return
	}
	if !deliveryEnabled {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "The product is unavailable for delivery in this locality.")
		return
	}
	query := productSelect + `
		WHERE p.id=$2 AND p.status='active' AND c.is_active AND c.vertical=$3
		  AND EXISTS (SELECT 1 FROM platform_catalog_product_district_visibility a WHERE a.product_id=p.id AND a.district_id=(SELECT id FROM platform_districts WHERE name=$4) AND a.is_active)
		  AND ($5='' OR EXISTS (SELECT 1 FROM platform_catalog_product_delivery_localities a JOIN platform_delivery_localities l ON l.id=a.locality_id WHERE a.product_id=p.id AND a.locality_id=$5::uuid AND a.is_active AND l.delivery_enabled AND l.is_active))
		  AND EXISTS (SELECT 1 FROM platform_catalog_variants v WHERE v.product_id=p.id AND v.is_active)`
	item, err := scanProduct(s.db.QueryRowxContext(r.Context(), query, false, id, vertical, city, localityID))
	if err != nil {
		responseFailure(w, err)
		return
	}
	writeJSON(w, http.StatusOK, apiEnvelope{Data: item})
}

func (s *Service) logAudit(ctx context.Context, tx *sqlx.Tx, actorID, action, targetType, targetID string) error {
	_, err := tx.ExecContext(ctx, `INSERT INTO audit_logs(actor_user_id,action,target_type,target_id,reason) VALUES($1,$2,$3,$4::uuid,$5)`, actorID, action, targetType, targetID, "Platform catalog management")
	return err
}

func (s *Service) adminListCategories(w http.ResponseWriter, r *http.Request, _ string) {
	vertical := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("vertical")))
	if vertical != "" && !validVertical(vertical) {
		writeError(w, http.StatusBadRequest, "INVALID_VERTICAL", "Vertical must be food or grocery.")
		return
	}
	query := `SELECT id::text,vertical,slug,name,parent_id::text,is_active,is_system,sort_order FROM platform_catalog_categories`
	args := []any{}
	if vertical != "" {
		query += ` WHERE vertical=$1`
		args = append(args, vertical)
	}
	query += ` ORDER BY vertical,sort_order,name`
	rows, err := s.db.QueryxContext(r.Context(), query, args...)
	if err != nil {
		responseFailure(w, err)
		return
	}
	defer rows.Close()
	items := make([]Category, 0)
	for rows.Next() {
		var item Category
		var parent sql.NullString
		if err := rows.Scan(&item.ID, &item.Vertical, &item.Slug, &item.Name, &parent, &item.IsActive, &item.IsSystem, &item.SortOrder); err != nil {
			responseFailure(w, err)
			return
		}
		if parent.Valid {
			item.ParentID = &parent.String
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		responseFailure(w, err)
		return
	}
	writeJSON(w, http.StatusOK, apiEnvelope{Data: items, Meta: map[string]any{"count": len(items)}})
}

type categoryInput struct {
	Vertical  string  `json:"vertical"`
	Slug      string  `json:"slug"`
	Name      string  `json:"name"`
	ParentID  *string `json:"parent_id"`
	IsActive  *bool   `json:"is_active"`
	SortOrder int     `json:"sort_order"`
}

func (s *Service) adminCreateCategory(w http.ResponseWriter, r *http.Request, actorID string) {
	var input categoryInput
	if !decodeJSON(w, r, &input) {
		return
	}
	input.Vertical = strings.ToLower(strings.TrimSpace(input.Vertical))
	input.Slug = strings.ToLower(strings.TrimSpace(input.Slug))
	input.Name = strings.TrimSpace(input.Name)
	if !validVertical(input.Vertical) || !slugPattern.MatchString(input.Slug) || len(input.Name) < 1 || len(input.Name) > 100 || input.SortOrder < 0 || input.SortOrder > 100000 {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Category vertical, slug, name, or sort order is invalid.")
		return
	}
	if input.ParentID != nil && !validateUUID(*input.ParentID) {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Parent category ID is invalid.")
		return
	}
	if input.IsActive == nil {
		active := true
		input.IsActive = &active
	}
	var id string
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if input.ParentID != nil {
			var valid bool
			if err := tx.GetContext(r.Context(), &valid, `SELECT EXISTS(SELECT 1 FROM platform_catalog_categories WHERE id=$1 AND vertical=$2 AND is_active)`, *input.ParentID, input.Vertical); err != nil {
				return err
			}
			if !valid {
				return errInvalidReference
			}
		}
		if err := tx.GetContext(r.Context(), &id, `INSERT INTO platform_catalog_categories(vertical,slug,name,parent_id,is_active,sort_order,created_by,updated_by) VALUES($1,$2,$3,$4,$5,$6,$7,$7) RETURNING id::text`, input.Vertical, input.Slug, input.Name, input.ParentID, *input.IsActive, input.SortOrder, actorID); err != nil {
			return err
		}
		return s.logAudit(r.Context(), tx, actorID, "platform_catalog.category.create", "platform_catalog_category", id)
	})
	if err != nil {
		if errors.Is(err, errInvalidReference) {
			writeError(w, http.StatusBadRequest, "INVALID_PARENT_CATEGORY", "The parent category must be active and belong to the same vertical.")
			return
		}
		if isUniqueViolation(err) {
			writeError(w, http.StatusConflict, "CATEGORY_EXISTS", "A category with this slug already exists in the vertical.")
			return
		}
		responseFailure(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, apiEnvelope{Data: map[string]string{"id": id}})
}

var errInvalidReference = errors.New("invalid platform catalog reference")

func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}

func (s *Service) adminUpdateCategory(w http.ResponseWriter, r *http.Request, actorID string) {
	id := r.PathValue("id")
	if !validateUUID(id) {
		writeError(w, http.StatusBadRequest, "INVALID_ID", "Category ID is invalid.")
		return
	}
	var input struct {
		Name      *string `json:"name"`
		IsActive  *bool   `json:"is_active"`
		SortOrder *int    `json:"sort_order"`
	}
	if !decodeJSON(w, r, &input) {
		return
	}
	if input.Name == nil && input.IsActive == nil && input.SortOrder == nil {
		writeError(w, http.StatusBadRequest, "EMPTY_UPDATE", "At least one category field must be supplied.")
		return
	}
	if input.Name != nil {
		*input.Name = strings.TrimSpace(*input.Name)
		if len(*input.Name) < 1 || len(*input.Name) > 100 {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Category name must be between 1 and 100 characters.")
			return
		}
	}
	if input.SortOrder != nil && (*input.SortOrder < 0 || *input.SortOrder > 100000) {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Sort order is invalid.")
		return
	}
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var system bool
		if err := tx.GetContext(r.Context(), &system, `SELECT is_system FROM platform_catalog_categories WHERE id=$1 FOR UPDATE`, id); err != nil {
			return err
		}
		if system && input.IsActive != nil && !*input.IsActive {
			return errSystemCategory
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE platform_catalog_categories SET name=COALESCE($2,name),is_active=COALESCE($3,is_active),sort_order=COALESCE($4,sort_order),updated_by=$5,updated_at=now() WHERE id=$1`, id, input.Name, input.IsActive, input.SortOrder, actorID); err != nil {
			return err
		}
		return s.logAudit(r.Context(), tx, actorID, "platform_catalog.category.update", "platform_catalog_category", id)
	})
	if errors.Is(err, errSystemCategory) {
		writeError(w, http.StatusConflict, "SYSTEM_CATEGORY", "The Food and Grocery root categories cannot be deactivated.")
		return
	}
	if err != nil {
		responseFailure(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

var errSystemCategory = errors.New("system category cannot be deactivated")

func (s *Service) adminListProducts(w http.ResponseWriter, r *http.Request, _ string) {
	limit, offset, ok := parsePage(r)
	vertical := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("vertical")))
	status := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("status")))
	query := strings.TrimSpace(r.URL.Query().Get("q"))
	if !ok || (vertical != "" && !validVertical(vertical)) || (status != "" && status != "draft" && status != "active" && status != "inactive") || len(query) > 100 {
		writeError(w, http.StatusBadRequest, "INVALID_FILTER", "The catalog filters are invalid or outside supported limits.")
		return
	}
	args := []any{true, vertical, status, query, limit + 1, offset}
	rows, err := s.db.QueryxContext(r.Context(), productSelect+`
		WHERE ($2='' OR c.vertical=$2) AND ($3='' OR p.status=$3)
		  AND ($4='' OR to_tsvector('simple',p.name || ' ' || p.description) @@ plainto_tsquery('simple',$4) OR strpos(lower(p.sku),lower($4))>0)
		ORDER BY p.updated_at DESC,p.id LIMIT $5 OFFSET $6`, args...)
	if err != nil {
		responseFailure(w, err)
		return
	}
	defer rows.Close()
	items := make([]Product, 0, limit)
	for rows.Next() {
		var dbRow productRow
		if err := rows.StructScan(&dbRow); err != nil {
			responseFailure(w, err)
			return
		}
		item, err := finishProduct(dbRow)
		if err != nil {
			responseFailure(w, err)
			return
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		responseFailure(w, err)
		return
	}
	hasMore := len(items) > limit
	if hasMore {
		items = items[:limit]
	}
	writeJSON(w, http.StatusOK, apiEnvelope{Data: items, Meta: map[string]any{"count": len(items), "limit": limit, "offset": offset, "has_more": hasMore}})
}

type variantInput struct {
	SKU        string `json:"sku"`
	Name       string `json:"name"`
	UnitLabel  string `json:"unit_label"`
	PriceMinor int64  `json:"price_minor"`
	Currency   string `json:"currency"`
}

type productCreateInput struct {
	SKU               string         `json:"sku"`
	CategoryID        string         `json:"category_id"`
	Name              string         `json:"name"`
	Description       string         `json:"description"`
	ImageURLs         []string       `json:"image_urls"`
	TaxClassification *string        `json:"tax_classification"`
	Status            string         `json:"status"`
	Areas             []Area         `json:"areas"`
	Variants          []variantInput `json:"variants"`
}

func cleanAreas(areas []Area) ([]Area, bool) {
	if len(areas) < 1 || len(areas) > 20 {
		return nil, false
	}
	seen := map[string]bool{}
	clean := make([]Area, 0, len(areas))
	for _, area := range areas {
		city := strings.TrimSpace(area.City)
		if area.DistrictID == "" {
			var ok bool
			city, ok = normalizeCity(city)
			if !ok {
				return nil, false
			}
		} else if !validateUUID(area.DistrictID) {
			return nil, false
		}
		if area.LocalityID != "" && !validateUUID(area.LocalityID) {
			return nil, false
		}
		var locality *string
		keyLocality := ""
		if area.Locality != nil && strings.TrimSpace(*area.Locality) != "" {
			value := strings.TrimSpace(*area.Locality)
			if len(value) > 100 {
				return nil, false
			}
			locality = &value
			keyLocality = strings.ToLower(value)
		}
		if area.LocalityID != "" {
			keyLocality = area.LocalityID
		}
		key := city + "\x00" + area.DistrictID + "\x00" + keyLocality
		if seen[key] {
			return nil, false
		}
		seen[key] = true
		clean = append(clean, Area{City: city, Locality: locality, DistrictID: area.DistrictID, LocalityID: area.LocalityID})
	}
	return clean, true
}

func insertProductArea(ctx context.Context, tx *sqlx.Tx, productID string, area Area, actorID string) error {
	var districtID, city string
	if area.DistrictID != "" {
		if err := tx.QueryRowxContext(ctx, `SELECT id::text,name FROM platform_districts WHERE id=$1 AND state_code='OD' AND is_active`, area.DistrictID).Scan(&districtID, &city); err != nil {
			return err
		}
	} else {
		city, _ = normalizeCity(area.City)
		if err := tx.QueryRowxContext(ctx, `SELECT id::text FROM platform_districts WHERE lower(name)=lower($1) AND is_active`, city).Scan(&districtID); err != nil {
			return err
		}
	}
	var localityName any
	localityID := area.LocalityID
	if localityID != "" {
		var name string
		if err := tx.QueryRowxContext(ctx, `SELECT name FROM platform_delivery_localities WHERE id=$1 AND district_id=$2 AND is_active`, localityID, districtID).Scan(&name); err != nil {
			return err
		}
		localityName = name
	} else if area.Locality != nil {
		localityName = *area.Locality
		// Legacy admin clients may continue sending a label. It is only used to
		// resolve an existing configured locality; it never grants eligibility.
		_ = tx.QueryRowxContext(ctx, `SELECT id::text FROM platform_delivery_localities WHERE district_id=$1 AND lower(name)=lower($2) AND is_active`, districtID, *area.Locality).Scan(&localityID)
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO platform_catalog_product_areas(product_id,city,locality,created_by) VALUES($1,$2,$3,$4)`, productID, city, localityName, actorID); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO platform_catalog_product_district_visibility(product_id,district_id) VALUES($1,$2) ON CONFLICT(product_id,district_id) DO UPDATE SET is_active=true`, productID, districtID); err != nil {
		return err
	}
	if localityID != "" {
		_, err := tx.ExecContext(ctx, `INSERT INTO platform_catalog_product_delivery_localities(product_id,locality_id) VALUES($1,$2) ON CONFLICT(product_id,locality_id) DO UPDATE SET is_active=true`, productID, localityID)
		return err
	}
	return nil
}

func cleanVariants(variants []variantInput) ([]variantInput, bool) {
	if len(variants) < 1 || len(variants) > 20 {
		return nil, false
	}
	seen := map[string]bool{}
	for index := range variants {
		v := &variants[index]
		v.SKU = strings.TrimSpace(v.SKU)
		v.Name = strings.TrimSpace(v.Name)
		v.UnitLabel = strings.TrimSpace(v.UnitLabel)
		v.Currency = strings.ToUpper(strings.TrimSpace(v.Currency))
		if v.Currency == "" {
			v.Currency = "INR"
		}
		if !validSKU(v.SKU) || len(v.Name) < 1 || len(v.Name) > 120 || len(v.UnitLabel) < 1 || len(v.UnitLabel) > 40 || v.PriceMinor < 0 || v.PriceMinor > 9_000_000_000_000_000 || v.Currency != "INR" || seen[strings.ToLower(v.SKU)] {
			return nil, false
		}
		seen[strings.ToLower(v.SKU)] = true
	}
	return variants, true
}

func (s *Service) adminCreateProduct(w http.ResponseWriter, r *http.Request, actorID string) {
	var input productCreateInput
	if !decodeJSON(w, r, &input) {
		return
	}
	input.SKU = strings.TrimSpace(input.SKU)
	input.Name = strings.TrimSpace(input.Name)
	input.Description = strings.TrimSpace(input.Description)
	if input.Status == "" {
		input.Status = "draft"
	}
	variants, variantsOK := cleanVariants(input.Variants)
	areas, areasOK := cleanAreas(input.Areas)
	if !validSKU(input.SKU) || !validateUUID(input.CategoryID) || len(input.Name) < 1 || len(input.Name) > 160 || len(input.Description) > 4000 || !validImageURLs(input.ImageURLs) || !variantsOK || !areasOK || (input.Status != "draft" && input.Status != "active" && input.Status != "inactive") || (input.TaxClassification != nil && len(strings.TrimSpace(*input.TaxClassification)) > 80) {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Product details, images, areas, variants, status, or price are invalid.")
		return
	}
	if input.ImageURLs == nil {
		input.ImageURLs = []string{}
	}
	for index := range input.ImageURLs {
		input.ImageURLs[index] = strings.TrimSpace(input.ImageURLs[index])
	}
	if input.TaxClassification != nil {
		value := strings.TrimSpace(*input.TaxClassification)
		if value == "" {
			input.TaxClassification = nil
		} else {
			input.TaxClassification = &value
		}
	}
	var productID string
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var categoryActive bool
		if err := tx.GetContext(r.Context(), &categoryActive, `SELECT is_active FROM platform_catalog_categories WHERE id=$1`, input.CategoryID); err != nil {
			return err
		}
		if !categoryActive && input.Status == "active" {
			return errInvalidReference
		}
		if err := tx.GetContext(r.Context(), &productID, `INSERT INTO platform_catalog_products(sku,category_id,name,description,image_urls,tax_classification,status,created_by,updated_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$8) RETURNING id::text`, input.SKU, input.CategoryID, input.Name, input.Description, input.ImageURLs, input.TaxClassification, input.Status, actorID); err != nil {
			return err
		}
		for _, variant := range variants {
			if _, err := tx.ExecContext(r.Context(), `INSERT INTO platform_catalog_variants(product_id,sku,name,unit_label,price_minor,currency,created_by,updated_by) VALUES($1,$2,$3,$4,$5,$6,$7,$7)`, productID, variant.SKU, variant.Name, variant.UnitLabel, variant.PriceMinor, variant.Currency, actorID); err != nil {
				return err
			}
		}
		for _, area := range areas {
			if err := insertProductArea(r.Context(), tx, productID, area, actorID); err != nil {
				return err
			}
		}
		return s.logAudit(r.Context(), tx, actorID, "platform_catalog.product.create", "platform_catalog_product", productID)
	})
	if err != nil {
		if errors.Is(err, errInvalidReference) {
			writeError(w, http.StatusConflict, "CATEGORY_INACTIVE", "An active product must use an active category.")
			return
		}
		if isUniqueViolation(err) {
			writeError(w, http.StatusConflict, "SKU_EXISTS", "A catalog or variant SKU is already in use.")
			return
		}
		responseFailure(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, apiEnvelope{Data: map[string]string{"id": productID}})
}

func (s *Service) adminUpdateProduct(w http.ResponseWriter, r *http.Request, actorID string) {
	productID := r.PathValue("id")
	if !validateUUID(productID) {
		writeError(w, http.StatusBadRequest, "INVALID_ID", "Product ID is invalid.")
		return
	}
	var input struct {
		CategoryID        *string   `json:"category_id"`
		Name              *string   `json:"name"`
		Description       *string   `json:"description"`
		ImageURLs         *[]string `json:"image_urls"`
		TaxClassification *string   `json:"tax_classification"`
		Status            *string   `json:"status"`
		Areas             *[]Area   `json:"areas"`
	}
	if !decodeJSON(w, r, &input) {
		return
	}
	if input.CategoryID == nil && input.Name == nil && input.Description == nil && input.ImageURLs == nil && input.TaxClassification == nil && input.Status == nil && input.Areas == nil {
		writeError(w, http.StatusBadRequest, "EMPTY_UPDATE", "At least one product field must be supplied.")
		return
	}
	if input.CategoryID != nil && !validateUUID(*input.CategoryID) {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Category ID is invalid.")
		return
	}
	if input.Name != nil {
		*input.Name = strings.TrimSpace(*input.Name)
		if len(*input.Name) < 1 || len(*input.Name) > 160 {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Product name must be between 1 and 160 characters.")
			return
		}
	}
	if input.Description != nil && len(strings.TrimSpace(*input.Description)) > 4000 {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Product description is too long.")
		return
	}
	if input.ImageURLs != nil && !validImageURLs(*input.ImageURLs) {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Image URLs must be https or relative media URLs, with at most 8 images.")
		return
	}
	if input.TaxClassification != nil && len(strings.TrimSpace(*input.TaxClassification)) > 80 {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Tax classification is too long.")
		return
	}
	if input.TaxClassification != nil {
		value := strings.TrimSpace(*input.TaxClassification)
		input.TaxClassification = &value
	}
	if input.Status != nil && *input.Status != "draft" && *input.Status != "active" && *input.Status != "inactive" {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Status must be draft, active, or inactive.")
		return
	}
	var cleanedAreas []Area
	if input.Areas != nil {
		var ok bool
		cleanedAreas, ok = cleanAreas(*input.Areas)
		if !ok {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "At least one unique supported city/locality is required.")
			return
		}
	}
	var oldStatus string
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := tx.GetContext(r.Context(), &oldStatus, `SELECT status FROM platform_catalog_products WHERE id=$1 FOR UPDATE`, productID); err != nil {
			return err
		}
		if input.CategoryID != nil {
			var active bool
			if err := tx.GetContext(r.Context(), &active, `SELECT is_active FROM platform_catalog_categories WHERE id=$1`, *input.CategoryID); err != nil {
				return err
			}
			if !active && input.Status != nil && *input.Status == "active" {
				return errInvalidReference
			}
		}
		if input.Status != nil && *input.Status == "active" {
			categoryID := ""
			if input.CategoryID != nil {
				categoryID = *input.CategoryID
			}
			var ready bool
			if err := tx.GetContext(r.Context(), &ready, `SELECT EXISTS(SELECT 1 FROM platform_catalog_variants v WHERE v.product_id=$1 AND v.is_active) AND EXISTS(SELECT 1 FROM platform_catalog_product_areas a WHERE a.product_id=$1 AND a.is_active) AND EXISTS(SELECT 1 FROM platform_catalog_categories c WHERE c.id=COALESCE(NULLIF($2,'')::uuid,(SELECT category_id FROM platform_catalog_products WHERE id=$1)) AND c.is_active)`, productID, categoryID); err != nil {
				return err
			}
			if !ready {
				return errProductNotReady
			}
		}
		_, err := tx.ExecContext(r.Context(), `UPDATE platform_catalog_products SET category_id=COALESCE($2::uuid,category_id),name=COALESCE($3,name),description=COALESCE($4,description),image_urls=COALESCE($5,image_urls),tax_classification=CASE WHEN $9 THEN NULLIF($6,'') ELSE tax_classification END,status=COALESCE($7,status),updated_by=$8,updated_at=now() WHERE id=$1`, productID, input.CategoryID, input.Name, input.Description, input.ImageURLs, input.TaxClassification, input.Status, actorID, input.TaxClassification != nil)
		if err != nil {
			return err
		}
		if input.Areas != nil {
			if _, err := tx.ExecContext(r.Context(), `DELETE FROM platform_catalog_product_areas WHERE product_id=$1`, productID); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `DELETE FROM platform_catalog_product_district_visibility WHERE product_id=$1`, productID); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `DELETE FROM platform_catalog_product_delivery_localities WHERE product_id=$1`, productID); err != nil {
				return err
			}
			for _, area := range cleanedAreas {
				if err := insertProductArea(r.Context(), tx, productID, area, actorID); err != nil {
					return err
				}
			}
		}
		return s.logAudit(r.Context(), tx, actorID, "platform_catalog.product.update", "platform_catalog_product", productID)
	})
	if errors.Is(err, errInvalidReference) {
		writeError(w, http.StatusConflict, "CATEGORY_INACTIVE", "An active product must use an active category.")
		return
	}
	if errors.Is(err, errProductNotReady) {
		writeError(w, http.StatusConflict, "PRODUCT_NOT_READY", "An active product requires an active category, variant, and geographic availability.")
		return
	}
	if err != nil {
		responseFailure(w, err)
		return
	}
	if input.Status != nil && *input.Status == "inactive" && oldStatus != "inactive" {
		// Status changes are intentionally visible through the normal update audit entry.
	}
	w.WriteHeader(http.StatusNoContent)
}

var errProductNotReady = errors.New("platform product is missing an active variant, active area, or category")

func (s *Service) adminCreateVariant(w http.ResponseWriter, r *http.Request, actorID string) {
	productID := r.PathValue("id")
	if !validateUUID(productID) {
		writeError(w, http.StatusBadRequest, "INVALID_ID", "Product ID is invalid.")
		return
	}
	var input variantInput
	if !decodeJSON(w, r, &input) {
		return
	}
	items, ok := cleanVariants([]variantInput{input})
	if !ok {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Variant name, SKU, unit, price, or currency is invalid.")
		return
	}
	var id string
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := tx.GetContext(r.Context(), &id, `INSERT INTO platform_catalog_variants(product_id,sku,name,unit_label,price_minor,currency,created_by,updated_by) VALUES($1,$2,$3,$4,$5,$6,$7,$7) RETURNING id::text`, productID, items[0].SKU, items[0].Name, items[0].UnitLabel, items[0].PriceMinor, items[0].Currency, actorID); err != nil {
			return err
		}
		return s.logAudit(r.Context(), tx, actorID, "platform_catalog.variant.create", "platform_catalog_product", productID)
	})
	if err != nil {
		if isUniqueViolation(err) {
			writeError(w, http.StatusConflict, "SKU_EXISTS", "A catalog or variant SKU is already in use.")
			return
		}
		responseFailure(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, apiEnvelope{Data: map[string]string{"id": id}})
}

func (s *Service) adminUpdateVariant(w http.ResponseWriter, r *http.Request, actorID string) {
	variantID := r.PathValue("id")
	if !validateUUID(variantID) {
		writeError(w, http.StatusBadRequest, "INVALID_ID", "Variant ID is invalid.")
		return
	}
	var input struct {
		Name       *string `json:"name"`
		UnitLabel  *string `json:"unit_label"`
		PriceMinor *int64  `json:"price_minor"`
		Currency   *string `json:"currency"`
		IsActive   *bool   `json:"is_active"`
	}
	if !decodeJSON(w, r, &input) {
		return
	}
	if input.Name == nil && input.UnitLabel == nil && input.PriceMinor == nil && input.Currency == nil && input.IsActive == nil {
		writeError(w, http.StatusBadRequest, "EMPTY_UPDATE", "At least one variant field must be supplied.")
		return
	}
	if input.Name != nil {
		*input.Name = strings.TrimSpace(*input.Name)
		if len(*input.Name) < 1 || len(*input.Name) > 120 {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Variant name is invalid.")
			return
		}
	}
	if input.UnitLabel != nil {
		*input.UnitLabel = strings.TrimSpace(*input.UnitLabel)
		if len(*input.UnitLabel) < 1 || len(*input.UnitLabel) > 40 {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Variant unit is invalid.")
			return
		}
	}
	if input.PriceMinor != nil && (*input.PriceMinor < 0 || *input.PriceMinor > 9_000_000_000_000_000) {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Price is outside the supported range.")
		return
	}
	if input.Currency != nil {
		value := strings.ToUpper(strings.TrimSpace(*input.Currency))
		input.Currency = &value
		if value != "INR" {
			writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Only INR is supported in this release.")
			return
		}
	}
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var productID string
		var oldPrice int64
		if err := tx.QueryRowxContext(r.Context(), `SELECT product_id::text,price_minor FROM platform_catalog_variants WHERE id=$1 FOR UPDATE`, variantID).Scan(&productID, &oldPrice); err != nil {
			return err
		}
		_, err := tx.ExecContext(r.Context(), `UPDATE platform_catalog_variants SET name=COALESCE($2,name),unit_label=COALESCE($3,unit_label),price_minor=COALESCE($4,price_minor),currency=COALESCE($5,currency),is_active=COALESCE($6,is_active),price_revision=price_revision+CASE WHEN $4::bigint IS NOT NULL AND $4::bigint<>price_minor THEN 1 ELSE 0 END,updated_by=$7,updated_at=now() WHERE id=$1`, variantID, input.Name, input.UnitLabel, input.PriceMinor, input.Currency, input.IsActive, actorID)
		if err != nil {
			return err
		}
		if input.IsActive != nil && !*input.IsActive {
			if _, err := tx.ExecContext(r.Context(), `UPDATE platform_catalog_products SET updated_at=now() WHERE id=$1`, productID); err != nil {
				return err
			}
		}
		_ = oldPrice
		return s.logAudit(r.Context(), tx, actorID, "platform_catalog.variant.update", "platform_catalog_product", productID)
	})
	if err != nil {
		responseFailure(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type mappingInput struct {
	BusinessID         string `json:"business_id"`
	VariantID          string `json:"variant_id"`
	InventoryMode      string `json:"inventory_mode"`
	AvailableQuantity  *int   `json:"available_quantity"`
	CapacityPerDay     *int   `json:"capacity_per_day"`
	PreparationMinutes *int   `json:"preparation_minutes"`
	SupplyPriceMinor   *int64 `json:"supply_price_minor"`
}

func validateMappingInput(input *mappingInput) bool {
	input.BusinessID = strings.TrimSpace(input.BusinessID)
	input.VariantID = strings.TrimSpace(input.VariantID)
	input.InventoryMode = strings.ToLower(strings.TrimSpace(input.InventoryMode))
	if input.InventoryMode == "" {
		input.InventoryMode = "untracked"
	}
	if !validateUUID(input.BusinessID) || !validateUUID(input.VariantID) {
		return false
	}
	if input.InventoryMode == "finite" {
		return input.AvailableQuantity != nil && *input.AvailableQuantity >= 0 && input.CapacityPerDay == nil && (input.PreparationMinutes == nil || (*input.PreparationMinutes >= 0 && *input.PreparationMinutes <= 1440)) && (input.SupplyPriceMinor == nil || *input.SupplyPriceMinor >= 0)
	}
	if input.InventoryMode == "capacity" {
		return input.AvailableQuantity == nil && input.CapacityPerDay != nil && *input.CapacityPerDay >= 0 && (input.PreparationMinutes == nil || (*input.PreparationMinutes >= 0 && *input.PreparationMinutes <= 1440)) && (input.SupplyPriceMinor == nil || *input.SupplyPriceMinor >= 0)
	}
	return input.InventoryMode == "untracked" && input.AvailableQuantity == nil && input.CapacityPerDay == nil && (input.PreparationMinutes == nil || (*input.PreparationMinutes >= 0 && *input.PreparationMinutes <= 1440)) && (input.SupplyPriceMinor == nil || *input.SupplyPriceMinor >= 0)
}

func (s *Service) adminListMappings(w http.ResponseWriter, r *http.Request, _ string) {
	businessID := strings.TrimSpace(r.URL.Query().Get("business_id"))
	status := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("status")))
	if businessID != "" && !validateUUID(businessID) {
		writeError(w, http.StatusBadRequest, "INVALID_FILTER", "Business ID is invalid.")
		return
	}
	if status != "" && status != "pending" && status != "approved" && status != "rejected" && status != "inactive" {
		writeError(w, http.StatusBadRequest, "INVALID_FILTER", "Mapping status is invalid.")
		return
	}
	rows, err := s.db.QueryContext(r.Context(), `
		SELECT m.id::text,m.business_id::text,b.name,b.city,m.variant_id::text,p.name,v.name,v.unit_label,c.vertical,
		       m.status,m.inventory_mode,m.available_quantity,m.capacity_per_day,m.preparation_minutes,
		       m.supply_price_minor,m.supply_currency,m.approved_at::text
		FROM platform_partner_product_mappings m
		JOIN businesses b ON b.id=m.business_id
		JOIN platform_catalog_variants v ON v.id=m.variant_id
		JOIN platform_catalog_products p ON p.id=v.product_id
		JOIN platform_catalog_categories c ON c.id=p.category_id
		WHERE ($1='' OR m.business_id=$1::uuid) AND ($2='' OR m.status=$2)
		ORDER BY CASE m.status WHEN 'pending' THEN 0 WHEN 'approved' THEN 1 ELSE 2 END,m.updated_at DESC,m.id
		LIMIT 300`, businessID, status)
	if err != nil {
		responseFailure(w, err)
		return
	}
	defer rows.Close()
	items := make([]map[string]any, 0)
	for rows.Next() {
		var id, bid, business, city, variantID, product, variant, unit, vertical, mappingStatus, mode, supplyCurrency string
		var quantity, capacity, preparation sql.NullInt64
		var supplyPrice sql.NullInt64
		var approvedAt sql.NullString
		if err := rows.Scan(&id, &bid, &business, &city, &variantID, &product, &variant, &unit, &vertical, &mappingStatus, &mode, &quantity, &capacity, &preparation, &supplyPrice, &supplyCurrency, &approvedAt); err != nil {
			responseFailure(w, err)
			return
		}
		item := map[string]any{"id": id, "business_id": bid, "business_name": business, "business_city": city, "variant_id": variantID, "product_name": product, "variant_name": variant, "unit_label": unit, "vertical": vertical, "status": mappingStatus, "inventory_mode": mode, "supply_currency": strings.TrimSpace(supplyCurrency)}
		if quantity.Valid {
			item["available_quantity"] = quantity.Int64
		}
		if capacity.Valid {
			item["capacity_per_day"] = capacity.Int64
		}
		if preparation.Valid {
			item["preparation_minutes"] = preparation.Int64
		}
		if supplyPrice.Valid {
			item["supply_price_minor"] = supplyPrice.Int64
		}
		if approvedAt.Valid {
			item["approved_at"] = approvedAt.String
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		responseFailure(w, err)
		return
	}
	writeJSON(w, http.StatusOK, apiEnvelope{Data: items, Meta: map[string]any{"count": len(items)}})
}

func (s *Service) adminCreateMapping(w http.ResponseWriter, r *http.Request, actorID string) {
	var input mappingInput
	if !decodeJSON(w, r, &input) {
		return
	}
	if !validateMappingInput(&input) {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Partner, variant, stock mode, quantity, capacity, or cost is invalid.")
		return
	}
	var id string
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var valid bool
		if err := tx.GetContext(r.Context(), &valid, `SELECT EXISTS(SELECT 1 FROM businesses WHERE id=$1) AND EXISTS(SELECT 1 FROM platform_catalog_variants WHERE id=$2)`, input.BusinessID, input.VariantID); err != nil {
			return err
		}
		if !valid {
			return errInvalidReference
		}
		if err := tx.GetContext(r.Context(), &id, `INSERT INTO platform_partner_product_mappings(business_id,variant_id,inventory_mode,available_quantity,capacity_per_day,preparation_minutes,supply_price_minor,created_by,updated_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$8) RETURNING id::text`, input.BusinessID, input.VariantID, input.InventoryMode, input.AvailableQuantity, input.CapacityPerDay, input.PreparationMinutes, input.SupplyPriceMinor, actorID); err != nil {
			return err
		}
		return s.logAudit(r.Context(), tx, actorID, "platform_catalog.partner_mapping.create", "platform_partner_product_mapping", id)
	})
	if err != nil {
		if errors.Is(err, errInvalidReference) {
			writeError(w, http.StatusBadRequest, "INVALID_REFERENCE", "The partner business or platform variant does not exist.")
			return
		}
		if isUniqueViolation(err) {
			writeError(w, http.StatusConflict, "MAPPING_EXISTS", "This business already has a mapping for the selected variant.")
			return
		}
		responseFailure(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, apiEnvelope{Data: map[string]string{"id": id, "status": "pending"}})
}

func (s *Service) adminUpdateMapping(w http.ResponseWriter, r *http.Request, actorID string) {
	id := r.PathValue("id")
	if !validateUUID(id) {
		writeError(w, http.StatusBadRequest, "INVALID_ID", "Mapping ID is invalid.")
		return
	}
	var input struct {
		Status             *string `json:"status"`
		InventoryMode      *string `json:"inventory_mode"`
		AvailableQuantity  *int    `json:"available_quantity"`
		CapacityPerDay     *int    `json:"capacity_per_day"`
		PreparationMinutes *int    `json:"preparation_minutes"`
		SupplyPriceMinor   *int64  `json:"supply_price_minor"`
	}
	if !decodeJSON(w, r, &input) {
		return
	}
	if input.Status == nil && input.InventoryMode == nil && input.AvailableQuantity == nil && input.CapacityPerDay == nil && input.PreparationMinutes == nil && input.SupplyPriceMinor == nil {
		writeError(w, 400, "EMPTY_UPDATE", "At least one mapping field must be supplied.")
		return
	}
	if input.Status != nil {
		*input.Status = strings.ToLower(strings.TrimSpace(*input.Status))
		if *input.Status != "pending" && *input.Status != "approved" && *input.Status != "rejected" && *input.Status != "inactive" {
			writeError(w, 400, "VALIDATION_ERROR", "Mapping status is invalid.")
			return
		}
	}
	if input.InventoryMode != nil {
		*input.InventoryMode = strings.ToLower(strings.TrimSpace(*input.InventoryMode))
		if *input.InventoryMode != "finite" && *input.InventoryMode != "untracked" && *input.InventoryMode != "capacity" {
			writeError(w, 400, "VALIDATION_ERROR", "Inventory mode is invalid.")
			return
		}
	}
	if input.AvailableQuantity != nil && *input.AvailableQuantity < 0 || input.CapacityPerDay != nil && *input.CapacityPerDay < 0 || input.PreparationMinutes != nil && (*input.PreparationMinutes < 0 || *input.PreparationMinutes > 1440) || input.SupplyPriceMinor != nil && *input.SupplyPriceMinor < 0 {
		writeError(w, 400, "VALIDATION_ERROR", "Mapping quantity, preparation time, or supply price is invalid.")
		return
	}
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var businessID, mode string
		var quantity, capacity sql.NullInt64
		if err := tx.QueryRowxContext(r.Context(), `SELECT business_id::text,inventory_mode,available_quantity,capacity_per_day FROM platform_partner_product_mappings WHERE id=$1 FOR UPDATE`, id).Scan(&businessID, &mode, &quantity, &capacity); err != nil {
			return err
		}
		newMode := mode
		if input.InventoryMode != nil {
			newMode = *input.InventoryMode
		}
		newQty := quantity
		newCapacity := capacity
		if input.InventoryMode != nil {
			newQty = sql.NullInt64{}
			newCapacity = sql.NullInt64{}
		}
		if input.AvailableQuantity != nil {
			newQty = sql.NullInt64{Int64: int64(*input.AvailableQuantity), Valid: true}
		}
		if input.CapacityPerDay != nil {
			newCapacity = sql.NullInt64{Int64: int64(*input.CapacityPerDay), Valid: true}
		}
		if newMode == "finite" && (!newQty.Valid || newCapacity.Valid) || newMode == "capacity" && (newQty.Valid || !newCapacity.Valid) || newMode == "untracked" && (newQty.Valid || newCapacity.Valid) {
			return errInvalidMappingInventory
		}
		if input.Status != nil && *input.Status == "approved" {
			var eligible bool
			if err := tx.GetContext(r.Context(), &eligible, `SELECT b.status='approved' AND b.verification_status='verified' AND p.status='active' AND c.is_active AND v.is_active AND EXISTS(SELECT 1 FROM platform_partner_coverage_areas ca WHERE ca.business_id=b.id AND ca.is_active AND EXISTS(SELECT 1 FROM platform_catalog_product_areas pa WHERE pa.product_id=p.id AND pa.is_active AND pa.city=ca.city AND (ca.locality IS NULL OR pa.locality IS NULL OR lower(ca.locality)=lower(pa.locality)))) FROM platform_partner_product_mappings m JOIN businesses b ON b.id=m.business_id JOIN platform_catalog_variants v ON v.id=m.variant_id JOIN platform_catalog_products p ON p.id=v.product_id JOIN platform_catalog_categories c ON c.id=p.category_id WHERE m.id=$1`, id); err != nil {
				return err
			}
			if !eligible {
				return errMappingNotEligible
			}
		}
		_, err := tx.ExecContext(r.Context(), `UPDATE platform_partner_product_mappings SET status=COALESCE($2,status),inventory_mode=$3,available_quantity=$4,capacity_per_day=$5,preparation_minutes=COALESCE($6,preparation_minutes),supply_price_minor=COALESCE($7,supply_price_minor),updated_by=$8,approved_by=CASE WHEN $2='approved' THEN $8 WHEN $2 IS NOT NULL THEN NULL ELSE approved_by END,approved_at=CASE WHEN $2='approved' THEN now() WHEN $2 IS NOT NULL THEN NULL ELSE approved_at END,updated_at=now() WHERE id=$1`, id, input.Status, newMode, nullInt(newQty), nullInt(newCapacity), input.PreparationMinutes, input.SupplyPriceMinor, actorID)
		if err != nil {
			return err
		}
		return s.logAudit(r.Context(), tx, actorID, "platform_catalog.partner_mapping.update", "platform_partner_product_mapping", id)
	})
	if errors.Is(err, errInvalidMappingInventory) {
		writeError(w, 400, "INVALID_INVENTORY_STATE", "Inventory mode and quantity/capacity values do not match.")
		return
	}
	if errors.Is(err, errMappingNotEligible) {
		writeError(w, 409, "PARTNER_NOT_ELIGIBLE", "Partner, product, variant, or coverage must be approved and active before mapping approval.")
		return
	}
	if err != nil {
		responseFailure(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func nullInt(value sql.NullInt64) any {
	if value.Valid {
		return value.Int64
	}
	return nil
}

var errInvalidMappingInventory = errors.New("invalid mapping inventory state")
var errMappingNotEligible = errors.New("partner mapping cannot be approved")

type coverageInput struct {
	City     string  `json:"city"`
	Locality *string `json:"locality"`
}

func (s *Service) adminListCoverage(w http.ResponseWriter, r *http.Request, _ string) {
	businessID := r.PathValue("businessId")
	if !validateUUID(businessID) {
		writeError(w, 400, "INVALID_ID", "Business ID is invalid.")
		return
	}
	rows, err := s.db.QueryContext(r.Context(), `SELECT id::text,city,locality,is_active,created_at::text FROM platform_partner_coverage_areas WHERE business_id=$1 ORDER BY city,locality`, businessID)
	if err != nil {
		responseFailure(w, err)
		return
	}
	defer rows.Close()
	items := make([]map[string]any, 0)
	for rows.Next() {
		var id, city, created string
		var locality sql.NullString
		var active bool
		if err := rows.Scan(&id, &city, &locality, &active, &created); err != nil {
			responseFailure(w, err)
			return
		}
		item := map[string]any{"id": id, "city": city, "is_active": active, "created_at": created}
		if locality.Valid {
			item["locality"] = locality.String
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		responseFailure(w, err)
		return
	}
	writeJSON(w, 200, apiEnvelope{Data: items, Meta: map[string]any{"count": len(items)}})
}

func (s *Service) adminAddCoverage(w http.ResponseWriter, r *http.Request, actorID string) {
	businessID := r.PathValue("businessId")
	if !validateUUID(businessID) {
		writeError(w, 400, "INVALID_ID", "Business ID is invalid.")
		return
	}
	var input coverageInput
	if !decodeJSON(w, r, &input) {
		return
	}
	city, ok := normalizeCity(input.City)
	if !ok {
		writeError(w, 400, "VALIDATION_ERROR", "Coverage city must be Cuttack or Jajpur.")
		return
	}
	if input.Locality != nil {
		value := strings.TrimSpace(*input.Locality)
		if value == "" || len(value) > 100 {
			writeError(w, 400, "VALIDATION_ERROR", "Coverage locality is invalid.")
			return
		}
		input.Locality = &value
	}
	var id string
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var exists bool
		if err := tx.GetContext(r.Context(), &exists, `SELECT EXISTS(SELECT 1 FROM businesses WHERE id=$1)`, businessID); err != nil {
			return err
		}
		if !exists {
			return sql.ErrNoRows
		}
		if err := tx.GetContext(r.Context(), &id, `INSERT INTO platform_partner_coverage_areas(business_id,city,locality,created_by,updated_by) VALUES($1,$2,$3,$4,$4) RETURNING id::text`, businessID, city, input.Locality, actorID); err != nil {
			return err
		}
		return s.logAudit(r.Context(), tx, actorID, "platform_catalog.partner_coverage.create", "platform_partner_coverage_area", id)
	})
	if err != nil {
		if isUniqueViolation(err) {
			writeError(w, 409, "COVERAGE_EXISTS", "This partner coverage area already exists.")
			return
		}
		responseFailure(w, err)
		return
	}
	writeJSON(w, 201, apiEnvelope{Data: map[string]string{"id": id}})
}

func (s *Service) adminDeleteCoverage(w http.ResponseWriter, r *http.Request, actorID string) {
	id := r.PathValue("coverageId")
	businessID := r.PathValue("businessId")
	if !validateUUID(id) || !validateUUID(businessID) {
		writeError(w, 400, "INVALID_ID", "Coverage or business ID is invalid.")
		return
	}
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		result, err := tx.ExecContext(r.Context(), `UPDATE platform_partner_coverage_areas SET is_active=false,updated_by=$3,updated_at=now() WHERE id=$1 AND business_id=$2`, id, businessID, actorID)
		if err != nil {
			return err
		}
		count, _ := result.RowsAffected()
		if count == 0 {
			return sql.ErrNoRows
		}
		return s.logAudit(r.Context(), tx, actorID, "platform_catalog.partner_coverage.deactivate", "platform_partner_coverage_area", id)
	})
	if err != nil {
		responseFailure(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Service) merchantCapabilities(w http.ResponseWriter, r *http.Request, userID string) {
	businessID := r.PathValue("id")
	if !validateUUID(businessID) {
		writeError(w, 400, "INVALID_ID", "Business ID is invalid.")
		return
	}
	var member bool
	err := s.db.GetContext(r.Context(), &member, `SELECT EXISTS(SELECT 1 FROM businesses b WHERE b.id=$1 AND (b.owner_user_id=$2 OR EXISTS(SELECT 1 FROM business_members m WHERE m.business_id=b.id AND m.user_id=$2 AND m.status='active')))`, businessID, userID)
	if err != nil {
		responseFailure(w, err)
		return
	}
	if !member {
		writeError(w, 403, "FORBIDDEN", "Active membership in this business is required.")
		return
	}
	rows, err := s.db.QueryContext(r.Context(), `SELECT m.id::text,m.variant_id::text,p.id::text,p.name,v.name,v.unit_label,v.price_minor,v.currency,v.price_revision,c.vertical,m.status,m.inventory_mode,m.available_quantity,m.capacity_per_day,m.preparation_minutes FROM platform_partner_product_mappings m JOIN platform_catalog_variants v ON v.id=m.variant_id JOIN platform_catalog_products p ON p.id=v.product_id JOIN platform_catalog_categories c ON c.id=p.category_id WHERE m.business_id=$1 ORDER BY m.status,p.name,v.name`, businessID)
	if err != nil {
		responseFailure(w, err)
		return
	}
	defer rows.Close()
	type capability struct {
		MappingID          string `json:"mapping_id"`
		VariantID          string `json:"variant_id"`
		ProductID          string `json:"product_id"`
		ProductName        string `json:"product_name"`
		VariantName        string `json:"variant_name"`
		UnitLabel          string `json:"unit_label"`
		SellingPriceMinor  int64  `json:"selling_price_minor"`
		Currency           string `json:"currency"`
		PriceRevision      int    `json:"price_revision"`
		Vertical           string `json:"vertical"`
		Status             string `json:"status"`
		InventoryMode      string `json:"inventory_mode"`
		AvailableQuantity  *int64 `json:"available_quantity,omitempty"`
		CapacityPerDay     *int64 `json:"capacity_per_day,omitempty"`
		PreparationMinutes *int64 `json:"preparation_minutes,omitempty"`
	}
	items := make([]capability, 0)
	for rows.Next() {
		var item capability
		var qty, capacity, prep sql.NullInt64
		if err := rows.Scan(&item.MappingID, &item.VariantID, &item.ProductID, &item.ProductName, &item.VariantName, &item.UnitLabel, &item.SellingPriceMinor, &item.Currency, &item.PriceRevision, &item.Vertical, &item.Status, &item.InventoryMode, &qty, &capacity, &prep); err != nil {
			responseFailure(w, err)
			return
		}
		if qty.Valid {
			item.AvailableQuantity = &qty.Int64
		}
		if capacity.Valid {
			item.CapacityPerDay = &capacity.Int64
		}
		if prep.Valid {
			item.PreparationMinutes = &prep.Int64
		}
		item.Currency = strings.TrimSpace(item.Currency)
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		responseFailure(w, err)
		return
	}
	writeJSON(w, 200, apiEnvelope{Data: items, Meta: map[string]any{"count": len(items)}})
}

func (s *Service) adminDeleteProduct(w http.ResponseWriter, r *http.Request, actorID string) {
	id := r.PathValue("id")
	if !validateUUID(id) {
		writeError(w, 400, "INVALID_ID", "Product ID is invalid.")
		return
	}
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		result, err := tx.ExecContext(r.Context(), `UPDATE platform_catalog_products SET status='inactive',updated_by=$2,updated_at=now() WHERE id=$1 AND status<>'inactive'`, id, actorID)
		if err != nil {
			return err
		}
		count, _ := result.RowsAffected()
		if count == 0 {
			var exists bool
			if e := tx.GetContext(r.Context(), &exists, `SELECT EXISTS(SELECT 1 FROM platform_catalog_products WHERE id=$1)`, id); e != nil {
				return e
			}
			if !exists {
				return sql.ErrNoRows
			}
			return nil
		}
		return s.logAudit(r.Context(), tx, actorID, "platform_catalog.product.deactivate", "platform_catalog_product", id)
	})
	if err != nil {
		responseFailure(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Service) getAdminProduct(w http.ResponseWriter, r *http.Request, _ string) {
	id := r.PathValue("id")
	if !validateUUID(id) {
		writeError(w, 400, "INVALID_ID", "Product ID is invalid.")
		return
	}
	item, err := scanProduct(s.db.QueryRowxContext(r.Context(), productSelect+` WHERE p.id=$2`, true, id))
	if err != nil {
		responseFailure(w, err)
		return
	}
	writeJSON(w, 200, apiEnvelope{Data: item})
}

func (s *Service) AdminListCategories(w http.ResponseWriter, r *http.Request, id string) {
	s.adminListCategories(w, r, id)
}
func (s *Service) AdminCreateCategory(w http.ResponseWriter, r *http.Request, id string) {
	s.adminCreateCategory(w, r, id)
}
func (s *Service) AdminUpdateCategory(w http.ResponseWriter, r *http.Request, id string) {
	s.adminUpdateCategory(w, r, id)
}
func (s *Service) AdminListProducts(w http.ResponseWriter, r *http.Request, id string) {
	s.adminListProducts(w, r, id)
}
func (s *Service) AdminCreateProduct(w http.ResponseWriter, r *http.Request, id string) {
	s.adminCreateProduct(w, r, id)
}
func (s *Service) AdminUpdateProduct(w http.ResponseWriter, r *http.Request, id string) {
	s.adminUpdateProduct(w, r, id)
}
func (s *Service) AdminDeleteProduct(w http.ResponseWriter, r *http.Request, id string) {
	s.adminDeleteProduct(w, r, id)
}
func (s *Service) AdminGetProduct(w http.ResponseWriter, r *http.Request, id string) {
	s.getAdminProduct(w, r, id)
}
func (s *Service) AdminCreateVariant(w http.ResponseWriter, r *http.Request, id string) {
	s.adminCreateVariant(w, r, id)
}
func (s *Service) AdminUpdateVariant(w http.ResponseWriter, r *http.Request, id string) {
	s.adminUpdateVariant(w, r, id)
}
func (s *Service) AdminListMappings(w http.ResponseWriter, r *http.Request, id string) {
	s.adminListMappings(w, r, id)
}
func (s *Service) AdminCreateMapping(w http.ResponseWriter, r *http.Request, id string) {
	s.adminCreateMapping(w, r, id)
}
func (s *Service) AdminUpdateMapping(w http.ResponseWriter, r *http.Request, id string) {
	s.adminUpdateMapping(w, r, id)
}
func (s *Service) AdminListCoverage(w http.ResponseWriter, r *http.Request, id string) {
	s.adminListCoverage(w, r, id)
}
func (s *Service) AdminAddCoverage(w http.ResponseWriter, r *http.Request, id string) {
	s.adminAddCoverage(w, r, id)
}
func (s *Service) AdminDeleteCoverage(w http.ResponseWriter, r *http.Request, id string) {
	s.adminDeleteCoverage(w, r, id)
}
func (s *Service) MerchantCapabilities(w http.ResponseWriter, r *http.Request, id string) {
	s.merchantCapabilities(w, r, id)
}
