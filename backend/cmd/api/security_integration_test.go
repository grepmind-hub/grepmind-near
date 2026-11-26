package main

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"fmt"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v4"
	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
	"grepmind-near/backend/internal/auth"
	"grepmind-near/backend/internal/deliverydispatch"
	"grepmind-near/backend/internal/discovery"
	"grepmind-near/backend/internal/media"
	"grepmind-near/backend/internal/merchantanalytics"
	"grepmind-near/backend/internal/moderation"
	"grepmind-near/backend/internal/notifications"
	"grepmind-near/backend/internal/operations"
	"grepmind-near/backend/internal/platformcommerce"
	"grepmind-near/backend/pkg/config"
	"grepmind-near/backend/pkg/database"
	"grepmind-near/backend/pkg/logger"
)

func TestCatalogInputValidation(t *testing.T) {
	price := 12.5
	negative := -1.0
	for _, tc := range []struct {
		label string
		name  string
		price *float64
		stock string
		valid bool
	}{
		{"valid", " Product ", &price, "in_stock", true},
		{"no price", "Product", nil, "unknown", true},
		{"negative price", "Product", &negative, "in_stock", false},
		{"invalid stock", "Product", &price, "available-ish", false},
		{"blank name", " ", &price, "in_stock", false},
	} {
		t.Run(tc.label, func(t *testing.T) {
			if got := validProductInput(tc.name, tc.price, tc.stock); got != tc.valid {
				t.Fatalf("valid=%v, want %v", got, tc.valid)
			}
		})
	}
	for _, tc := range []struct {
		value string
		valid bool
	}{{"09:00", true}, {"23:59:59", true}, {"24:00", false}, {"9:00", false}, {"not-a-time", false}} {
		if got := validBusinessTime(tc.value); got != tc.valid {
			t.Errorf("validBusinessTime(%q)=%v, want %v", tc.value, got, tc.valid)
		}
	}
}

func TestMerchantCatalogPricingFlow(t *testing.T) {
	db, ownerID, _, _, _, _, _, _, _, _, _ := newAPISecurityFixture(t)

	admit := func(method, id, body string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, "/api/v1/merchant/products", strings.NewReader(body))
		r.SetPathValue("id", id)
		w := httptest.NewRecorder()
		switch method {
		case http.MethodPost:
			merchantCreateProduct(nil, db, w, r, ownerID)
		case http.MethodPatch:
			merchantUpdateProduct(nil, db, w, r, ownerID)
		case http.MethodGet:
			merchantListProducts(nil, db, w, r, ownerID)
		}
		return w
	}

	w := admit(http.MethodPost, "", `{"name":"Catalog item","price":100.25,"mrp":125,"unit_label":"750 g","gst_rate_bps":1800}`)
	var created struct {
		Data struct{ ID string } `json:"data"`
	}
	if w.Code != http.StatusCreated || json.Unmarshal(w.Body.Bytes(), &created) != nil || created.Data.ID == "" {
		t.Fatalf("create catalog item: %d %s", w.Code, w.Body.String())
	}
	w = admit(http.MethodGet, "", "")
	for _, value := range []string{`"supports_catalog_gst":true`, `"gst_rate_bps":1800`, `"unit_label":"750 g"`, `"price":100.25`, `"mrp":125`} {
		if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), value) {
			t.Fatalf("catalog missing %s: %d %s", value, w.Code, w.Body.String())
		}
	}
	if w = admit(http.MethodPatch, created.Data.ID, `{"gst_rate_bps":10001}`); w.Code != http.StatusBadRequest {
		t.Fatalf("invalid GST rate: %d %s", w.Code, w.Body.String())
	}
	if w = admit(http.MethodPatch, created.Data.ID, `{"mrp":null,"gst_rate_bps":null,"inventory_mode":"finite","available_quantity":2,"stock_status":"limited"}`); w.Code != http.StatusOK {
		t.Fatalf("clear optional values and update stock: %d %s", w.Code, w.Body.String())
	}
	w = admit(http.MethodGet, "", "")
	if w.Code != http.StatusOK || strings.Contains(w.Body.String(), "gst_rate_bps") || strings.Contains(w.Body.String(), `"mrp"`) ||
		!strings.Contains(w.Body.String(), `"stock_status":"limited"`) || !strings.Contains(w.Body.String(), `"available_quantity":2`) {
		t.Fatalf("catalog after edit: %d %s", w.Code, w.Body.String())
	}
}

func TestOwnershipAndTenantRoutes(t *testing.T) {
	logger.Init("error")
	db, ownerA, memberA, customerA, customerB, businessA, businessB, productB, requestB, notificationB, orderB := newAPISecurityFixture(t)
	cfg := &config.Config{Env: "test", JWTSecret: "integration-test-secret-with-over-32-characters"}
	authSvc := auth.NewService(db, cfg)
	router := setupRouter(authSvc, discovery.NewService(db, cfg), moderation.NewService(db, cfg), nil, notifications.NewHub(db.DB), operations.NewService(db), platformcommerce.NewService(db))
	token := func(subject string) string {
		t.Helper()
		tok, err := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.RegisteredClaims{
			Subject: subject, Issuer: "grepmind-near", IssuedAt: jwt.NewNumericDate(time.Now()),
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour)),
		}).SignedString([]byte(cfg.JWTSecret))
		if err != nil {
			t.Fatal(err)
		}
		return tok
	}
	request := func(method, path, bearer, body string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, path, strings.NewReader(body))
		if bearer != "" {
			r.Header.Set("Authorization", "Bearer "+bearer)
		}
		w := httptest.NewRecorder()
		router.ServeHTTP(w, r)
		return w
	}
	requestWithIdempotency := func(path, bearer, key, body string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(http.MethodPost, path, strings.NewReader(body))
		r.Header.Set("Authorization", "Bearer "+bearer)
		r.Header.Set("Idempotency-Key", key)
		w := httptest.NewRecorder()
		router.ServeHTTP(w, r)
		return w
	}
	var w *httptest.ResponseRecorder

	// Platform catalog is a separate admin-owned domain. Public clients receive
	// only active products and their selling prices; partner costs stay private.
	adminID := uuid.NewString()
	if _, err := db.Exec(`INSERT INTO users(id,phone_e164) VALUES($1,$2)`, adminID, "+919900000001"); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO user_roles(user_id,role) VALUES($1,'admin')`, adminID); err != nil {
		t.Fatal(err)
	}
	foodCategoryID := ""
	if err := db.Get(&foodCategoryID, `SELECT id::text FROM platform_catalog_categories WHERE vertical='food' AND is_system`); err != nil {
		t.Fatal(err)
	}
	adminCatalogPath := "/api/v1/admin/catalog/products"
	productBody := `{"sku":"TEST-RICE","category_id":"` + foodCategoryID + `","name":"Test rice","description":"A catalog test product","image_urls":["/media/catalog/rice.png","https://cdn.example.test/rice-detail.png"],"status":"draft","areas":[{"city":"Cuttack"}],"variants":[{"sku":"TEST-RICE-1KG","name":"1 kg","unit_label":"1 kg","price_minor":12500,"currency":"INR"}]}`
	if w = request(http.MethodPost, adminCatalogPath, "", productBody); w.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous platform product write status=%d, want 401", w.Code)
	}
	if w = request(http.MethodPost, adminCatalogPath, token(customerA), productBody); w.Code != http.StatusForbidden {
		t.Fatalf("customer platform product write status=%d, want 403", w.Code)
	}
	if w = request(http.MethodPost, adminCatalogPath, token(ownerA), productBody); w.Code != http.StatusForbidden {
		t.Fatalf("merchant platform product write status=%d, want 403", w.Code)
	}
	w = request(http.MethodPost, adminCatalogPath, token(adminID), productBody)
	if w.Code != http.StatusCreated {
		t.Fatalf("admin platform product create status=%d body=%s", w.Code, w.Body.String())
	}
	var platformProductCreated struct {
		Data map[string]string `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &platformProductCreated); err != nil {
		t.Fatal(err)
	}
	platformProductID := platformProductCreated.Data["id"]
	platformVariantID := ""
	if err := db.Get(&platformVariantID, `SELECT id::text FROM platform_catalog_variants WHERE product_id=$1`, platformProductID); err != nil {
		t.Fatal(err)
	}
	if w = request(http.MethodPatch, "/api/v1/admin/catalog/variants/"+platformVariantID, token(ownerA), `{"price_minor":1}`); w.Code != http.StatusForbidden {
		t.Fatalf("merchant selling-price mutation status=%d, want 403: %s", w.Code, w.Body.String())
	}
	if w = request(http.MethodPatch, adminCatalogPath+"/"+platformProductID, token(adminID), `{"status":"active"}`); w.Code != http.StatusNoContent {
		t.Fatalf("activate platform product status=%d body=%s", w.Code, w.Body.String())
	}
	w = request(http.MethodGet, "/api/v1/catalog/products?vertical=food&city=Cuttack", "", "")
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), platformProductID) || !strings.Contains(w.Body.String(), "/media/catalog/rice.png") || !strings.Contains(w.Body.String(), "https://cdn.example.test/rice-detail.png") || strings.Contains(w.Body.String(), "supply_price_minor") {
		t.Fatalf("public catalog should list active product without partner cost: status=%d body=%s", w.Code, w.Body.String())
	}
	// Omitted image_urls must persist as the schema's empty array, not SQL NULL.
	defaultImagesBody := `{"sku":"TEST-NO-IMAGES","category_id":"` + foodCategoryID + `","name":"No image array","areas":[{"city":"Jajpur"}],"variants":[{"sku":"TEST-NO-IMAGES-UNIT","name":"Each","unit_label":"each","price_minor":100,"currency":"INR"}]}`
	w = request(http.MethodPost, adminCatalogPath, token(adminID), defaultImagesBody)
	if w.Code != http.StatusCreated {
		t.Fatalf("product create with omitted image_urls status=%d body=%s", w.Code, w.Body.String())
	}
	var noImagesCreated struct {
		Data map[string]string `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &noImagesCreated); err != nil {
		t.Fatal(err)
	}
	w = request(http.MethodGet, adminCatalogPath+"/"+noImagesCreated.Data["id"], token(adminID), "")
	var noImagesRead struct {
		Data struct {
			ImageURLs []string `json:"image_urls"`
		} `json:"data"`
	}
	if w.Code != http.StatusOK || json.Unmarshal(w.Body.Bytes(), &noImagesRead) != nil || noImagesRead.Data.ImageURLs == nil || len(noImagesRead.Data.ImageURLs) != 0 {
		t.Fatalf("omitted image_urls should return an empty array: status=%d body=%s", w.Code, w.Body.String())
	}
	nullImagesBody := strings.ReplaceAll(defaultImagesBody, "TEST-NO-IMAGES", "TEST-NULL-IMAGES")
	nullImagesBody = strings.Replace(nullImagesBody, `"areas":`, `"image_urls":null,"areas":`, 1)
	w = request(http.MethodPost, adminCatalogPath, token(adminID), nullImagesBody)
	if w.Code != http.StatusCreated {
		t.Fatalf("product create with null image_urls status=%d body=%s", w.Code, w.Body.String())
	}
	if err := json.Unmarshal(w.Body.Bytes(), &noImagesCreated); err != nil {
		t.Fatal(err)
	}
	w = request(http.MethodGet, adminCatalogPath+"/"+noImagesCreated.Data["id"], token(adminID), "")
	if w.Code != http.StatusOK || json.Unmarshal(w.Body.Bytes(), &noImagesRead) != nil || noImagesRead.Data.ImageURLs == nil || len(noImagesRead.Data.ImageURLs) != 0 {
		t.Fatalf("null image_urls should normalize to an empty array: status=%d body=%s", w.Code, w.Body.String())
	}
	w = request(http.MethodGet, "/api/v1/catalog/products?vertical=food&city=Jajpur", "", "")
	if w.Code != http.StatusOK || strings.Contains(w.Body.String(), platformProductID) {
		t.Fatalf("public catalog leaked a product outside its city: status=%d body=%s", w.Code, w.Body.String())
	}
	if w = request(http.MethodPost, "/api/v1/admin/catalog/partners/"+businessA+"/coverage", token(adminID), `{"city":"Cuttack"}`); w.Code != http.StatusCreated {
		t.Fatalf("partner coverage create status=%d body=%s", w.Code, w.Body.String())
	}
	mappingBody := `{"business_id":"` + businessA + `","variant_id":"` + platformVariantID + `","inventory_mode":"finite","available_quantity":7,"supply_price_minor":8000}`
	w = request(http.MethodPost, "/api/v1/admin/catalog/partner-mappings", token(adminID), mappingBody)
	if w.Code != http.StatusCreated {
		t.Fatalf("partner mapping create status=%d body=%s", w.Code, w.Body.String())
	}
	var mappingCreated struct {
		Data map[string]string `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &mappingCreated); err != nil {
		t.Fatal(err)
	}
	mappingID := mappingCreated.Data["id"]
	if w = request(http.MethodPatch, "/api/v1/admin/catalog/partner-mappings/"+mappingID, token(adminID), `{"status":"approved"}`); w.Code != http.StatusNoContent {
		t.Fatalf("eligible partner mapping approval status=%d body=%s", w.Code, w.Body.String())
	}
	capabilityPath := "/api/v1/merchant/businesses/" + businessA + "/catalog-capabilities"
	if w = request(http.MethodGet, capabilityPath, token(memberA), ""); w.Code != http.StatusOK || strings.Contains(w.Body.String(), "supply_price_minor") {
		t.Fatalf("merchant capability view status=%d leaked private supply price: %s", w.Code, w.Body.String())
	}
	if w = request(http.MethodGet, "/api/v1/merchant/businesses/"+businessB+"/catalog-capabilities", token(memberA), ""); w.Code != http.StatusForbidden {
		t.Fatalf("cross-business catalog capability status=%d, want 403: %s", w.Code, w.Body.String())
	}
	var catalogAuditCount int
	if err := db.Get(&catalogAuditCount, `SELECT count(*) FROM audit_logs WHERE actor_user_id=$1 AND action LIKE 'platform_catalog.%'`, adminID); err != nil || catalogAuditCount < 3 {
		t.Fatalf("catalog mutations were not audited: count=%d err=%v", catalogAuditCount, err)
	}

	// View metrics count authenticated customer interest once per UTC day and
	// remain isolated to the merchant's own business.
	analyticsProductID := uuid.NewString()
	if _, err := db.Exec(`INSERT INTO products(id,business_id,name,stock_status,is_published) VALUES($1,$2,'Published analytics product','in_stock',true)`, analyticsProductID, businessA); err != nil {
		t.Fatal(err)
	}
	viewPath := "/api/v1/analytics/businesses/" + businessA + "/views"
	if w = request(http.MethodPost, viewPath, "", `{"view_type":"profile"}`); w.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous view status=%d, want 401", w.Code)
	}
	for _, viewType := range []string{merchantanalytics.ViewProfile, merchantanalytics.ViewProfile, merchantanalytics.ViewCatalog, merchantanalytics.ViewCatalog} {
		w = request(http.MethodPost, viewPath, token(customerA), `{"view_type":"`+viewType+`"}`)
		if w.Code != http.StatusNoContent {
			t.Fatalf("customer %s view status=%d body=%s", viewType, w.Code, w.Body.String())
		}
	}
	if w = request(http.MethodPost, "/api/v1/analytics/businesses/"+businessB+"/views", token(customerA), `{"view_type":"catalog"}`); w.Code != http.StatusNotFound {
		t.Fatalf("empty catalog view status=%d, want 404", w.Code)
	}
	if w = request(http.MethodPost, viewPath, token(ownerA), `{"view_type":"profile"}`); w.Code != http.StatusForbidden {
		t.Fatalf("merchant view status=%d, want 403", w.Code)
	}
	if w = request(http.MethodPost, "/api/v1/analytics/businesses/"+businessB+"/views", token(customerB), `{"view_type":"profile"}`); w.Code != http.StatusForbidden {
		t.Fatalf("own business view status=%d, want 403", w.Code)
	}
	if w = request(http.MethodPost, viewPath, token(customerA), `{"view_type":"invalid"}`); w.Code != http.StatusBadRequest {
		t.Fatalf("invalid view type status=%d, want 400", w.Code)
	}
	if w = request(http.MethodGet, "/api/v1/merchant/analytics/summary?business_id="+businessB, token(memberA), ""); w.Code != http.StatusForbidden {
		t.Fatalf("cross-business view analytics status=%d, want 403", w.Code)
	}
	w = request(http.MethodGet, "/api/v1/merchant/analytics/summary?business_id="+businessA, token(ownerA), "")
	if w.Code != http.StatusOK {
		t.Fatalf("merchant analytics summary status=%d body=%s", w.Code, w.Body.String())
	}
	var analyticsResponse struct {
		Data map[string]interface{} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &analyticsResponse); err != nil {
		t.Fatal(err)
	}
	if analyticsResponse.Data["profile_views_30d"] != float64(1) || analyticsResponse.Data["product_catalog_views_30d"] != float64(1) {
		t.Fatalf("daily dedupe/summary failed: %s", w.Body.String())
	}
	if _, err := db.Exec(`DELETE FROM products WHERE id=$1`, analyticsProductID); err != nil {
		t.Fatal(err)
	}

	// Merchant access resolves businesses from the authenticated owner/member
	// relationship and rejects explicit cross-business IDs.
	w = request(http.MethodGet, "/api/v1/merchant/businesses", token(memberA), "")
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), businessA) || strings.Contains(w.Body.String(), businessB) {
		t.Fatalf("merchant business directory was not tenant-scoped: %d %s", w.Code, w.Body.String())
	}

	// Public new-arrivals results include only current catalog records from
	// approved businesses in the selected supported city.
	publishedProductID, foreignPublishedProductID, inactiveProductID := uuid.NewString(), uuid.NewString(), uuid.NewString()
	publishedServiceID, foreignPublishedServiceID, inactiveServiceID := uuid.NewString(), uuid.NewString(), uuid.NewString()
	if _, err := db.Exec(`INSERT INTO products(id,business_id,name,is_published,stock_status,published_at) VALUES($1,$2,'Cuttack published item',true,'in_stock',now()),($3,$4,'Jajpur published item',true,'in_stock',now()),($5,$2,'Out of stock item',true,'out_of_stock',now())`, publishedProductID, businessA, foreignPublishedProductID, businessB, inactiveProductID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO services(id,business_id,name,is_active,activated_at) VALUES($1,$2,'Cuttack active service',true,now()),($3,$4,'Jajpur active service',true,now()),($5,$2,'Inactive service',false,NULL)`, publishedServiceID, businessA, foreignPublishedServiceID, businessB, inactiveServiceID); err != nil {
		t.Fatal(err)
	}
	w = request(http.MethodGet, "/api/v1/catalog/new-arrivals?city=Cuttack&type=all&limit=10", "", "")
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), publishedProductID) || !strings.Contains(w.Body.String(), publishedServiceID) || strings.Contains(w.Body.String(), businessB) || strings.Contains(w.Body.String(), inactiveProductID) {
		t.Fatalf("new catalog feed must be published and city scoped: status=%d response=%s", w.Code, w.Body.String())
	}
	w = request(http.MethodGet, "/api/v1/catalog/new-arrivals?city=Cuttack&type=services", "", "")
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), publishedServiceID) || strings.Contains(w.Body.String(), publishedProductID) {
		t.Fatalf("service filter failed: status=%d response=%s", w.Code, w.Body.String())
	}
	if _, err := db.Exec(`DELETE FROM products WHERE id IN ($1,$2,$3)`, publishedProductID, foreignPublishedProductID, inactiveProductID); err != nil {
		t.Fatalf("remove product feed fixtures from shared test schema: %v", err)
	}
	if _, err := db.Exec(`DELETE FROM services WHERE id IN ($1,$2,$3)`, publishedServiceID, foreignPublishedServiceID, inactiveServiceID); err != nil {
		t.Fatalf("remove feed fixtures from shared test schema: %v", err)
	}
	w = request(http.MethodGet, "/api/v1/merchant/profile?business_id="+businessA, token(memberA), "")
	if w.Code != http.StatusOK {
		t.Fatalf("member profile access status=%d body=%s", w.Code, w.Body.String())
	}
	var memberProfile struct {
		Data map[string]interface{} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &memberProfile); err != nil || memberProfile.Data["can_edit_profile"] != false {
		t.Fatalf("non-owner profile capability should be false: %s (%v)", w.Body.String(), err)
	}
	w = request(http.MethodPatch, "/api/v1/merchant/profile?business_id="+businessA, token(memberA), `{"name":"Unauthorized update"}`)
	if w.Code != http.StatusForbidden {
		t.Fatalf("non-owner profile update status=%d, want 403: %s", w.Code, w.Body.String())
	}
	w = request(http.MethodGet, "/api/v1/merchant/products?business_id="+businessB, token(memberA), "")
	if w.Code != http.StatusForbidden {
		t.Fatalf("cross-business catalog read status=%d, want 403: %s", w.Code, w.Body.String())
	}

	// A fresh authenticated customer can create a pending listing and receives
	// merchant role atomically; caller-supplied approval state is rejected.
	createBody := `{"name":"QA Merchant Fresh","description":"Local test listing","category_slug":"general","phone_e164":"+919876543219","whatsapp_e164":"+919876543219","address_text":"12 Test Road","locality":"Badambadi","city":"Cuttack","postal_code":"753001","latitude":20.46575,"longitude":85.879,"hours":[{"weekday":0,"is_closed":true},{"weekday":1,"is_closed":false,"opens_at":"09:00","closes_at":"18:00"},{"weekday":2,"is_closed":false,"opens_at":"09:00","closes_at":"18:00"},{"weekday":3,"is_closed":false,"opens_at":"09:00","closes_at":"18:00"},{"weekday":4,"is_closed":false,"opens_at":"09:00","closes_at":"18:00"},{"weekday":5,"is_closed":false,"opens_at":"09:00","closes_at":"18:00"},{"weekday":6,"is_closed":false,"opens_at":"09:00","closes_at":"18:00"}]}`
	w = request(http.MethodPost, "/api/v1/merchant/businesses", token(customerA), createBody)
	if w.Code != http.StatusCreated {
		t.Fatalf("create business status=%d body=%s", w.Code, w.Body.String())
	}
	var createdBusiness struct {
		Data struct {
			ID           string `json:"id"`
			Status       string `json:"status"`
			Verification string `json:"verification_status"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &createdBusiness); err != nil || createdBusiness.Data.ID == "" || createdBusiness.Data.Status != "pending" || createdBusiness.Data.Verification != "pending" {
		t.Fatalf("business create response=%s err=%v", w.Body.String(), err)
	}
	var merchantRole bool
	if err := db.Get(&merchantRole, `SELECT EXISTS(SELECT 1 FROM user_roles WHERE user_id=$1 AND role='merchant')`, customerA); err != nil || !merchantRole {
		t.Fatalf("merchant role not assigned transactionally: role=%v err=%v", merchantRole, err)
	}
	var ownerMembership string
	if err := db.Get(&ownerMembership, `SELECT role FROM business_members WHERE business_id=$1 AND user_id=$2 AND status='active'`, createdBusiness.Data.ID, customerA); err != nil || ownerMembership != "owner" {
		t.Fatalf("new business owner membership=%q err=%v", ownerMembership, err)
	}
	var savedHours int
	if err := db.Get(&savedHours, `SELECT count(*) FROM business_hours WHERE business_id=$1`, createdBusiness.Data.ID); err != nil || savedHours != 7 {
		t.Fatalf("business schedule rows=%d err=%v, want seven", savedHours, err)
	}
	var listingAuditEvents int
	if err := db.Get(&listingAuditEvents, `SELECT count(*) FROM audit_logs WHERE actor_user_id=$1 AND action='create_business' AND target_type='business' AND target_id=$2`, customerA, createdBusiness.Data.ID); err != nil || listingAuditEvents != 1 {
		t.Fatalf("listing creation audit events=%d err=%v, want exactly one actor-attributed event", listingAuditEvents, err)
	}
	w = request(http.MethodPost, "/api/v1/merchant/businesses", token(customerB), strings.Replace(createBody, `"city":"Cuttack"`, `"city":"Bhubaneswar"`, 1))
	if w.Code != http.StatusBadRequest {
		t.Errorf("unsupported city registration status=%d, want 400", w.Code)
	}

	// Profile edits are scoped to the authenticated user and persisted by PATCH /me.
	w = request(http.MethodPatch, "/api/v1/me", token(customerA), `{"display_name":"Customer A","preferred_language":"or","notification_preferences":{"booking_updates":false,"offers":true,"service_updates":false}}`)
	if w.Code != http.StatusOK {
		t.Errorf("update own profile status=%d: %s", w.Code, w.Body.String())
	} else {
		var profile struct {
			Data struct {
				DisplayName string          `json:"display_name"`
				Language    string          `json:"preferred_language"`
				Preferences map[string]bool `json:"notification_preferences"`
			} `json:"data"`
		}
		if err := json.Unmarshal(w.Body.Bytes(), &profile); err != nil || profile.Data.DisplayName != "Customer A" || profile.Data.Language != "or" || profile.Data.Preferences["booking_updates"] {
			t.Errorf("profile update was not returned/persisted: body=%s err=%v", w.Body.String(), err)
		}
	}
	w = request(http.MethodPatch, "/api/v1/me", token(customerA), `{"id":"`+customerB+`","status":"admin"}`)
	if w.Code != http.StatusBadRequest {
		t.Errorf("profile rejected-field status=%d, want 400", w.Code)
	}
	w = request(http.MethodPatch, "/api/v1/me", token(customerA), `{"preferred_language":"xx"}`)
	if w.Code != http.StatusBadRequest {
		t.Errorf("unsupported profile language status=%d, want 400", w.Code)
	}
	_, err := db.Exec(`INSERT INTO media_uploads(user_id,purpose,object_key) VALUES($1,'avatar','avatar/foreign.jpg')`, customerB)
	if err != nil {
		t.Fatalf("insert foreign avatar fixture: %v", err)
	}
	w = request(http.MethodPatch, "/api/v1/me", token(customerA), `{"avatar_url":"/media/avatar/foreign.jpg"}`)
	if w.Code != http.StatusBadRequest {
		t.Errorf("foreign avatar assignment status=%d, want 400", w.Code)
	}

	// Customers cannot read another customer's request, order or notification.
	for _, tc := range []struct {
		method, path, body string
		want               int
	}{
		{http.MethodGet, "/api/v1/requests/" + requestB, "", http.StatusForbidden},
		{http.MethodPost, "/api/v1/requests/" + requestB + "/cancel", "", http.StatusForbidden},
		{http.MethodGet, "/api/v1/orders/" + orderB, "", http.StatusNotFound},
		{http.MethodPost, "/api/v1/orders/" + orderB + "/cancel", "", http.StatusNotFound},
		{http.MethodGet, "/api/v1/notifications?user_id=" + customerB, "", http.StatusForbidden},
		{http.MethodGet, "/api/v1/events?user_id=" + customerB, "", http.StatusForbidden},
		{http.MethodGet, "/api/v1/events?request_id=" + requestB, "", http.StatusForbidden},
		{http.MethodGet, "/api/v1/events?order_id=" + orderB, "", http.StatusForbidden},
		{http.MethodGet, "/api/v1/events?order_id=" + orderB + "&user_id=" + customerA, "", http.StatusForbidden},
	} {
		w = request(tc.method, tc.path, token(customerA), tc.body)
		if w.Code != tc.want {
			t.Errorf("%s %s status=%d, want %d: %s", tc.method, tc.path, w.Code, tc.want, w.Body.String())
		}
	}
	ownedOrderEventRequest := httptest.NewRequest(http.MethodGet, "/api/v1/events?order_id="+orderB, nil)
	if !authorizeEventSubscription(ownedOrderEventRequest.Context(), db, ownedOrderEventRequest, customerB) {
		t.Error("customer was denied the order-scoped stream for their own order")
	}
	for _, path := range []string{"/api/v1/customer/orders", "/api/v1/customer/requests"} {
		w = request(http.MethodGet, path, token(customerA), "")
		if w.Code != http.StatusOK {
			t.Errorf("own list %s status=%d", path, w.Code)
		}
		var payload map[string]interface{}
		if err := json.Unmarshal(w.Body.Bytes(), &payload); err != nil {
			t.Errorf("decode %s: %v", path, err)
		}
		data, _ := payload["data"].(map[string]interface{})
		if path == "/api/v1/customer/orders" {
			items, _ := data["data"].([]interface{})
			if len(items) != 0 {
				t.Errorf("customer order list leaked %d foreign rows", len(items))
			}
		} else {
			items, _ := data["requests"].([]interface{})
			if len(items) != 0 {
				t.Errorf("customer request list leaked %d foreign rows", len(items))
			}
		}
	}
	w = request(http.MethodPost, "/api/v1/notifications/"+notificationB+"/read", token(customerA), "")
	if w.Code != http.StatusNotFound {
		t.Errorf("foreign notification mark-read status=%d, want 404", w.Code)
	}
	w = request(http.MethodPatch, "/api/v1/merchant/orders/"+orderB+"/status", token(ownerA), `{"status":"confirmed"}`)
	if w.Code != http.StatusForbidden {
		t.Errorf("cross-business order update status=%d, want 403", w.Code)
	}
	w = request(http.MethodPatch, "/api/v1/merchant/orders/"+orderB+"/status", token(customerB), `{"status":"completed"}`)
	if w.Code != http.StatusConflict {
		t.Errorf("invalid order transition status=%d, want 409", w.Code)
	}

	// Exact customer detail, paginated history, event timeline, support reporting,
	// and cancellation retries remain owner-scoped and side-effect safe.
	orderA, orderA2, productA := uuid.NewString(), uuid.NewString(), uuid.NewString()
	if _, err := db.Exec(`INSERT INTO products(id,business_id,name,price,inventory_mode,available_quantity,stock_status,is_published) VALUES($1,$2,'QA meal',12.50,'finite',3,'in_stock',true)`, productA, businessA); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,item_total,delivery_fee,tax_amount,grand_total,reference_code,created_at,updated_at) VALUES($1,$2,$3,'food_delivery','placed',25,0,0,25,'REF-A1',now(),now()),($4,$2,$3,'table_reservation','confirmed',0,0,0,0,'REF-A2',now()-interval '1 minute',now()-interval '1 minute')`, orderA, customerA, businessA, orderA2); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO customer_order_items(order_id,product_id,product_name,unit_price,quantity) VALUES($1,$2,'QA meal',12.50,2)`, orderA, productA); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO customer_order_status_events(order_id,status,actor_user_id) VALUES($1,'placed',$2),($3,'confirmed',$2)`, orderA, customerA, orderA2); err != nil {
		t.Fatal(err)
	}
	w = request(http.MethodGet, "/api/v1/orders/"+orderA, token(customerA), "")
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"status_events"`) {
		t.Errorf("exact owned order detail status=%d body=%s", w.Code, w.Body.String())
	}
	w = request(http.MethodGet, "/api/v1/orders/"+orderA, token(customerB), "")
	if w.Code != http.StatusNotFound {
		t.Errorf("other customer order detail status=%d, want 404", w.Code)
	}
	w = request(http.MethodPost, "/api/v1/orders/"+orderA+"/support", token(customerB), `{"reason":"This order is not mine"}`)
	if w.Code != http.StatusNotFound {
		t.Errorf("other customer support report status=%d, want 404", w.Code)
	}
	w = request(http.MethodPost, "/api/v1/orders/"+orderA+"/support", token(customerA), `{"reason":"The order details need review"}`)
	if w.Code != http.StatusCreated {
		t.Fatalf("order support report status=%d body=%s", w.Code, w.Body.String())
	}
	var firstReport, secondReport struct {
		Data struct {
			ReportID string `json:"report_id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &firstReport); err != nil {
		t.Fatal(err)
	}
	w = request(http.MethodPost, "/api/v1/orders/"+orderA+"/support", token(customerA), `{"reason":"Duplicate retry after timeout"}`)
	if w.Code != http.StatusCreated || json.Unmarshal(w.Body.Bytes(), &secondReport) != nil || secondReport.Data.ReportID != firstReport.Data.ReportID {
		t.Errorf("support retry did not return same open report: status=%d body=%s", w.Code, w.Body.String())
	}
	var reportCount int
	if err := db.Get(&reportCount, `SELECT count(*) FROM reports WHERE target_type='order' AND target_id=$1 AND reporter_user_id=$2`, orderA, customerA); err != nil || reportCount != 1 {
		t.Errorf("support retry reports=%d err=%v, want one", reportCount, err)
	}
	w = request(http.MethodGet, "/api/v1/customer/orders?limit=1", token(customerA), "")
	var pageOne struct {
		Data []map[string]interface{} `json:"data"`
		Meta struct {
			HasMore    bool   `json:"has_more"`
			NextCursor string `json:"next_cursor"`
		} `json:"meta"`
	}
	if w.Code != http.StatusOK || json.Unmarshal(w.Body.Bytes(), &pageOne) != nil || len(pageOne.Data) != 1 || !pageOne.Meta.HasMore || pageOne.Meta.NextCursor == "" {
		t.Fatalf("first order page status=%d body=%s", w.Code, w.Body.String())
	}
	w = request(http.MethodGet, "/api/v1/customer/orders?limit=1&before="+url.QueryEscape(pageOne.Meta.NextCursor), token(customerA), "")
	var pageTwo struct {
		Data []map[string]interface{} `json:"data"`
	}
	if w.Code != http.StatusOK || json.Unmarshal(w.Body.Bytes(), &pageTwo) != nil || len(pageTwo.Data) != 1 || pageTwo.Data[0]["id"] == pageOne.Data[0]["id"] {
		t.Errorf("second order page duplicated or failed: status=%d body=%s", w.Code, w.Body.String())
	}
	for i := 0; i < 2; i++ {
		w = request(http.MethodPost, "/api/v1/orders/"+orderA+"/cancel", token(customerA), "")
		if w.Code != http.StatusOK {
			t.Errorf("cancellation attempt %d status=%d body=%s", i+1, w.Code, w.Body.String())
		}
	}
	var available, cancelledEvents int
	if err := db.Get(&available, `SELECT available_quantity FROM products WHERE id=$1`, productA); err != nil || available != 5 {
		t.Errorf("cancel retry stock=%d err=%v, want 5 (restored once)", available, err)
	}
	if err := db.Get(&cancelledEvents, `SELECT count(*) FROM customer_order_status_events WHERE order_id=$1 AND status='cancelled'`, orderA); err != nil || cancelledEvents != 1 {
		t.Errorf("cancel events=%d err=%v, want one", cancelledEvents, err)
	}
	w = request(http.MethodPatch, "/api/v1/merchant/orders/"+orderA2+"/status", token(ownerA), `{"status":"completed"}`)
	if w.Code != http.StatusOK {
		t.Errorf("authorized merchant status update=%d body=%s", w.Code, w.Body.String())
	}
	var orderNotifications int
	if err := db.Get(&orderNotifications, `SELECT count(*) FROM notifications WHERE user_id=$1 AND event_type='order.status'`, customerA); err != nil || orderNotifications == 0 {
		t.Errorf("customer order status notifications=%d err=%v", orderNotifications, err)
	}

	// Membership is scoped to one business, including event and notification subscriptions.
	for _, path := range []string{
		"/api/v1/notifications?business_id=" + businessB,
		"/api/v1/events?business_id=" + businessB,
		"/api/v1/events?business_id=" + businessA + "&request_id=" + requestB,
	} {
		w := request(http.MethodGet, path, token(memberA), "")
		if w.Code != http.StatusForbidden {
			t.Errorf("cross-business subscription %s status=%d, want 403", path, w.Code)
		}
	}
	// A member of A cannot mutate a product owned by B.
	for _, tc := range []struct{ method, body string }{{http.MethodPatch, `{"name":"attacked"}`}, {http.MethodDelete, ""}} {
		w := request(tc.method, "/api/v1/merchant/products/"+productB, token(memberA), tc.body)
		if w.Code != http.StatusForbidden {
			t.Errorf("staff cross-business product %s status=%d, want 403", tc.method, w.Code)
		}
	}
	// Product create, update and delete persist their state for the authenticated owner's business.
	w = request(http.MethodPost, "/api/v1/merchant/products", token(ownerA), `{"name":"Test product","price":25,"stock_status":"in_stock","is_published":true,"image_url":"https://assets.example/product.jpg"}`)
	if w.Code != http.StatusCreated {
		t.Fatalf("create product status=%d body=%s", w.Code, w.Body.String())
	}
	var created struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &created); err != nil || created.Data.ID == "" {
		t.Fatalf("created product response invalid: %s (%v)", w.Body.String(), err)
	}
	w = request(http.MethodPatch, "/api/v1/merchant/products/"+created.Data.ID, token(ownerA), `{"name":"Updated product","stock_status":"limited"}`)
	if w.Code != http.StatusOK {
		t.Fatalf("update product status=%d body=%s", w.Code, w.Body.String())
	}
	w = request(http.MethodGet, "/api/v1/merchant/products", token(ownerA), "")
	var products struct {
		Data []struct {
			ID    string `json:"id"`
			Name  string `json:"name"`
			Stock string `json:"stock_status"`
			Image string `json:"image_url"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &products); err != nil {
		t.Fatalf("decode merchant products: %v", err)
	}
	var roundTripFound bool
	for _, product := range products.Data {
		if product.ID == created.Data.ID && product.Name == "Updated product" && product.Stock == "limited" && product.Image == "https://assets.example/product.jpg" {
			roundTripFound = true
		}
	}
	if !roundTripFound {
		t.Fatalf("updated catalog product did not round-trip: %s (%v)", w.Body.String(), err)
	}
	w = request(http.MethodPatch, "/api/v1/merchant/products/"+created.Data.ID, token(ownerA), `{}`)
	if w.Code != http.StatusBadRequest {
		t.Errorf("empty product update status=%d, want 400", w.Code)
	}
	w = request(http.MethodDelete, "/api/v1/merchant/products/"+created.Data.ID, token(ownerA), "")
	if w.Code != http.StatusOK {
		t.Fatalf("delete product status=%d body=%s", w.Code, w.Body.String())
	}
	w = request(http.MethodPost, "/api/v1/merchant/products", token(ownerA), `{"name":"bad","price":-1,"stock_status":"nonsense"}`)
	if w.Code != http.StatusBadRequest {
		t.Errorf("invalid product status=%d, want 400", w.Code)
	}
	// Open and closed schedules round-trip; malformed schedules fail before any write.
	w = request(http.MethodPut, "/api/v1/merchant/operating-hours", token(ownerA), `{"hours":[{"weekday":0,"is_closed":true},{"weekday":1,"opens_at":"09:30","closes_at":"18:00","is_closed":false}]}`)
	if w.Code != http.StatusOK {
		t.Fatalf("save hours status=%d body=%s", w.Code, w.Body.String())
	}
	var closed bool
	if err := db.Get(&closed, `SELECT is_closed FROM business_hours WHERE business_id=$1 AND weekday=0`, businessA); err != nil || !closed {
		t.Fatalf("closed day not persisted (closed=%v err=%v)", closed, err)
	}
	w = request(http.MethodPut, "/api/v1/merchant/operating-hours", token(ownerA), `{"hours":[{"weekday":1,"opens_at":"not-time","closes_at":"18:00","is_closed":false}]}`)
	if w.Code != http.StatusBadRequest {
		t.Errorf("invalid hours status=%d, want 400", w.Code)
	}
	if _, err := db.Exec(`UPDATE businesses SET phone_e164=NULL,description=NULL WHERE id=$1`, businessA); err != nil {
		t.Fatal(err)
	}
	w = request(http.MethodGet, "/api/v1/merchant/profile", token(ownerA), "")
	if w.Code != http.StatusOK {
		t.Fatalf("merchant profile status=%d body=%s", w.Code, w.Body.String())
	}
	var profile struct {
		Data map[string]interface{} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &profile); err != nil || profile.Data["cover_photo_url"] != "https://assets.example/storefront.jpg" {
		t.Fatalf("profile cover photo missing: %s (%v)", w.Body.String(), err)
	}
	if profile.Data["can_edit_profile"] != true {
		t.Fatalf("business owner profile capability missing: %s", w.Body.String())
	}
	w = request(http.MethodPatch, "/api/v1/merchant/profile", token(ownerA), `{"cover_photo_url":"https://assets.example/new-storefront.jpg"}`)
	if w.Code != http.StatusOK {
		t.Fatalf("merchant profile image update status=%d body=%s", w.Code, w.Body.String())
	}
	w = request(http.MethodGet, "/api/v1/merchant/profile", token(ownerA), "")
	if err := json.Unmarshal(w.Body.Bytes(), &profile); err != nil || profile.Data["cover_photo_url"] != "https://assets.example/new-storefront.jpg" {
		t.Fatalf("updated profile image did not round-trip: %s (%v)", w.Body.String(), err)
	}
	weekday := int(time.Now().In(mustLocation(t, "Asia/Kolkata")).Weekday())
	if _, err := db.Exec(`INSERT INTO business_hours(business_id,weekday,opens_at,closes_at,is_closed) VALUES($1,$2,'00:00','23:59:59',false) ON CONFLICT(business_id,weekday) DO UPDATE SET opens_at=EXCLUDED.opens_at,closes_at=EXCLUDED.closes_at,is_closed=false`, businessA, weekday); err != nil {
		t.Fatal(err)
	}
	w = request(http.MethodGet, "/api/v1/businesses?city=Cuttack&open_now=true", "", "")
	if w.Code != http.StatusOK {
		t.Fatalf("open-now search status=%d body=%s", w.Code, w.Body.String())
	}
	var searchResult struct {
		Data []struct {
			ID              string `json:"id"`
			IsOpenNow       bool   `json:"is_open_now"`
			AcceptsRequests bool   `json:"accepts_requests"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &searchResult); err != nil || len(searchResult.Data) != 1 || searchResult.Data[0].ID != businessA || !searchResult.Data[0].IsOpenNow {
		t.Fatalf("open-now filtering/flag incorrect: %s (%v)", w.Body.String(), err)
	}
	w = request(http.MethodGet, "/api/v1/businesses?city=Jajpur&open_now=true", "", "")
	if w.Code != http.StatusOK {
		t.Fatalf("closed business open-now search status=%d", w.Code)
	}
	if err := json.Unmarshal(w.Body.Bytes(), &searchResult); err != nil || len(searchResult.Data) != 0 {
		t.Fatalf("closed merchant appeared in open-now search: %s (%v)", w.Body.String(), err)
	}
	newestBusiness := uuid.NewString()
	if _, err := db.Exec(`INSERT INTO businesses(id,owner_user_id,name,category_slug,address_text,city,location,status,verification_status) SELECT $1,owner_user_id,'Recently added test listing',category_slug,address_text,city,location,'approved','unverified' FROM businesses WHERE id=$2`, newestBusiness, businessA); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`UPDATE businesses SET created_at=now()-interval '1 day' WHERE id=$1`, businessA); err != nil {
		t.Fatal(err)
	}
	w = request(http.MethodGet, "/api/v1/businesses?city=Cuttack&available_now=true", "", "")
	if w.Code != http.StatusOK {
		t.Fatalf("available-now search status=%d body=%s", w.Code, w.Body.String())
	}
	if err := json.Unmarshal(w.Body.Bytes(), &searchResult); err != nil || len(searchResult.Data) != 1 || searchResult.Data[0].ID != businessA || !searchResult.Data[0].AcceptsRequests {
		t.Fatalf("available-now filtering/flag incorrect: %s (%v)", w.Body.String(), err)
	}
	w = request(http.MethodGet, "/api/v1/businesses?city=Cuttack&sort=recent", "", "")
	if w.Code != http.StatusOK {
		t.Fatalf("recent business search status=%d body=%s", w.Code, w.Body.String())
	}
	if err := json.Unmarshal(w.Body.Bytes(), &searchResult); err != nil || len(searchResult.Data) != 2 || searchResult.Data[0].ID != newestBusiness {
		t.Fatalf("recent listings must be ordered by creation time: %s (%v)", w.Body.String(), err)
	}
	from := time.Now().UTC().Add(24 * time.Hour).Truncate(time.Hour)
	to := from.Add(7 * 24 * time.Hour)
	if _, err := db.Exec(`INSERT INTO availability_slots(id,business_id,starts_at,ends_at,capacity,booked_count,status) VALUES($1,$2,$3,$4,2,1,'open'),($5,$2,$6,$7,1,1,'open'),($8,$2,$9,$10,1,0,'closed')`, uuid.NewString(), businessA, from, from.Add(time.Hour), uuid.NewString(), from.Add(2*time.Hour), from.Add(3*time.Hour), uuid.NewString(), from.Add(4*time.Hour), from.Add(5*time.Hour)); err != nil {
		t.Fatal(err)
	}
	availabilityPath := "/api/v1/businesses/" + businessA + "/availability?from=" + url.QueryEscape(from.Format(time.RFC3339)) + "&to=" + url.QueryEscape(to.Format(time.RFC3339))
	w = request(http.MethodGet, availabilityPath, "", "")
	if w.Code != http.StatusOK {
		t.Fatalf("availability query status=%d body=%s", w.Code, w.Body.String())
	}
	var availability struct {
		Data []struct {
			Remaining int `json:"remaining_capacity"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &availability); err != nil || len(availability.Data) != 1 || availability.Data[0].Remaining != 1 {
		t.Fatalf("availability must return only in-range, open, non-full slots: %s (%v)", w.Body.String(), err)
	}
	w = request(http.MethodGet, "/api/v1/businesses/"+businessA+"/availability?from=bad", "", "")
	if w.Code != http.StatusBadRequest {
		t.Errorf("invalid availability date status=%d, want 400", w.Code)
	}

	// Merchant slot inventory is scoped to the authenticated business member and uses its IANA zone.
	for weekday := 0; weekday < 7; weekday++ {
		if _, err := db.Exec(`INSERT INTO business_hours(business_id,weekday,opens_at,closes_at,is_closed) VALUES($1,$2,'08:00','20:00',false) ON CONFLICT(business_id,weekday) DO UPDATE SET opens_at=EXCLUDED.opens_at,closes_at=EXCLUDED.closes_at,is_closed=false`, businessA, weekday); err != nil {
			t.Fatal(err)
		}
	}
	localNow := time.Now().In(mustLocation(t, "Asia/Kolkata"))
	dateOne := time.Date(localNow.Year(), localNow.Month(), localNow.Day(), 0, 0, 0, 0, localNow.Location()).AddDate(0, 0, 7)
	dateTwo := dateOne.AddDate(0, 0, 1)
	dateKey := func(date time.Time) string { return date.Format("2006-01-02") }
	merchantBase := "/api/v1/merchant/businesses/"
	w = request(http.MethodPost, merchantBase+businessB+"/availability-slots", token(memberA), `{"date":"`+dateKey(dateOne)+`","starts_at":"10:00","ends_at":"11:00","capacity":1}`)
	if w.Code != http.StatusNotFound {
		t.Errorf("cross-business slot creation status=%d, want 404: %s", w.Code, w.Body.String())
	}
	w = request(http.MethodPost, merchantBase+businessA+"/availability-slots", token(ownerA), `{"date":"`+dateKey(dateOne)+`","starts_at":"10:00","ends_at":"11:00","capacity":1}`)
	if w.Code != http.StatusCreated {
		t.Fatalf("create merchant slot status=%d body=%s", w.Code, w.Body.String())
	}
	var createdSlot struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &createdSlot); err != nil || createdSlot.Data.ID == "" {
		t.Fatalf("invalid slot response: %s (%v)", w.Body.String(), err)
	}
	var storedStart time.Time
	if err := db.Get(&storedStart, `SELECT starts_at FROM availability_slots WHERE id=$1`, createdSlot.Data.ID); err != nil {
		t.Fatal(err)
	}
	wantUTC, _ := time.Parse(time.RFC3339, dateKey(dateOne)+"T04:30:00Z")
	if !storedStart.Equal(wantUTC) {
		t.Errorf("local 10:00 Asia/Kolkata stored as %s, want %s", storedStart, wantUTC)
	}
	w = request(http.MethodGet, merchantBase+businessA+"/availability?from="+dateKey(dateOne)+"&to="+dateKey(dateOne), token(memberA), "")
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"time_zone":"Asia/Kolkata"`) || !strings.Contains(w.Body.String(), createdSlot.Data.ID) {
		t.Errorf("merchant slot list did not return scoped local-time data: status=%d body=%s", w.Code, w.Body.String())
	}
	fromLocal := time.Date(dateOne.Year(), dateOne.Month(), dateOne.Day(), 0, 0, 0, 0, localNow.Location())
	publicAvailability := "/api/v1/businesses/" + businessA + "/availability?from=" + url.QueryEscape(fromLocal.UTC().Format(time.RFC3339)) + "&to=" + url.QueryEscape(fromLocal.AddDate(0, 0, 1).UTC().Format(time.RFC3339))
	w = request(http.MethodGet, publicAvailability, "", "")
	var customerSlots struct {
		Data []struct {
			Date     string `json:"local_date"`
			Start    string `json:"local_starts_at"`
			TimeZone string `json:"time_zone"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &customerSlots); err != nil || w.Code != http.StatusOK || len(customerSlots.Data) != 1 || customerSlots.Data[0].Date != dateKey(dateOne) || customerSlots.Data[0].Start != "10:00" || customerSlots.Data[0].TimeZone != "Asia/Kolkata" {
		t.Errorf("customer availability must expose business-local time: status=%d body=%s err=%v", w.Code, w.Body.String(), err)
	}
	w = request(http.MethodPost, merchantBase+businessA+"/availability-slots", token(ownerA), `{"date":"`+dateKey(dateOne)+`","starts_at":"10:30","ends_at":"11:30","capacity":1}`)
	if w.Code != http.StatusConflict {
		t.Errorf("overlapping slot create status=%d, want 409: %s", w.Code, w.Body.String())
	}
	w = request(http.MethodPatch, merchantBase+businessB+"/availability-slots/"+createdSlot.Data.ID, token(memberA), `{"status":"closed"}`)
	if w.Code != http.StatusNotFound {
		t.Errorf("cross-business slot edit status=%d, want 404", w.Code)
	}
	w = request(http.MethodPut, merchantBase+businessA+"/availability-exceptions", token(ownerA), `{"date":"`+dateKey(dateOne)+`","is_closed":true,"note":"Holiday closure"}`)
	if w.Code != http.StatusOK {
		t.Fatalf("close appointment date status=%d body=%s", w.Code, w.Body.String())
	}
	w = request(http.MethodGet, publicAvailability, "", "")
	if w.Code != http.StatusOK || strings.Contains(w.Body.String(), createdSlot.Data.ID) {
		t.Errorf("closed date must be unavailable to customer: status=%d body=%s", w.Code, w.Body.String())
	}
	w = request(http.MethodPost, merchantBase+businessA+"/availability-slots", token(ownerA), `{"date":"`+dateKey(dateOne)+`","starts_at":"12:00","ends_at":"13:00","capacity":1}`)
	if w.Code != http.StatusConflict {
		t.Errorf("slot create on closed date status=%d, want 409", w.Code)
	}

	// Concurrent customer requests cannot oversell a capacity-one slot; merchant state changes are validated.
	w = request(http.MethodPost, merchantBase+businessA+"/availability-slots", token(ownerA), `{"date":"`+dateKey(dateTwo)+`","starts_at":"10:00","ends_at":"11:00","capacity":1}`)
	if w.Code != http.StatusCreated {
		t.Fatalf("create race-test slot status=%d body=%s", w.Code, w.Body.String())
	}
	if err := json.Unmarshal(w.Body.Bytes(), &createdSlot); err != nil || createdSlot.Data.ID == "" {
		t.Fatalf("invalid race-test slot response: %s (%v)", w.Body.String(), err)
	}
	bookingBody := `{"slot_id":"` + createdSlot.Data.ID + `","description":"Book appointment","requested_for":"2001-01-01T00:00:00Z"}`
	type bookingResult struct {
		status     int
		body       string
		customerID string
	}
	results := make(chan bookingResult, 2)
	for _, customer := range []string{customerA, customerB} {
		go func(customerID string) {
			result := request(http.MethodPost, "/api/v1/businesses/"+businessA+"/requests", token(customerID), bookingBody)
			results <- bookingResult{status: result.Code, body: result.Body.String(), customerID: customerID}
		}(customer)
	}
	var winnerID, winnerCustomerID string
	createdCount, conflictCount := 0, 0
	for range 2 {
		result := <-results
		if result.status == http.StatusCreated {
			createdCount++
			var payload struct {
				Data struct {
					ID          string    `json:"id"`
					RequestedAt time.Time `json:"requested_for"`
				} `json:"data"`
			}
			if err := json.Unmarshal([]byte(result.body), &payload); err != nil {
				t.Fatalf("decode booking result %s: %v", result.body, err)
			}
			winnerID = payload.Data.ID
			winnerCustomerID = result.customerID
			want := time.Date(dateTwo.Year(), dateTwo.Month(), dateTwo.Day(), 10, 0, 0, 0, localNow.Location()).UTC()
			if !payload.Data.RequestedAt.Equal(want) {
				t.Errorf("booking trusted caller requested_for; got %s want slot start %s", payload.Data.RequestedAt, want)
			}
		} else if result.status == http.StatusConflict {
			conflictCount++
		} else {
			t.Errorf("booking racer returned status %d body %s", result.status, result.body)
		}
	}
	if createdCount != 1 || conflictCount != 1 {
		t.Errorf("capacity-one race: created=%d conflicts=%d, want one of each", createdCount, conflictCount)
	}
	var bookedCount int
	if err := db.Get(&bookedCount, `SELECT booked_count FROM availability_slots WHERE id=$1`, createdSlot.Data.ID); err != nil || bookedCount != 1 {
		t.Errorf("booked_count=%d err=%v, want exactly 1", bookedCount, err)
	}
	if winnerID != "" {
		merchantStatusPath := "/api/v1/merchant/requests/" + winnerID + "/status?business_id=" + businessA
		w = request(http.MethodPut, merchantBase+businessA+"/availability-exceptions", token(ownerA), `{"date":"`+dateKey(dateTwo)+`","is_closed":true}`)
		if w.Code != http.StatusConflict {
			t.Errorf("closing a date with a booked appointment status=%d, want 409", w.Code)
		}
		w = request(http.MethodPatch, merchantStatusPath, token(ownerA), `{"status":"completed"}`)
		if w.Code != http.StatusConflict {
			t.Errorf("requested to completed transition status=%d, want 409", w.Code)
		}
		w = request(http.MethodPatch, merchantStatusPath, token(ownerA), `{"status":"accepted"}`)
		if w.Code != http.StatusOK {
			t.Fatalf("accept request status=%d body=%s", w.Code, w.Body.String())
		}
		if w = request(http.MethodPatch, merchantStatusPath, token(ownerA), `{"status":"rescheduled"}`); w.Code != http.StatusBadRequest {
			t.Errorf("generic status endpoint must reject slotless reschedule status=%d body=%s", w.Code, w.Body.String())
		}
		replacementSlotID, closedReplacementID, fullReplacementID := uuid.NewString(), uuid.NewString(), uuid.NewString()
		if _, err := db.Exec(`INSERT INTO availability_slots(id,business_id,starts_at,ends_at,capacity,booked_count,status) VALUES($1,$2,$3,$4,1,0,'open'),($5,$2,$6,$7,1,0,'closed'),($8,$2,$9,$10,1,1,'open')`, replacementSlotID, businessA, time.Date(dateTwo.Year(), dateTwo.Month(), dateTwo.Day(), 12, 0, 0, 0, localNow.Location()).UTC(), time.Date(dateTwo.Year(), dateTwo.Month(), dateTwo.Day(), 12, 30, 0, 0, localNow.Location()).UTC(), closedReplacementID, time.Date(dateTwo.Year(), dateTwo.Month(), dateTwo.Day(), 14, 0, 0, 0, localNow.Location()).UTC(), time.Date(dateTwo.Year(), dateTwo.Month(), dateTwo.Day(), 14, 30, 0, 0, localNow.Location()).UTC(), fullReplacementID, time.Date(dateTwo.Year(), dateTwo.Month(), dateTwo.Day(), 16, 0, 0, 0, localNow.Location()).UTC(), time.Date(dateTwo.Year(), dateTwo.Month(), dateTwo.Day(), 16, 30, 0, 0, localNow.Location()).UTC()); err != nil {
			t.Fatal(err)
		}
		reschedulePath := "/api/v1/merchant/businesses/" + businessA + "/requests/" + winnerID + "/reschedule"
		if w = request(http.MethodPatch, "/api/v1/merchant/businesses/"+businessB+"/requests/"+winnerID+"/reschedule", token(ownerA), `{"slot_id":"`+replacementSlotID+`"}`); w.Code != http.StatusNotFound {
			t.Errorf("cross-business reschedule status=%d, want 404", w.Code)
		}
		if w = request(http.MethodPatch, reschedulePath, token(ownerA), `{"slot_id":"`+closedReplacementID+`"}`); w.Code != http.StatusConflict {
			t.Errorf("closed replacement slot status=%d, want 409: %s", w.Code, w.Body.String())
		}
		if w = request(http.MethodPatch, reschedulePath, token(ownerA), `{"slot_id":"`+fullReplacementID+`"}`); w.Code != http.StatusConflict {
			t.Errorf("full replacement slot status=%d, want 409: %s", w.Code, w.Body.String())
		}
		if err := db.Get(&bookedCount, `SELECT booked_count FROM availability_slots WHERE id=$1`, createdSlot.Data.ID); err != nil || bookedCount != 1 {
			t.Errorf("failed reschedule changed original reservation: booked=%d err=%v", bookedCount, err)
		}
		if _, err := db.Exec(`UPDATE availability_slots SET booked_count=0 WHERE id=$1`, fullReplacementID); err != nil {
			t.Fatal(err)
		}
		if w = request(http.MethodPatch, reschedulePath, token(ownerA), `{"slot_id":"`+replacementSlotID+`"}`); w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"status":"rescheduled"`) {
			t.Fatalf("atomic reschedule status=%d body=%s", w.Code, w.Body.String())
		}
		if w = request(http.MethodPatch, merchantStatusPath, token(ownerA), `{"status":"accepted"}`); w.Code != http.StatusConflict {
			t.Errorf("merchant must not confirm its own reschedule status=%d, want 409", w.Code)
		}
		var movedStatus, movedSlotID string
		var movedTime time.Time
		if err := db.QueryRowx(`SELECT status,slot_id,requested_for FROM service_requests WHERE id=$1`, winnerID).Scan(&movedStatus, &movedSlotID, &movedTime); err != nil || movedStatus != "rescheduled" || movedSlotID != replacementSlotID || !movedTime.Equal(time.Date(dateTwo.Year(), dateTwo.Month(), dateTwo.Day(), 12, 0, 0, 0, localNow.Location()).UTC()) {
			t.Errorf("persisted reschedule status=%q slot=%q time=%s err=%v", movedStatus, movedSlotID, movedTime, err)
		}
		if err := db.Get(&bookedCount, `SELECT booked_count FROM availability_slots WHERE id=$1`, createdSlot.Data.ID); err != nil || bookedCount != 0 {
			t.Errorf("reschedule did not release original slot: booked=%d err=%v", bookedCount, err)
		}
		if err := db.Get(&bookedCount, `SELECT booked_count FROM availability_slots WHERE id=$1`, replacementSlotID); err != nil || bookedCount != 1 {
			t.Errorf("reschedule did not reserve replacement slot: booked=%d err=%v", bookedCount, err)
		}
		nonOwnerID := customerA
		if winnerCustomerID == customerA {
			nonOwnerID = customerB
		}
		if w = request(http.MethodPost, "/api/v1/requests/"+winnerID+"/confirm-reschedule", token(nonOwnerID), ""); w.Code != http.StatusForbidden {
			t.Errorf("non-owner confirmed replacement time status=%d, want 403", w.Code)
		}
		if w = request(http.MethodPost, "/api/v1/requests/"+winnerID+"/confirm-reschedule", token(winnerCustomerID), ""); w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"status":"accepted"`) {
			t.Fatalf("customer confirmation status=%d body=%s", w.Code, w.Body.String())
		}
		var secondRequestID string
		secondBooking := request(http.MethodPost, "/api/v1/businesses/"+businessA+"/requests", token(customerB), `{"slot_id":"`+createdSlot.Data.ID+`","description":"Customer cancellation after rescheduling"}`)
		if secondBooking.Code != http.StatusCreated {
			t.Fatalf("second request create status=%d body=%s", secondBooking.Code, secondBooking.Body.String())
		}
		var secondBookingResponse struct {
			Data struct {
				ID string `json:"id"`
			} `json:"data"`
		}
		if err := json.Unmarshal(secondBooking.Body.Bytes(), &secondBookingResponse); err != nil {
			t.Fatal(err)
		}
		secondRequestID = secondBookingResponse.Data.ID
		secondStatusPath := "/api/v1/merchant/requests/" + secondRequestID + "/status?business_id=" + businessA
		if w = request(http.MethodPatch, secondStatusPath, token(ownerA), `{"status":"accepted"}`); w.Code != http.StatusOK {
			t.Fatalf("second request accept status=%d body=%s", w.Code, w.Body.String())
		}
		secondReschedulePath := "/api/v1/merchant/businesses/" + businessA + "/requests/" + secondRequestID + "/reschedule"
		if w = request(http.MethodPatch, secondReschedulePath, token(ownerA), `{"slot_id":"`+closedReplacementID+`"}`); w.Code != http.StatusConflict {
			t.Errorf("second closed replacement slot status=%d, want 409", w.Code)
		}
		if _, err := db.Exec(`UPDATE availability_slots SET status='open' WHERE id=$1`, closedReplacementID); err != nil {
			t.Fatal(err)
		}
		if w = request(http.MethodPatch, secondReschedulePath, token(ownerA), `{"slot_id":"`+closedReplacementID+`"}`); w.Code != http.StatusOK {
			t.Fatalf("second request reschedule status=%d body=%s", w.Code, w.Body.String())
		}
		if w = request(http.MethodPost, "/api/v1/requests/"+secondRequestID+"/cancel", token(customerB), ""); w.Code != http.StatusOK {
			t.Fatalf("customer cancel while rescheduled status=%d body=%s", w.Code, w.Body.String())
		}
		if err := db.Get(&bookedCount, `SELECT booked_count FROM availability_slots WHERE id=$1`, closedReplacementID); err != nil || bookedCount != 0 {
			t.Errorf("customer cancellation did not release proposed slot: booked=%d err=%v", bookedCount, err)
		}
		w = request(http.MethodPatch, merchantStatusPath, token(ownerA), `{"status":"cancelled"}`)
		if w.Code != http.StatusOK {
			t.Fatalf("cancel accepted request status=%d body=%s", w.Code, w.Body.String())
		}
		if err := db.Get(&bookedCount, `SELECT booked_count FROM availability_slots WHERE id=$1`, replacementSlotID); err != nil || bookedCount != 0 {
			t.Errorf("merchant cancellation did not release replacement slot: booked=%d err=%v", bookedCount, err)
		}
		var remainingBookings int
		if err := db.Get(&remainingBookings, `SELECT COALESCE(SUM(booked_count),0) FROM availability_slots WHERE business_id=$1 AND starts_at >= $2 AND starts_at < $3`, businessA, time.Date(dateTwo.Year(), dateTwo.Month(), dateTwo.Day(), 0, 0, 0, 0, localNow.Location()).UTC(), time.Date(dateTwo.Year(), dateTwo.Month(), dateTwo.Day(), 0, 0, 0, 0, localNow.Location()).AddDate(0, 0, 1).UTC()); err != nil || remainingBookings != 0 {
			t.Errorf("all appointment reservations should be released before closing the date: booked=%d err=%v", remainingBookings, err)
		}
		w = request(http.MethodPut, merchantBase+businessA+"/availability-exceptions", token(ownerA), `{"date":"`+dateKey(dateTwo)+`","is_closed":true}`)
		if w.Code != http.StatusOK {
			t.Errorf("closing date after cancellation status=%d body=%s", w.Code, w.Body.String())
		}
	}

	// A member of business A cannot read a service request attached to business B.
	w = request(http.MethodGet, "/api/v1/requests/"+requestB, token(memberA), "")
	if w.Code != http.StatusForbidden {
		t.Errorf("non-member reading B request status=%d, want 403", w.Code)
	}

	// Cart validation is role-gated, category/default-deny scoped, and prices
	// finite stock from the database without exposing foreign-business items.
	if _, err := db.Exec(`UPDATE businesses SET category_slug='restaurant',delivery_enabled=true,min_order_amount=10,delivery_fee=25 WHERE id=$1`, businessA); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO categories(slug,name) VALUES('restaurant','Restaurant') ON CONFLICT(slug) DO NOTHING`); err != nil {
		t.Fatal(err)
	}
	w = request(http.MethodGet, "/api/v1/businesses?category_slug=restaurant&lat=20.465&lng=85.879", "", "")
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"delivery_enabled":true`) {
		t.Fatalf("restaurant discovery omitted its ordering capability: status=%d body=%s", w.Code, w.Body.String())
	}
	cartProductID := uuid.NewString()
	if _, err := db.Exec(`INSERT INTO products(id,business_id,name,price,stock_status,inventory_mode,available_quantity,is_published) VALUES($1,$2,'Cart product',12.35,'in_stock','finite',3,true)`, cartProductID, businessA); err != nil {
		t.Fatal(err)
	}
	cartPath := "/api/v1/businesses/" + businessA + "/cart/validate"
	if w = request(http.MethodPost, cartPath, token(memberA), `{"items":[{"product_id":"`+cartProductID+`","quantity":1}]}`); w.Code != http.StatusForbidden {
		t.Fatalf("merchant cart validation status=%d, want 403 body=%s", w.Code, w.Body.String())
	}
	if w = request(http.MethodPost, cartPath, token(customerA), `{"items":[{"product_id":"`+cartProductID+`","quantity":1}]}`); w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"item_subtotal_minor":1235`) {
		t.Fatalf("server cart price status=%d body=%s", w.Code, w.Body.String())
	}
	if w = request(http.MethodPost, cartPath, token(customerA), `{"items":[{"product_id":"`+cartProductID+`","quantity":4}]}`); w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"insufficient_stock"`) {
		t.Fatalf("insufficient cart stock status=%d body=%s", w.Code, w.Body.String())
	}
	if w = request(http.MethodPost, cartPath, token(customerA), `{"items":[{"product_id":"`+productB+`","quantity":1}]}`); w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"available":false`) {
		t.Fatalf("cross-business cart item status=%d body=%s", w.Code, w.Body.String())
	}
	if w = request(http.MethodPost, "/api/v1/businesses/"+businessB+"/cart/validate", token(customerB), `{"items":[{"product_id":"`+productB+`","quantity":1}]}`); w.Code != http.StatusConflict {
		t.Fatalf("unsupported category cart status=%d, want 409 body=%s", w.Code, w.Body.String())
	}
	if w = request(http.MethodPatch, "/api/v1/merchant/products/"+cartProductID+"?business_id="+businessA, token(ownerA), `{"inventory_mode":"finite","available_quantity":7}`); w.Code != http.StatusOK {
		t.Fatalf("merchant stock update status=%d body=%s", w.Code, w.Body.String())
	}
	var merchantStock int
	if err := db.Get(&merchantStock, `SELECT available_quantity FROM products WHERE id=$1 AND business_id=$2`, cartProductID, businessA); err != nil || merchantStock != 7 {
		t.Fatalf("merchant stock persistence=%d err=%v", merchantStock, err)
	}
	if w = request(http.MethodPatch, "/api/v1/merchant/products/"+cartProductID+"?business_id="+businessB, token(ownerA), `{"available_quantity":9}`); w.Code != http.StatusForbidden {
		t.Fatalf("cross-business inventory update status=%d, want 403 body=%s", w.Code, w.Body.String())
	}
	if _, err := db.Exec(`UPDATE products SET price=15.05 WHERE id=$1`, cartProductID); err != nil {
		t.Fatal(err)
	}
	if w = request(http.MethodPost, cartPath, token(customerA), `{"items":[{"product_id":"`+cartProductID+`","quantity":1}]}`); w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"item_subtotal_minor":1505`) {
		t.Fatalf("changed server price was not reflected in minor units: status=%d body=%s", w.Code, w.Body.String())
	}
	if _, err := db.Exec(`UPDATE businesses SET min_order_amount=20 WHERE id=$1`, businessA); err != nil {
		t.Fatal(err)
	}
	if w = request(http.MethodPost, cartPath, token(customerA), `{"items":[{"product_id":"`+cartProductID+`","quantity":1}]}`); w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"minimum_met":false`) {
		t.Fatalf("server minimum-order status missing: status=%d body=%s", w.Code, w.Body.String())
	}
	if _, err := db.Exec(`UPDATE businesses SET min_order_amount=10 WHERE id=$1`, businessA); err != nil {
		t.Fatal(err)
	}
	if w = request(http.MethodPost, "/api/v1/businesses/"+businessA+"/orders", token(memberA), `{"order_type":"food_delivery","fulfillment_type":"takeaway","items":[{"product_id":"`+cartProductID+`","quantity":1}]}`); w.Code != http.StatusForbidden {
		t.Fatalf("merchant order creation status=%d, want 403 body=%s", w.Code, w.Body.String())
	}

	// Phase 2C delivery addresses are customer-owned, map pins drive coverage,
	// quotes never reserve stock, and orders use server quote plus idempotency.
	addressBody := func(label, locality string, latitude, longitude *float64, makeDefault bool) string {
		lat, lng := "null", "null"
		if latitude != nil && longitude != nil {
			lat = fmt.Sprintf("%f", *latitude)
			lng = fmt.Sprintf("%f", *longitude)
		}
		return fmt.Sprintf(`{"label":%q,"recipient_name":"Customer A","address_line1":"12 Market Road","locality":%q,"landmark":"Near clock tower","city":"Cuttack","state":"Odisha","postal_code":"753001","contact_phone":"+919876543210","latitude":%s,"longitude":%s,"is_default":%t}`, label, locality, lat, lng, makeDefault)
	}
	lat, lng := 20.501, 85.901
	addrResponse := request(http.MethodPost, "/api/v1/customer/addresses", token(customerA), addressBody("Home", "Badambadi", &lat, &lng, true))
	if addrResponse.Code != http.StatusCreated {
		t.Fatalf("customer address create status=%d body=%s", addrResponse.Code, addrResponse.Body.String())
	}
	var addressResult struct {
		Data struct {
			ID        string `json:"id"`
			IsDefault bool   `json:"is_default"`
		} `json:"data"`
	}
	if err := json.Unmarshal(addrResponse.Body.Bytes(), &addressResult); err != nil || addressResult.Data.ID == "" || !addressResult.Data.IsDefault {
		t.Fatalf("first address should be default: %s err=%v", addrResponse.Body.String(), err)
	}
	addressA := addressResult.Data.ID
	if foreignAddress := request(http.MethodPost, "/api/v1/customer/addresses", token(customerB), addressBody("Home", "Jajpur Road", nil, nil, true)); foreignAddress.Code != http.StatusCreated {
		t.Fatalf("customer B address create status=%d body=%s", foreignAddress.Code, foreignAddress.Body.String())
	}
	var addressB string
	if err := db.Get(&addressB, `SELECT id::text FROM customer_addresses WHERE customer_user_id=$1`, customerB); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO business_hours(business_id,weekday,opens_at,closes_at,is_closed) VALUES($1,$2,'00:00','23:59:59',false) ON CONFLICT(business_id,weekday) DO UPDATE SET opens_at='00:00',closes_at='23:59:59',is_closed=false`, businessA, time.Now().In(mustLocation(t, "Asia/Kolkata")).Weekday()); err != nil {
		t.Fatal(err)
	}
	makeQuote := func(customer, addressID, fulfillment, productID string, quantity int) *httptest.ResponseRecorder {
		addr := ""
		if addressID != "" {
			addr = `,"address_id":"` + addressID + `"`
		}
		body := fmt.Sprintf(`{"fulfillment_type":%q%s,"items":[{"product_id":%q,"quantity":%d}]}`, fulfillment, addr, productID, quantity)
		return request(http.MethodPost, "/api/v1/businesses/"+businessA+"/orders/quote", token(customer), body)
	}
	quote := makeQuote(customerA, addressA, "delivery", cartProductID, 1)
	if quote.Code != http.StatusCreated || !strings.Contains(quote.Body.String(), `"tax_status":"not_configured"`) || !strings.Contains(quote.Body.String(), `"serviceability_method":"radius"`) {
		t.Fatalf("serviceable delivery quote status=%d body=%s", quote.Code, quote.Body.String())
	}
	if err := db.Get(&merchantStock, `SELECT available_quantity FROM products WHERE id=$1`, cartProductID); err != nil || merchantStock != 7 {
		t.Fatalf("quote must not reserve finite stock: quantity=%d err=%v", merchantStock, err)
	}
	// A price update after quote issuance must require a new quote and must not
	// reserve any inventory.
	stalePriceQuote := makeQuote(customerA, "", "takeaway", cartProductID, 1)
	var stalePriceData struct {
		Data struct {
			QuoteID string `json:"quote_id"`
		} `json:"data"`
	}
	_ = json.Unmarshal(stalePriceQuote.Body.Bytes(), &stalePriceData)
	if _, err := db.Exec(`UPDATE products SET price=16.05 WHERE id=$1`, cartProductID); err != nil {
		t.Fatal(err)
	}
	stalePriceOrder := requestWithIdempotency("/api/v1/businesses/"+businessA+"/orders", token(customerA), uuid.NewString(), fmt.Sprintf(`{"order_type":"food_delivery","checkout_quote_id":%q,"fulfillment_type":"takeaway"}`, stalePriceData.Data.QuoteID))
	if stalePriceOrder.Code != http.StatusConflict {
		t.Errorf("changed price should invalidate quote: status=%d body=%s", stalePriceOrder.Code, stalePriceOrder.Body.String())
	}
	if _, err := db.Exec(`UPDATE products SET price=15.05 WHERE id=$1`, cartProductID); err != nil {
		t.Fatal(err)
	}
	if err := db.Get(&merchantStock, `SELECT available_quantity FROM products WHERE id=$1`, cartProductID); err != nil || merchantStock != 7 {
		t.Fatalf("stale price must not reserve stock: quantity=%d err=%v", merchantStock, err)
	}
	// Expired quotes are rejected before stock changes.
	expiredQuote := makeQuote(customerA, "", "takeaway", cartProductID, 1)
	var expiredData struct {
		Data struct {
			QuoteID string `json:"quote_id"`
		} `json:"data"`
	}
	_ = json.Unmarshal(expiredQuote.Body.Bytes(), &expiredData)
	if _, err := db.Exec(`UPDATE checkout_quotes SET expires_at=now()-interval '1 second' WHERE id=$1`, expiredData.Data.QuoteID); err != nil {
		t.Fatal(err)
	}
	expiredOrder := requestWithIdempotency("/api/v1/businesses/"+businessA+"/orders", token(customerA), uuid.NewString(), fmt.Sprintf(`{"order_type":"food_delivery","checkout_quote_id":%q,"fulfillment_type":"takeaway"}`, expiredData.Data.QuoteID))
	if expiredOrder.Code != http.StatusConflict || !strings.Contains(expiredOrder.Body.String(), `"QUOTE_EXPIRED"`) {
		t.Errorf("expired quote status=%d body=%s", expiredOrder.Code, expiredOrder.Body.String())
	}
	unavailableQuote := makeQuote(customerA, "", "takeaway", cartProductID, 1)
	var unavailableData struct {
		Data struct {
			QuoteID string `json:"quote_id"`
		} `json:"data"`
	}
	_ = json.Unmarshal(unavailableQuote.Body.Bytes(), &unavailableData)
	if _, err := db.Exec(`UPDATE products SET available_quantity=0,stock_status='out_of_stock' WHERE id=$1`, cartProductID); err != nil {
		t.Fatal(err)
	}
	unavailableOrder := requestWithIdempotency("/api/v1/businesses/"+businessA+"/orders", token(customerA), uuid.NewString(), fmt.Sprintf(`{"order_type":"food_delivery","checkout_quote_id":%q,"fulfillment_type":"takeaway"}`, unavailableData.Data.QuoteID))
	if unavailableOrder.Code != http.StatusConflict || !strings.Contains(unavailableOrder.Body.String(), `"ITEM_UNAVAILABLE"`) {
		t.Errorf("item made unavailable after quote: status=%d body=%s", unavailableOrder.Code, unavailableOrder.Body.String())
	}
	if _, err := db.Exec(`UPDATE products SET available_quantity=7,stock_status='in_stock' WHERE id=$1`, cartProductID); err != nil {
		t.Fatal(err)
	}
	if foreignQuote := makeQuote(customerA, addressB, "delivery", cartProductID, 1); foreignQuote.Code != http.StatusUnprocessableEntity {
		t.Errorf("another customer's address quote status=%d, want 422 body=%s", foreignQuote.Code, foreignQuote.Body.String())
	}
	farLat, farLng := 20.5, 86.1
	farAddressResponse := request(http.MethodPost, "/api/v1/customer/addresses", token(customerA), addressBody("Work", "Badambadi", &farLat, &farLng, false))
	if farAddressResponse.Code != http.StatusCreated {
		t.Fatalf("far address create status=%d %s", farAddressResponse.Code, farAddressResponse.Body.String())
	}
	var farAddress struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	_ = json.Unmarshal(farAddressResponse.Body.Bytes(), &farAddress)
	if outOfRange := makeQuote(customerA, farAddress.Data.ID, "delivery", cartProductID, 1); outOfRange.Code != http.StatusUnprocessableEntity {
		t.Errorf("out-of-coverage quote status=%d, want 422 body=%s", outOfRange.Code, outOfRange.Body.String())
	}
	if malformed := request(http.MethodPost, "/api/v1/customer/addresses", token(customerA), strings.Replace(addressBody("Bad", "Badambadi", nil, nil, false), `"postal_code":"753001"`, `"postal_code":"123"`, 1)); malformed.Code != http.StatusBadRequest {
		t.Errorf("invalid PIN address status=%d, want 400 body=%s", malformed.Code, malformed.Body.String())
	}
	// Updating an address invalidates a quote bound to the previous version.
	var deliveryQuote struct {
		Data struct {
			QuoteID string `json:"quote_id"`
		} `json:"data"`
	}
	_ = json.Unmarshal(quote.Body.Bytes(), &deliveryQuote)
	updateAddressBody := strings.Replace(addressBody("Home Updated", "Badambadi", &lat, &lng, true), `"label":"Home Updated"`, `"label":"Home Updated"`, 1)
	if updated := request(http.MethodPut, "/api/v1/customer/addresses/"+addressA, token(customerA), updateAddressBody); updated.Code != http.StatusOK {
		t.Fatalf("address update status=%d body=%s", updated.Code, updated.Body.String())
	}
	staleDelivery := requestWithIdempotency("/api/v1/businesses/"+businessA+"/orders", token(customerA), uuid.NewString(), fmt.Sprintf(`{"order_type":"food_delivery","checkout_quote_id":%q,"fulfillment_type":"delivery"}`, deliveryQuote.Data.QuoteID))
	if staleDelivery.Code != http.StatusUnprocessableEntity {
		t.Errorf("address mutation should invalidate quote: status=%d body=%s", staleDelivery.Code, staleDelivery.Body.String())
	}

	// Quote and submit one stock unit, retrying the same idempotency key.
	takeawayQuote := makeQuote(customerA, "", "takeaway", cartProductID, 1)
	var takeaway struct {
		Data struct {
			QuoteID string `json:"quote_id"`
			Total   int64  `json:"grand_total_minor"`
		} `json:"data"`
	}
	if err := json.Unmarshal(takeawayQuote.Body.Bytes(), &takeaway); err != nil || takeawayQuote.Code != http.StatusCreated || takeaway.Data.QuoteID == "" || takeaway.Data.Total != 1505 {
		t.Fatalf("takeaway quote status=%d body=%s err=%v", takeawayQuote.Code, takeawayQuote.Body.String(), err)
	}
	key := uuid.NewString()
	orderBody := fmt.Sprintf(`{"order_type":"food_delivery","checkout_quote_id":%q,"fulfillment_type":"takeaway"}`, takeaway.Data.QuoteID)
	createdOrder := requestWithIdempotency("/api/v1/businesses/"+businessA+"/orders", token(customerA), key, orderBody)
	if createdOrder.Code != http.StatusCreated || !strings.Contains(createdOrder.Body.String(), `"payment_status":"not_collected"`) {
		t.Fatalf("quote-based order create status=%d body=%s", createdOrder.Code, createdOrder.Body.String())
	}
	var createdResult struct {
		Data struct {
			ID         string  `json:"id"`
			GrandTotal float64 `json:"grand_total"`
		} `json:"data"`
	}
	if err := json.Unmarshal(createdOrder.Body.Bytes(), &createdResult); err != nil || createdResult.Data.ID == "" || createdResult.Data.GrandTotal != 15.05 {
		t.Fatalf("order response totals=%s err=%v", createdOrder.Body.String(), err)
	}
	replayedOrder := requestWithIdempotency("/api/v1/businesses/"+businessA+"/orders", token(customerA), key, orderBody)
	if replayedOrder.Code != http.StatusOK || !strings.Contains(replayedOrder.Body.String(), `"idempotent_replay":true`) || !strings.Contains(replayedOrder.Body.String(), createdResult.Data.ID) {
		t.Fatalf("idempotency replay status=%d body=%s", replayedOrder.Code, replayedOrder.Body.String())
	}
	if err := db.Get(&merchantStock, `SELECT available_quantity FROM products WHERE id=$1`, cartProductID); err != nil || merchantStock != 6 {
		t.Fatalf("idempotent retry consumed extra stock: quantity=%d err=%v", merchantStock, err)
	}
	if conflict := requestWithIdempotency("/api/v1/businesses/"+businessA+"/orders", token(customerA), key, `{"order_type":"food_delivery","checkout_quote_id":"`+uuid.NewString()+`","fulfillment_type":"takeaway"}`); conflict.Code != http.StatusConflict {
		t.Errorf("reused key for another quote status=%d, want 409 body=%s", conflict.Code, conflict.Body.String())
	}
	if cancelled := request(http.MethodPost, "/api/v1/orders/"+createdResult.Data.ID+"/cancel", token(customerA), ""); cancelled.Code != http.StatusOK {
		t.Fatalf("cancel quote-based order status=%d body=%s", cancelled.Code, cancelled.Body.String())
	}
	if err := db.Get(&merchantStock, `SELECT available_quantity FROM products WHERE id=$1`, cartProductID); err != nil || merchantStock != 7 {
		t.Fatalf("order cancellation failed to restore stock: quantity=%d err=%v", merchantStock, err)
	}
	finalDeliveryQuote := makeQuote(customerA, addressA, "delivery", cartProductID, 1)
	var finalDeliveryData struct {
		Data struct {
			QuoteID string `json:"quote_id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(finalDeliveryQuote.Body.Bytes(), &finalDeliveryData); err != nil || finalDeliveryQuote.Code != http.StatusCreated {
		t.Fatalf("final delivery quote status=%d body=%s err=%v", finalDeliveryQuote.Code, finalDeliveryQuote.Body.String(), err)
	}
	deliveryOrder := requestWithIdempotency("/api/v1/businesses/"+businessA+"/orders", token(customerA), uuid.NewString(), fmt.Sprintf(`{"order_type":"food_delivery","checkout_quote_id":%q,"fulfillment_type":"delivery"}`, finalDeliveryData.Data.QuoteID))
	if deliveryOrder.Code != http.StatusCreated || !strings.Contains(deliveryOrder.Body.String(), `"delivery_address_snapshot"`) {
		t.Fatalf("delivery order snapshot status=%d body=%s", deliveryOrder.Code, deliveryOrder.Body.String())
	}
	var deliveryOrderResult struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	_ = json.Unmarshal(deliveryOrder.Body.Bytes(), &deliveryOrderResult)
	if cancelled := request(http.MethodPost, "/api/v1/orders/"+deliveryOrderResult.Data.ID+"/cancel", token(customerA), ""); cancelled.Code != http.StatusOK {
		t.Fatalf("delivery order cleanup cancel status=%d body=%s", cancelled.Code, cancelled.Body.String())
	}
	if deleteResponse := request(http.MethodDelete, "/api/v1/customer/addresses/"+addressA, token(customerA), ""); deleteResponse.Code != http.StatusOK {
		t.Errorf("delete saved address status=%d body=%s", deleteResponse.Code, deleteResponse.Body.String())
	}
	var addressReferenceNull, snapshotRetained bool
	if err := db.QueryRowx(`SELECT delivery_address_id IS NULL,delivery_address_snapshot IS NOT NULL FROM customer_orders WHERE id=$1`, deliveryOrderResult.Data.ID).Scan(&addressReferenceNull, &snapshotRetained); err != nil || !addressReferenceNull || !snapshotRetained {
		t.Errorf("deleting saved address should preserve the order snapshot: reference_null=%v snapshot=%v err=%v", addressReferenceNull, snapshotRetained, err)
	}
	var promotedDefault bool
	if err := db.Get(&promotedDefault, `SELECT is_default FROM customer_addresses WHERE id=$1`, farAddress.Data.ID); err != nil || !promotedDefault {
		t.Errorf("deleting default should promote remaining address: default=%v err=%v", promotedDefault, err)
	}

	// Concurrent distinct customers competing for the last unit serialize on
	// the product row; one succeeds and the rejected transaction reserves none.
	lastUnitID := uuid.NewString()
	if _, err := db.Exec(`INSERT INTO products(id,business_id,name,price,stock_status,inventory_mode,available_quantity,is_published) VALUES($1,$2,'Last unit',10,'in_stock','finite',1,true)`, lastUnitID, businessA); err != nil {
		t.Fatal(err)
	}
	quoteA, quoteB := makeQuote(customerA, "", "takeaway", lastUnitID, 1), makeQuote(customerB, "", "takeaway", lastUnitID, 1)
	var quoteAData, quoteBData struct {
		Data struct {
			QuoteID string `json:"quote_id"`
		} `json:"data"`
	}
	if quoteA.Code != http.StatusCreated || quoteB.Code != http.StatusCreated {
		t.Fatalf("last-unit quotes status=%d/%d bodies=%s / %s", quoteA.Code, quoteB.Code, quoteA.Body.String(), quoteB.Body.String())
	}
	_ = json.Unmarshal(quoteA.Body.Bytes(), &quoteAData)
	_ = json.Unmarshal(quoteB.Body.Bytes(), &quoteBData)
	orderBodyA := fmt.Sprintf(`{"order_type":"food_delivery","checkout_quote_id":%q,"fulfillment_type":"takeaway"}`, quoteAData.Data.QuoteID)
	orderBodyB := fmt.Sprintf(`{"order_type":"food_delivery","checkout_quote_id":%q,"fulfillment_type":"takeaway"}`, quoteBData.Data.QuoteID)
	type finiteStockResult struct {
		code     int
		orderID  string
		customer string
	}
	orderResults := make(chan finiteStockResult, 2)
	for i, customer := range []string{customerA, customerB} {
		go func(customer, body string) {
			response := requestWithIdempotency("/api/v1/businesses/"+businessA+"/orders", token(customer), uuid.NewString(), body)
			result := finiteStockResult{code: response.Code, customer: customer}
			if response.Code == http.StatusCreated {
				var body struct {
					Data struct {
						ID string `json:"id"`
					} `json:"data"`
				}
				_ = json.Unmarshal(response.Body.Bytes(), &body)
				result.orderID = body.Data.ID
			}
			orderResults <- result
		}(customer, []string{orderBodyA, orderBodyB}[i])
	}
	createdOrders, rejectedOrders := 0, 0
	var createdOrderID string
	var winningCustomer string
	for i := 0; i < 2; i++ {
		result := <-orderResults
		if result.code == http.StatusCreated {
			createdOrders++
			createdOrderID = result.orderID
			winningCustomer = result.customer
		} else {
			rejectedOrders++
		}
	}
	var remaining int
	if err := db.Get(&remaining, `SELECT available_quantity FROM products WHERE id=$1`, lastUnitID); err != nil {
		t.Fatal(err)
	}
	if createdOrders != 1 || rejectedOrders != 1 || remaining != 0 {
		t.Fatalf("concurrent finite stock: created=%d rejected=%d remaining=%d", createdOrders, rejectedOrders, remaining)
	}
	if createdOrderID == "" {
		t.Fatal("successful concurrent order did not return an ID")
	}
	if w = request(http.MethodPost, "/api/v1/orders/"+createdOrderID+"/cancel", token(winningCustomer), ""); w.Code != http.StatusOK {
		t.Fatalf("customer cancellation status=%d body=%s", w.Code, w.Body.String())
	}
	if err := db.Get(&remaining, `SELECT available_quantity FROM products WHERE id=$1`, lastUnitID); err != nil || remaining != 1 {
		t.Fatalf("cancelled order did not restore stock: remaining=%d err=%v", remaining, err)
	}
	if w = request(http.MethodPost, "/api/v1/orders/"+createdOrderID+"/cancel", token(winningCustomer), ""); w.Code != http.StatusOK {
		t.Fatalf("idempotent cancellation retry status=%d want 200 body=%s", w.Code, w.Body.String())
	}
	if err := db.Get(&remaining, `SELECT available_quantity FROM products WHERE id=$1`, lastUnitID); err != nil || remaining != 1 {
		t.Fatalf("repeated cancellation changed stock: remaining=%d err=%v", remaining, err)
	}
	secondQuote := makeQuote(winningCustomer, "", "takeaway", lastUnitID, 1)
	var secondQuoteData struct {
		Data struct {
			QuoteID string `json:"quote_id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(secondQuote.Body.Bytes(), &secondQuoteData); err != nil || secondQuote.Code != http.StatusCreated {
		t.Fatalf("second quote status=%d body=%s err=%v", secondQuote.Code, secondQuote.Body.String(), err)
	}
	secondBody := fmt.Sprintf(`{"order_type":"food_delivery","checkout_quote_id":%q,"fulfillment_type":"takeaway"}`, secondQuoteData.Data.QuoteID)
	secondOrder := requestWithIdempotency("/api/v1/businesses/"+businessA+"/orders", token(winningCustomer), uuid.NewString(), secondBody)
	if secondOrder.Code != http.StatusCreated {
		t.Fatalf("second order for restored unit status=%d body=%s", secondOrder.Code, secondOrder.Body.String())
	}
	var secondOrderBody struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(secondOrder.Body.Bytes(), &secondOrderBody); err != nil || secondOrderBody.Data.ID == "" {
		t.Fatalf("decode second order ID: %v body=%s", err, secondOrder.Body.String())
	}
	if w = request(http.MethodPatch, "/api/v1/merchant/orders/"+secondOrderBody.Data.ID+"/status", token(ownerA), `{"status":"cancelled"}`); w.Code != http.StatusOK {
		t.Fatalf("merchant cancellation status=%d body=%s", w.Code, w.Body.String())
	}
	if err := db.Get(&remaining, `SELECT available_quantity FROM products WHERE id=$1`, lastUnitID); err != nil || remaining != 1 {
		t.Fatalf("merchant cancellation did not restore finite stock: remaining=%d err=%v", remaining, err)
	}
}

func TestPlatformCheckoutPartnerSelectionIdempotencyAndStockRestoration(t *testing.T) {
	logger.Init("error")
	db, ownerA, _, customerA, customerB, businessA, businessB, _, _, _, _ := newAPISecurityFixture(t)
	localityID := "02200000-0000-4000-8000-000000000101"
	weekday := int(time.Now().In(mustLocation(t, "Asia/Kolkata")).Weekday())
	if _, err := db.Exec(`UPDATE businesses SET delivery_enabled=true WHERE id=$1`, businessA); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO business_hours(business_id,weekday,opens_at,closes_at,is_closed) VALUES($1,$2,'00:00','23:59',false)`, businessA, weekday); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO platform_partner_delivery_localities(business_id,locality_id,is_active) VALUES($1,$2,true)`, businessA, localityID); err != nil {
		t.Fatal(err)
	}
	var categoryID string
	if err := db.Get(&categoryID, `SELECT id::text FROM platform_catalog_categories WHERE vertical='food' AND is_system`); err != nil {
		t.Fatal(err)
	}
	productID, variantID := uuid.NewString(), uuid.NewString()
	if _, err := db.Exec(`INSERT INTO platform_catalog_products(id,sku,category_id,name,status) VALUES($1,$2,$3,'QA Test Meal','active')`, productID, "INTEGRATION-FOOD-"+strings.ReplaceAll(productID, "-", ""), categoryID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO platform_catalog_variants(id,product_id,sku,name,unit_label,price_minor,currency) VALUES($1,$2,$3,'Single','portion',25000,'INR')`, variantID, productID, "INTEGRATION-VARIANT-"+strings.ReplaceAll(variantID, "-", "")); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO platform_catalog_product_district_visibility(product_id,district_id) VALUES($1,'02200000-0000-4000-8000-000000000001')`, productID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO platform_catalog_product_delivery_localities(product_id,locality_id) VALUES($1,$2)`, productID, localityID); err != nil {
		t.Fatal(err)
	}
	mappingID := uuid.NewString()
	if _, err := db.Exec(`INSERT INTO platform_partner_product_mappings(id,business_id,variant_id,status,inventory_mode,available_quantity,supply_price_minor,created_by,updated_by,approved_by,approved_at) VALUES($1,$2,$3,'approved','finite',1,7000,$4,$4,$4,now())`, mappingID, businessA, variantID, ownerA); err != nil {
		t.Fatal(err)
	}
	// A second partner can supply a second item, but neither partner can fulfill
	// the complete basket. The quote must reject it rather than split the order.
	if _, err := db.Exec(`UPDATE businesses SET status='approved',verification_status='verified',delivery_enabled=true WHERE id=$1`, businessB); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO business_hours(business_id,weekday,opens_at,closes_at,is_closed) VALUES($1,$2,'00:00','23:59',false) ON CONFLICT (business_id,weekday) DO UPDATE SET opens_at=EXCLUDED.opens_at,closes_at=EXCLUDED.closes_at,is_closed=false`, businessB, weekday); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO platform_partner_delivery_localities(business_id,locality_id,is_active) VALUES($1,$2,true)`, businessB, localityID); err != nil {
		t.Fatal(err)
	}
	secondProduct, secondVariant := uuid.NewString(), uuid.NewString()
	if _, err := db.Exec(`INSERT INTO platform_catalog_products(id,sku,category_id,name,status) VALUES($1,$2,$3,'QA Second Meal','active')`, secondProduct, "INTEGRATION-FOOD-"+strings.ReplaceAll(secondProduct, "-", ""), categoryID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO platform_catalog_variants(id,product_id,sku,name,unit_label,price_minor,currency) VALUES($1,$2,$3,'Single','portion',5000,'INR')`, secondVariant, secondProduct, "INTEGRATION-VARIANT-"+strings.ReplaceAll(secondVariant, "-", "")); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO platform_catalog_product_district_visibility(product_id,district_id) VALUES($1,'02200000-0000-4000-8000-000000000001')`, secondProduct); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO platform_catalog_product_delivery_localities(product_id,locality_id) VALUES($1,$2)`, secondProduct, localityID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO platform_partner_product_mappings(business_id,variant_id,status,inventory_mode,available_quantity,created_by,updated_by,approved_by,approved_at) VALUES($1,$2,'approved','untracked',NULL,$3,$3,$3,now())`, businessB, secondVariant, ownerA); err != nil {
		t.Fatal(err)
	}
	addressID := uuid.NewString()
	createAddress := func(customer string) string {
		t.Helper()
		id := uuid.NewString()
		_, err := db.Exec(`INSERT INTO customer_addresses(id,customer_user_id,label,recipient_name,address_line1,locality,delivery_locality_id,landmark,city,state,postal_code,contact_phone,is_default) VALUES($1,$2,'Home','Test Customer','12 Main Road','Kuanpal',$3,'Near Market','Cuttack','Odisha','753001','+919876543210',true)`, id, customer, localityID)
		if err != nil {
			t.Fatal(err)
		}
		return id
	}
	addressID = createAddress(customerA)
	cfg := &config.Config{Env: "test", JWTSecret: "integration-test-secret-with-over-32-characters"}
	authSvc := auth.NewService(db, cfg)
	router := setupRouter(authSvc, discovery.NewService(db, cfg), moderation.NewService(db, cfg), nil, notifications.NewHub(db.DB), operations.NewService(db), platformcommerce.NewService(db))
	token := func(subject string) string {
		t.Helper()
		tok, err := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.RegisteredClaims{Subject: subject, Issuer: "grepmind-near", IssuedAt: jwt.NewNumericDate(time.Now()), ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour))}).SignedString([]byte(cfg.JWTSecret))
		if err != nil {
			t.Fatal(err)
		}
		return tok
	}
	request := func(customer, method, path, body, key string) *httptest.ResponseRecorder {
		t.Helper()
		r := httptest.NewRequest(method, path, strings.NewReader(body))
		r.Header.Set("Authorization", "Bearer "+token(customer))
		if key != "" {
			r.Header.Set("Idempotency-Key", key)
		}
		w := httptest.NewRecorder()
		router.ServeHTTP(w, r)
		return w
	}
	quoteBody := func(address string) string {
		return `{"vertical":"food","address_id":"` + address + `","items":[{"variant_id":"` + variantID + `","quantity":1}]}`
	}
	mixedBasket := `{"vertical":"food","address_id":"` + addressID + `","items":[{"variant_id":"` + variantID + `","quantity":1},{"variant_id":"` + secondVariant + `","quantity":1}]}`
	if mixed := request(customerA, http.MethodPost, "/api/v1/platform/orders/quote", mixedBasket, ""); mixed.Code != http.StatusConflict || !strings.Contains(mixed.Body.String(), "PARTNER_UNAVAILABLE") {
		t.Fatalf("basket without one complete-order partner status=%d body=%s", mixed.Code, mixed.Body.String())
	}
	w := request(customerA, http.MethodPost, "/api/v1/platform/orders/quote", quoteBody(addressID), "")
	if w.Code != http.StatusCreated || strings.Contains(w.Body.String(), "supply_price_minor") {
		t.Fatalf("quote status=%d body=%s", w.Code, w.Body.String())
	}
	var quote struct {
		Data struct {
			QuoteID string `json:"quote_id"`
			Partner struct {
				ID string `json:"business_id"`
			} `json:"partner"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &quote); err != nil || quote.Data.Partner.ID != businessA {
		t.Fatalf("partner quote parse=%+v err=%v", quote, err)
	}
	var stock int
	if err := db.Get(&stock, `SELECT available_quantity FROM platform_partner_product_mappings WHERE id=$1`, mappingID); err != nil || stock != 1 {
		t.Fatalf("quote must not reserve stock=%d err=%v", stock, err)
	}
	if w = request(customerB, http.MethodPost, "/api/v1/platform/orders", `{"quote_id":"`+quote.Data.QuoteID+`"}`, uuid.NewString()); w.Code != http.StatusNotFound {
		t.Fatalf("cross-customer quote submit=%d body=%s", w.Code, w.Body.String())
	}
	idem := uuid.NewString()
	submitBody := `{"quote_id":"` + quote.Data.QuoteID + `","notes":"QA"}`
	w = request(customerA, http.MethodPost, "/api/v1/platform/orders", submitBody, idem)
	if w.Code != http.StatusCreated {
		t.Fatalf("submit=%d body=%s", w.Code, w.Body.String())
	}
	var order struct {
		Data struct {
			ID            string `json:"id"`
			PaymentStatus string `json:"payment_status"`
			Type          string `json:"order_type"`
		} `json:"data"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &order); err != nil || order.Data.PaymentStatus != "not_collected" || order.Data.Type != "platform_order" {
		t.Fatalf("order=%+v err=%v", order, err)
	}
	var supplySnapshot sql.NullInt64
	var supplyCurrency sql.NullString
	if err := db.QueryRow(`SELECT partner_supply_price_minor,partner_supply_currency FROM platform_customer_order_items WHERE order_id=$1`, order.Data.ID).Scan(&supplySnapshot, &supplyCurrency); err != nil {
		t.Fatal(err)
	}
	if !supplySnapshot.Valid || supplySnapshot.Int64 != 7000 || !supplyCurrency.Valid || strings.TrimSpace(supplyCurrency.String) != "INR" {
		t.Fatalf("order-time partner supply snapshot=%v %q, want 7000 INR", supplySnapshot, supplyCurrency.String)
	}
	w = request(customerA, http.MethodPost, "/api/v1/platform/orders", submitBody, idem)
	var replay struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
		Meta struct {
			Replay bool `json:"idempotent_replay"`
		} `json:"meta"`
	}
	if w.Code != http.StatusOK || json.Unmarshal(w.Body.Bytes(), &replay) != nil || !replay.Meta.Replay || replay.Data.ID != order.Data.ID {
		t.Fatalf("idempotent replay=%d %s", w.Code, w.Body.String())
	}
	var partnerAssignmentEvents, customerPlacementEvents int
	if err := db.Get(&partnerAssignmentEvents, `SELECT count(*) FROM notifications WHERE business_id=$1 AND event_type='platform.order.assigned' AND payload->>'order_id'=$2`, businessA, order.Data.ID); err != nil || partnerAssignmentEvents != 1 {
		t.Fatalf("partner assignment notifications=%d err=%v, want one", partnerAssignmentEvents, err)
	}
	if err := db.Get(&customerPlacementEvents, `SELECT count(*) FROM notifications WHERE user_id=$1 AND event_type='order.status' AND payload->>'order_id'=$2`, customerA, order.Data.ID); err != nil || customerPlacementEvents != 1 {
		t.Fatalf("customer placement notifications=%d err=%v, want one", customerPlacementEvents, err)
	}
	if mismatch := request(customerA, http.MethodPost, "/api/v1/platform/orders", `{"quote_id":"`+quote.Data.QuoteID+`","notes":"changed request"}`, idem); mismatch.Code != http.StatusConflict {
		t.Fatalf("idempotency key reused with changed request=%d body=%s", mismatch.Code, mismatch.Body.String())
	}
	if err := db.Get(&stock, `SELECT available_quantity FROM platform_partner_product_mappings WHERE id=$1`, mappingID); err != nil || stock != 0 {
		t.Fatalf("submit stock=%d err=%v", stock, err)
	}
	w = request(customerA, http.MethodGet, "/api/v1/orders/"+order.Data.ID, "", "")
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), "QA Test Meal") || !strings.Contains(w.Body.String(), "platform_catalog") {
		t.Fatalf("platform order details=%d %s", w.Code, w.Body.String())
	}
	w = request(customerB, http.MethodPost, "/api/v1/orders/"+order.Data.ID+"/cancel", "{}", "")
	if w.Code != http.StatusNotFound {
		t.Fatalf("cross-customer cancel=%d %s", w.Code, w.Body.String())
	}
	w = request(customerA, http.MethodPost, "/api/v1/orders/"+order.Data.ID+"/cancel", "{}", "")
	if w.Code != http.StatusOK {
		t.Fatalf("cancel=%d %s", w.Code, w.Body.String())
	}
	if err := db.Get(&stock, `SELECT available_quantity FROM platform_partner_product_mappings WHERE id=$1`, mappingID); err != nil || stock != 1 {
		t.Fatalf("cancel did not restore stock=%d err=%v", stock, err)
	}
	// Two customers can receive quotes for the last unit, but only one order may reserve it.
	addressB := createAddress(customerB)
	wA := request(customerA, http.MethodPost, "/api/v1/platform/orders/quote", quoteBody(addressID), "")
	wB := request(customerB, http.MethodPost, "/api/v1/platform/orders/quote", quoteBody(addressB), "")
	if wA.Code != http.StatusCreated || wB.Code != http.StatusCreated {
		t.Fatalf("concurrent quote statuses=%d,%d bodies=%s %s", wA.Code, wB.Code, wA.Body.String(), wB.Body.String())
	}
	var qa, qb struct {
		Data struct {
			QuoteID string `json:"quote_id"`
		} `json:"data"`
	}
	if json.Unmarshal(wA.Body.Bytes(), &qa) != nil || json.Unmarshal(wB.Body.Bytes(), &qb) != nil {
		t.Fatal("could not decode concurrent quotes")
	}
	results := make(chan int, 2)
	for _, entry := range []struct{ customer, quote string }{{customerA, qa.Data.QuoteID}, {customerB, qb.Data.QuoteID}} {
		go func(customer, quote string) {
			result := request(customer, http.MethodPost, "/api/v1/platform/orders", `{"quote_id":"`+quote+`"}`, uuid.NewString())
			results <- result.Code
		}(entry.customer, entry.quote)
	}
	first, second := <-results, <-results
	if !((first == http.StatusCreated && second == http.StatusConflict) || (second == http.StatusCreated && first == http.StatusConflict)) {
		t.Fatalf("last-unit concurrent submit statuses=%d,%d; only one may reserve", first, second)
	}
	if err := db.Get(&stock, `SELECT available_quantity FROM platform_partner_product_mappings WHERE id=$1`, mappingID); err != nil || stock != 0 {
		t.Fatalf("concurrent stock=%d err=%v", stock, err)
	}
	// Jajpur/Chhatia is a distinct stable locality and can map to its own partner.
	chhatiaID := "02200000-0000-4000-8000-000000000201"
	var groceryCategory string
	if err := db.Get(&groceryCategory, `SELECT id::text FROM platform_catalog_categories WHERE vertical='grocery' AND is_system`); err != nil {
		t.Fatal(err)
	}
	var businessJajpur string
	if err := db.Get(&businessJajpur, `SELECT id::text FROM businesses WHERE city='Jajpur' LIMIT 1`); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`UPDATE businesses SET delivery_enabled=true WHERE id=$1`, businessJajpur); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO business_hours(business_id,weekday,opens_at,closes_at,is_closed) VALUES($1,$2,'00:00','23:59',false) ON CONFLICT (business_id,weekday) DO UPDATE SET opens_at=EXCLUDED.opens_at,closes_at=EXCLUDED.closes_at,is_closed=false`, businessJajpur, weekday); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO platform_partner_delivery_localities(business_id,locality_id,is_active) VALUES($1,$2,true)`, businessJajpur, chhatiaID); err != nil {
		t.Fatal(err)
	}
	groceryProduct, groceryVariant := uuid.NewString(), uuid.NewString()
	if _, err := db.Exec(`INSERT INTO platform_catalog_products(id,sku,category_id,name,status) VALUES($1,$2,$3,'QA Test Grocery','active')`, groceryProduct, "INTEGRATION-GROCERY-"+strings.ReplaceAll(groceryProduct, "-", ""), groceryCategory); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO platform_catalog_variants(id,product_id,sku,name,unit_label,price_minor,currency) VALUES($1,$2,$3,'1 kg','1 kg',8500,'INR')`, groceryVariant, groceryProduct, "INTEGRATION-GROCERY-VARIANT-"+strings.ReplaceAll(groceryVariant, "-", "")); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO platform_catalog_product_district_visibility(product_id,district_id) VALUES($1,'02200000-0000-4000-8000-000000000002')`, groceryProduct); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO platform_catalog_product_delivery_localities(product_id,locality_id) VALUES($1,$2)`, groceryProduct, chhatiaID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO platform_partner_product_mappings(business_id,variant_id,status,inventory_mode,available_quantity,created_by,updated_by,approved_by,approved_at) VALUES($1,$2,'approved','untracked',NULL,$3,$3,$3,now())`, businessJajpur, groceryVariant, ownerA); err != nil {
		t.Fatal(err)
	}
	chhatiaAddress := uuid.NewString()
	if _, err := db.Exec(`INSERT INTO customer_addresses(id,customer_user_id,label,recipient_name,address_line1,locality,delivery_locality_id,landmark,city,state,postal_code,contact_phone,is_default) VALUES($1,$2,'Home','Test Customer','14 Main Road','Chhatia',$3,'Near Market','Jajpur','Odisha','755026','+919876543210',true)`, chhatiaAddress, customerB, chhatiaID); err != nil {
		t.Fatal(err)
	}
	groceryQuote := request(customerB, http.MethodPost, "/api/v1/platform/orders/quote", `{"vertical":"grocery","address_id":"`+chhatiaAddress+`","items":[{"variant_id":"`+groceryVariant+`","quantity":1}]}`, "")
	if groceryQuote.Code != http.StatusCreated || !strings.Contains(groceryQuote.Body.String(), businessJajpur) || !strings.Contains(groceryQuote.Body.String(), "QA Test Grocery") || strings.Contains(groceryQuote.Body.String(), "supply_price_minor") {
		t.Fatalf("Jajpur Grocery quote=%d %s", groceryQuote.Code, groceryQuote.Body.String())
	}
}

func TestPlatformCatalogMediaUploadRequiresAdmin(t *testing.T) {
	logger.Init("error")
	db, owner, _, customer, _, _, _, _, _, _, _ := newAPISecurityFixture(t)
	admin := uuid.NewString()
	if _, err := db.Exec(`INSERT INTO users(id,phone_e164) VALUES($1,$2)`, admin, "+919900000099"); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO user_roles(user_id,role) VALUES($1,'admin')`, admin); err != nil {
		t.Fatal(err)
	}
	cfg := &config.Config{Env: "test", JWTSecret: "integration-test-secret-with-over-32-characters", S3Endpoint: "http://127.0.0.1:9000", S3AccessKey: "test", S3SecretKey: "test", S3Bucket: "media-test"}
	authSvc := auth.NewService(db, cfg)
	mediaSvc, err := media.NewService(db, cfg)
	if err != nil {
		t.Fatal(err)
	}
	router := setupRouter(authSvc, discovery.NewService(db, cfg), moderation.NewService(db, cfg), mediaSvc, notifications.NewHub(db.DB), operations.NewService(db), platformcommerce.NewService(db))
	token := func(subject string) string {
		t.Helper()
		value, err := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.RegisteredClaims{Subject: subject, Issuer: "grepmind-near", IssuedAt: jwt.NewNumericDate(time.Now()), ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour))}).SignedString([]byte(cfg.JWTSecret))
		if err != nil {
			t.Fatal(err)
		}
		return value
	}
	request := func(bearer, purpose string) *httptest.ResponseRecorder {
		t.Helper()
		var body bytes.Buffer
		form := multipart.NewWriter(&body)
		if err := form.WriteField("purpose", purpose); err != nil {
			t.Fatal(err)
		}
		if err := form.Close(); err != nil {
			t.Fatal(err)
		}
		req := httptest.NewRequest(http.MethodPost, "/api/v1/media/upload", &body)
		req.Header.Set("Content-Type", form.FormDataContentType())
		if bearer != "" {
			req.Header.Set("Authorization", "Bearer "+bearer)
		}
		response := httptest.NewRecorder()
		router.ServeHTTP(response, req)
		return response
	}
	if got := request("", "platform-catalog").Code; got != http.StatusUnauthorized {
		t.Fatalf("anonymous platform-catalog upload status=%d, want 401", got)
	}
	if got := request(token(customer), "platform-catalog").Code; got != http.StatusForbidden {
		t.Fatalf("customer platform-catalog upload status=%d, want 403", got)
	}
	if got := request(token(owner), "platform-catalog").Code; got != http.StatusForbidden {
		t.Fatalf("merchant platform-catalog upload status=%d, want 403", got)
	}
	if got := request(token(owner), "product").Code; got != http.StatusBadRequest {
		t.Fatalf("merchant product upload should pass role check and fail only for missing file; status=%d, want 400", got)
	}
	if got := request(token(admin), "platform-catalog").Code; got != http.StatusBadRequest {
		t.Fatalf("admin platform-catalog upload should pass role check and fail only for missing file; status=%d, want 400", got)
	}
}

func TestAdminUserAccessRoleBoundaries(t *testing.T) {
	db, _, memberA, _, _, _, _, _, _, _, _ := newAPISecurityFixture(t)
	cfg := &config.Config{Env: "test", JWTSecret: "integration-test-secret-with-over-32-characters"}
	authSvc := auth.NewService(db, cfg)
	dispatchSvc := deliverydispatch.NewService(db, nil, cfg)
	router := setupRouter(authSvc, discovery.NewService(db, cfg), moderation.NewService(db, cfg), nil, notifications.NewHub(db.DB), operations.NewService(db), platformcommerce.NewService(db), dispatchSvc)
	token := func(subject string) string {
		t.Helper()
		tok, err := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.RegisteredClaims{
			Subject: subject, Issuer: "grepmind-near", IssuedAt: jwt.NewNumericDate(time.Now()),
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour)),
		}).SignedString([]byte(cfg.JWTSecret))
		if err != nil {
			t.Fatal(err)
		}
		return tok
	}
	rootID, targetID := uuid.NewString(), uuid.NewString()
	if _, err := db.Exec(`INSERT INTO users(id,phone_e164,display_name) VALUES($1,$2,'Primary Superadmin')`, rootID, "+910000000000"); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO user_roles(user_id,role) VALUES($1,'admin'),($2,'admin')`, rootID, memberA); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO users(id,phone_e164,display_name) VALUES($1,'+919876543212','Role target')`, targetID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO user_roles(user_id,role) VALUES($1,'customer')`, targetID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO sessions(id,user_id,refresh_token_hash,expires_at) VALUES($1,$2,'hash',now()+interval '1 day')`, uuid.NewString(), targetID); err != nil {
		t.Fatal(err)
	}
	request := func(method, path, bearer, body string) *httptest.ResponseRecorder {
		t.Helper()
		req := httptest.NewRequest(method, path, strings.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+bearer)
		res := httptest.NewRecorder()
		router.ServeHTTP(res, req)
		return res
	}
	rootToken, adminToken := token(rootID), token(memberA)
	rootList := request(http.MethodGet, "/api/v1/admin/user-access", rootToken, "")
	if rootList.Code != http.StatusOK || !strings.Contains(rootList.Body.String(), `"can_manage_roles":true`) {
		t.Fatalf("root role directory status=%d response=%s", rootList.Code, rootList.Body.String())
	}
	adminList := request(http.MethodGet, "/api/v1/admin/user-access", adminToken, "")
	if adminList.Code != http.StatusOK || !strings.Contains(adminList.Body.String(), `"can_manage_roles":false`) {
		t.Fatalf("admin role directory status=%d response=%s", adminList.Code, adminList.Body.String())
	}
	if got := request(http.MethodPost, "/api/v1/admin/user-access", adminToken, `{"phone_e164":"+919876543212","roles":["admin"]}`); got.Code != http.StatusForbidden {
		t.Fatalf("non-root role change status=%d, want 403", got.Code)
	}
	if got := request(http.MethodPost, "/api/v1/admin/user-access", rootToken, `{"phone_e164":"+910000000000","roles":["customer"]}`); got.Code != http.StatusForbidden {
		t.Fatalf("root account role change status=%d, want 403", got.Code)
	}
	updated := request(http.MethodPost, "/api/v1/admin/user-access", rootToken, `{"phone_e164":"+919876543212","display_name":"Role target","roles":["customer","merchant"]}`)
	if updated.Code != http.StatusOK || !strings.Contains(updated.Body.String(), `"merchant"`) {
		t.Fatalf("root role update status=%d response=%s", updated.Code, updated.Body.String())
	}
	var roles int
	if err := db.Get(&roles, `SELECT count(*) FROM user_roles WHERE user_id=$1 AND role IN ('customer','merchant')`, targetID); err != nil || roles != 2 {
		t.Fatalf("assigned roles=%d err=%v, want customer+merchant", roles, err)
	}
	var revoked bool
	if err := db.Get(&revoked, `SELECT revoked_at IS NOT NULL FROM sessions WHERE user_id=$1`, targetID); err != nil || !revoked {
		t.Fatalf("target session revoked=%v err=%v", revoked, err)
	}
	operatorGrant := request(http.MethodPost, "/api/v1/admin/user-access", rootToken, `{"phone_e164":"+919876543212","display_name":"Recovery operator","roles":["admin","delivery_operator"]}`)
	if operatorGrant.Code != http.StatusOK || !strings.Contains(operatorGrant.Body.String(), `"delivery_operator"`) {
		t.Fatalf("root could not grant delivery operator role: HTTP %d %s", operatorGrant.Code, operatorGrant.Body.String())
	}
	if got := request(http.MethodGet, "/api/v1/admin/delivery-recovery-cases", adminToken, ""); got.Code != http.StatusForbidden {
		t.Fatalf("ordinary Admin accessed delivery recovery queue: HTTP %d %s", got.Code, got.Body.String())
	}
	if got := request(http.MethodGet, "/api/v1/admin/delivery-operations/alerts", adminToken, ""); got.Code != http.StatusForbidden {
		t.Fatalf("ordinary Admin accessed delivery operations alerts: HTTP %d %s", got.Code, got.Body.String())
	}
	resolvePath := "/api/v1/admin/delivery-jobs/" + uuid.NewString() + "/exceptions/" + uuid.NewString() + "/resolve"
	resolveReq := func(bearer string) *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodPost, resolvePath, strings.NewReader(`{"action":"require_return","reason":"Reviewed custody evidence and require partner return."}`))
		req.Header.Set("Authorization", "Bearer "+bearer)
		req.Header.Set("Idempotency-Key", "qa-denied-resolve-01")
		res := httptest.NewRecorder()
		router.ServeHTTP(res, req)
		return res
	}
	if got := resolveReq(adminToken); got.Code != http.StatusForbidden {
		t.Fatalf("ordinary Admin resolved delivery exception without delivery_operator permission: HTTP %d %s", got.Code, got.Body.String())
	}
	if got := resolveReq(token(targetID)); got.Code != http.StatusServiceUnavailable || !strings.Contains(got.Body.String(), "DISPATCH_DISABLED") {
		t.Fatalf("delivery operator should pass route authorization before feature gate: HTTP %d %s", got.Code, got.Body.String())
	}
	operatorQueue := request(http.MethodGet, "/api/v1/admin/delivery-recovery-cases", token(targetID), "")
	if operatorQueue.Code != http.StatusServiceUnavailable || !strings.Contains(operatorQueue.Body.String(), "DISPATCH_DISABLED") {
		t.Fatalf("delivery operator should pass role gate and reach disabled feature response: HTTP %d %s", operatorQueue.Code, operatorQueue.Body.String())
	}
	operatorAlerts := request(http.MethodGet, "/api/v1/admin/delivery-operations/alerts", token(targetID), "")
	if operatorAlerts.Code != http.StatusServiceUnavailable || !strings.Contains(operatorAlerts.Body.String(), "DISPATCH_DISABLED") {
		t.Fatalf("delivery operator should pass role gate and reach disabled alerts response: HTTP %d %s", operatorAlerts.Code, operatorAlerts.Body.String())
	}
	if _, err := db.Exec(`UPDATE users SET status='suspended' WHERE id=$1`, targetID); err != nil {
		t.Fatal(err)
	}
	if inactiveQueue := request(http.MethodGet, "/api/v1/admin/delivery-recovery-cases", token(targetID), ""); inactiveQueue.Code != http.StatusForbidden {
		t.Fatalf("suspended delivery operator retained recovery access: HTTP %d %s", inactiveQueue.Code, inactiveQueue.Body.String())
	}
	rootQueue := request(http.MethodGet, "/api/v1/admin/delivery-recovery-cases", rootToken, "")
	if rootQueue.Code != http.StatusServiceUnavailable || !strings.Contains(rootQueue.Body.String(), "DISPATCH_DISABLED") {
		t.Fatalf("primary superadmin should bypass operator role requirement: HTTP %d %s", rootQueue.Code, rootQueue.Body.String())
	}
}

func newAPISecurityFixture(t *testing.T) (*database.DB, string, string, string, string, string, string, string, string, string, string) {
	t.Helper()
	dsn := os.Getenv("GREPMIND_TEST_DATABASE_URL")
	if dsn == "" {
		dsn = os.Getenv("TEST_DATABASE_URL")
	}
	if dsn == "" {
		t.Skip("set GREPMIND_TEST_DATABASE_URL to run API authorization integration tests")
	}
	admin, err := sqlx.Open("pgx", dsn)
	if err != nil {
		t.Fatal(err)
	}
	if err = admin.Ping(); err != nil {
		admin.Close()
		t.Fatal(err)
	}
	schema := "api_security_" + strings.ReplaceAll(uuid.NewString(), "-", "")
	if _, err = admin.Exec(`CREATE SCHEMA ` + schema); err != nil {
		admin.Close()
		t.Fatal(err)
	}
	parsed, err := url.Parse(dsn)
	if err != nil {
		t.Fatal(err)
	}
	query := parsed.Query()
	query.Set("search_path", schema+",public")
	parsed.RawQuery = query.Encode()
	raw, err := sqlx.Open("pgx", parsed.String())
	if err != nil {
		t.Fatal(err)
	}
	if err = raw.Ping(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = raw.Close(); _, _ = admin.Exec(`DROP SCHEMA ` + schema + ` CASCADE`); _ = admin.Close() })
	for _, ddl := range []string{
		`CREATE TABLE users(id UUID PRIMARY KEY DEFAULT gen_random_uuid(), phone_e164 TEXT NOT NULL UNIQUE, display_name TEXT, avatar_url TEXT, status TEXT NOT NULL DEFAULT 'active', preferred_language TEXT NOT NULL DEFAULT 'en', notification_preferences JSONB NOT NULL DEFAULT '{"booking_updates":true,"offers":true,"service_updates":true}'::jsonb, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now())`,
		`CREATE TABLE sessions(id UUID PRIMARY KEY DEFAULT gen_random_uuid(), user_id UUID NOT NULL, refresh_token_hash TEXT NOT NULL, expires_at TIMESTAMPTZ NOT NULL, revoked_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now())`,
		`CREATE TABLE media_uploads(id UUID PRIMARY KEY DEFAULT gen_random_uuid(), user_id UUID, purpose TEXT NOT NULL, object_key TEXT NOT NULL)`,
		`CREATE TABLE user_roles(user_id UUID NOT NULL, role TEXT NOT NULL)`,
		`CREATE TABLE categories(slug TEXT PRIMARY KEY, name TEXT NOT NULL, is_active BOOLEAN NOT NULL DEFAULT true)`,
		`CREATE TABLE audit_logs(id UUID PRIMARY KEY DEFAULT gen_random_uuid(), actor_user_id UUID, action TEXT NOT NULL, target_type TEXT NOT NULL, target_id UUID NOT NULL, reason TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now())`,
		`CREATE TABLE businesses(id UUID PRIMARY KEY, owner_user_id UUID NOT NULL, name TEXT NOT NULL, slug TEXT, description TEXT, category_slug TEXT NOT NULL, address_text TEXT NOT NULL, locality TEXT, city TEXT, postal_code TEXT, phone_e164 TEXT, whatsapp_e164 TEXT, cover_photo_url TEXT, location GEOGRAPHY(POINT,4326), status TEXT NOT NULL, verification_status TEXT NOT NULL, delivery_enabled BOOLEAN NOT NULL DEFAULT false, delivery_fee NUMERIC(12,2) NOT NULL DEFAULT 0, min_order_amount NUMERIC(12,2) NOT NULL DEFAULT 0, delivery_time_mins INT NOT NULL DEFAULT 30, table_booking_enabled BOOLEAN NOT NULL DEFAULT false, room_booking_enabled BOOLEAN NOT NULL DEFAULT false, time_zone TEXT NOT NULL DEFAULT 'Asia/Kolkata', created_at TIMESTAMPTZ NOT NULL DEFAULT now())`,
		`CREATE TABLE merchant_view_events(business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE, view_type TEXT NOT NULL CHECK(view_type IN ('profile','catalog')), view_date DATE NOT NULL, viewer_fingerprint BYTEA NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY(business_id,view_type,view_date,viewer_fingerprint))`,
		`CREATE TABLE business_members(id UUID PRIMARY KEY DEFAULT gen_random_uuid(), business_id UUID NOT NULL, user_id UUID NOT NULL, role TEXT NOT NULL DEFAULT 'staff', status TEXT NOT NULL)`,
		`CREATE TABLE business_hours(id UUID PRIMARY KEY DEFAULT gen_random_uuid(), business_id UUID NOT NULL, weekday SMALLINT NOT NULL, opens_at TIME, closes_at TIME, is_closed BOOLEAN NOT NULL, UNIQUE(business_id,weekday))`,
		`CREATE TABLE business_hour_exceptions(id UUID PRIMARY KEY DEFAULT gen_random_uuid(), business_id UUID NOT NULL, local_date DATE NOT NULL, is_closed BOOLEAN NOT NULL DEFAULT false, opens_at TIME, closes_at TIME, UNIQUE(business_id,local_date))`,
		`CREATE TABLE products(id UUID PRIMARY KEY DEFAULT gen_random_uuid(), business_id UUID NOT NULL, name TEXT NOT NULL, description TEXT, price NUMERIC(12,2), currency CHAR(3) NOT NULL DEFAULT 'INR', stock_status TEXT NOT NULL DEFAULT 'unknown', inventory_mode TEXT NOT NULL DEFAULT 'untracked', available_quantity INT, dietary_type TEXT, unit_label TEXT, mrp NUMERIC(12,2), barcode TEXT, grocery_category TEXT, is_published BOOLEAN NOT NULL DEFAULT false, image_url TEXT, updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), published_at TIMESTAMPTZ)`,
		`CREATE TABLE services(id UUID PRIMARY KEY, business_id UUID, name TEXT, description TEXT, indicative_price_min NUMERIC, indicative_price_max NUMERIC, currency CHAR(3) NOT NULL DEFAULT 'INR', is_active BOOLEAN NOT NULL DEFAULT true, activated_at TIMESTAMPTZ)`,
		`CREATE TABLE service_requests(id UUID PRIMARY KEY DEFAULT gen_random_uuid(), customer_user_id UUID NOT NULL, business_id UUID NOT NULL, service_id UUID, slot_id UUID, description TEXT, requested_for TIMESTAMPTZ, status TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now())`,
		`CREATE TABLE service_request_events(id UUID PRIMARY KEY DEFAULT gen_random_uuid(), request_id UUID, status TEXT, actor_user_id UUID, created_at TIMESTAMPTZ DEFAULT now())`,
		`CREATE TABLE availability_slots(id UUID PRIMARY KEY, business_id UUID NOT NULL, starts_at TIMESTAMPTZ NOT NULL, ends_at TIMESTAMPTZ NOT NULL, capacity INT NOT NULL, booked_count INT NOT NULL DEFAULT 0, status TEXT NOT NULL, updated_at TIMESTAMPTZ DEFAULT now())`,
		`CREATE TABLE business_availability_exceptions(id UUID PRIMARY KEY DEFAULT gen_random_uuid(), business_id UUID NOT NULL, local_date DATE NOT NULL, is_closed BOOLEAN NOT NULL DEFAULT false, opens_at TIME, closes_at TIME, note TEXT NOT NULL DEFAULT '', created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), UNIQUE(business_id,local_date))`,
		`CREATE TABLE professional_profiles(business_id UUID PRIMARY KEY, accepts_requests BOOLEAN NOT NULL DEFAULT false, service_radius_m INT NOT NULL DEFAULT 5000, experience_years INT, service_description TEXT)`,
		`CREATE TABLE offers(id UUID PRIMARY KEY DEFAULT gen_random_uuid(), business_id UUID NOT NULL, status TEXT NOT NULL DEFAULT 'draft', starts_at TIMESTAMPTZ NOT NULL DEFAULT now(), ends_at TIMESTAMPTZ NOT NULL DEFAULT now())`,
		`CREATE TABLE notifications(id UUID PRIMARY KEY DEFAULT gen_random_uuid(), user_id UUID, business_id UUID, title TEXT NOT NULL, body TEXT NOT NULL, event_type TEXT NOT NULL, reference_id TEXT, payload JSONB, is_read BOOLEAN NOT NULL DEFAULT false, created_at TIMESTAMPTZ NOT NULL DEFAULT now())`,
		`CREATE TABLE reports(id UUID PRIMARY KEY DEFAULT gen_random_uuid(), reporter_user_id UUID, target_type TEXT NOT NULL, target_id UUID NOT NULL, reason TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'open', created_at TIMESTAMPTZ NOT NULL DEFAULT now(), resolved_at TIMESTAMPTZ, resolution_reason TEXT)`,
		`CREATE TABLE customer_addresses(id UUID PRIMARY KEY DEFAULT gen_random_uuid(), customer_user_id UUID NOT NULL, label TEXT NOT NULL, recipient_name TEXT NOT NULL, address_line1 TEXT NOT NULL, locality TEXT NOT NULL, landmark TEXT NOT NULL DEFAULT '', city TEXT NOT NULL, state TEXT NOT NULL, postal_code TEXT NOT NULL, contact_phone TEXT NOT NULL, location GEOGRAPHY(POINT,4326), is_default BOOLEAN NOT NULL DEFAULT false, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now())`,
		`CREATE TABLE customer_orders(id UUID PRIMARY KEY, customer_user_id UUID NOT NULL, business_id UUID NOT NULL, order_type TEXT NOT NULL CHECK(order_type IN ('food_delivery','table_reservation','hotel_booking')), status TEXT NOT NULL CHECK(status IN ('placed','confirmed','preparing','out_for_delivery','delivered','completed','cancelled')), fulfillment_type TEXT, delivery_address TEXT, delivery_address_id UUID REFERENCES customer_addresses(id) ON DELETE SET NULL, delivery_address_snapshot JSONB, checkout_quote_id UUID, checkout_idempotency_key UUID, checkout_request_hash TEXT, payment_status TEXT NOT NULL DEFAULT 'not_collected', customer_notes TEXT, item_total NUMERIC NOT NULL, delivery_fee NUMERIC NOT NULL, tax_amount NUMERIC NOT NULL, grand_total NUMERIC NOT NULL, currency CHAR(3) NOT NULL DEFAULT 'INR', eta_minutes INT, reservation_at TIMESTAMPTZ, reservation_end_at TIMESTAMPTZ, guest_count INT, seating_area TEXT, room_product_id UUID, reference_code TEXT NOT NULL, cancelled_at TIMESTAMPTZ, created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now())`,
		`CREATE TABLE customer_order_items(order_id UUID, product_id UUID, product_name TEXT, unit_price NUMERIC, quantity INT, dietary_type TEXT)`,
		`CREATE TABLE customer_order_status_events(id UUID PRIMARY KEY DEFAULT gen_random_uuid(), order_id UUID NOT NULL REFERENCES customer_orders(id) ON DELETE CASCADE, status TEXT NOT NULL CHECK(status IN ('placed','confirmed','preparing','out_for_delivery','delivered','completed','cancelled')), event_kind TEXT NOT NULL DEFAULT 'status_change' CHECK(event_kind IN ('status_change','history_snapshot')), actor_user_id UUID, created_at TIMESTAMPTZ NOT NULL DEFAULT now())`,
		`CREATE TABLE checkout_quotes(id UUID PRIMARY KEY, customer_user_id UUID NOT NULL, business_id UUID NOT NULL, fulfillment_type TEXT NOT NULL, address_id UUID REFERENCES customer_addresses(id) ON DELETE CASCADE, address_updated_at TIMESTAMPTZ, items JSONB NOT NULL, item_subtotal_minor BIGINT NOT NULL, minimum_order_minor BIGINT NOT NULL, delivery_fee_minor BIGINT NOT NULL, tax_minor BIGINT NOT NULL, grand_total_minor BIGINT NOT NULL, currency CHAR(3) NOT NULL DEFAULT 'INR', serviceability_method TEXT, expires_at TIMESTAMPTZ NOT NULL, consumed_order_id UUID, created_at TIMESTAMPTZ NOT NULL DEFAULT now())`,
		`ALTER TABLE customer_orders ADD CONSTRAINT customer_orders_checkout_quote_fk FOREIGN KEY(checkout_quote_id) REFERENCES checkout_quotes(id) ON DELETE SET NULL`,
		`CREATE UNIQUE INDEX customer_orders_checkout_quote_uidx ON customer_orders(checkout_quote_id) WHERE checkout_quote_id IS NOT NULL`,
		`ALTER TABLE checkout_quotes ADD CONSTRAINT checkout_quotes_consumed_order_fk FOREIGN KEY(consumed_order_id) REFERENCES customer_orders(id) ON DELETE SET NULL`,
	} {
		if _, err := raw.Exec(ddl); err != nil {
			t.Fatalf("create isolated fixture: %v", err)
		}
	}
	for _, migration := range []string{"021_platform_catalog.sql", "022_delivery_locality_hierarchy.sql", "023_platform_cart_checkout.sql", "024_platform_partner_fulfillment.sql", "025_rider_onboarding.sql", "050_merchant_product_gst.sql"} {
		migrationSQL, err := os.ReadFile("../../migrations/" + migration)
		if err != nil {
			t.Fatalf("read %s: %v", migration, err)
		}
		if migration == "024_platform_partner_fulfillment.sql" || migration == "025_rider_onboarding.sql" {
			if _, err := raw.Exec(string(migrationSQL)); err != nil {
				t.Fatalf("apply %s to isolated fixture: %v", migration, err)
			}
			continue
		}
		for _, statement := range splitMigrationStatements(string(migrationSQL)) {
			statement = strings.TrimSpace(statement)
			if statement == "" {
				continue
			}
			if _, err := raw.Exec(statement); err != nil {
				t.Fatalf("apply %s to isolated fixture: %v\nSQL: %s", migration, err, statement)
			}
		}
	}
	ownerA, memberA, customerA, customerB := uuid.NewString(), uuid.NewString(), uuid.NewString(), uuid.NewString()
	businessA, businessB := uuid.NewString(), uuid.NewString()
	productB, requestB, notificationB, orderB := uuid.NewString(), uuid.NewString(), uuid.NewString(), uuid.NewString()
	for _, u := range []string{ownerA, memberA, customerA, customerB} {
		if _, err := raw.Exec(`INSERT INTO users(id,phone_e164) VALUES($1,$2)`, u, "+1"+strings.ReplaceAll(u[:12], "-", "")); err != nil {
			t.Fatal(err)
		}
	}
	_, _ = raw.Exec(`INSERT INTO categories(slug,name) VALUES('general','General')`)
	_, err = raw.Exec(`INSERT INTO user_roles(user_id,role) VALUES($1,'merchant')`, ownerA)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := raw.Exec(`INSERT INTO user_roles(user_id,role) VALUES($1,'customer'),($2,'customer')`, customerA, customerB); err != nil {
		t.Fatal(err)
	}
	_, err = raw.Exec(`INSERT INTO businesses(id,owner_user_id,name,slug,description,category_slug,address_text,city,phone_e164,cover_photo_url,location,status,verification_status) VALUES($1,$2,'A','business-a','Test business','general','A','Cuttack','+919876543210','https://assets.example/storefront.jpg',ST_SetSRID(ST_MakePoint(85.9,20.5),4326)::geography,'approved','verified'),($3,$4,'B','business-b','Test business','general','B','Jajpur','+919876543211',NULL,ST_SetSRID(ST_MakePoint(86.3,20.8),4326)::geography,'approved','verified')`, businessA, ownerA, businessB, customerB)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := raw.Exec(`INSERT INTO professional_profiles(business_id,accepts_requests) VALUES($1,true)`, businessA); err != nil {
		t.Fatal(err)
	}
	_, err = raw.Exec(`INSERT INTO business_members(business_id,user_id,status) VALUES($1,$2,'active')`, businessA, memberA)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := raw.Exec(`INSERT INTO user_roles(user_id,role) VALUES($1,'merchant')`, memberA); err != nil {
		t.Fatal(err)
	}
	_, err = raw.Exec(`INSERT INTO products(id,business_id,name) VALUES($1,$2,'B product')`, productB, businessB)
	if err != nil {
		t.Fatal(err)
	}
	_, err = raw.Exec(`INSERT INTO service_requests(id,customer_user_id,business_id,description,status) VALUES($1,$2,$3,'Private request','requested')`, requestB, customerB, businessB)
	if err != nil {
		t.Fatal(err)
	}
	_, err = raw.Exec(`INSERT INTO notifications(id,user_id,title,body,event_type) VALUES($1,$2,'Private','Private','test')`, notificationB, customerB)
	if err != nil {
		t.Fatal(err)
	}
	_, err = raw.Exec(`INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,item_total,delivery_fee,tax_amount,grand_total,reference_code) VALUES($1,$2,$3,'food_delivery','placed',1,0,0,1,'REF-B')`, orderB, customerB, businessB)
	if err != nil {
		t.Fatal(err)
	}
	return &database.DB{DB: raw}, ownerA, memberA, customerA, customerB, businessA, businessB, productB, requestB, notificationB, orderB
}

func splitMigrationStatements(source string) []string {
	var executable strings.Builder
	for _, line := range strings.Split(source, "\n") {
		if strings.HasPrefix(strings.TrimSpace(line), "--") {
			continue
		}
		executable.WriteString(line)
		executable.WriteByte('\n')
	}
	return strings.Split(executable.String(), ";")
}

func TestRiderOnboardingApprovalAndImmediateSuspensionRevocation(t *testing.T) {
	logger.Init("error")
	db, adminUser, _, applicant, otherApplicant, _, _, _, _, _, _ := newAPISecurityFixture(t)
	cfg := &config.Config{Env: "test", JWTSecret: "integration-test-secret-with-over-32-characters"}
	if _, err := db.Exec(`INSERT INTO user_roles(user_id,role) VALUES($1,'admin'),($2,'rider'),($2,'admin')`, adminUser, applicant); err != nil {
		t.Fatal(err)
	}
	authSvc := auth.NewService(db, cfg)
	router := setupRouter(authSvc, discovery.NewService(db, cfg), moderation.NewService(db, cfg), nil, notifications.NewHub(db.DB), operations.NewService(db), platformcommerce.NewService(db))
	token := func(subject string) string {
		t.Helper()
		tok, err := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.RegisteredClaims{Subject: subject, Issuer: "grepmind-near", IssuedAt: jwt.NewNumericDate(time.Now()), ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour))}).SignedString([]byte(cfg.JWTSecret))
		if err != nil {
			t.Fatal(err)
		}
		return tok
	}
	request := func(method, path, bearer, body string) *httptest.ResponseRecorder {
		t.Helper()
		req := httptest.NewRequest(method, path, strings.NewReader(body))
		if bearer != "" {
			req.Header.Set("Authorization", "Bearer "+bearer)
		}
		res := httptest.NewRecorder()
		router.ServeHTTP(res, req)
		return res
	}
	adminToken, applicantToken, otherToken := token(adminUser), token(applicant), token(otherApplicant)
	if _, err := db.Exec(`INSERT INTO sessions(user_id,refresh_token_hash,expires_at) VALUES($1,'qa-refresh-hash',now()+interval '1 hour')`, applicant); err != nil {
		t.Fatal(err)
	}
	if got := request("GET", "/api/v1/rider/application", "", ""); got.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous application read=%d", got.Code)
	}
	// A pre-existing rider role does not by itself authorize rider workspace APIs.
	if got := request("GET", "/api/v1/rider/profile", applicantToken, ""); got.Code != http.StatusForbidden {
		t.Fatalf("role-only rider workspace=%d", got.Code)
	}
	locality := "02200000-0000-4000-8000-000000000101"
	secondaryLocality := "02200000-0000-4000-8000-000000000201"
	if got := request("PUT", "/api/v1/rider/application", applicantToken, `{"display_name":"QA Rider","vehicle_type":"bicycle","locality_ids":["02200000-0000-4000-8000-000000000102"]}`); got.Code != http.StatusBadRequest {
		t.Fatalf("planned locality was accepted: %d %s", got.Code, got.Body.String())
	}
	created := request("PUT", "/api/v1/rider/application", applicantToken, `{"display_name":"QA Rider","vehicle_type":"bicycle","vehicle_details":"","locality_ids":["`+locality+`","`+secondaryLocality+`"]}`)
	if created.Code != http.StatusOK {
		t.Fatalf("save draft=%d %s", created.Code, created.Body.String())
	}
	var profileID string
	if err := db.Get(&profileID, `SELECT id::text FROM rider_profiles WHERE user_id=$1`, applicant); err != nil {
		t.Fatal(err)
	}
	var requirementID, documentID string
	if err := db.QueryRow(`INSERT INTO rider_document_requirements(code,label,vehicle_type,is_required,is_active) VALUES('qa_optional','QA optional image','bicycle',false,true) RETURNING id::text`).Scan(&requirementID); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRow(`INSERT INTO rider_documents(rider_profile_id,requirement_id,bucket,object_key,content_type,size_bytes,sha256) VALUES($1,$2,'private-qa','rider-kyc/private-test.jpg','image/jpeg',32,$3) RETURNING id::text`, profileID, requirementID, bytes.Repeat([]byte{1}, 32)).Scan(&documentID); err != nil {
		t.Fatal(err)
	}
	ownDoc := request("GET", "/api/v1/rider/application", applicantToken, "")
	if ownDoc.Code != http.StatusOK || strings.Contains(ownDoc.Body.String(), "object_key") || strings.Contains(ownDoc.Body.String(), "private-qa") || strings.Contains(ownDoc.Body.String(), "/media/") {
		t.Fatalf("private document metadata leaked: %d %s", ownDoc.Code, ownDoc.Body.String())
	}
	if got := request("POST", "/api/v1/admin/rider-documents/"+documentID+"/review", otherToken, `{"status":"accepted"}`); got.Code != http.StatusForbidden {
		t.Fatalf("non-admin document review=%d", got.Code)
	}
	if got := request("POST", "/api/v1/admin/rider-document-requirements", adminToken, `{"code":"qa_policy","label":"QA policy","vehicle_type":"any","is_required":false,"is_active":true}`); got.Code != http.StatusForbidden {
		t.Fatalf("non-primary admin changed rider requirements=%d", got.Code)
	}
	if got := request("GET", "/api/v1/admin/rider-documents/"+documentID+"/content", otherToken, ""); got.Code != http.StatusForbidden {
		t.Fatalf("unauthorized document read=%d", got.Code)
	}
	if got := request("POST", "/api/v1/admin/rider-documents/"+documentID+"/review", adminToken, `{"status":"accepted"}`); got.Code != http.StatusOK {
		t.Fatalf("document acceptance=%d %s", got.Code, got.Body.String())
	}
	if got := request("GET", "/api/v1/rider/application", otherToken, ""); got.Code != http.StatusOK || !strings.Contains(got.Body.String(), `"data":null`) {
		t.Fatalf("other account saw application: %d %s", got.Code, got.Body.String())
	}
	if got := request("POST", "/api/v1/admin/rider-applications/"+profileID+"/review", applicantToken, `{"decision":"approved","approved_locality_ids":["`+locality+`"]}`); got.Code != http.StatusForbidden {
		t.Fatalf("self-approval=%d", got.Code)
	}
	if got := request("POST", "/api/v1/rider/application/submit", applicantToken, `{}`); got.Code != http.StatusOK || !strings.Contains(got.Body.String(), `"status":"submitted"`) {
		t.Fatalf("submit=%d %s", got.Code, got.Body.String())
	}
	if got := request("POST", "/api/v1/rider/application/submit", applicantToken, `{}`); got.Code != http.StatusConflict {
		t.Fatalf("duplicate application submission=%d, want 409", got.Code)
	}
	if got := request("GET", "/api/v1/rider/profile", applicantToken, ""); got.Code != http.StatusForbidden {
		t.Fatalf("pending rider workspace=%d", got.Code)
	}
	if got := request("POST", "/api/v1/admin/rider-applications/"+profileID+"/review", otherToken, `{"decision":"approved","approved_locality_ids":["`+locality+`"]}`); got.Code != http.StatusForbidden {
		t.Fatalf("non-admin approval=%d", got.Code)
	}
	approved := request("POST", "/api/v1/admin/rider-applications/"+profileID+"/review", adminToken, `{"decision":"approved","approved_locality_ids":["`+locality+`"]}`)
	if approved.Code != http.StatusOK {
		t.Fatalf("approval=%d %s", approved.Code, approved.Body.String())
	}
	if got := request("GET", "/api/v1/rider/profile", applicantToken, ""); got.Code != http.StatusOK {
		t.Fatalf("approved rider profile=%d %s", got.Code, got.Body.String())
	}
	var approvedLocalityStatus, omittedLocalityStatus string
	if err := db.QueryRow(`SELECT status FROM rider_profile_localities WHERE rider_profile_id=$1 AND locality_id=$2`, profileID, locality).Scan(&approvedLocalityStatus); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRow(`SELECT status FROM rider_profile_localities WHERE rider_profile_id=$1 AND locality_id=$2`, profileID, secondaryLocality).Scan(&omittedLocalityStatus); err != nil {
		t.Fatal(err)
	}
	if approvedLocalityStatus != "approved" || omittedLocalityStatus != "rejected" {
		t.Fatalf("reviewer locality decision was not explicit: selected=%s omitted=%s", approvedLocalityStatus, omittedLocalityStatus)
	}
	suspended := request("POST", "/api/v1/admin/riders/"+profileID+"/suspend", adminToken, `{"reason":"QA suspension for access-revocation verification"}`)
	if suspended.Code != http.StatusOK {
		t.Fatalf("suspend=%d %s", suspended.Code, suspended.Body.String())
	}
	if got := request("GET", "/api/v1/rider/profile", applicantToken, ""); got.Code != http.StatusForbidden {
		t.Fatalf("same JWT after suspension got=%d", got.Code)
	}
	var revoked, auditCount, eventCount int
	if err := db.Get(&revoked, `SELECT count(*) FROM sessions WHERE user_id=$1 AND revoked_at IS NOT NULL`, applicant); err != nil {
		t.Fatal(err)
	}
	if err := db.Get(&auditCount, `SELECT count(*) FROM audit_logs WHERE target_id=$1 AND action IN ('rider.approved','rider.suspended')`, profileID); err != nil {
		t.Fatal(err)
	}
	if err := db.Get(&eventCount, `SELECT count(*) FROM rider_application_events WHERE rider_profile_id=$1`, profileID); err != nil {
		t.Fatal(err)
	}
	if revoked == 0 || auditCount != 2 || eventCount < 3 {
		t.Fatalf("session revocation/audit/events=%d/%d/%d", revoked, auditCount, eventCount)
	}
	// A deterministic rejection leaves no rider entitlement or workspace access.
	rejectedApplicant := uuid.NewString()
	if _, err := db.Exec(`INSERT INTO users(id,phone_e164) VALUES($1,$2)`, rejectedApplicant, "+919900000099"); err != nil {
		t.Fatal(err)
	}
	rejectedToken := token(rejectedApplicant)
	if got := request("PUT", "/api/v1/rider/application", rejectedToken, `{"display_name":"QA Rejected Rider","vehicle_type":"bicycle","locality_ids":["`+locality+`"]}`); got.Code != http.StatusOK {
		t.Fatalf("rejected fixture draft=%d %s", got.Code, got.Body.String())
	}
	var rejectedProfileID string
	if err := db.Get(&rejectedProfileID, `SELECT id::text FROM rider_profiles WHERE user_id=$1`, rejectedApplicant); err != nil {
		t.Fatal(err)
	}
	if got := request("POST", "/api/v1/rider/application/submit", rejectedToken, `{}`); got.Code != http.StatusOK {
		t.Fatalf("rejected fixture submit=%d %s", got.Code, got.Body.String())
	}
	if got := request("POST", "/api/v1/admin/rider-applications/"+rejectedProfileID+"/review", adminToken, `{"decision":"rejected","reason":"QA verification did not meet the review requirements"}`); got.Code != http.StatusOK {
		t.Fatalf("reject rider application=%d %s", got.Code, got.Body.String())
	}
	if got := request("GET", "/api/v1/rider/profile", rejectedToken, ""); got.Code != http.StatusForbidden {
		t.Fatalf("rejected rider workspace=%d, want 403", got.Code)
	}
	// Concurrent approve/reject must serialize on the application row: one
	// decision wins and the stale competing decision receives a conflict.
	if got := request("PUT", "/api/v1/rider/application", otherToken, `{"display_name":"QA Concurrent Rider","vehicle_type":"bicycle","locality_ids":["`+locality+`"]}`); got.Code != http.StatusOK {
		t.Fatalf("concurrent fixture draft=%d %s", got.Code, got.Body.String())
	}
	var concurrentID string
	if err := db.Get(&concurrentID, `SELECT id::text FROM rider_profiles WHERE user_id=$1`, otherApplicant); err != nil {
		t.Fatal(err)
	}
	if got := request("POST", "/api/v1/rider/application/submit", otherToken, `{}`); got.Code != http.StatusOK {
		t.Fatalf("concurrent fixture submit=%d %s", got.Code, got.Body.String())
	}
	start := make(chan struct{})
	results := make(chan int, 2)
	var wg sync.WaitGroup
	for _, action := range []struct{ token, body string }{{adminToken, `{"decision":"approved","approved_locality_ids":["` + locality + `"]}`}, {applicantToken, `{"decision":"rejected","reason":"QA concurrent rejection decision"}`}} {
		wg.Add(1)
		go func(token, body string) {
			defer wg.Done()
			<-start
			results <- request("POST", "/api/v1/admin/rider-applications/"+concurrentID+"/review", token, body).Code
		}(action.token, action.body)
	}
	close(start)
	wg.Wait()
	close(results)
	success, conflict := 0, 0
	for code := range results {
		if code == http.StatusOK {
			success++
		}
		if code == http.StatusConflict {
			conflict++
		}
	}
	if success != 1 || conflict != 1 {
		t.Fatalf("concurrent review outcomes success/conflict=%d/%d", success, conflict)
	}
}

func TestPlatformFulfillmentIsolationTransitionsRejectionAndNotifications(t *testing.T) {
	logger.Init("error")
	db, owner, member, customer, otherCustomer, business, otherBusiness, _, _, _, _ := newAPISecurityFixture(t)
	cfg := &config.Config{Env: "test", JWTSecret: "integration-test-secret-with-over-32-characters"}
	authSvc := auth.NewService(db, cfg)
	router := setupRouter(authSvc, discovery.NewService(db, cfg), moderation.NewService(db, cfg), nil, notifications.NewHub(db.DB), operations.NewService(db), platformcommerce.NewService(db))
	token := func(subject string) string {
		t.Helper()
		tok, err := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.RegisteredClaims{Subject: subject, Issuer: "grepmind-near", IssuedAt: jwt.NewNumericDate(time.Now()), ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour))}).SignedString([]byte(cfg.JWTSecret))
		if err != nil {
			t.Fatal(err)
		}
		return tok
	}
	request := func(method, path, bearer, body string) *httptest.ResponseRecorder {
		t.Helper()
		req := httptest.NewRequest(method, path, strings.NewReader(body))
		req.Header.Set("Authorization", "Bearer "+bearer)
		res := httptest.NewRecorder()
		router.ServeHTTP(res, req)
		return res
	}
	var categoryID, localityID, productID, variantID, mappingID, addressID string
	if err := db.Get(&categoryID, `SELECT id::text FROM platform_catalog_categories WHERE vertical='food' AND parent_id IS NULL LIMIT 1`); err != nil {
		t.Fatal(err)
	}
	if err := db.Get(&localityID, `SELECT l.id::text FROM platform_delivery_localities l JOIN platform_districts d ON d.id=l.district_id WHERE d.name='Cuttack' AND l.name='Kuanpal'`); err != nil {
		t.Fatal(err)
	}
	productID, variantID, mappingID, addressID = uuid.NewString(), uuid.NewString(), uuid.NewString(), uuid.NewString()
	if _, err := db.Exec(`INSERT INTO platform_catalog_products(id,sku,category_id,name,status) VALUES($1,'QA-FULFILLMENT-SKU',$2,'QA Biryani','active')`, productID, categoryID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO platform_catalog_variants(id,product_id,sku,name,unit_label,price_minor) VALUES($1,$2,'QA-FULFILLMENT-VARIANT','Regular','plate',9900)`, variantID, productID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO platform_partner_product_mappings(id,business_id,variant_id,status,inventory_mode,available_quantity,approved_by,approved_at) VALUES($1,$2,$3,'approved','finite',10,$4,now())`, mappingID, business, variantID, owner); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO customer_addresses(id,customer_user_id,label,recipient_name,address_line1,locality,landmark,city,state,postal_code,contact_phone,is_default,delivery_locality_id) VALUES($1,$2,'QA','QA Customer','QA Test Lane','Kuanpal','','Cuttack','Odisha','753011','+919900000001',true,$3)`, addressID, customer, localityID); err != nil {
		t.Fatal(err)
	}
	createOrder := func(reference string) string {
		t.Helper()
		orderID, quoteID := uuid.NewString(), uuid.NewString()
		if _, err := db.Exec(`INSERT INTO platform_checkout_quotes(id,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,grand_total_minor,expires_at) SELECT $1,$2,'food',$3,current_date,$4,now(),$5,'[{}]'::jsonb,9900,9900,now()+interval '5 minutes'`, quoteID, customer, localityID, addressID, business); err != nil {
			t.Fatal(err)
		}
		if _, err := db.Exec(`INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,fulfillment_type,delivery_address,delivery_address_id,delivery_address_snapshot,platform_checkout_quote_id,payment_status,item_total,delivery_fee,tax_amount,grand_total,reference_code,order_source,platform_vertical,delivery_locality_id) VALUES($1,$2,$3,'platform_order','placed','delivery','QA Test Lane, Kuanpal',$4,'{}'::jsonb,$5,'not_collected',99,0,0,99,$6,'platform_catalog','food',$7)`, orderID, customer, business, addressID, quoteID, reference, localityID); err != nil {
			t.Fatal(err)
		}
		if _, err := db.Exec(`INSERT INTO platform_customer_order_items(order_id,product_id,variant_id,vertical,product_name,variant_name,unit_label,unit_price_minor,quantity,price_revision) VALUES($1,$2,$3,'food','QA Biryani','Regular','plate',9900,1,1)`, orderID, productID, variantID); err != nil {
			t.Fatal(err)
		}
		if _, err := db.Exec(`INSERT INTO platform_inventory_reservations(order_id,mapping_id,quantity,inventory_mode,service_date) VALUES($1,$2,1,'finite',current_date)`, orderID, mappingID); err != nil {
			t.Fatal(err)
		}
		if _, err := db.Exec(`INSERT INTO customer_order_status_events(order_id,status,event_kind,actor_user_id) VALUES($1,'placed','status_change',$2)`, orderID, customer); err != nil {
			t.Fatal(err)
		}
		return orderID
	}
	acceptedOrder := createOrder("QA-FULFILL-ACCEPT")
	rejectedOrder := createOrder("QA-FULFILL-REJECT")
	racingOrder := createOrder("QA-FULFILL-RACE")
	if _, err := db.Exec(`INSERT INTO user_roles(user_id,role) VALUES($1,'merchant') ON CONFLICT DO NOTHING`, otherCustomer); err != nil {
		t.Fatal(err)
	}

	base := "/api/v1/merchant/businesses/" + business + "/platform-orders"
	list := request(http.MethodGet, base, token(member), "")
	if list.Code != 200 || !strings.Contains(list.Body.String(), acceptedOrder) || strings.Contains(list.Body.String(), "customer_phone") || strings.Contains(list.Body.String(), "delivery_address") || strings.Contains(list.Body.String(), "supply_price") || strings.Contains(list.Body.String(), "unit_price_minor") {
		t.Fatalf("assigned order list status=%d body=%s", list.Code, list.Body.String())
	}
	if got := request(http.MethodGet, base, token(customer), ""); got.Code != 403 {
		t.Fatalf("customer listing status=%d, want 403", got.Code)
	}
	otherPath := "/api/v1/merchant/businesses/" + otherBusiness + "/platform-orders/" + acceptedOrder
	if got := request(http.MethodGet, otherPath, token(otherCustomer), ""); got.Code != 404 {
		t.Fatalf("other partner detail status=%d body=%s, want 404", got.Code, got.Body.String())
	}
	if got := request(http.MethodPost, otherPath+"/accept", token(otherCustomer), "{}"); got.Code != 404 {
		t.Fatalf("other partner action status=%d, want 404", got.Code)
	}
	if got := request(http.MethodPost, base+"/"+acceptedOrder+"/accept", token(customer), "{}"); got.Code != 403 {
		t.Fatalf("customer action status=%d, want 403", got.Code)
	}
	if got := request(http.MethodPost, base+"/"+rejectedOrder+"/reject", token(member), `{"reason":"no"}`); got.Code != 400 {
		t.Fatalf("short rejection reason status=%d, want 400", got.Code)
	}

	accept := request(http.MethodPost, base+"/"+acceptedOrder+"/accept", token(owner), "")
	if accept.Code != 200 || !strings.Contains(accept.Body.String(), `"status":"accepted"`) {
		t.Fatalf("accept status=%d body=%s", accept.Code, accept.Body.String())
	}
	acceptReplay := request(http.MethodPost, base+"/"+acceptedOrder+"/accept", token(member), "")
	if acceptReplay.Code != 200 || !strings.Contains(acceptReplay.Body.String(), `"changed":false`) {
		t.Fatalf("accept retry status=%d body=%s", acceptReplay.Code, acceptReplay.Body.String())
	}
	if got := request(http.MethodPatch, "/api/v1/merchant/orders/"+acceptedOrder+"/status", token(owner), `{"status":"ready_for_pickup"}`); got.Code != 409 {
		t.Fatalf("legacy status route platform order status=%d, want 409", got.Code)
	}
	if got := request(http.MethodPost, base+"/"+acceptedOrder+"/prepare", token(member), ""); got.Code != 200 {
		t.Fatalf("prepare status=%d body=%s", got.Code, got.Body.String())
	}
	if got := request(http.MethodPost, base+"/"+acceptedOrder+"/ready", token(member), ""); got.Code != 200 || !strings.Contains(got.Body.String(), `"status":"ready_for_pickup"`) {
		t.Fatalf("ready status=%d body=%s", got.Code, got.Body.String())
	}
	customerDetail := request(http.MethodGet, "/api/v1/orders/"+acceptedOrder, token(customer), "")
	if customerDetail.Code != 200 || !strings.Contains(customerDetail.Body.String(), `"status":"ready_for_pickup"`) {
		t.Fatalf("customer tracking status=%d body=%s", customerDetail.Code, customerDetail.Body.String())
	}
	if got := request(http.MethodPost, base+"/"+acceptedOrder+"/prepare", token(member), ""); got.Code != 409 {
		t.Fatalf("invalid repeated transition status=%d, want 409", got.Code)
	}

	var beforeReject, afterReject, afterRejectRetry int
	if err := db.Get(&beforeReject, `SELECT available_quantity FROM platform_partner_product_mappings WHERE id=$1`, mappingID); err != nil {
		t.Fatal(err)
	}
	reject := request(http.MethodPost, base+"/"+rejectedOrder+"/reject", token(member), `{"reason":"Partner capacity is unavailable today."}`)
	if reject.Code != 200 || !strings.Contains(reject.Body.String(), `"status":"rejected"`) {
		t.Fatalf("reject status=%d body=%s", reject.Code, reject.Body.String())
	}
	if err := db.Get(&afterReject, `SELECT available_quantity FROM platform_partner_product_mappings WHERE id=$1`, mappingID); err != nil {
		t.Fatal(err)
	}
	if afterReject != beforeReject+1 {
		t.Fatalf("rejection stock=%d, want %d", afterReject, beforeReject+1)
	}
	rejectReplay := request(http.MethodPost, base+"/"+rejectedOrder+"/reject", token(owner), `{"reason":"Partner capacity is unavailable today."}`)
	if rejectReplay.Code != 200 || !strings.Contains(rejectReplay.Body.String(), `"changed":false`) {
		t.Fatalf("rejection retry status=%d body=%s", rejectReplay.Code, rejectReplay.Body.String())
	}
	if err := db.Get(&afterRejectRetry, `SELECT available_quantity FROM platform_partner_product_mappings WHERE id=$1`, mappingID); err != nil {
		t.Fatal(err)
	}
	if afterRejectRetry != afterReject {
		t.Fatalf("replayed rejection changed stock from %d to %d", afterReject, afterRejectRetry)
	}
	customerRejected := request(http.MethodGet, "/api/v1/orders/"+rejectedOrder, token(customer), "")
	if customerRejected.Code != 200 || !strings.Contains(customerRejected.Body.String(), "Partner capacity is unavailable today.") {
		t.Fatalf("customer rejection detail status=%d body=%s", customerRejected.Code, customerRejected.Body.String())
	}
	var rejectionAudit, customerEvents, businessEvents int
	if err := db.Get(&rejectionAudit, `SELECT count(*) FROM customer_order_status_events WHERE order_id=$1 AND event_kind='partner_rejected' AND reason='Partner capacity is unavailable today.'`, rejectedOrder); err != nil || rejectionAudit != 1 {
		t.Fatalf("rejection audit rows=%d err=%v", rejectionAudit, err)
	}
	if err := db.Get(&customerEvents, `SELECT count(*) FROM notifications WHERE user_id=$1 AND event_type='order.status' AND payload->>'order_id'=$2`, customer, rejectedOrder); err != nil || customerEvents != 1 {
		t.Fatalf("customer rejection notifications=%d err=%v", customerEvents, err)
	}
	if err := db.Get(&businessEvents, `SELECT count(*) FROM notifications WHERE business_id=$1 AND event_type='platform.order.status' AND payload->>'order_id'=$2`, business, rejectedOrder); err != nil || businessEvents != 1 {
		t.Fatalf("business rejection notifications=%d err=%v", businessEvents, err)
	}
	if _, err := db.Exec(`UPDATE customer_order_status_events SET reason='tampered' WHERE order_id=$1 AND event_kind='partner_rejected'`, rejectedOrder); err == nil {
		t.Fatal("status history allowed mutation")
	}

	results := make(chan int, 2)
	go func() { results <- request(http.MethodPost, base+"/"+racingOrder+"/accept", token(owner), "").Code }()
	go func() {
		results <- request(http.MethodPost, base+"/"+racingOrder+"/reject", token(member), `{"reason":"Capacity unavailable for this order."}`).Code
	}()
	a, b := <-results, <-results
	if !((a == 200 && b == 409) || (a == 409 && b == 200)) {
		t.Fatalf("accept/reject race returned %d and %d, want one success and one conflict", a, b)
	}
	var finalStatus string
	if err := db.Get(&finalStatus, `SELECT status FROM customer_orders WHERE id=$1`, racingOrder); err != nil {
		t.Fatal(err)
	}
	if finalStatus != "accepted" && finalStatus != "rejected" {
		t.Fatalf("concurrent transition ended in %q", finalStatus)
	}
	var eventCount int
	if err := db.Get(&eventCount, `SELECT count(*) FROM customer_order_status_events WHERE order_id=$1 AND status IN ('accepted','rejected')`, racingOrder); err != nil || eventCount != 1 {
		t.Fatalf("race event count=%d err=%v, want 1", eventCount, err)
	}
	if got := request(http.MethodGet, "/api/v1/orders/"+acceptedOrder, token(otherCustomer), ""); got.Code != 404 {
		t.Fatalf("customer order ownership status=%d, want 404", got.Code)
	}
}

func mustLocation(t *testing.T, name string) *time.Location {
	t.Helper()
	location, err := time.LoadLocation(name)
	if err != nil {
		t.Fatal(err)
	}
	return location
}
