package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v4"
	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
	"grepmind-near/backend/internal/auth"
	"grepmind-near/backend/internal/discovery"
	"grepmind-near/backend/internal/merchantanalytics"
	"grepmind-near/backend/internal/moderation"
	"grepmind-near/backend/internal/notifications"
	"grepmind-near/backend/internal/operations"
	"grepmind-near/backend/pkg/config"
	"grepmind-near/backend/pkg/database"
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

func TestOwnershipAndTenantRoutes(t *testing.T) {
	db, ownerA, memberA, customerA, customerB, businessA, businessB, productB, requestB, notificationB, orderB := newAPISecurityFixture(t)
	cfg := &config.Config{Env: "test", JWTSecret: "integration-test-secret-with-over-32-characters"}
	authSvc := auth.NewService(db, cfg)
	router := setupRouter(authSvc, discovery.NewService(db, cfg), moderation.NewService(db, cfg), nil, notifications.NewHub(db.DB), operations.NewService(db))
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
	var w *httptest.ResponseRecorder

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
	} {
		w = request(tc.method, tc.path, token(customerA), tc.body)
		if w.Code != tc.want {
			t.Errorf("%s %s status=%d, want %d: %s", tc.method, tc.path, w.Code, tc.want, w.Body.String())
		}
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
	if err := json.Unmarshal(w.Body.Bytes(), &products); err != nil || len(products.Data) != 1 || products.Data[0].ID != created.Data.ID || products.Data[0].Name != "Updated product" || products.Data[0].Stock != "limited" || products.Data[0].Image != "https://assets.example/product.jpg" {
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
		status int
		body   string
	}
	results := make(chan bookingResult, 2)
	for _, customer := range []string{customerA, customerB} {
		go func(customerID string) {
			result := request(http.MethodPost, "/api/v1/businesses/"+businessA+"/requests", token(customerID), bookingBody)
			results <- bookingResult{status: result.Code, body: result.Body.String()}
		}(customer)
	}
	var winnerID string
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
		w = request(http.MethodPatch, merchantStatusPath, token(ownerA), `{"status":"cancelled"}`)
		if w.Code != http.StatusOK {
			t.Fatalf("cancel accepted request status=%d body=%s", w.Code, w.Body.String())
		}
		if err := db.Get(&bookedCount, `SELECT booked_count FROM availability_slots WHERE id=$1`, createdSlot.Data.ID); err != nil || bookedCount != 0 {
			t.Errorf("merchant cancellation did not release slot capacity: booked=%d err=%v", bookedCount, err)
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
}

func TestAdminUserAccessRoleBoundaries(t *testing.T) {
	db, _, memberA, _, _, _, _, _, _, _, _ := newAPISecurityFixture(t)
	cfg := &config.Config{Env: "test", JWTSecret: "integration-test-secret-with-over-32-characters"}
	authSvc := auth.NewService(db, cfg)
	router := setupRouter(authSvc, discovery.NewService(db, cfg), moderation.NewService(db, cfg), nil, notifications.NewHub(db.DB), operations.NewService(db))
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
		`CREATE TABLE businesses(id UUID PRIMARY KEY, owner_user_id UUID NOT NULL, name TEXT NOT NULL, slug TEXT, description TEXT, category_slug TEXT NOT NULL, address_text TEXT NOT NULL, locality TEXT, city TEXT, postal_code TEXT, phone_e164 TEXT, whatsapp_e164 TEXT, cover_photo_url TEXT, location GEOGRAPHY(POINT,4326), status TEXT NOT NULL, verification_status TEXT NOT NULL, time_zone TEXT NOT NULL DEFAULT 'Asia/Kolkata', created_at TIMESTAMPTZ NOT NULL DEFAULT now())`,
		`CREATE TABLE merchant_view_events(business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE, view_type TEXT NOT NULL CHECK(view_type IN ('profile','catalog')), view_date DATE NOT NULL, viewer_fingerprint BYTEA NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY(business_id,view_type,view_date,viewer_fingerprint))`,
		`CREATE TABLE business_members(id UUID PRIMARY KEY DEFAULT gen_random_uuid(), business_id UUID NOT NULL, user_id UUID NOT NULL, role TEXT NOT NULL DEFAULT 'staff', status TEXT NOT NULL)`,
		`CREATE TABLE business_hours(id UUID PRIMARY KEY DEFAULT gen_random_uuid(), business_id UUID NOT NULL, weekday SMALLINT NOT NULL, opens_at TIME, closes_at TIME, is_closed BOOLEAN NOT NULL, UNIQUE(business_id,weekday))`,
		`CREATE TABLE products(id UUID PRIMARY KEY DEFAULT gen_random_uuid(), business_id UUID NOT NULL, name TEXT NOT NULL, description TEXT, price NUMERIC(12,2), currency CHAR(3) NOT NULL DEFAULT 'INR', stock_status TEXT NOT NULL DEFAULT 'unknown', is_published BOOLEAN NOT NULL DEFAULT false, image_url TEXT, updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), published_at TIMESTAMPTZ)`,
		`CREATE TABLE services(id UUID PRIMARY KEY, business_id UUID, name TEXT, description TEXT, indicative_price_min NUMERIC, indicative_price_max NUMERIC, currency CHAR(3) NOT NULL DEFAULT 'INR', is_active BOOLEAN NOT NULL DEFAULT true, activated_at TIMESTAMPTZ)`,
		`CREATE TABLE service_requests(id UUID PRIMARY KEY DEFAULT gen_random_uuid(), customer_user_id UUID NOT NULL, business_id UUID NOT NULL, service_id UUID, slot_id UUID, description TEXT, requested_for TIMESTAMPTZ, status TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now())`,
		`CREATE TABLE service_request_events(id UUID PRIMARY KEY DEFAULT gen_random_uuid(), request_id UUID, status TEXT, actor_user_id UUID, created_at TIMESTAMPTZ DEFAULT now())`,
		`CREATE TABLE availability_slots(id UUID PRIMARY KEY, business_id UUID NOT NULL, starts_at TIMESTAMPTZ NOT NULL, ends_at TIMESTAMPTZ NOT NULL, capacity INT NOT NULL, booked_count INT NOT NULL DEFAULT 0, status TEXT NOT NULL, updated_at TIMESTAMPTZ DEFAULT now())`,
		`CREATE TABLE business_availability_exceptions(id UUID PRIMARY KEY DEFAULT gen_random_uuid(), business_id UUID NOT NULL, local_date DATE NOT NULL, is_closed BOOLEAN NOT NULL DEFAULT false, opens_at TIME, closes_at TIME, note TEXT NOT NULL DEFAULT '', created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), UNIQUE(business_id,local_date))`,
		`CREATE TABLE professional_profiles(business_id UUID PRIMARY KEY, accepts_requests BOOLEAN NOT NULL DEFAULT false, service_radius_m INT NOT NULL DEFAULT 5000, experience_years INT, service_description TEXT)`,
		`CREATE TABLE notifications(id UUID PRIMARY KEY DEFAULT gen_random_uuid(), user_id UUID, business_id UUID, title TEXT NOT NULL, body TEXT NOT NULL, event_type TEXT NOT NULL, reference_id TEXT, payload JSONB, is_read BOOLEAN NOT NULL DEFAULT false, created_at TIMESTAMPTZ NOT NULL DEFAULT now())`,
		`CREATE TABLE customer_orders(id UUID PRIMARY KEY, customer_user_id UUID NOT NULL, business_id UUID NOT NULL, order_type TEXT NOT NULL, status TEXT NOT NULL, fulfillment_type TEXT, delivery_address TEXT, customer_notes TEXT, item_total NUMERIC NOT NULL, delivery_fee NUMERIC NOT NULL, tax_amount NUMERIC NOT NULL, grand_total NUMERIC NOT NULL, currency CHAR(3) NOT NULL DEFAULT 'INR', eta_minutes INT, reservation_at TIMESTAMPTZ, reservation_end_at TIMESTAMPTZ, guest_count INT, seating_area TEXT, room_product_id UUID, reference_code TEXT NOT NULL, cancelled_at TIMESTAMPTZ, created_at TIMESTAMPTZ DEFAULT now(), updated_at TIMESTAMPTZ DEFAULT now())`,
		`CREATE TABLE customer_order_items(order_id UUID, product_id UUID, product_name TEXT, unit_price NUMERIC, quantity INT, dietary_type TEXT)`,
	} {
		if _, err := raw.Exec(ddl); err != nil {
			t.Fatalf("create isolated fixture: %v", err)
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

func mustLocation(t *testing.T, name string) *time.Location {
	t.Helper()
	location, err := time.LoadLocation(name)
	if err != nil {
		t.Fatal(err)
	}
	return location
}
