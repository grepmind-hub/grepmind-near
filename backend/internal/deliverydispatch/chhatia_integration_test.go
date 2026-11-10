package deliverydispatch

import (
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
	"grepmind-near/backend/internal/platformfulfillment"
	"grepmind-near/backend/internal/riderearnings"
	"grepmind-near/backend/pkg/config"
	"grepmind-near/backend/pkg/database"
)

// TestChhatiaDeliveryTimelineAndLocalityIsolation is opt-in and requires a
// disposable database whose name ends in _qa or _test. The caller owns DB
// creation and teardown.
func TestChhatiaDeliveryTimelineAndLocalityIsolation(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_DSN")
	if dsn == "" {
		t.Skip("TEST_DATABASE_DSN is not set")
	}
	databaseName := databaseNameFromDSN(dsn)
	if !strings.HasSuffix(databaseName, "_qa") && !strings.HasSuffix(databaseName, "_test") {
		t.Fatal("refusing Chhatia delivery integration test: database name must end in _qa or _test")
	}

	db, err := database.Open(dsn, 8, 8, time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	const chhatiaID = "02200000-0000-4000-8000-000000000201"
	const kuanpalID = "02200000-0000-4000-8000-000000000101"
	var localityEnabled bool
	if err := db.GetContext(ctx, &localityEnabled, `SELECT is_active AND delivery_enabled FROM platform_delivery_localities WHERE id=$1`, chhatiaID); err != nil || !localityEnabled {
		t.Fatalf("Jajpur/Chhatia must be configured as active delivery locality (enabled=%v, err=%v)", localityEnabled, err)
	}
	policyID := uuid.NewString()
	if _, err := db.ExecContext(ctx, `INSERT INTO rider_compensation_policies(id,policy_key,version,locality_id,currency,fixed_amount_minor,effective_from,status,is_synthetic)
		VALUES($1,$2,1,$3,'INR',475,now()-interval '1 day','active',true)`, policyID, "qa-chhatia-"+uuid.NewString(), chhatiaID); err != nil {
		t.Fatalf("create synthetic Chhatia QA compensation policy: %v", err)
	}

	newID := func() string { return uuid.NewString() }
	customerID, merchantID := newID(), newID()
	var rootAdminID string
	if err := db.GetContext(ctx, &rootAdminID, `SELECT id::text FROM users WHERE phone_e164='+910000000000'`); err != nil {
		t.Fatalf("load isolated primary admin: %v", err)
	}
	chhatiaRiderID, kuanpalRiderID := newID(), newID()
	businessID, orderID, addressID, quoteID := newID(), newID(), newID(), newID()
	productID, variantID := newID(), newID()
	queries := []struct {
		query string
		args  []any
	}{
		{`INSERT INTO users(id,phone_e164,display_name,status) VALUES($1,$2,'QA Chhatia Customer','active'),($3,$4,'QA Chhatia Merchant','active'),($5,$6,'QA Chhatia Rider','active'),($7,$8,'QA Kuanpal-only Rider','active')`, []any{customerID, "+91" + phoneSuffix(), merchantID, "+91" + phoneSuffix(), chhatiaRiderID, "+91" + phoneSuffix(), kuanpalRiderID, "+91" + phoneSuffix()}},
		{`INSERT INTO user_roles(user_id,role) VALUES($1,'customer'),($2,'merchant'),($3,'rider'),($4,'rider')`, []any{customerID, merchantID, chhatiaRiderID, kuanpalRiderID}},
		{`INSERT INTO businesses(id,owner_user_id,name,slug,description,category_slug,phone_e164,address_text,locality,city,postal_code,location,status,verification_status,delivery_enabled) VALUES($1,$2,'QA Chhatia Food Partner',$3,'Disposable Chhatia delivery test partner.','restaurant',$4,'QA pickup, Chhatia','Chhatia','Jajpur','755046',ST_SetSRID(ST_MakePoint(86.22,20.75)::geography,4326),'approved','verified',true)`, []any{businessID, merchantID, "qa-chhatia-" + uuid.NewString(), "+91" + phoneSuffix()}},
		{`INSERT INTO business_members(business_id,user_id,role,status) VALUES($1,$2,'owner','active')`, []any{businessID, merchantID}},
		{`INSERT INTO platform_partner_delivery_localities(business_id,locality_id,is_active) VALUES($1,$2,true)`, []any{businessID, chhatiaID}},
		{`INSERT INTO rider_profiles(user_id,display_name,vehicle_type,status) VALUES($1,'QA Chhatia Rider','two_wheeler','approved'),($2,'QA Kuanpal-only Rider','bicycle','approved')`, []any{chhatiaRiderID, kuanpalRiderID}},
		{`INSERT INTO rider_profile_localities(rider_profile_id,locality_id,status) SELECT id,$2,'approved' FROM rider_profiles WHERE user_id=$1`, []any{chhatiaRiderID, chhatiaID}},
		{`INSERT INTO rider_profile_localities(rider_profile_id,locality_id,status) SELECT id,$2,'approved' FROM rider_profiles WHERE user_id=$1`, []any{kuanpalRiderID, kuanpalID}},
		{`INSERT INTO rider_availability_sessions(rider_user_id,is_online,lease_expires_at,last_heartbeat_at) VALUES($1,true,now()+interval '10 minutes',now()),($2,true,now()+interval '10 minutes',now())`, []any{chhatiaRiderID, kuanpalRiderID}},
		{`INSERT INTO customer_addresses(id,customer_user_id,label,recipient_name,address_line1,locality,landmark,city,state,postal_code,contact_phone,is_default,delivery_locality_id) VALUES($1,$2,'QA Home','QA Customer','QA Test Lane','Chhatia','QA landmark','Jajpur','Odisha','755046',$3,true,$4)`, []any{addressID, customerID, "+91" + phoneSuffix(), chhatiaID}},
		{`INSERT INTO platform_catalog_products(id,sku,category_id,name,status) SELECT $1,$2,id,'QA Chhatia Meal','active' FROM platform_catalog_categories WHERE vertical='food' AND slug='food'`, []any{productID, "qa-chhatia-" + uuid.NewString()}},
		{`INSERT INTO platform_catalog_variants(id,product_id,sku,name,unit_label,price_minor) VALUES($1,$2,$3,'QA serving','1 serving',12900)`, []any{variantID, productID, "qa-chhatia-variant-" + uuid.NewString()}},
		{`INSERT INTO platform_partner_product_mappings(business_id,variant_id,status,inventory_mode,available_quantity,preparation_minutes,supply_price_minor,created_by,updated_by,approved_by,approved_at) VALUES($1,$2,'approved','finite',5,20,8000,$3,$3,$3,now())`, []any{businessID, variantID, merchantID}},
		{`INSERT INTO platform_checkout_quotes(id,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,grand_total_minor,expires_at) SELECT $1,$2,'food',$3,CURRENT_DATE,$4,updated_at,$5,'[{"product":"QA Chhatia Meal","quantity":1}]'::jsonb,12900,12900,now()+interval '5 minutes' FROM customer_addresses WHERE id=$4`, []any{quoteID, customerID, chhatiaID, addressID, businessID}},
		{`INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,fulfillment_type,item_total,grand_total,reference_code,order_source,platform_vertical,delivery_locality_id,platform_checkout_quote_id,payment_status,delivery_address_snapshot) VALUES($1,$2,$3,'platform_order','placed','delivery',12900,12900,$4,'platform_catalog','food',$5,$6,'not_collected','{"address_line1":"QA Test Lane","locality":"Chhatia","city":"Jajpur","state":"Odisha","postal_code":"755046","recipient_name":"QA Customer"}'::jsonb)`, []any{orderID, customerID, businessID, "QA-CHHATIA-" + uuid.NewString(), chhatiaID, quoteID}},
		{`UPDATE platform_checkout_quotes SET consumed_order_id=$1 WHERE id=$2`, []any{orderID, quoteID}},
		{`INSERT INTO platform_customer_order_items(order_id,product_id,variant_id,vertical,product_name,variant_name,unit_label,unit_price_minor,quantity,price_revision) VALUES($1,$2,$3,'food','QA Chhatia Meal','QA serving','1 serving',12900,1,1)`, []any{orderID, productID, variantID}},
		{`INSERT INTO customer_order_status_events(order_id,status,event_kind,actor_user_id) VALUES($1,'placed','status_change',$2)`, []any{orderID, customerID}},
	}
	for _, item := range queries {
		if _, err := db.ExecContext(ctx, item.query, item.args...); err != nil {
			t.Fatalf("create disposable Chhatia fixture: %v", err)
		}
	}
	countRows := func(query string, args ...any) int {
		var count int
		if err := db.GetContext(ctx, &count, query, args...); err != nil {
			t.Fatalf("count Chhatia QA rows: %v", err)
		}
		return count
	}

	partner := platformfulfillment.NewService(db)
	fulfillmentAction := func(orderAction string, handler func(http.ResponseWriter, *http.Request, string)) *httptest.ResponseRecorder {
		recorder := httptest.NewRecorder()
		request := httptest.NewRequest("POST", "/merchant/businesses/"+businessID+"/platform-orders/"+orderID+"/"+orderAction, nil)
		request.SetPathValue("businessId", businessID)
		request.SetPathValue("orderId", orderID)
		handler(recorder, request, merchantID)
		return recorder
	}
	if got := fulfillmentAction("accept", partner.Accept); got.Code != 200 {
		t.Fatalf("Chhatia partner accept failed: HTTP %d %s", got.Code, got.Body.String())
	}
	if got := fulfillmentAction("prepare", partner.Prepare); got.Code != 200 {
		t.Fatalf("Chhatia partner preparation failed: HTTP %d %s", got.Code, got.Body.String())
	}
	if got := countRows(`SELECT count(*) FROM delivery_jobs WHERE order_id=$1`, orderID); got != 1 {
		t.Fatalf("expected preparation to create exactly one Chhatia delivery job, got %d", got)
	}
	if got := countRows(`SELECT count(*) FROM delivery_events e JOIN delivery_jobs j ON j.id=e.job_id WHERE j.order_id=$1 AND e.event_type='job_created'`, orderID); got != 1 {
		t.Fatalf("expected exactly one Chhatia job_created event, got %d", got)
	}

	earnings := riderearnings.NewService(db, &config.Config{Env: "qa", RiderEarningsPostingEnabled: true, RiderEarningsAllowSynthetic: true})
	dispatch := NewService(db, nil, &config.Config{RiderDispatchEnabled: true, RiderOfferTimeout: 30 * time.Second, RiderAvailabilityLease: 2 * time.Minute, JWTSecret: "disposable-chhatia-test-secret"}, earnings.RecordCompletionTx)
	if err := dispatch.Process(ctx); err != nil {
		t.Fatalf("process Chhatia dispatch: %v", err)
	}
	var jobID, offerID, offeredRider string
	if err := db.QueryRowxContext(ctx, `SELECT j.id::text,x.id::text,x.rider_user_id::text FROM delivery_jobs j JOIN delivery_offers x ON x.job_id=j.id AND x.state='offered' WHERE j.order_id=$1`, orderID).Scan(&jobID, &offerID, &offeredRider); err != nil {
		t.Fatalf("Chhatia order did not produce an eligible rider offer: %v", err)
	}
	if offeredRider != chhatiaRiderID || offeredRider == kuanpalRiderID {
		t.Fatalf("Chhatia offer sent to wrong locality rider: got %s", offeredRider)
	}
	if got := countRows(`SELECT count(*) FROM delivery_offers WHERE job_id=$1 AND rider_user_id=$2`, jobID, kuanpalRiderID); got != 0 {
		t.Fatalf("Kuanpal-only rider received Chhatia offer: count=%d", got)
	}
	accept := httptest.NewRecorder()
	acceptRequest := httptest.NewRequest("POST", "/rider/offers/"+offerID+"/accept", strings.NewReader(`{}`))
	acceptRequest.SetPathValue("offerId", offerID)
	dispatch.RespondOffer(accept, acceptRequest, chhatiaRiderID, "accept")
	if accept.Code != 200 {
		t.Fatalf("Chhatia rider could not accept offer: HTTP %d %s", accept.Code, accept.Body.String())
	}
	if got := fulfillmentAction("ready", partner.Ready); got.Code != 200 {
		t.Fatalf("Chhatia partner could not mark order ready: HTTP %d %s", got.Code, got.Body.String())
	}

	deliveryAction := func(path string, body string, actor string, handler func(http.ResponseWriter, *http.Request, string)) *httptest.ResponseRecorder {
		recorder := httptest.NewRecorder()
		request := httptest.NewRequest("POST", path, strings.NewReader(body))
		request.SetPathValue("jobId", jobID)
		request.SetPathValue("id", orderID)
		request.SetPathValue("businessId", businessID)
		handler(recorder, request, actor)
		return recorder
	}
	if got := deliveryAction("/rider/delivery-jobs/"+jobID+"/state", `{"state":"arriving_at_pickup"}`, chhatiaRiderID, dispatch.RiderTransition); got.Code != 200 {
		t.Fatalf("Chhatia rider arrival failed: HTTP %d %s", got.Code, got.Body.String())
	}
	if got := deliveryAction("/rider/delivery-jobs/"+jobID+"/state", `{"state":"at_pickup"}`, chhatiaRiderID, dispatch.RiderTransition); got.Code != 200 {
		t.Fatalf("Chhatia rider at-pickup failed: HTTP %d %s", got.Code, got.Body.String())
	}
	pickup := httptest.NewRecorder()
	pickupRequest := httptest.NewRequest("POST", "/merchant/businesses/"+businessID+"/delivery-jobs/"+jobID+"/pickup-code", nil)
	pickupRequest.SetPathValue("businessId", businessID)
	pickupRequest.SetPathValue("jobId", jobID)
	dispatch.IssuePickupCode(pickup, pickupRequest, merchantID)
	var pickupPayload struct {
		Data struct {
			Code string `json:"pickup_code"`
		} `json:"data"`
	}
	if pickup.Code != 200 || json.Unmarshal(pickup.Body.Bytes(), &pickupPayload) != nil || len(pickupPayload.Data.Code) != 8 {
		t.Fatalf("Chhatia partner pickup verification issue failed: HTTP %d %s", pickup.Code, pickup.Body.String())
	}
	if got := deliveryAction("/rider/delivery-jobs/"+jobID+"/pickup/verify", `{"code":"`+pickupPayload.Data.Code+`"}`, chhatiaRiderID, dispatch.VerifyPickup); got.Code != 200 {
		t.Fatalf("Chhatia pickup verification failed: HTTP %d %s", got.Code, got.Body.String())
	}
	if got := deliveryAction("/rider/delivery-jobs/"+jobID+"/state", `{"state":"en_route"}`, chhatiaRiderID, dispatch.RiderTransition); got.Code != 200 {
		t.Fatalf("Chhatia rider en-route transition failed: HTTP %d %s", got.Code, got.Body.String())
	}
	deliveryCode := httptest.NewRecorder()
	deliveryCodeRequest := httptest.NewRequest("POST", "/orders/"+orderID+"/delivery-code", nil)
	deliveryCodeRequest.SetPathValue("id", orderID)
	dispatch.IssueDeliveryCode(deliveryCode, deliveryCodeRequest, customerID)
	var deliveryPayload struct {
		Data struct {
			Code string `json:"delivery_code"`
		} `json:"data"`
	}
	if deliveryCode.Code != 200 || json.Unmarshal(deliveryCode.Body.Bytes(), &deliveryPayload) != nil || len(deliveryPayload.Data.Code) != 8 {
		t.Fatalf("Chhatia customer delivery verification issue failed: HTTP %d %s", deliveryCode.Code, deliveryCode.Body.String())
	}
	if got := deliveryAction("/rider/delivery-jobs/"+jobID+"/delivery/confirm", `{"code":"`+deliveryPayload.Data.Code+`"}`, chhatiaRiderID, dispatch.ConfirmDelivery); got.Code != 200 {
		t.Fatalf("Chhatia customer-code delivery confirmation failed: HTTP %d %s", got.Code, got.Body.String())
	}
	if got := deliveryAction("/rider/delivery-jobs/"+jobID+"/delivery/confirm", `{"code":"00000000"}`, chhatiaRiderID, dispatch.ConfirmDelivery); got.Code != 200 || !strings.Contains(got.Body.String(), `"idempotent":true`) {
		t.Fatalf("duplicate delivered command was not idempotent: HTTP %d %s", got.Code, got.Body.String())
	}
	var earningCount int
	var earningAmount int64
	var earningRider, earningPolicy string
	if err := db.QueryRowxContext(ctx, `SELECT count(*)::int,COALESCE(sum(amount_minor),0)::bigint,min(rider_user_id::text),min(policy_id::text) FROM rider_earning_entries WHERE delivery_job_id=$1 AND entry_type='delivery_earning'`, jobID).Scan(&earningCount, &earningAmount, &earningRider, &earningPolicy); err != nil {
		t.Fatal(err)
	}
	if earningCount != 1 || earningAmount != 475 || earningRider != chhatiaRiderID || earningPolicy != policyID {
		t.Fatalf("expected one synthetic policy earning for correct rider/job, got count=%d amount=%d rider=%s policy=%s", earningCount, earningAmount, earningRider, earningPolicy)
	}
	adminLocalities := httptest.NewRecorder()
	earnings.AdminLocalities(adminLocalities, httptest.NewRequest("GET", "/admin/rider-earnings/localities", nil), rootAdminID)
	var localityPayload struct {
		Data []map[string]any `json:"data"`
	}
	if adminLocalities.Code != http.StatusOK || json.Unmarshal(adminLocalities.Body.Bytes(), &localityPayload) != nil {
		t.Fatalf("Admin earnings locality filter failed: HTTP %d %s", adminLocalities.Code, adminLocalities.Body.String())
	}
	chhatiaListed := false
	for _, locality := range localityPayload.Data {
		if locality["name"] == "Chhatia" && locality["district"] == "Jajpur" {
			chhatiaListed = true
			break
		}
	}
	if !chhatiaListed {
		t.Fatalf("Admin earnings locality filter did not list Chhatia, Jajpur: %#v", localityPayload.Data)
	}
	// The live UI acceptance needs a fresh, unadjusted earning so the browser can
	// exercise adjustment and reversal actions against this exact delivery. The
	// normal integration run continues through all financial mutation checks.
	if os.Getenv("PHASE3F_LIVE_UI_FIXTURE") == "1" {
		t.Log("created disposable completed-delivery earnings fixture for live UI acceptance")
		return
	}
	// Production configuration must ignore the synthetic QA policy and leave a
	// transparent unpriced record instead of inventing compensation.
	unpricedOrderID, unpricedJobID := uuid.NewString(), uuid.NewString()
	if _, err := db.ExecContext(ctx, `INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,fulfillment_type,item_total,grand_total,currency,reference_code)
		VALUES($1,$2,$3,'food_delivery','delivered','delivery',0,0,'INR',$4)`, unpricedOrderID, customerID, businessID, "QA-UNPRICED-"+unpricedOrderID[:8]); err != nil {
		t.Fatalf("create QA-only completed order for disabled posting check: %v", err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO delivery_jobs(id,order_id,business_id,locality_id,state,execution_state)
		VALUES($1,$2,$3,$4,'assigned','delivered')`, unpricedJobID, unpricedOrderID, businessID, chhatiaID); err != nil {
		t.Fatalf("create QA-only completed delivery job: %v", err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO delivery_assignments(job_id,rider_user_id,state,assigned_at,ended_at)
		VALUES($1,$2,'released',now(),now())`, unpricedJobID, chhatiaRiderID); err != nil {
		t.Fatalf("create QA-only historical rider assignment: %v", err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO delivery_execution_events(job_id,actor_user_id,actor_type,event_type,from_state,to_state)
		VALUES($1,$2,'rider','customer_otp_verified','en_route','delivered')`, unpricedJobID, chhatiaRiderID); err != nil {
		t.Fatalf("create QA-only verified completion event: %v", err)
	}
	productionConfigured := riderearnings.NewService(db, &config.Config{Env: "production", RiderEarningsPostingEnabled: false, RiderEarningsAllowSynthetic: false})
	if err := db.Transaction(ctx, func(tx *sqlx.Tx) error {
		return productionConfigured.RecordCompletionTx(ctx, tx, unpricedJobID, chhatiaRiderID)
	}); err != nil {
		t.Fatalf("record production-disabled unpriced completion: %v", err)
	}
	var unpricedCount int
	var unpricedAmount sql.NullInt64
	var unpricedReason string
	if err := db.QueryRowxContext(ctx, `SELECT count(*)::int,min(amount_minor),min(metadata->>'reason') FROM rider_earning_entries WHERE delivery_job_id=$1 AND entry_type='unpriced'`, unpricedJobID).Scan(&unpricedCount, &unpricedAmount, &unpricedReason); err != nil {
		t.Fatal(err)
	}
	if unpricedCount != 1 || unpricedAmount.Valid || unpricedReason != "posting_disabled" {
		t.Fatalf("production-disabled posting must remain unpriced, got count=%d amount=%v reason=%q", unpricedCount, unpricedAmount, unpricedReason)
	}
	// Concurrent completion hooks must have one economic effect even when invoked
	// by duplicate/recovery work after the delivery has already been committed.
	var workers sync.WaitGroup
	for i := 0; i < 8; i++ {
		workers.Add(1)
		go func() {
			defer workers.Done()
			if err := db.Transaction(ctx, func(tx *sqlx.Tx) error { return earnings.RecordCompletionTx(ctx, tx, jobID, chhatiaRiderID) }); err != nil {
				t.Errorf("concurrent idempotent earning post failed: %v", err)
			}
		}()
	}
	workers.Wait()
	if got := countRows(`SELECT count(*) FROM rider_earning_entries WHERE delivery_job_id=$1 AND entry_type IN ('delivery_earning','unpriced')`, jobID); got != 1 {
		t.Fatalf("concurrent earning posting created %d delivery effects", got)
	}
	adjustmentKey := "qa-adjustment-" + uuid.NewString()
	adjustmentRequest := func(amount int64, key string) *httptest.ResponseRecorder {
		payload, _ := json.Marshal(map[string]any{"rider_user_id": chhatiaRiderID, "delivery_job_id": jobID, "amount_minor": amount, "currency": "INR", "reason": "Synthetic QA compensation correction", "idempotency_key": key})
		req := httptest.NewRequest("POST", "/api/v1/admin/rider-earnings/adjustments", strings.NewReader(string(payload)))
		w := httptest.NewRecorder()
		earnings.AdminAdjustment(w, req, rootAdminID)
		return w
	}
	if got := adjustmentRequest(125, adjustmentKey); got.Code != 201 {
		t.Fatalf("authorized QA adjustment failed: HTTP %d %s", got.Code, got.Body.String())
	}
	if got := adjustmentRequest(125, adjustmentKey); got.Code != 201 {
		t.Fatalf("idempotent QA adjustment retry failed: HTTP %d %s", got.Code, got.Body.String())
	}
	if got := adjustmentRequest(126, adjustmentKey); got.Code != 400 {
		t.Fatalf("adjustment idempotency payload change returned HTTP %d, want 400", got.Code)
	}
	var earningEntryID string
	if err := db.GetContext(ctx, &earningEntryID, `SELECT id::text FROM rider_earning_entries WHERE delivery_job_id=$1 AND entry_type='delivery_earning'`, jobID); err != nil {
		t.Fatal(err)
	}
	reverseRequest := func() *httptest.ResponseRecorder {
		req := httptest.NewRequest("POST", "/api/v1/admin/rider-earnings/entries/"+earningEntryID+"/reverse", strings.NewReader(`{"reason":"Synthetic QA delivery correction","idempotency_key":"qa-reverse-`+earningEntryID+`"}`))
		req.SetPathValue("entryId", earningEntryID)
		w := httptest.NewRecorder()
		earnings.AdminReverse(w, req, rootAdminID)
		return w
	}
	if got := reverseRequest(); got.Code != 201 {
		t.Fatalf("authorized QA reversal failed: HTTP %d %s", got.Code, got.Body.String())
	}
	if got := reverseRequest(); got.Code != 201 {
		t.Fatalf("idempotent QA reversal retry failed: HTTP %d %s", got.Code, got.Body.String())
	}
	if got := countRows(`SELECT count(*) FROM rider_earning_entries WHERE delivery_job_id=$1 AND entry_type='reversal'`, jobID); got != 1 {
		t.Fatalf("expected one compensating reversal, got %d", got)
	}
	if got := countRows(`SELECT count(*) FROM rider_earning_entries WHERE id=$1 AND entry_type='delivery_earning' AND amount_minor=475`, earningEntryID); got != 1 {
		t.Fatal("reversal mutated or deleted the original earning")
	}
	if got := countRows(`SELECT count(*) FROM rider_earning_audit_events a JOIN rider_earning_entries e ON e.id=a.entry_id WHERE e.delivery_job_id=$1 AND a.event_type='earning_recorded'`, jobID); got != 1 {
		t.Fatalf("expected one immutable earning audit event, got %d", got)
	}
	dateQuery := "?from=" + time.Now().Add(-24*time.Hour).UTC().Format(time.RFC3339) + "&to=" + time.Now().Add(time.Hour).UTC().Format(time.RFC3339)
	riderSummary := httptest.NewRecorder()
	earnings.RiderSummary(riderSummary, httptest.NewRequest("GET", "/rider/earnings/summary"+dateQuery, nil), chhatiaRiderID)
	var summaryPayload map[string]any
	if riderSummary.Code != 200 || json.Unmarshal(riderSummary.Body.Bytes(), &summaryPayload) != nil {
		t.Fatalf("rider earnings summary failed: HTTP %d %s", riderSummary.Code, riderSummary.Body.String())
	}
	if got := summaryPayload["data"].(map[string]any)["total_recorded_minor"]; got != "125" {
		t.Fatalf("expected exact string minor-unit aggregate after adjustment/reversal, got %#v", got)
	}
	riderHistory := httptest.NewRecorder()
	earnings.RiderHistory(riderHistory, httptest.NewRequest("GET", "/rider/earnings"+dateQuery, nil), chhatiaRiderID)
	var historyPayload struct {
		Data []map[string]any `json:"data"`
	}
	if riderHistory.Code != 200 || json.Unmarshal(riderHistory.Body.Bytes(), &historyPayload) != nil || len(historyPayload.Data) < 3 {
		t.Fatalf("rider earnings history failed: HTTP %d %s", riderHistory.Code, riderHistory.Body.String())
	}
	for _, row := range historyPayload.Data {
		if row["entry_type"] == "delivery_earning" && row["amount_minor"] != "475" {
			t.Fatalf("earning amount should be a precise decimal string, got %#v", row["amount_minor"])
		}
	}
	adminRange := dateQuery + "&locality_id=" + chhatiaID
	adminOverview := httptest.NewRecorder()
	earnings.AdminOverview(adminOverview, httptest.NewRequest("GET", "/admin/rider-earnings/overview"+adminRange, nil), rootAdminID)
	var adminOverviewPayload struct {
		Data []map[string]any `json:"data"`
	}
	if adminOverview.Code != 200 || json.Unmarshal(adminOverview.Body.Bytes(), &adminOverviewPayload) != nil || len(adminOverviewPayload.Data) == 0 {
		var queryDiagnostic []map[string]any
		diagnosticErr := db.SelectContext(ctx, &queryDiagnostic, `SELECT e.rider_user_id::text,COALESCE(u.display_name,'Rider') rider_name,count(*) FILTER(WHERE e.entry_type='delivery_earning')::int completed_deliveries,
			count(*) FILTER(WHERE e.entry_type='unpriced')::int unpriced_deliveries,COALESCE(sum(e.amount_minor) FILTER(WHERE e.entry_type<>'unpriced'),0)::text total_recorded_minor,min(e.currency) currency
			FROM rider_earning_entries e JOIN users u ON u.id=e.rider_user_id LEFT JOIN delivery_jobs j ON j.id=e.delivery_job_id
			WHERE e.effective_at >= $1 AND e.effective_at < $2 AND ($3='' OR j.locality_id::text=$3) GROUP BY e.rider_user_id,u.display_name ORDER BY total_recorded_minor DESC LIMIT 200`, time.Now().Add(-24*time.Hour), time.Now().Add(time.Hour), chhatiaID)
		t.Fatalf("admin earnings overview failed: HTTP %d %s; direct query error: %v; rows=%#v", adminOverview.Code, adminOverview.Body.String(), diagnosticErr, queryDiagnostic)
	}
	for _, row := range adminOverviewPayload.Data {
		if row["rider_user_id"] == chhatiaRiderID && row["total_recorded_minor"] != "125" {
			t.Fatalf("admin overview should preserve exact string total, got %#v", row["total_recorded_minor"])
		}
	}
	adminPolicies := httptest.NewRecorder()
	earnings.AdminPolicies(adminPolicies, httptest.NewRequest("GET", "/admin/rider-earnings/policies", nil), rootAdminID)
	var policyPayload struct {
		Data []map[string]any `json:"data"`
	}
	if adminPolicies.Code != 200 || json.Unmarshal(adminPolicies.Body.Bytes(), &policyPayload) != nil || len(policyPayload.Data) != 1 || policyPayload.Data[0]["fixed_amount_minor"] != "475" {
		t.Fatalf("Admin policy API must serialize exact minor units as strings: HTTP %d %s", adminPolicies.Code, adminPolicies.Body.String())
	}

	timelineRecorder := httptest.NewRecorder()
	timelineRequest := httptest.NewRequest("GET", "/orders/"+orderID+"/delivery-history", nil)
	timelineRequest.SetPathValue("id", orderID)
	dispatch.CustomerTimeline(timelineRecorder, timelineRequest, customerID)
	if timelineRecorder.Code != 200 {
		t.Fatalf("Chhatia customer timeline failed: HTTP %d %s", timelineRecorder.Code, timelineRecorder.Body.String())
	}
	var timeline struct {
		Data []struct {
			EventType string `json:"event_type"`
			ToState   string `json:"to_state"`
		} `json:"data"`
	}
	if err := json.Unmarshal(timelineRecorder.Body.Bytes(), &timeline); err != nil {
		t.Fatal(err)
	}
	counts := map[string]int{}
	lastIndex := map[string]int{}
	for i, event := range timeline.Data {
		key := event.EventType + ":" + event.ToState
		counts[key]++
		lastIndex[key] = i
		if event.EventType == "pickup_code_issued" {
			t.Fatal("pickup-code issuance leaked into customer milestones")
		}
	}
	expected := []string{"order_status:placed", "order_status:accepted", "order_status:preparing", "rider_assigned:assigned", "order_status:ready_for_pickup", "state_changed:arriving_at_pickup", "state_changed:at_pickup", "pickup_verified:picked_up", "state_changed:en_route", "customer_otp_verified:delivered"}
	previous := -1
	for _, key := range expected {
		if counts[key] != 1 || lastIndex[key] <= previous {
			t.Fatalf("Chhatia customer timeline missing, duplicated, or misordered %s: %#v; response=%s", key, counts, timelineRecorder.Body.String())
		}
		previous = lastIndex[key]
	}
	var finalOrder, finalExecution, payment string
	if err := db.QueryRowxContext(ctx, `SELECT o.status,j.execution_state,o.payment_status FROM customer_orders o JOIN delivery_jobs j ON j.order_id=o.id WHERE o.id=$1`, orderID).Scan(&finalOrder, &finalExecution, &payment); err != nil {
		t.Fatal(err)
	}
	if finalOrder != "delivered" || finalExecution != "delivered" || payment != "not_collected" {
		t.Fatalf("unexpected Chhatia terminal states: order=%s execution=%s payment=%s", finalOrder, finalExecution, payment)
	}
	if got := countRows(`SELECT count(*) FROM delivery_assignments WHERE job_id=$1 AND state='active'`, jobID); got != 0 {
		t.Fatalf("Chhatia delivery retained active rider assignment: %d", got)
	}
}
