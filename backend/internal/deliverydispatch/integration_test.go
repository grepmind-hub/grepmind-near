package deliverydispatch

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"grepmind-near/backend/pkg/config"
	"grepmind-near/backend/pkg/database"
)

// This test is opt-in and must only target a disposable database whose name
// ends in _qa or _test. Migration-level workflow tests leave records behind;
// the caller is responsible for dropping that disposable database/container.
func TestDispatchPrepareOfferAcceptAndIsolation(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_DSN")
	if dsn == "" {
		t.Skip("TEST_DATABASE_DSN is not set")
	}
	if !strings.HasSuffix(databaseNameFromDSN(dsn), "_qa") && !strings.HasSuffix(databaseNameFromDSN(dsn), "_test") {
		t.Fatal("refusing delivery dispatch integration test: database name must end in _qa or _test")
	}
	db, err := database.Open(dsn, 8, 8, time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	// This test intentionally owns the disposable QA dispatch surface. Older
	// failed invocations may have left approved QA riders online; take them out
	// of rotation so the two riders created below are the only candidates.
	if _, err := db.ExecContext(ctx, `UPDATE rider_availability_sessions SET is_online=false,updated_at=now()`); err != nil {
		t.Fatalf("could not isolate QA rider availability: %v", err)
	}
	// Close leftover dispatch state from earlier test runs in this disposable
	// database so a rider cannot be excluded by a stale offer or assignment.
	if _, err := db.ExecContext(ctx, `UPDATE delivery_offers SET state='expired',responded_at=now() WHERE state='offered'`); err != nil {
		t.Fatalf("could not clear stale QA offers: %v", err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE delivery_assignments SET state='cancelled',ended_at=now() WHERE state='active'`); err != nil {
		t.Fatalf("could not clear stale QA assignments: %v", err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE delivery_dispatch_runs SET state='no_rider_available',completed_at=now() WHERE state='searching'`); err != nil {
		t.Fatalf("could not close stale QA dispatch runs: %v", err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE delivery_jobs SET state='no_rider_available',updated_at=now() WHERE state IN ('pending_dispatch','offered')`); err != nil {
		t.Fatalf("could not close stale QA jobs: %v", err)
	}
	newID := func() string { return uuid.NewString() }
	customerID, merchantID, foreignMerchantID, adminID, businessID := newID(), newID(), newID(), newID(), newID()
	riderOne, riderTwo := newID(), newID()
	orderID, quoteID, addressID := newID(), newID(), newID()
	productID, variantID := newID(), newID()
	localityID := "02200000-0000-4000-8000-000000000101" // Cuttack → Kuanpal

	queries := []struct {
		query string
		args  []any
	}{
		{`INSERT INTO users(id,phone_e164,display_name,status) VALUES($1,$2,$3,'active')`, []any{customerID, "+91" + phoneSuffix(), "QA Dispatch Customer"}},
		{`INSERT INTO user_roles(user_id,role) VALUES($1,'customer')`, []any{customerID}},
		{`INSERT INTO users(id,phone_e164,display_name,status) VALUES($1,$2,$3,'active')`, []any{merchantID, "+91" + phoneSuffix(), "QA Dispatch Merchant"}},
		{`INSERT INTO user_roles(user_id,role) VALUES($1,'merchant')`, []any{merchantID}},
		{`INSERT INTO users(id,phone_e164,display_name,status) VALUES($1,$2,$3,'active')`, []any{foreignMerchantID, "+91" + phoneSuffix(), "QA Foreign Merchant"}},
		{`INSERT INTO user_roles(user_id,role) VALUES($1,'merchant')`, []any{foreignMerchantID}},
		{`INSERT INTO users(id,phone_e164,display_name,status) VALUES($1,$2,$3,'active')`, []any{adminID, "+91" + phoneSuffix(), "QA Dispatch Admin"}},
		{`INSERT INTO user_roles(user_id,role) VALUES($1,'admin')`, []any{adminID}},
		{`INSERT INTO businesses(id,owner_user_id,name,slug,description,category_slug,phone_e164,address_text,locality,city,postal_code,location,status,verification_status) VALUES($1,$2,'QA Dispatch Partner',$3,'Disposable QA fulfillment partner','restaurant',$4,'QA partner pickup','Kuanpal','Cuttack','754082',ST_SetSRID(ST_MakePoint(85.75,20.45)::geography,4326),'approved','verified')`, []any{businessID, merchantID, "qa-dispatch-" + uuid.NewString(), "+91" + phoneSuffix()}},
		{`INSERT INTO platform_partner_delivery_localities(business_id,locality_id,is_active) VALUES($1,$2,true)`, []any{businessID, localityID}},
		{`INSERT INTO users(id,phone_e164,display_name,status) VALUES($1,$2,$3,'active'),($4,$5,$6,'active')`, []any{riderOne, "+91" + phoneSuffix(), "QA Rider One", riderTwo, "+91" + phoneSuffix(), "QA Rider Two"}},
		{`INSERT INTO user_roles(user_id,role) VALUES($1,'rider'),($2,'rider')`, []any{riderOne, riderTwo}},
		{`INSERT INTO rider_profiles(user_id,display_name,vehicle_type,status) VALUES($1,'QA Rider One','two_wheeler','approved'),($2,'QA Rider Two','bicycle','approved')`, []any{riderOne, riderTwo}},
		{`INSERT INTO rider_profile_localities(rider_profile_id,locality_id,status) SELECT id,$3,'approved' FROM rider_profiles WHERE user_id IN ($1,$2)`, []any{riderOne, riderTwo, localityID}},
		{`INSERT INTO rider_availability_sessions(rider_user_id,is_online,lease_expires_at,last_heartbeat_at) VALUES($1,true,now()+interval '10 minutes',now()),($2,true,now()+interval '10 minutes',now())`, []any{riderOne, riderTwo}},
		{`INSERT INTO customer_addresses(id,customer_user_id,label,recipient_name,address_line1,locality,city,state,postal_code,contact_phone,is_default,delivery_locality_id) VALUES($1,$2,'QA','QA Customer','QA House 1','Kuanpal','Cuttack','Odisha','754082',$3,true,$4)`, []any{addressID, customerID, "+91" + phoneSuffix(), localityID}},
		{`INSERT INTO platform_checkout_quotes(id,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,delivery_fee_minor,tax_minor,grand_total_minor,expires_at) SELECT $1,$2,'food',$3,CURRENT_DATE,$4,updated_at,$5,'[{}]'::jsonb,10000,0,0,10000,now()+interval '5 minutes' FROM customer_addresses WHERE id=$4`, []any{quoteID, customerID, localityID, addressID, businessID}},
		{`INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,fulfillment_type,item_total,grand_total,reference_code,order_source,platform_vertical,delivery_locality_id,platform_checkout_quote_id,delivery_address_snapshot) VALUES($1,$2,$3,'platform_order','placed','delivery',100,100,$4,'platform_catalog','food',$5,$6,'{}'::jsonb)`, []any{orderID, customerID, businessID, "QA-" + uuid.NewString(), localityID, quoteID}},
		{`INSERT INTO platform_catalog_products(id,sku,category_id,name,status) SELECT $1,$2,id,'QA Dispatch Test Dish','active' FROM platform_catalog_categories WHERE vertical='food' AND slug='food'`, []any{productID, "qa-dispatch-" + uuid.NewString()}},
		{`INSERT INTO platform_catalog_variants(id,product_id,sku,name,unit_label,price_minor) VALUES($1,$2,$3,'QA Portion','1 serving',10000)`, []any{variantID, productID, "qa-dispatch-variant-" + uuid.NewString()}},
		{`INSERT INTO platform_customer_order_items(order_id,product_id,variant_id,vertical,product_name,variant_name,unit_label,unit_price_minor,quantity,price_revision) VALUES($1,$2,$3,'food','QA Dispatch Test Dish','QA Portion','1 serving',10000,1,1)`, []any{orderID, productID, variantID}},
		{`UPDATE platform_checkout_quotes SET consumed_order_id=$1 WHERE id=$2`, []any{orderID, quoteID}},
		{`UPDATE customer_orders SET status='accepted' WHERE id=$1`, []any{orderID}},
		{`UPDATE customer_orders SET status='preparing' WHERE id=$1`, []any{orderID}},
	}
	for _, item := range queries {
		if _, err := db.ExecContext(ctx, item.query, item.args...); err != nil {
			t.Fatalf("QA fixture/setup failed: %v", err)
		}
	}

	// Customers can open order history immediately after checkout, before the
	// merchant starts preparation and the dispatch job exists.
	preDispatchOrderID := newID()
	preDispatchQuoteID := newID()
	if _, err := db.ExecContext(ctx, `INSERT INTO platform_checkout_quotes(id,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,delivery_fee_minor,tax_minor,grand_total_minor,expires_at) SELECT $1,$2,'food',$3,CURRENT_DATE,$4,updated_at,$5,'[{}]'::jsonb,10000,0,0,10000,now()+interval '5 minutes' FROM customer_addresses WHERE id=$4`, preDispatchQuoteID, customerID, localityID, addressID, businessID); err != nil {
		t.Fatalf("create pre-dispatch QA quote: %v", err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,fulfillment_type,item_total,grand_total,reference_code,order_source,platform_vertical,delivery_locality_id,platform_checkout_quote_id) VALUES($1,$2,$3,'platform_order','placed','delivery',100,100,$4,'platform_catalog','food',$5,$6)`, preDispatchOrderID, customerID, businessID, "QA-"+uuid.NewString(), localityID, preDispatchQuoteID); err != nil {
		t.Fatalf("create pre-dispatch QA order: %v", err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO customer_order_status_events(order_id,status,event_kind,actor_user_id) VALUES($1,'placed','status_change',$2)`, preDispatchOrderID, customerID); err != nil {
		t.Fatalf("create pre-dispatch QA order event: %v", err)
	}
	preDispatchStatus := httptest.NewRecorder()
	preDispatchRequest := httptest.NewRequest("GET", "/orders/"+preDispatchOrderID+"/delivery-status", nil)
	preDispatchRequest.SetPathValue("id", preDispatchOrderID)
	service := NewService(db, nil, &config.Config{RiderDispatchEnabled: true, RiderOfferTimeout: 30 * time.Second, RiderAvailabilityLease: 2 * time.Minute})
	service.CustomerSummary(preDispatchStatus, preDispatchRequest, customerID)
	if preDispatchStatus.Code != 200 || !strings.Contains(preDispatchStatus.Body.String(), `"delivery_state":"not_dispatched"`) || !strings.Contains(preDispatchStatus.Body.String(), `"execution_state":"not_started"`) {
		t.Fatalf("owned pre-dispatch order should return an accurate empty delivery state: HTTP %d %s", preDispatchStatus.Code, preDispatchStatus.Body.String())
	}
	// A dispatch job that has exhausted candidates is not an assigned rider.
	// The customer API must not expose the schema's default execution state as
	// proof of assignment when no active assignment row exists.
	if _, err := db.ExecContext(ctx, `INSERT INTO delivery_jobs(order_id,business_id,locality_id,state) VALUES($1,$2,$3,'no_rider_available')`, preDispatchOrderID, businessID, localityID); err != nil {
		t.Fatalf("create no-rider QA delivery job: %v", err)
	}
	noRiderStatus := httptest.NewRecorder()
	service.CustomerSummary(noRiderStatus, preDispatchRequest, customerID)
	if noRiderStatus.Code != 200 || !strings.Contains(noRiderStatus.Body.String(), `"delivery_state":"no_rider_available"`) || !strings.Contains(noRiderStatus.Body.String(), `"rider_assigned":false`) || !strings.Contains(noRiderStatus.Body.String(), `"execution_state":"not_started"`) {
		t.Fatalf("no-rider job should not imply rider assignment: HTTP %d %s", noRiderStatus.Code, noRiderStatus.Body.String())
	}
	preDispatchTimeline := httptest.NewRecorder()
	service.CustomerTimeline(preDispatchTimeline, preDispatchRequest, customerID)
	if preDispatchTimeline.Code != 200 || !strings.Contains(preDispatchTimeline.Body.String(), `"to_state":"placed"`) {
		t.Fatalf("owned pre-dispatch order should return its available order history: HTTP %d %s", preDispatchTimeline.Code, preDispatchTimeline.Body.String())
	}
	foreignPreDispatchTimeline := httptest.NewRecorder()
	service.CustomerTimeline(foreignPreDispatchTimeline, preDispatchRequest, newID())
	if foreignPreDispatchTimeline.Code != 404 {
		t.Fatalf("foreign customer read pre-dispatch order history: HTTP %d", foreignPreDispatchTimeline.Code)
	}

	heartbeat := httptest.NewRecorder()
	service.Heartbeat(heartbeat, httptest.NewRequest("POST", "/rider/availability/heartbeat", nil), riderOne)
	if heartbeat.Code != 200 {
		t.Fatalf("eligible rider availability heartbeat failed: HTTP %d %s", heartbeat.Code, heartbeat.Body.String())
	}
	// Deterministic heartbeat-vs-expiry race (Gate B case 7): pause the real
	// handler after its valid initial lease read, let the real expiry worker
	// commit, then resume the conditional heartbeat update.
	type raceResult struct {
		name string
		code int
		err  error
	}
	heartbeatAtUpdate := make(chan struct{})
	resumeHeartbeat := make(chan struct{})
	service.beforeHeartbeatLeaseUpdate = func() {
		close(heartbeatAtUpdate)
		<-resumeHeartbeat
	}
	raceResults := make(chan raceResult, 2)
	go func() {
		res := httptest.NewRecorder()
		service.Heartbeat(res, httptest.NewRequest("POST", "/rider/availability/heartbeat", nil), riderOne)
		raceResults <- raceResult{name: "heartbeat", code: res.Code}
	}()
	select {
	case <-heartbeatAtUpdate:
	case <-time.After(5 * time.Second):
		t.Fatal("heartbeat did not reach the explicit pre-update barrier")
	}
	if _, err := db.ExecContext(ctx, `UPDATE rider_availability_sessions SET lease_expires_at=now()-interval '1 second' WHERE rider_user_id=$1`, riderOne); err != nil {
		close(resumeHeartbeat)
		t.Fatalf("expire rider lease at barrier: %v", err)
	}
	if err := service.Process(ctx); err != nil {
		close(resumeHeartbeat)
		t.Fatalf("expiry worker failed at controlled race boundary: %v", err)
	}
	close(resumeHeartbeat)
	service.beforeHeartbeatLeaseUpdate = nil
	heartbeatResult := <-raceResults
	var leaseOnline bool
	if err := db.GetContext(ctx, &leaseOnline, `SELECT is_online AND lease_expires_at>now() FROM rider_availability_sessions WHERE rider_user_id=$1`, riderOne); err != nil {
		t.Fatal(err)
	}
	if leaseOnline || heartbeatResult.code != 409 {
		t.Fatalf("expiry winner must be reflected by heartbeat response and canonical DB state: heartbeat_http=%d online=%v", heartbeatResult.code, leaseOnline)
	}
	// The real recovery path is to explicitly go online again; restore Rider
	// One for the remaining independent legacy acceptance scenario.
	reonline := httptest.NewRecorder()
	service.SetAvailability(reonline, httptest.NewRequest("PUT", "/rider/availability", strings.NewReader(`{"online":true}`)), riderOne)
	if reonline.Code != 200 {
		t.Fatalf("rider could not restore availability after lease expiry: HTTP %d %s", reonline.Code, reonline.Body.String())
	}
	if err := service.Process(ctx); err != nil {
		t.Fatal(err)
	}
	var jobID, offerID, assignedRider string
	if err := db.QueryRowxContext(ctx, `SELECT id::text FROM delivery_jobs WHERE order_id=$1`, orderID).Scan(&jobID); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRowxContext(ctx, `SELECT id::text,rider_user_id::text FROM delivery_offers WHERE job_id=$1 AND state='offered'`, jobID).Scan(&offerID, &assignedRider); err != nil {
		t.Fatal(err)
	}
	if assignedRider != riderOne && assignedRider != riderTwo {
		t.Fatalf("offer assigned to ineligible rider %s", assignedRider)
	}
	otherRider := riderOne
	if assignedRider == riderOne {
		otherRider = riderTwo
	}
	wrongOwner := httptest.NewRecorder()
	wrongRequest := httptest.NewRequest("GET", "/rider/offers/"+offerID, nil)
	wrongRequest.SetPathValue("offerId", offerID)
	service.GetOffer(wrongOwner, wrongRequest, otherRider)
	if wrongOwner.Code != 404 {
		t.Fatalf("another rider read offer: HTTP %d", wrongOwner.Code)
	}
	offerList := httptest.NewRecorder()
	service.Offers(offerList, httptest.NewRequest("GET", "/rider/offers", nil), assignedRider)
	if offerList.Code != 200 || !strings.Contains(offerList.Body.String(), "QA Dispatch Test Dish") {
		t.Fatalf("rider offer inbox failed to load order item snapshots: HTTP %d %s", offerList.Code, offerList.Body.String())
	}

	// Gate B case 2: acceptance is queued on the offer row while the expiry
	// worker is held at its database scan boundary. Advance expiry in the
	// disposable transaction, then release both real service paths.
	if _, err := db.ExecContext(ctx, `UPDATE delivery_offers SET offered_at=now()-interval '1 minute',expires_at=now()+interval '500 milliseconds' WHERE id=$1`, offerID); err != nil {
		t.Fatalf("prepare acceptance/expiry race offer: %v", err)
	}
	expiryLock, err := db.BeginTxx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	var expiryLockedID string
	if err := expiryLock.QueryRowxContext(ctx, `SELECT id::text FROM delivery_offers WHERE id=$1 FOR UPDATE`, offerID).Scan(&expiryLockedID); err != nil {
		expiryLock.Rollback()
		t.Fatal(err)
	}
	processAtScan := make(chan struct{})
	resumeProcess := make(chan struct{})
	service.beforeProcessExpiredOffers = func() { close(processAtScan); <-resumeProcess }
	processResult := make(chan error, 1)
	go func() { processResult <- service.Process(ctx) }()
	select {
	case <-processAtScan:
	case <-time.After(5 * time.Second):
		expiryLock.Rollback()
		t.Fatal("expiry worker did not reach controlled scan barrier")
	}
	type offerAcceptResult struct {
		code int
		body string
	}
	acceptResult := make(chan offerAcceptResult, 1)
	go func() {
		rec := httptest.NewRecorder()
		req := httptest.NewRequest("POST", "/rider/offers/"+offerID+"/accept", nil)
		req.SetPathValue("offerId", offerID)
		service.RespondOffer(rec, req, assignedRider, "accept")
		acceptResult <- offerAcceptResult{code: rec.Code, body: rec.Body.String()}
	}()
	if err := waitForDatabaseLockWaits(ctx, db, 1); err != nil {
		expiryLock.Rollback()
		close(resumeProcess)
		t.Fatalf("acceptance did not queue on offer row: %v", err)
	}
	if _, err := expiryLock.ExecContext(ctx, `UPDATE delivery_offers SET expires_at=now()-interval '1 second' WHERE id=$1`, offerID); err != nil {
		expiryLock.Rollback()
		close(resumeProcess)
		t.Fatalf("expire offer at barrier: %v", err)
	}
	if err := expiryLock.Commit(); err != nil {
		close(resumeProcess)
		t.Fatal(err)
	}
	close(resumeProcess)
	service.beforeProcessExpiredOffers = nil
	select {
	case err := <-processResult:
		if err != nil {
			t.Fatalf("expiry processing failed: %v", err)
		}
	case <-time.After(8 * time.Second):
		t.Fatal("expiry processing exceeded bounded deadline")
	}
	select {
	case result := <-acceptResult:
		if result.code != 409 {
			t.Fatalf("expired offer acceptance returned HTTP %d, expected 409: %s", result.code, result.body)
		}
	case <-time.After(8 * time.Second):
		t.Fatal("offer acceptance exceeded bounded deadline")
	}
	var expiredOfferState string
	var expiredOfferAssignments, expiryEventCount int
	if err := db.QueryRowxContext(ctx, `SELECT x.state,(SELECT count(*) FROM delivery_assignments a WHERE a.offer_id=x.id),(SELECT count(*) FROM delivery_events e WHERE e.offer_id=x.id AND e.event_type='offer_expired') FROM delivery_offers x WHERE x.id=$1`, offerID).Scan(&expiredOfferState, &expiredOfferAssignments, &expiryEventCount); err != nil {
		t.Fatal(err)
	}
	if expiredOfferState != "expired" || expiredOfferAssignments != 0 || expiryEventCount != 1 {
		t.Fatalf("expired offer must be terminal without assignment: state=%s assignments=%d expiry_events=%d", expiredOfferState, expiredOfferAssignments, expiryEventCount)
	}
	var secondOfferID, secondRider string
	if err := db.QueryRowxContext(ctx, `SELECT id::text,rider_user_id::text FROM delivery_offers WHERE job_id=$1 AND state='offered'`, jobID).Scan(&secondOfferID, &secondRider); err != nil {
		t.Fatalf("dispatch did not advance after expiry: %v", err)
	}
	if secondRider != otherRider {
		t.Fatalf("expiry did not advance sequentially to remaining rider %s: got %s", otherRider, secondRider)
	}

	// Gate B case 1 equivalent: the schema and sequential dispatcher enforce
	// one active offer per job, so distinct riders cannot legitimately own the
	// same offer. Race its assigned rider against a different rider claiming it.
	acceptAs := func(rider string) int {
		recorder := httptest.NewRecorder()
		request := httptest.NewRequest("POST", "/rider/offers/"+secondOfferID+"/accept", nil)
		request.SetPathValue("offerId", secondOfferID)
		service.RespondOffer(recorder, request, rider, "accept")
		return recorder.Code
	}
	ownerAndIntruder := raceWhileRowLocked(t, ctx, db, `SELECT id FROM delivery_offers WHERE id=$1 FOR UPDATE`, []any{secondOfferID}, 1,
		func() int { return acceptAs(secondRider) },
		func() int { return acceptAs(assignedRider) },
	)
	if !containsStatus(ownerAndIntruder, 200) || !containsStatus(ownerAndIntruder, 404) || len(ownerAndIntruder) != 2 {
		t.Fatalf("same-offer ownership race should allow one assigned rider and reject the other: responses=%v", ownerAndIntruder)
	}
	var assignments int
	if err := db.GetContext(ctx, &assignments, `SELECT count(*) FROM delivery_assignments WHERE job_id=$1 AND state='active'`, jobID); err != nil {
		t.Fatal(err)
	}
	if assignments != 1 {
		t.Fatalf("expected exactly one active assignment, got %d", assignments)
	}
	var acceptanceAuditCount int
	if err := db.GetContext(ctx, &acceptanceAuditCount, `SELECT count(*) FROM audit_logs WHERE action='delivery.rider_accepted' AND target_id=$1`, jobID); err != nil {
		t.Fatal(err)
	}
	if acceptanceAuditCount != 1 {
		t.Fatalf("same-offer ownership race created %d acceptance audit rows; expected 1", acceptanceAuditCount)
	}
	activeHeartbeat := httptest.NewRecorder()
	service.Heartbeat(activeHeartbeat, httptest.NewRequest("POST", "/rider/availability/heartbeat", nil), secondRider)
	if activeHeartbeat.Code != 200 {
		t.Fatalf("assigned rider heartbeat should keep its lease alive: HTTP %d %s", activeHeartbeat.Code, activeHeartbeat.Body.String())
	}
	unableBody := `{"reason":"Rider reports a vehicle issue and requests operations assistance."}`
	unableRequest := httptest.NewRequest("POST", "/rider/delivery-jobs/"+jobID+"/unable-to-continue", strings.NewReader(unableBody))
	unableRequest.SetPathValue("jobId", jobID)
	unableRequest.Header.Set("Idempotency-Key", "qa-rider-unable-1")
	unable := httptest.NewRecorder()
	service.ReportUnableToContinue(unable, unableRequest, secondRider)
	if unable.Code != 201 {
		t.Fatalf("rider recovery report failed: HTTP %d %s", unable.Code, unable.Body.String())
	}
	unableReplayRequest := httptest.NewRequest("POST", unableRequest.URL.Path, strings.NewReader(unableBody))
	unableReplayRequest.SetPathValue("jobId", jobID)
	unableReplayRequest.Header.Set("Idempotency-Key", "qa-rider-unable-1")
	unableReplay := httptest.NewRecorder()
	service.ReportUnableToContinue(unableReplay, unableReplayRequest, secondRider)
	if unableReplay.Code != 201 || !strings.Contains(unableReplay.Body.String(), `"idempotent":true`) {
		t.Fatalf("rider recovery retry was not idempotent: HTTP %d %s", unableReplay.Code, unableReplay.Body.String())
	}
	if _, err := db.ExecContext(ctx, `UPDATE rider_availability_sessions SET lease_expires_at=now()-interval '1 second' WHERE rider_user_id=$1`, secondRider); err != nil {
		t.Fatal(err)
	}
	if err := service.Process(ctx); err != nil {
		t.Fatalf("stale lease processing failed: %v", err)
	}
	var staleCaseCount, retainedAssignments int
	if err := db.GetContext(ctx, &staleCaseCount, `SELECT count(*) FROM delivery_recovery_cases WHERE job_id=$1 AND assignment_id=(SELECT id FROM delivery_assignments WHERE job_id=$1 AND state='active') AND incident_type='assignment_heartbeat_stale' AND state='open'`, jobID); err != nil {
		t.Fatal(err)
	}
	if err := db.GetContext(ctx, &retainedAssignments, `SELECT count(*) FROM delivery_assignments WHERE job_id=$1 AND state='active'`, jobID); err != nil {
		t.Fatal(err)
	}
	if staleCaseCount != 1 || retainedAssignments != 1 {
		t.Fatalf("lease expiry must open one case without releasing custody: cases=%d active_assignments=%d", staleCaseCount, retainedAssignments)
	}
	queueRecorder := httptest.NewRecorder()
	service.AdminRecoveryCases(queueRecorder, httptest.NewRequest("GET", "/admin/delivery-recovery-cases", nil), adminID)
	if queueRecorder.Code != 200 {
		t.Fatalf("Admin recovery queue failed: HTTP %d %s", queueRecorder.Code, queueRecorder.Body.String())
	}
	var queuePayload struct {
		Data []map[string]any `json:"data"`
	}
	if err := json.Unmarshal(queueRecorder.Body.Bytes(), &queuePayload); err != nil || len(queuePayload.Data) < 2 {
		t.Fatalf("recovery queue should include rider and stale-lease cases: rows=%d err=%v", len(queuePayload.Data), err)
	}
	var reportCaseID string
	for _, row := range queuePayload.Data {
		if row["incident_type"] == "rider_reports_unable_to_continue" {
			reportCaseID, _ = row["id"].(string)
			if row["custody_transferred"] != false || row["assignment_active"] != true || row["partner_confirmed_no_handover"] != false {
				t.Fatalf("recovery queue should show active pre-pickup custody evidence truthfully: %#v", row)
			}
		}
	}
	if reportCaseID == "" {
		t.Fatal("recovery queue omitted rider incident")
	}
	alertsRecorder := httptest.NewRecorder()
	service.AdminOperationsAlerts(alertsRecorder, httptest.NewRequest("GET", "/admin/delivery-operations/alerts", nil), adminID)
	if alertsRecorder.Code != 200 {
		t.Fatalf("Admin operations alerts failed: HTTP %d %s", alertsRecorder.Code, alertsRecorder.Body.String())
	}
	var alertsPayload struct {
		Data []map[string]any `json:"data"`
		Meta map[string]any   `json:"meta"`
	}
	if err := json.Unmarshal(alertsRecorder.Body.Bytes(), &alertsPayload); err != nil {
		t.Fatalf("invalid operations alerts response: %v", err)
	}
	var staleAlertFound bool
	for _, alert := range alertsPayload.Data {
		if alert["alert_type"] == "assignment_heartbeat_stale" && alert["job_id"] == jobID {
			staleAlertFound = true
			if alert["custody_active"] != false || alert["recommended_action"] != "Investigate rider lease; assignment retained" {
				t.Fatalf("stale lease alert must preserve custody truth: %#v", alert)
			}
			for _, sensitive := range []string{"contact_phone", "recipient_name", "address", "otp", "rider_kyc"} {
				if _, exists := alert[sensitive]; exists {
					t.Fatalf("operations alert leaked sensitive field %q", sensitive)
				}
			}
		}
	}
	if !staleAlertFound || alertsPayload.Meta["automatic_resolution"] != false {
		t.Fatalf("expected persisted stale-assignment alert and no automatic resolution: %#v", alertsPayload)
	}
	eventRequest := httptest.NewRequest("GET", "/admin/delivery-recovery-cases/"+reportCaseID+"/events", nil)
	eventRequest.SetPathValue("caseId", reportCaseID)
	eventsRecorder := httptest.NewRecorder()
	service.AdminRecoveryCaseEvents(eventsRecorder, eventRequest, adminID)
	if eventsRecorder.Code != 200 || !strings.Contains(eventsRecorder.Body.String(), "rider_reported_unable_to_continue") {
		t.Fatalf("sanitized recovery history failed: HTTP %d %s", eventsRecorder.Code, eventsRecorder.Body.String())
	}
	if _, err := db.ExecContext(ctx, `UPDATE rider_availability_sessions SET is_online=true,lease_expires_at=now()+interval '2 minutes',last_heartbeat_at=now(),updated_at=now() WHERE rider_user_id=$1`, secondRider); err != nil {
		t.Fatal(err)
	}
	var jobState string
	if err := db.GetContext(ctx, &jobState, `SELECT state FROM delivery_jobs WHERE id=$1`, jobID); err != nil {
		t.Fatal(err)
	}
	if jobState != "assigned" {
		t.Fatalf("expected assigned job, got %s", jobState)
	}
	var paymentStatus string
	if err := db.GetContext(ctx, &paymentStatus, `SELECT payment_status FROM customer_orders WHERE id=$1`, orderID); err != nil {
		t.Fatal(err)
	}
	if paymentStatus != "not_collected" {
		t.Fatalf("dispatch changed payment status to %s", paymentStatus)
	}

	customerStatus := httptest.NewRecorder()
	customerRequest := httptest.NewRequest("GET", "/orders/"+orderID+"/delivery-status", nil)
	customerRequest.SetPathValue("id", orderID)
	service.CustomerSummary(customerStatus, customerRequest, customerID)
	if customerStatus.Code != 200 {
		t.Fatalf("order owner couldn't see status: %d", customerStatus.Code)
	}
	if strings.Contains(customerStatus.Body.String(), secondRider) {
		t.Fatal("customer delivery status exposed rider identity before pickup")
	}
	foreignStatus := httptest.NewRecorder()
	service.CustomerSummary(foreignStatus, customerRequest, newID())
	if foreignStatus.Code != 404 {
		t.Fatalf("foreign customer read dispatch status: %d", foreignStatus.Code)
	}
	merchantStatus := httptest.NewRecorder()
	merchantRequest := httptest.NewRequest("GET", "/merchant/businesses/"+businessID+"/delivery-dispatch", nil)
	merchantRequest.SetPathValue("businessId", businessID)
	service.MerchantSummary(merchantStatus, merchantRequest, merchantID)
	if merchantStatus.Code != 200 {
		t.Fatalf("assigned business couldn't see dispatch summary: %d %s", merchantStatus.Code, merchantStatus.Body.String())
	}
	foreignMerchantStatus := httptest.NewRecorder()
	service.MerchantSummary(foreignMerchantStatus, merchantRequest, foreignMerchantID)
	if foreignMerchantStatus.Code != 403 {
		t.Fatalf("foreign merchant read dispatch summary: %d", foreignMerchantStatus.Code)
	}

	// Admin assignment must not bypass the explicit online lease, and a valid
	// override must leave both dispatch and general audit records.
	if _, err := db.ExecContext(ctx, `UPDATE rider_availability_sessions SET is_online=false,updated_at=now() WHERE rider_user_id=$1`, otherRider); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE delivery_assignments SET state='cancelled',ended_at=now() WHERE job_id=$1 AND state='active'`, jobID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE delivery_jobs SET state='pending_dispatch',updated_at=now() WHERE id=$1`, jobID); err != nil {
		t.Fatal(err)
	}
	manualBody := `{"rider_user_id":"` + otherRider + `","reason":"QA manual assignment verification"}`
	manualRequest := httptest.NewRequest("POST", "/admin/delivery-jobs/"+jobID+"/assign", strings.NewReader(manualBody))
	manualRequest.SetPathValue("jobId", jobID)
	offlineAssignment := httptest.NewRecorder()
	service.ManualAssign(offlineAssignment, manualRequest, adminID)
	if offlineAssignment.Code != 409 {
		t.Fatalf("Admin assignment bypassed offline rider state: HTTP %d %s", offlineAssignment.Code, offlineAssignment.Body.String())
	}
	if _, err := db.ExecContext(ctx, `UPDATE rider_availability_sessions SET is_online=true,lease_expires_at=now()+interval '2 minutes',updated_at=now() WHERE rider_user_id=$1`, otherRider); err != nil {
		t.Fatal(err)
	}
	manualRequest = httptest.NewRequest("POST", "/admin/delivery-jobs/"+jobID+"/assign", strings.NewReader(manualBody))
	manualRequest.SetPathValue("jobId", jobID)
	manualAssignment := httptest.NewRecorder()
	service.ManualAssign(manualAssignment, manualRequest, adminID)
	if manualAssignment.Code != 200 {
		t.Fatalf("eligible Admin override failed: HTTP %d %s", manualAssignment.Code, manualAssignment.Body.String())
	}
	var auditCount int
	if err := db.GetContext(ctx, &auditCount, `SELECT count(*) FROM audit_logs WHERE actor_user_id=$1 AND action='delivery.manual_assignment' AND target_id=$2`, adminID, jobID); err != nil {
		t.Fatal(err)
	}
	if auditCount != 1 {
		t.Fatalf("expected one Admin manual-assignment audit row, got %d", auditCount)
	}

	// Exhausting the eligible rider pool records a typed run number in the
	// dispatch event. This protects the PostgreSQL JSON parameter path used by
	// the background worker when every offer has been declined or no rider is
	// currently available.
	if _, err := db.ExecContext(ctx, `UPDATE rider_availability_sessions SET is_online=false,updated_at=now() WHERE rider_user_id IN ($1,$2)`, riderOne, riderTwo); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE delivery_assignments SET state='cancelled',ended_at=now() WHERE job_id=$1 AND state='active'`, jobID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE delivery_jobs SET state='pending_dispatch',updated_at=now() WHERE id=$1`, jobID); err != nil {
		t.Fatal(err)
	}
	if err := service.Process(ctx); err != nil {
		t.Fatalf("dispatch exhaustion failed: %v", err)
	}
	var exhaustedState string
	if err := db.GetContext(ctx, &exhaustedState, `SELECT state FROM delivery_jobs WHERE id=$1`, jobID); err != nil {
		t.Fatal(err)
	}
	if exhaustedState != "no_rider_available" {
		t.Fatalf("expected no_rider_available after exhausting candidates, got %s", exhaustedState)
	}
	var eventCount int
	if err := db.GetContext(ctx, &eventCount, `SELECT count(*) FROM delivery_events WHERE job_id=$1 AND event_type='dispatch_exhausted' AND jsonb_typeof(metadata->'run_number')='number'`, jobID); err != nil {
		t.Fatal(err)
	}
	if eventCount == 0 {
		t.Fatal("dispatch exhaustion did not persist a numeric run_number audit event")
	}

	// Create a second populated QA order to exercise verified pickup, delivery
	// OTP, replay protection, concurrency, cancellation protection, and history.
	executionOrderID, executionQuoteID := newID(), newID()
	if _, err := db.ExecContext(ctx, `INSERT INTO platform_checkout_quotes(id,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,grand_total_minor,expires_at) SELECT $1,$2,'food',$3,CURRENT_DATE,$4,updated_at,$5,'[{}]'::jsonb,10000,10000,now()+interval '5 minutes' FROM customer_addresses WHERE id=$4`, executionQuoteID, customerID, localityID, addressID, businessID); err != nil {
		t.Fatalf("create execution QA quote: %v", err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,fulfillment_type,item_total,grand_total,reference_code,order_source,platform_vertical,delivery_locality_id,platform_checkout_quote_id,payment_status,delivery_address_snapshot) VALUES($1,$2,$3,'platform_order','accepted','delivery',100,100,$4,'platform_catalog','food',$5,$6,'not_collected','{"address_line1":"QA House","locality":"Kuanpal","city":"Cuttack","state":"Odisha","postal_code":"754082","recipient_name":"QA Customer","contact_phone":"+919900000002"}'::jsonb)`, executionOrderID, customerID, businessID, "QA-EXEC-"+uuid.NewString(), localityID, executionQuoteID); err != nil {
		t.Fatalf("create execution QA order: %v", err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE platform_checkout_quotes SET consumed_order_id=$1 WHERE id=$2`, executionOrderID, executionQuoteID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO platform_customer_order_items(order_id,product_id,variant_id,vertical,product_name,variant_name,unit_label,unit_price_minor,quantity,price_revision) VALUES($1,$2,$3,'food','QA Dispatch Test Dish','QA Portion','1 serving',10000,1,1)`, executionOrderID, productID, variantID); err != nil {
		t.Fatalf("create populated delivery order: %v", err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE customer_orders SET status='preparing' WHERE id=$1`, executionOrderID); err != nil {
		t.Fatalf("prepare execution QA order: %v", err)
	}
	var executionJobID string
	if err := db.GetContext(ctx, &executionJobID, `SELECT id::text FROM delivery_jobs WHERE order_id=$1`, executionOrderID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO delivery_assignments(job_id,rider_user_id) VALUES($1,$2)`, executionJobID, riderOne); err != nil {
		t.Fatalf("assign execution QA rider: %v", err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE delivery_jobs SET state='assigned' WHERE id=$1`, executionJobID); err != nil {
		t.Fatal(err)
	}
	transition := func(state string) *httptest.ResponseRecorder {
		recorder := httptest.NewRecorder()
		request := httptest.NewRequest("POST", "/rider/delivery-jobs/"+executionJobID+"/state", strings.NewReader(`{"state":"`+state+`"}`))
		request.SetPathValue("jobId", executionJobID)
		service.RiderTransition(recorder, request, riderOne)
		return recorder
	}
	if _, err := db.ExecContext(ctx, `UPDATE rider_profiles SET status='suspended' WHERE user_id=$1`, riderOne); err != nil {
		t.Fatal(err)
	}
	if got := transition("arriving_at_pickup"); got.Code != 403 {
		t.Fatalf("suspended rider execution returned %d", got.Code)
	}
	if _, err := db.ExecContext(ctx, `UPDATE rider_profiles SET status='approved' WHERE user_id=$1`, riderOne); err != nil {
		t.Fatal(err)
	}
	if got := transition("arriving_at_pickup"); got.Code != 200 {
		t.Fatalf("rider arrival failed: %d %s", got.Code, got.Body.String())
	}
	if got := transition("at_pickup"); got.Code != 409 {
		t.Fatalf("rider reached pickup before partner readiness: %d", got.Code)
	}
	if _, err := db.ExecContext(ctx, `UPDATE customer_orders SET status='ready_for_pickup' WHERE id=$1`, executionOrderID); err != nil {
		t.Fatalf("ready execution QA order: %v", err)
	}
	if got := transition("at_pickup"); got.Code != 200 {
		t.Fatalf("rider at-pickup transition failed: %d %s", got.Code, got.Body.String())
	}
	pickupMerchantSummary := httptest.NewRecorder()
	pickupMerchantRequest := httptest.NewRequest("GET", "/merchant/businesses/"+businessID+"/delivery-dispatch", nil)
	pickupMerchantRequest.SetPathValue("businessId", businessID)
	service.MerchantSummary(pickupMerchantSummary, pickupMerchantRequest, merchantID)
	if pickupMerchantSummary.Code != 200 ||
		!strings.Contains(pickupMerchantSummary.Body.String(), `"order_id":"`+executionOrderID+`"`) ||
		!strings.Contains(pickupMerchantSummary.Body.String(), `"execution_state":"at_pickup"`) ||
		!strings.Contains(pickupMerchantSummary.Body.String(), `"rider_assigned":true`) {
		t.Fatalf("Merchant dispatch projection did not expose pickup eligibility: HTTP %d %s", pickupMerchantSummary.Code, pickupMerchantSummary.Body.String())
	}

	foreignPickup := httptest.NewRecorder()
	foreignPickupRequest := httptest.NewRequest("POST", "/merchant/businesses/"+businessID+"/delivery-jobs/"+executionJobID+"/pickup-code", nil)
	foreignPickupRequest.SetPathValue("businessId", businessID)
	foreignPickupRequest.SetPathValue("jobId", executionJobID)
	service.IssuePickupCode(foreignPickup, foreignPickupRequest, foreignMerchantID)
	if foreignPickup.Code != 403 {
		t.Fatalf("foreign business issued pickup code: %d", foreignPickup.Code)
	}

	issuePickup := func() string {
		recorder := httptest.NewRecorder()
		request := httptest.NewRequest("POST", "/merchant/businesses/"+businessID+"/delivery-jobs/"+executionJobID+"/pickup-code", nil)
		request.SetPathValue("businessId", businessID)
		request.SetPathValue("jobId", executionJobID)
		service.IssuePickupCode(recorder, request, merchantID)
		if recorder.Code != 200 {
			t.Fatalf("pickup code issue failed: %d %s", recorder.Code, recorder.Body.String())
		}
		var data struct {
			Data struct {
				Code string `json:"pickup_code"`
			} `json:"data"`
		}
		if err := json.Unmarshal(recorder.Body.Bytes(), &data); err != nil {
			t.Fatal(err)
		}
		return data.Data.Code
	}
	verifyPickup := func(rider, code string) *httptest.ResponseRecorder {
		recorder := httptest.NewRecorder()
		request := httptest.NewRequest("POST", "/rider/delivery-jobs/"+executionJobID+"/pickup/verify", strings.NewReader(`{"code":"`+code+`"}`))
		request.SetPathValue("jobId", executionJobID)
		service.VerifyPickup(recorder, request, rider)
		return recorder
	}
	pickupCode := issuePickup()
	unassignedRider := riderTwo
	if got := verifyPickup(unassignedRider, pickupCode); got.Code != 404 {
		t.Fatalf("unassigned rider verified pickup: %d", got.Code)
	}
	if _, err := db.ExecContext(ctx, `UPDATE delivery_verification_codes SET issued_at=now()-interval '10 minutes',expires_at=now()-interval '5 minutes' WHERE job_id=$1 AND purpose='pickup'`, executionJobID); err != nil {
		t.Fatal(err)
	}
	if got := verifyPickup(riderOne, pickupCode); got.Code != 401 {
		t.Fatalf("expired pickup code accepted: %d %s", got.Code, got.Body.String())
	}
	pickupCode = issuePickup()
	wrongPickupCode := "0" + pickupCode[1:]
	if wrongPickupCode == pickupCode {
		wrongPickupCode = "1" + pickupCode[1:]
	}
	for attempt := 0; attempt < verificationMaxAttempts; attempt++ {
		if got := verifyPickup(riderOne, wrongPickupCode); got.Code != 401 {
			t.Fatalf("incorrect pickup code attempt %d returned %d", attempt+1, got.Code)
		}
	}
	if got := verifyPickup(riderOne, pickupCode); got.Code != 409 {
		t.Fatalf("pickup code remained valid after attempt limit: %d", got.Code)
	}
	if _, err := db.ExecContext(ctx, `UPDATE delivery_verification_codes SET issued_at=now()-interval '31 seconds' WHERE id=(SELECT id FROM delivery_verification_codes WHERE job_id=$1 AND purpose='pickup' ORDER BY issued_at DESC LIMIT 1)`, executionJobID); err != nil {
		t.Fatal(err)
	}
	pickupCode = issuePickup()
	var pickupWG sync.WaitGroup
	pickupCodes := make(chan int, 2)
	for range 2 {
		pickupWG.Add(1)
		go func() { defer pickupWG.Done(); pickupCodes <- verifyPickup(riderOne, pickupCode).Code }()
	}
	pickupWG.Wait()
	close(pickupCodes)
	for code := range pickupCodes {
		if code != 200 {
			t.Fatalf("concurrent pickup verification returned HTTP %d", code)
		}
	}
	if got := verifyPickup(riderOne, pickupCode); got.Code != 200 || !strings.Contains(got.Body.String(), "idempotent") {
		t.Fatalf("pickup replay was not idempotent: %d %s", got.Code, got.Body.String())
	}
	var pickedAssignmentID string
	if err := db.GetContext(ctx, &pickedAssignmentID, `SELECT id::text FROM delivery_assignments WHERE job_id=$1 AND state='active'`, executionJobID); err != nil {
		t.Fatal(err)
	}
	pickedRecoveryBody := `{"action":"release_and_reassign_before_pickup","reason":"Test must not release physical custody after verified pickup.","expected_assignment_id":"` + pickedAssignmentID + `","expected_execution_state":"picked_up","partner_confirmed_no_handover":true}`
	pickedRecoveryRequest := httptest.NewRequest("POST", "/admin/delivery-jobs/"+executionJobID+"/recovery", strings.NewReader(pickedRecoveryBody))
	pickedRecoveryRequest.SetPathValue("jobId", executionJobID)
	pickedRecoveryRequest.Header.Set("Idempotency-Key", "qa-picked-recovery-1")
	pickedRecovery := httptest.NewRecorder()
	service.AdminRecover(pickedRecovery, pickedRecoveryRequest, adminID)
	if pickedRecovery.Code != 422 || !strings.Contains(pickedRecovery.Body.String(), "INVALID_RECOVERY_STATE") {
		t.Fatalf("recovery accepted a post-pickup state: HTTP %d %s", pickedRecovery.Code, pickedRecovery.Body.String())
	}
	if _, err := db.ExecContext(ctx, `UPDATE customer_orders SET status='cancelled' WHERE id=$1`, executionOrderID); err == nil {
		t.Fatal("order cancellation after physical pickup was accepted")
	}
	if got := transition("en_route"); got.Code != 200 {
		t.Fatalf("en-route transition failed: %d %s", got.Code, got.Body.String())
	}
	issueDeliveryCode := func(customer string) *httptest.ResponseRecorder {
		recorder := httptest.NewRecorder()
		request := httptest.NewRequest("POST", "/orders/"+executionOrderID+"/delivery-code", nil)
		request.SetPathValue("id", executionOrderID)
		service.IssueDeliveryCode(recorder, request, customer)
		return recorder
	}
	if got := issueDeliveryCode(newID()); got.Code != 404 {
		t.Fatalf("foreign customer requested delivery code: %d", got.Code)
	}
	deliveryCodeResponse := issueDeliveryCode(customerID)
	if deliveryCodeResponse.Code != 200 {
		t.Fatalf("customer delivery code issue failed: %d %s", deliveryCodeResponse.Code, deliveryCodeResponse.Body.String())
	}
	var deliveryData struct {
		Data struct {
			Code string `json:"delivery_code"`
		} `json:"data"`
	}
	if err := json.Unmarshal(deliveryCodeResponse.Body.Bytes(), &deliveryData); err != nil {
		t.Fatal(err)
	}
	confirmDelivery := func(code string) *httptest.ResponseRecorder {
		recorder := httptest.NewRecorder()
		request := httptest.NewRequest("POST", "/rider/delivery-jobs/"+executionJobID+"/delivery/confirm", strings.NewReader(`{"code":"`+code+`"}`))
		request.SetPathValue("jobId", executionJobID)
		service.ConfirmDelivery(recorder, request, riderOne)
		return recorder
	}
	if _, err := db.ExecContext(ctx, `UPDATE delivery_verification_codes SET issued_at=now()-interval '31 seconds',expires_at=now()-interval '1 second' WHERE job_id=$1 AND purpose='delivery'`, executionJobID); err != nil {
		t.Fatal(err)
	}
	if got := confirmDelivery(deliveryData.Data.Code); got.Code != 401 {
		t.Fatalf("expired customer delivery code accepted: %d", got.Code)
	}
	deliveryCodeResponse = issueDeliveryCode(customerID)
	if deliveryCodeResponse.Code != 200 {
		t.Fatalf("customer could not request a fresh expired code: %d %s", deliveryCodeResponse.Code, deliveryCodeResponse.Body.String())
	}
	if err := json.Unmarshal(deliveryCodeResponse.Body.Bytes(), &deliveryData); err != nil {
		t.Fatal(err)
	}
	deliveryCode := deliveryData.Data.Code
	wrongDeliveryCode := "0" + deliveryCode[1:]
	if wrongDeliveryCode == deliveryCode {
		wrongDeliveryCode = "1" + deliveryCode[1:]
	}
	for attempt := 0; attempt < verificationMaxAttempts; attempt++ {
		if got := confirmDelivery(wrongDeliveryCode); got.Code != 401 {
			t.Fatalf("incorrect delivery code attempt %d returned %d", attempt+1, got.Code)
		}
	}
	if got := confirmDelivery(deliveryCode); got.Code != 409 {
		t.Fatalf("delivery code remained valid after attempt limit: %d", got.Code)
	}
	if _, err := db.ExecContext(ctx, `UPDATE delivery_verification_codes SET issued_at=now()-interval '31 seconds' WHERE id=(SELECT id FROM delivery_verification_codes WHERE job_id=$1 AND purpose='delivery' ORDER BY issued_at DESC LIMIT 1)`, executionJobID); err != nil {
		t.Fatal(err)
	}
	deliveryCodeResponse = issueDeliveryCode(customerID)
	if deliveryCodeResponse.Code != 200 {
		t.Fatalf("customer could not request code after cooldown: %d %s", deliveryCodeResponse.Code, deliveryCodeResponse.Body.String())
	}
	if err := json.Unmarshal(deliveryCodeResponse.Body.Bytes(), &deliveryData); err != nil {
		t.Fatal(err)
	}
	deliveryCode = deliveryData.Data.Code
	var completionWG sync.WaitGroup
	completionCodes := make(chan int, 2)
	for range 2 {
		completionWG.Add(1)
		go func() { defer completionWG.Done(); completionCodes <- confirmDelivery(deliveryCode).Code }()
	}
	completionWG.Wait()
	close(completionCodes)
	for code := range completionCodes {
		if code != 200 {
			t.Fatalf("concurrent delivery completion returned HTTP %d", code)
		}
	}
	var finalExecution, finalOrder, finalPayment string
	if err := db.QueryRowxContext(ctx, `SELECT j.execution_state,o.status,o.payment_status FROM delivery_jobs j JOIN customer_orders o ON o.id=j.order_id WHERE j.id=$1`, executionJobID).Scan(&finalExecution, &finalOrder, &finalPayment); err != nil {
		t.Fatal(err)
	}
	if finalExecution != "delivered" || finalOrder != "delivered" || finalPayment != "not_collected" {
		t.Fatalf("unexpected final states: delivery=%s order=%s payment=%s", finalExecution, finalOrder, finalPayment)
	}
	completedSummary := httptest.NewRecorder()
	completedSummaryRequest := httptest.NewRequest("GET", "/orders/"+executionOrderID+"/delivery-status", nil)
	completedSummaryRequest.SetPathValue("id", executionOrderID)
	service.CustomerSummary(completedSummary, completedSummaryRequest, customerID)
	if completedSummary.Code != 200 || !strings.Contains(completedSummary.Body.String(), `"execution_state":"delivered"`) || !strings.Contains(completedSummary.Body.String(), `"rider_assigned":false`) {
		t.Fatalf("completed customer summary did not preserve terminal state after assignment release: HTTP %d %s", completedSummary.Code, completedSummary.Body.String())
	}
	var completionHistory int
	if err := db.GetContext(ctx, &completionHistory, `SELECT count(*) FROM delivery_execution_events WHERE job_id=$1 AND to_state='delivered'`, executionJobID); err != nil {
		t.Fatal(err)
	}
	if completionHistory != 1 {
		t.Fatalf("expected one immutable completion event, got %d", completionHistory)
	}
	adminBoard := httptest.NewRecorder()
	service.AdminBoard(adminBoard, httptest.NewRequest("GET", "/admin/delivery-jobs", nil), adminID)
	if adminBoard.Code != 200 || !strings.Contains(adminBoard.Body.String(), `"assigned_rider_user_id":"`+secondRider+`"`) ||
		!strings.Contains(adminBoard.Body.String(), `"order_id":"`+executionOrderID+`"`) ||
		!strings.Contains(adminBoard.Body.String(), `"customer_user_id":"`+customerID+`"`) {
		t.Fatalf("Admin dispatch board lost the completed order identity or rider: HTTP %d %s", adminBoard.Code, adminBoard.Body.String())
	}
	foreignTimeline := httptest.NewRecorder()
	foreignTimelineRequest := httptest.NewRequest("GET", "/orders/"+executionOrderID+"/delivery-history", nil)
	foreignTimelineRequest.SetPathValue("id", executionOrderID)
	service.CustomerTimeline(foreignTimeline, foreignTimelineRequest, newID())
	if foreignTimeline.Code != 404 {
		t.Fatalf("foreign customer read delivery timeline: %d", foreignTimeline.Code)
	}
	for index, status := range []string{"placed", "accepted", "preparing", "ready_for_pickup", "out_for_delivery", "delivered"} {
		if _, err := db.ExecContext(ctx, `INSERT INTO customer_order_status_events(order_id,status,event_kind,created_at) VALUES($1,$2,'status_change',now() - ((4 - $3) * interval '1 minute'))`, executionOrderID, status, index); err != nil {
			t.Fatalf("insert customer timeline fixture status %s: %v", status, err)
		}
	}
	customerTimeline := httptest.NewRecorder()
	customerTimelineRequest := httptest.NewRequest("GET", "/orders/"+executionOrderID+"/delivery-history", nil)
	customerTimelineRequest.SetPathValue("id", executionOrderID)
	service.CustomerTimeline(customerTimeline, customerTimelineRequest, customerID)
	var timelineResponse struct {
		Data []struct {
			EventType string `json:"event_type"`
			ToState   string `json:"to_state"`
		} `json:"data"`
	}
	if customerTimeline.Code != 200 || json.Unmarshal(customerTimeline.Body.Bytes(), &timelineResponse) != nil {
		t.Fatalf("customer unified timeline omitted real milestones, duplicated execution states, or exposed code issuance: HTTP %d %s", customerTimeline.Code, customerTimeline.Body.String())
	}
	counts := make(map[string]int)
	for _, event := range timelineResponse.Data {
		counts[event.EventType+":"+event.ToState]++
	}
	if counts["order_status:placed"] != 1 || counts["order_status:accepted"] != 1 || counts["order_status:preparing"] != 1 || counts["order_status:ready_for_pickup"] != 1 || counts["rider_assigned:assigned"] != 1 || counts["pickup_verified:picked_up"] != 1 || counts["customer_otp_verified:delivered"] != 1 || counts["order_status:out_for_delivery"] != 0 || counts["order_status:delivered"] != 0 || counts["pickup_code_issued:"] != 0 {
		t.Fatalf("customer timeline did not contain exactly one safe milestone of each expected kind: %#v; response=%s", counts, customerTimeline.Body.String())
	}

	// Exercise an unreachable-customer exception, audited Admin return decision,
	// rider return, and partner return receipt. This does not restore stock or
	// mark the customer order delivered.
	exceptionOrderID, exceptionQuoteID, returnVariantID, returnMappingID := newID(), newID(), newID(), newID()
	if _, err := db.ExecContext(ctx, `INSERT INTO platform_checkout_quotes(id,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,grand_total_minor,expires_at) SELECT $1,$2,'food',$3,CURRENT_DATE,$4,updated_at,$5,'[{}]'::jsonb,10000,10000,now()+interval '5 minutes' FROM customer_addresses WHERE id=$4`, exceptionQuoteID, customerID, localityID, addressID, businessID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,fulfillment_type,item_total,grand_total,reference_code,order_source,platform_vertical,delivery_locality_id,platform_checkout_quote_id,payment_status,delivery_address_snapshot) VALUES($1,$2,$3,'platform_order','accepted','delivery',100,100,$4,'platform_catalog','food',$5,$6,'not_collected','{"address_line1":"QA House","locality":"Kuanpal","city":"Cuttack","state":"Odisha","postal_code":"754082","recipient_name":"QA Customer","contact_phone":"+919900000002"}'::jsonb)`, exceptionOrderID, customerID, businessID, "QA-EXCEPTION-"+uuid.NewString(), localityID, exceptionQuoteID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE platform_checkout_quotes SET consumed_order_id=$1 WHERE id=$2`, exceptionOrderID, exceptionQuoteID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO platform_customer_order_items(order_id,product_id,variant_id,vertical,product_name,variant_name,unit_label,unit_price_minor,quantity,price_revision) VALUES($1,$2,$3,'food','QA Dispatch Test Dish','QA Portion','1 serving',10000,1,1)`, exceptionOrderID, productID, variantID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO platform_catalog_variants(id,product_id,sku,name,unit_label,price_minor) VALUES($1,$2,$3,'QA Return Portion','1 serving',10000)`, returnVariantID, productID, "qa-return-variant-"+uuid.NewString()); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO platform_partner_product_mappings(id,business_id,variant_id,status,inventory_mode,available_quantity,supply_price_minor,created_by,approved_by,approved_at) VALUES($1,$2,$3,'approved','finite',0,5000,$4,$5,now())`, returnMappingID, businessID, returnVariantID, merchantID, adminID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO platform_inventory_reservations(order_id,mapping_id,quantity,inventory_mode,service_date,status) VALUES($1,$2,1,'finite',CURRENT_DATE,'reserved')`, exceptionOrderID, returnMappingID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE customer_orders SET status='preparing' WHERE id=$1`, exceptionOrderID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE customer_orders SET status='ready_for_pickup' WHERE id=$1`, exceptionOrderID); err != nil {
		t.Fatal(err)
	}
	var exceptionJobID string
	if err := db.GetContext(ctx, &exceptionJobID, `SELECT id::text FROM delivery_jobs WHERE order_id=$1`, exceptionOrderID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO delivery_assignments(job_id,rider_user_id) VALUES($1,$2)`, exceptionJobID, riderTwo); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE delivery_jobs SET state='assigned' WHERE id=$1`, exceptionJobID); err != nil {
		t.Fatal(err)
	}
	for _, next := range []string{"arriving_at_pickup", "at_pickup"} {
		rec := httptest.NewRecorder()
		req := httptest.NewRequest("POST", "/rider/delivery-jobs/"+exceptionJobID+"/state", strings.NewReader(`{"state":"`+next+`"}`))
		req.SetPathValue("jobId", exceptionJobID)
		service.RiderTransition(rec, req, riderTwo)
		if rec.Code != 200 {
			t.Fatalf("exception scenario transition %s failed: %d %s", next, rec.Code, rec.Body.String())
		}
	}
	exceptionPickup := httptest.NewRecorder()
	exceptionPickupRequest := httptest.NewRequest("POST", "/merchant/businesses/"+businessID+"/delivery-jobs/"+exceptionJobID+"/pickup-code", nil)
	exceptionPickupRequest.SetPathValue("businessId", businessID)
	exceptionPickupRequest.SetPathValue("jobId", exceptionJobID)
	service.IssuePickupCode(exceptionPickup, exceptionPickupRequest, merchantID)
	var exceptionPickupData struct {
		Data struct {
			Code string `json:"pickup_code"`
		} `json:"data"`
	}
	if err := json.Unmarshal(exceptionPickup.Body.Bytes(), &exceptionPickupData); err != nil {
		t.Fatal(err)
	}
	if exceptionPickup.Code != 200 {
		t.Fatalf("exception scenario pickup code failed: %d %s", exceptionPickup.Code, exceptionPickup.Body.String())
	}
	exceptionVerify := httptest.NewRecorder()
	exceptionVerifyRequest := httptest.NewRequest("POST", "/rider/delivery-jobs/"+exceptionJobID+"/pickup/verify", strings.NewReader(`{"code":"`+exceptionPickupData.Data.Code+`"}`))
	exceptionVerifyRequest.SetPathValue("jobId", exceptionJobID)
	service.VerifyPickup(exceptionVerify, exceptionVerifyRequest, riderTwo)
	if exceptionVerify.Code != 200 {
		t.Fatalf("exception scenario pickup verification failed: %d %s", exceptionVerify.Code, exceptionVerify.Body.String())
	}
	exceptionEnRoute := httptest.NewRecorder()
	exceptionEnRouteRequest := httptest.NewRequest("POST", "/rider/delivery-jobs/"+exceptionJobID+"/state", strings.NewReader(`{"state":"en_route"}`))
	exceptionEnRouteRequest.SetPathValue("jobId", exceptionJobID)
	service.RiderTransition(exceptionEnRoute, exceptionEnRouteRequest, riderTwo)
	if exceptionEnRoute.Code != 200 {
		t.Fatalf("exception scenario en-route failed: %d %s", exceptionEnRoute.Code, exceptionEnRoute.Body.String())
	}
	reportException := httptest.NewRecorder()
	reportExceptionRequest := httptest.NewRequest("POST", "/rider/delivery-jobs/"+exceptionJobID+"/unable-to-continue", strings.NewReader(`{"reason":"Rider vehicle issue requires operations help after pickup."}`))
	reportExceptionRequest.SetPathValue("jobId", exceptionJobID)
	reportExceptionRequest.Header.Set("Idempotency-Key", "qa-rider-unable-after-pickup")
	service.ReportUnableToContinue(reportException, reportExceptionRequest, riderTwo)
	if reportException.Code != 201 {
		t.Fatalf("post-pickup unable-to-continue report failed: %d %s", reportException.Code, reportException.Body.String())
	}
	adminExceptions := httptest.NewRecorder()
	service.AdminExceptions(adminExceptions, httptest.NewRequest("GET", "/admin/delivery-exceptions", nil), adminID)
	if adminExceptions.Code != 200 || !strings.Contains(adminExceptions.Body.String(), "rider_unable_to_continue") {
		t.Fatalf("Admin exception list failed: %d %s", adminExceptions.Code, adminExceptions.Body.String())
	}
	var exceptionID string
	if err := db.GetContext(ctx, &exceptionID, `SELECT id::text FROM delivery_exceptions WHERE job_id=$1 AND state='open'`, exceptionJobID); err != nil {
		t.Fatal(err)
	}
	var exceptionAssignmentID string
	if err := db.GetContext(ctx, &exceptionAssignmentID, `SELECT id::text FROM delivery_assignments WHERE job_id=$1 AND state='active'`, exceptionJobID); err != nil {
		t.Fatal(err)
	}
	wrongAssignmentRequest := httptest.NewRequest("POST", "/admin/delivery-jobs/"+exceptionJobID+"/exceptions/"+exceptionID+"/resolve", strings.NewReader(`{"action":"require_return","reason":"Rider cannot continue; direct return to the partner for inspection.","expected_assignment_id":"`+newID()+`"}`))
	wrongAssignmentRequest.SetPathValue("jobId", exceptionJobID)
	wrongAssignmentRequest.SetPathValue("exceptionId", exceptionID)
	wrongAssignmentRequest.Header.Set("Idempotency-Key", "qa-admin-wrong-assignment")
	wrongAssignmentResponse := httptest.NewRecorder()
	service.ResolveException(wrongAssignmentResponse, wrongAssignmentRequest, adminID)
	if wrongAssignmentResponse.Code != 409 {
		t.Fatalf("wrong assignment reference should be rejected: HTTP %d %s", wrongAssignmentResponse.Code, wrongAssignmentResponse.Body.String())
	}
	resolutionBody := `{"action":"require_return","reason":"Rider cannot continue; direct return to the partner for inspection.","expected_assignment_id":"` + exceptionAssignmentID + `"}`
	resolveExceptionRequest := func() *httptest.ResponseRecorder {
		request := httptest.NewRequest("POST", "/admin/delivery-jobs/"+exceptionJobID+"/exceptions/"+exceptionID+"/resolve", strings.NewReader(resolutionBody))
		request.SetPathValue("jobId", exceptionJobID)
		request.SetPathValue("exceptionId", exceptionID)
		request.Header.Set("Idempotency-Key", "qa-admin-require-return-1")
		recorder := httptest.NewRecorder()
		service.ResolveException(recorder, request, adminID)
		return recorder
	}
	// Concurrent retries with one idempotency key must apply the transition once
	// and return the same successful resolution to both requests.
	var resolutionWait sync.WaitGroup
	resolutionResults := make(chan *httptest.ResponseRecorder, 2)
	for range 2 {
		resolutionWait.Add(1)
		go func() { defer resolutionWait.Done(); resolutionResults <- resolveExceptionRequest() }()
	}
	resolutionWait.Wait()
	close(resolutionResults)
	for result := range resolutionResults {
		if result.Code != 200 || !strings.Contains(result.Body.String(), `"state":"resolved"`) {
			t.Fatalf("concurrent Admin return resolution failed: %d %s", result.Code, result.Body.String())
		}
	}
	var activeAfterRequire bool
	var assignmentStateAfterRequire, executionStateAfterRequire string
	if err := db.QueryRowxContext(ctx, `SELECT a.state,j.execution_state FROM delivery_assignments a JOIN delivery_jobs j ON j.id=a.job_id WHERE a.id=$1`, exceptionAssignmentID).Scan(&assignmentStateAfterRequire, &executionStateAfterRequire); err != nil {
		t.Fatal(err)
	}
	activeAfterRequire = assignmentStateAfterRequire == "active"
	if !activeAfterRequire || executionStateAfterRequire != "return_required" {
		t.Fatalf("requiring return must preserve active physical custody: assignment=%s delivery=%s", assignmentStateAfterRequire, executionStateAfterRequire)
	}
	var returnOverrideCount, returnRecoveryEventCount, returnAuditCount int
	if err := db.QueryRowxContext(ctx, `SELECT (SELECT count(*) FROM delivery_execution_events WHERE job_id=$1 AND event_type='admin_return_override' AND from_state='en_route' AND to_state='return_required'),(SELECT count(*) FROM delivery_recovery_events WHERE job_id=$1 AND event_type='admin_required_return'),(SELECT count(*) FROM audit_logs WHERE target_id=$1 AND action='delivery.exception_resolved')`, exceptionJobID).Scan(&returnOverrideCount, &returnRecoveryEventCount, &returnAuditCount); err != nil {
		t.Fatal(err)
	}
	if returnOverrideCount != 1 || returnRecoveryEventCount != 1 || returnAuditCount != 1 {
		t.Fatalf("require-return audit/state transition was not exactly once: execution=%d recovery=%d audit=%d", returnOverrideCount, returnRecoveryEventCount, returnAuditCount)
	}
	returning := httptest.NewRecorder()
	returningRequest := httptest.NewRequest("POST", "/rider/delivery-jobs/"+exceptionJobID+"/state", strings.NewReader(`{"state":"return_in_progress"}`))
	returningRequest.SetPathValue("jobId", exceptionJobID)
	service.RiderTransition(returning, returningRequest, riderTwo)
	if returning.Code != 200 {
		t.Fatalf("rider return transition failed: %d %s", returning.Code, returning.Body.String())
	}
	returnReceivedRequest := httptest.NewRequest("POST", "/merchant/businesses/"+businessID+"/delivery-jobs/"+exceptionJobID+"/return/confirm", nil)
	returnReceivedRequest.SetPathValue("businessId", businessID)
	returnReceivedRequest.SetPathValue("jobId", exceptionJobID)
	returnResults := raceWhileRowLocked(t, ctx, db, `SELECT id FROM delivery_jobs WHERE id=$1 FOR UPDATE`, []any{exceptionJobID}, 2,
		func() int {
			res := httptest.NewRecorder()
			req := httptest.NewRequest("POST", returnReceivedRequest.URL.Path, nil)
			req.SetPathValue("businessId", businessID)
			req.SetPathValue("jobId", exceptionJobID)
			service.ConfirmReturn(res, req, merchantID)
			return res.Code
		},
		func() int {
			res := httptest.NewRecorder()
			req := httptest.NewRequest("POST", returnReceivedRequest.URL.Path, nil)
			req.SetPathValue("businessId", businessID)
			req.SetPathValue("jobId", exceptionJobID)
			service.ConfirmReturn(res, req, merchantID)
			return res.Code
		},
	)
	if returnResults[0] != 200 || returnResults[1] != 200 {
		t.Fatalf("concurrent duplicate merchant return receipt failed: responses=%v", returnResults)
	}
	var concurrentReceiptCount, concurrentReturnAuditCount, concurrentReturnEventCount int
	if err := db.QueryRowxContext(ctx, `SELECT (SELECT count(*) FROM delivery_return_receipts WHERE job_id=$1),(SELECT count(*) FROM audit_logs WHERE target_id=$1 AND action='delivery.return_received'),(SELECT count(*) FROM delivery_execution_events WHERE job_id=$1 AND event_type='return_received')`, exceptionJobID).Scan(&concurrentReceiptCount, &concurrentReturnAuditCount, &concurrentReturnEventCount); err != nil {
		t.Fatal(err)
	}
	if concurrentReceiptCount != 1 || concurrentReturnAuditCount != 1 || concurrentReturnEventCount != 1 {
		t.Fatalf("duplicate return race effects must be exactly once: receipts=%d audit=%d events=%d", concurrentReceiptCount, concurrentReturnAuditCount, concurrentReturnEventCount)
	}
	var returnedState, returnedOrder, paymentAfterReturn string
	if err := db.QueryRowxContext(ctx, `SELECT j.execution_state,o.status,o.payment_status FROM delivery_jobs j JOIN customer_orders o ON o.id=j.order_id WHERE j.id=$1`, exceptionJobID).Scan(&returnedState, &returnedOrder, &paymentAfterReturn); err != nil {
		t.Fatal(err)
	}
	if returnedState != "returned" || returnedOrder != "out_for_delivery" || paymentAfterReturn != "not_collected" {
		t.Fatalf("return handling changed order/payment unexpectedly: delivery=%s order=%s payment=%s", returnedState, returnedOrder, paymentAfterReturn)
	}
	returnReplay := httptest.NewRecorder()
	service.ConfirmReturn(returnReplay, returnReceivedRequest, merchantID)
	if returnReplay.Code != 200 || !strings.Contains(returnReplay.Body.String(), `"idempotent":true`) {
		t.Fatalf("duplicate return receipt should be idempotent: HTTP %d %s", returnReplay.Code, returnReplay.Body.String())
	}
	dispositionBody := `{"inventory_disposition":"restockable","reason":"Sealed items were inspected and remain safe for restocking."}`
	dispositionRequest := httptest.NewRequest("POST", "/merchant/businesses/"+businessID+"/delivery-jobs/"+exceptionJobID+"/return/disposition", strings.NewReader(dispositionBody))
	dispositionRequest.SetPathValue("businessId", businessID)
	dispositionRequest.SetPathValue("jobId", exceptionJobID)
	dispositionRequest.Header.Set("Idempotency-Key", "qa-return-disposition-1")
	disposition := httptest.NewRecorder()
	service.RecordReturnDisposition(disposition, dispositionRequest, merchantID)
	if disposition.Code != 200 {
		t.Fatalf("merchant return disposition failed: HTTP %d %s", disposition.Code, disposition.Body.String())
	}
	foreignDispositionRequest := httptest.NewRequest("POST", "/merchant/businesses/"+businessID+"/delivery-jobs/"+exceptionJobID+"/return/disposition", strings.NewReader(dispositionBody))
	foreignDispositionRequest.SetPathValue("businessId", businessID)
	foreignDispositionRequest.SetPathValue("jobId", exceptionJobID)
	foreignDispositionRequest.Header.Set("Idempotency-Key", "qa-foreign-disposition-1")
	foreignDisposition := httptest.NewRecorder()
	service.RecordReturnDisposition(foreignDisposition, foreignDispositionRequest, foreignMerchantID)
	if foreignDisposition.Code != 403 {
		t.Fatalf("foreign merchant recorded return inventory disposition: HTTP %d", foreignDisposition.Code)
	}
	dispositionReplayRequest := httptest.NewRequest("POST", dispositionRequest.URL.Path, strings.NewReader(dispositionBody))
	dispositionReplayRequest.SetPathValue("businessId", businessID)
	dispositionReplayRequest.SetPathValue("jobId", exceptionJobID)
	dispositionReplayRequest.Header.Set("Idempotency-Key", "qa-return-disposition-1")
	dispositionReplay := httptest.NewRecorder()
	service.RecordReturnDisposition(dispositionReplay, dispositionReplayRequest, merchantID)
	if dispositionReplay.Code != 200 || !strings.Contains(dispositionReplay.Body.String(), `"idempotent":true`) {
		t.Fatalf("replayed return disposition should be idempotent: HTTP %d %s", dispositionReplay.Code, dispositionReplay.Body.String())
	}
	finalizeBody := `{"reason":"Reviewed merchant inspection and finalized returned order disposition."}`
	finalizeRequest := httptest.NewRequest("POST", "/admin/delivery-jobs/"+exceptionJobID+"/return/finalize", strings.NewReader(finalizeBody))
	finalizeRequest.SetPathValue("jobId", exceptionJobID)
	finalizeRequest.Header.Set("Idempotency-Key", "qa-return-finalize-1")
	finalizeResults := raceWhileRowLocked(t, ctx, db, `SELECT id FROM delivery_jobs WHERE id=$1 FOR UPDATE`, []any{exceptionJobID}, 2,
		func() int {
			req := httptest.NewRequest("POST", finalizeRequest.URL.Path, strings.NewReader(finalizeBody))
			req.SetPathValue("jobId", exceptionJobID)
			req.Header.Set("Idempotency-Key", "qa-return-finalize-1")
			res := httptest.NewRecorder()
			service.AdminFinalizeReturn(res, req, adminID)
			return res.Code
		},
		func() int {
			req := httptest.NewRequest("POST", finalizeRequest.URL.Path, strings.NewReader(finalizeBody))
			req.SetPathValue("jobId", exceptionJobID)
			req.Header.Set("Idempotency-Key", "qa-return-finalize-1")
			res := httptest.NewRecorder()
			service.AdminFinalizeReturn(res, req, adminID)
			return res.Code
		},
	)
	if finalizeResults[0] != 200 || finalizeResults[1] != 200 {
		t.Fatalf("concurrent duplicate Admin finalization failed: responses=%v", finalizeResults)
	}
	var finalizeAuditCount int
	if err := db.GetContext(ctx, &finalizeAuditCount, `SELECT count(*) FROM audit_logs WHERE target_id=$1 AND action='delivery.return_finalized'`, exceptionJobID); err != nil {
		t.Fatal(err)
	}
	if finalizeAuditCount != 1 {
		t.Fatalf("duplicate finalization race wrote %d audit rows; expected 1", finalizeAuditCount)
	}
	finalizeReplayRequest := httptest.NewRequest("POST", finalizeRequest.URL.Path, strings.NewReader(finalizeBody))
	finalizeReplayRequest.SetPathValue("jobId", exceptionJobID)
	finalizeReplayRequest.Header.Set("Idempotency-Key", "qa-return-finalize-1")
	finalizeReplay := httptest.NewRecorder()
	service.AdminFinalizeReturn(finalizeReplay, finalizeReplayRequest, adminID)
	if finalizeReplay.Code != 200 || !strings.Contains(finalizeReplay.Body.String(), `"idempotent":true`) {
		t.Fatalf("replayed return finalization should be idempotent: HTTP %d %s", finalizeReplay.Code, finalizeReplay.Body.String())
	}
	var finalOrderStatus, finalPaymentStatus, finalReservationStatus string
	var returnedInventory int
	if err := db.QueryRowxContext(ctx, `SELECT o.status,o.payment_status,r.status,m.available_quantity FROM customer_orders o JOIN platform_inventory_reservations r ON r.order_id=o.id JOIN platform_partner_product_mappings m ON m.id=r.mapping_id WHERE o.id=$1`, exceptionOrderID).Scan(&finalOrderStatus, &finalPaymentStatus, &finalReservationStatus, &returnedInventory); err != nil {
		t.Fatal(err)
	}
	if finalOrderStatus != "returned" || finalPaymentStatus != "not_collected" || finalReservationStatus != "released" || returnedInventory != 1 {
		t.Fatalf("restockable return disposition was not applied once: order=%s payment=%s reservation=%s quantity=%d", finalOrderStatus, finalPaymentStatus, finalReservationStatus, returnedInventory)
	}
	var unresolvedRiderCases, finalizedRiderCases, riderReturnHistory, returnEarnings int
	if err := db.QueryRowxContext(ctx, `SELECT
		(SELECT count(*) FROM delivery_recovery_cases WHERE job_id=$1 AND incident_type='rider_reports_unable_to_continue' AND state IN ('open','investigating','action_pending','escalated')),
		(SELECT count(*) FROM delivery_recovery_cases WHERE job_id=$1 AND incident_type='rider_reports_unable_to_continue' AND state='resolved' AND resolution_code='returned_to_partner'),
		(SELECT count(*) FROM delivery_recovery_events e JOIN delivery_recovery_cases c ON c.id=e.case_id WHERE e.job_id=$1 AND e.event_type='return_finalized' AND c.incident_type='rider_reports_unable_to_continue'),
		(SELECT count(*) FROM rider_earning_entries WHERE delivery_job_id=$1 AND entry_type IN ('delivery_earning','unpriced'))`, exceptionJobID).Scan(&unresolvedRiderCases, &finalizedRiderCases, &riderReturnHistory, &returnEarnings); err != nil {
		t.Fatal(err)
	}
	if unresolvedRiderCases != 0 || finalizedRiderCases != 1 || riderReturnHistory != 1 || returnEarnings != 0 {
		t.Fatalf("finalized return must close rider case without earnings: open_cases=%d finalized_cases=%d return_events=%d earnings=%d", unresolvedRiderCases, finalizedRiderCases, riderReturnHistory, returnEarnings)
	}

	// Failed pre-pickup handover can be cancelled by Admin with exactly-once
	// reservation release; cancellation after pickup was rejected above.
	cancelOrderID, cancelQuoteID, mappingID := newID(), newID(), newID()
	if _, err := db.ExecContext(ctx, `INSERT INTO platform_checkout_quotes(id,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,grand_total_minor,expires_at) SELECT $1,$2,'food',$3,CURRENT_DATE,$4,updated_at,$5,'[{}]'::jsonb,20000,20000,now()+interval '5 minutes' FROM customer_addresses WHERE id=$4`, cancelQuoteID, customerID, localityID, addressID, businessID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,fulfillment_type,item_total,grand_total,reference_code,order_source,platform_vertical,delivery_locality_id,platform_checkout_quote_id,payment_status,delivery_address_snapshot) VALUES($1,$2,$3,'platform_order','accepted','delivery',200,200,$4,'platform_catalog','food',$5,$6,'not_collected','{"address_line1":"QA House","locality":"Kuanpal","city":"Cuttack","state":"Odisha","postal_code":"754082","recipient_name":"QA Customer","contact_phone":"+919900000002"}'::jsonb)`, cancelOrderID, customerID, businessID, "QA-CANCEL-"+uuid.NewString(), localityID, cancelQuoteID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE platform_checkout_quotes SET consumed_order_id=$1 WHERE id=$2`, cancelOrderID, cancelQuoteID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO platform_customer_order_items(order_id,product_id,variant_id,vertical,product_name,variant_name,unit_label,unit_price_minor,quantity,price_revision) VALUES($1,$2,$3,'food','QA Dispatch Test Dish','QA Portion','1 serving',10000,2,1)`, cancelOrderID, productID, variantID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO platform_partner_product_mappings(id,business_id,variant_id,status,inventory_mode,available_quantity,supply_price_minor,created_by,approved_by,approved_at) VALUES($1,$2,$3,'approved','finite',3,5000,$4,$5,now())`, mappingID, businessID, variantID, merchantID, adminID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO platform_inventory_reservations(order_id,mapping_id,quantity,inventory_mode,service_date,status) VALUES($1,$2,2,'finite',CURRENT_DATE,'reserved')`, cancelOrderID, mappingID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE customer_orders SET status='preparing' WHERE id=$1`, cancelOrderID); err != nil {
		t.Fatal(err)
	}
	var cancelJobID string
	if err := db.GetContext(ctx, &cancelJobID, `SELECT id::text FROM delivery_jobs WHERE order_id=$1`, cancelOrderID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO delivery_assignments(job_id,rider_user_id) VALUES($1,$2)`, cancelJobID, riderTwo); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE delivery_jobs SET state='assigned' WHERE id=$1`, cancelJobID); err != nil {
		t.Fatal(err)
	}
	pickupFailure := httptest.NewRecorder()
	pickupFailureRequest := httptest.NewRequest("POST", "/rider/delivery-jobs/"+cancelJobID+"/exceptions", strings.NewReader(`{"type":"pickup_failed","reason":"The partner could not provide the packed items."}`))
	pickupFailureRequest.SetPathValue("jobId", cancelJobID)
	service.ReportException(pickupFailure, pickupFailureRequest, riderTwo)
	if pickupFailure.Code != 201 {
		t.Fatalf("pickup failure report returned %d %s", pickupFailure.Code, pickupFailure.Body.String())
	}
	var openCancelExceptions int
	if err := db.GetContext(ctx, &openCancelExceptions, `SELECT count(*) FROM delivery_exceptions WHERE job_id=$1 AND state='open'`, cancelJobID); err != nil {
		t.Fatal(err)
	}
	if openCancelExceptions != 1 {
		t.Fatalf("expected one open pickup failure before recovery, got %d", openCancelExceptions)
	}
	var cancelAssignmentID string
	if err := db.GetContext(ctx, &cancelAssignmentID, `SELECT id::text FROM delivery_assignments WHERE job_id=$1 AND state='active'`, cancelJobID); err != nil {
		t.Fatal(err)
	}
	recoveryBody := `{"action":"cancel_before_pickup","reason":"Partner cannot fulfill and confirms goods remain at location.","expected_assignment_id":"` + cancelAssignmentID + `","expected_execution_state":"pickup_failed","partner_confirmed_no_handover":true}`
	unprovenRequest := httptest.NewRequest("POST", "/admin/delivery-jobs/"+cancelJobID+"/recovery", strings.NewReader(recoveryBody))
	unprovenRequest.SetPathValue("jobId", cancelJobID)
	unprovenRequest.Header.Set("Idempotency-Key", "qa-unproven-recovery-1")
	unproven := httptest.NewRecorder()
	service.AdminRecover(unproven, unprovenRequest, adminID)
	if unproven.Code != 422 || !strings.Contains(unproven.Body.String(), "HANDOVER_UNCONFIRMED") {
		t.Fatalf("Admin recovery proceeded without partner evidence: HTTP %d %s", unproven.Code, unproven.Body.String())
	}
	noHandoverRequest := httptest.NewRequest("POST", "/merchant/businesses/"+businessID+"/delivery-jobs/"+cancelJobID+"/recovery/no-handover", strings.NewReader(`{"assignment_id":"`+cancelAssignmentID+`","reason":"Partner confirms the packed goods were not handed to the assigned rider."}`))
	noHandoverRequest.SetPathValue("businessId", businessID)
	noHandoverRequest.SetPathValue("jobId", cancelJobID)
	noHandoverRequest.Header.Set("Idempotency-Key", "qa-no-handover-1")
	noHandover := httptest.NewRecorder()
	service.ConfirmNoHandover(noHandover, noHandoverRequest, merchantID)
	if noHandover.Code != 200 {
		t.Fatalf("merchant no-handover evidence failed: HTTP %d %s", noHandover.Code, noHandover.Body.String())
	}
	noHandoverReplayRequest := httptest.NewRequest("POST", noHandoverRequest.URL.Path, strings.NewReader(`{"assignment_id":"`+cancelAssignmentID+`","reason":"Partner confirms the packed goods were not handed to the assigned rider."}`))
	noHandoverReplayRequest.SetPathValue("businessId", businessID)
	noHandoverReplayRequest.SetPathValue("jobId", cancelJobID)
	noHandoverReplayRequest.Header.Set("Idempotency-Key", "qa-no-handover-1")
	noHandoverReplay := httptest.NewRecorder()
	service.ConfirmNoHandover(noHandoverReplay, noHandoverReplayRequest, merchantID)
	if noHandoverReplay.Code != 200 || !strings.Contains(noHandoverReplay.Body.String(), `"idempotent":true`) {
		t.Fatalf("partner no-handover replay was not idempotent: HTTP %d %s", noHandoverReplay.Code, noHandoverReplay.Body.String())
	}
	recoveryRequest := httptest.NewRequest("POST", "/admin/delivery-jobs/"+cancelJobID+"/recovery", strings.NewReader(recoveryBody))
	recoveryRequest.SetPathValue("jobId", cancelJobID)
	recoveryRequest.Header.Set("Idempotency-Key", "qa-cancel-recovery-1")
	var recoveryWG sync.WaitGroup
	recoveryResponses := make(chan *httptest.ResponseRecorder, 2)
	for range 2 {
		recoveryWG.Add(1)
		go func() {
			defer recoveryWG.Done()
			req := httptest.NewRequest("POST", recoveryRequest.URL.Path, strings.NewReader(recoveryBody))
			req.SetPathValue("jobId", cancelJobID)
			req.Header.Set("Idempotency-Key", "qa-cancel-recovery-1")
			res := httptest.NewRecorder()
			service.AdminRecover(res, req, adminID)
			recoveryResponses <- res
		}()
	}
	recoveryWG.Wait()
	close(recoveryResponses)
	for response := range recoveryResponses {
		if response.Code != 200 || !strings.Contains(response.Body.String(), `"state":"cancelled"`) {
			t.Fatalf("concurrent pre-pickup cancellation recovery failed: HTTP %d %s", response.Code, response.Body.String())
		}
	}
	recoveryReplayRequest := httptest.NewRequest("POST", recoveryRequest.URL.Path, strings.NewReader(recoveryBody))
	recoveryReplayRequest.SetPathValue("jobId", cancelJobID)
	recoveryReplayRequest.Header.Set("Idempotency-Key", "qa-cancel-recovery-1")
	recoveryReplay := httptest.NewRecorder()
	service.AdminRecover(recoveryReplay, recoveryReplayRequest, adminID)
	if recoveryReplay.Code != 200 || !strings.Contains(recoveryReplay.Body.String(), `"idempotent":true`) {
		t.Fatalf("pre-pickup cancellation replay was not idempotent: HTTP %d %s", recoveryReplay.Code, recoveryReplay.Body.String())
	}
	conflictingReplayRequest := httptest.NewRequest("POST", recoveryRequest.URL.Path, strings.NewReader(strings.Replace(recoveryBody, "Partner cannot fulfill", "Partner has another reason", 1)))
	conflictingReplayRequest.SetPathValue("jobId", cancelJobID)
	conflictingReplayRequest.Header.Set("Idempotency-Key", "qa-cancel-recovery-1")
	conflictingReplay := httptest.NewRecorder()
	service.AdminRecover(conflictingReplay, conflictingReplayRequest, adminID)
	if conflictingReplay.Code != 409 || !strings.Contains(conflictingReplay.Body.String(), "IDEMPOTENCY_CONFLICT") {
		t.Fatalf("same key with changed payload was not rejected: HTTP %d %s", conflictingReplay.Code, conflictingReplay.Body.String())
	}
	var cancelledExecution, cancelledOrder, reservationState string
	var restoredQuantity int
	if err := db.QueryRowxContext(ctx, `SELECT j.execution_state,o.status,r.status,m.available_quantity FROM delivery_jobs j JOIN customer_orders o ON o.id=j.order_id JOIN platform_inventory_reservations r ON r.order_id=o.id JOIN platform_partner_product_mappings m ON m.id=r.mapping_id WHERE j.id=$1`, cancelJobID).Scan(&cancelledExecution, &cancelledOrder, &reservationState, &restoredQuantity); err != nil {
		t.Fatal(err)
	}
	var activeCancelledAssignments int
	if err := db.GetContext(ctx, &activeCancelledAssignments, `SELECT count(*) FROM delivery_assignments WHERE job_id=$1 AND state='active'`, cancelJobID); err != nil {
		t.Fatal(err)
	}
	if cancelledExecution != "cancelled" || cancelledOrder != "cancelled" || reservationState != "released" || restoredQuantity != 5 || activeCancelledAssignments != 0 {
		t.Fatalf("pre-pickup cancellation didn't close assignment and release inventory exactly once: execution=%s order=%s reservation=%s quantity=%d active_assignments=%d", cancelledExecution, cancelledOrder, reservationState, restoredQuantity, activeCancelledAssignments)
	}
	var cancellationAuditCount, recoveryEffectCount int
	if err := db.GetContext(ctx, &cancellationAuditCount, `SELECT count(*) FROM audit_logs WHERE actor_user_id=$1 AND action='delivery.recovery.cancel_before_pickup' AND target_id=$2`, adminID, cancelJobID); err != nil {
		t.Fatal(err)
	}
	if err := db.GetContext(ctx, &recoveryEffectCount, `SELECT count(*) FROM delivery_recovery_events WHERE job_id=$1 AND event_type='cancelled_before_pickup'`, cancelJobID); err != nil {
		t.Fatal(err)
	}
	if cancellationAuditCount != 1 || recoveryEffectCount != 1 {
		t.Fatalf("concurrent recovery emitted duplicate effects: audit=%d recovery_events=%d", cancellationAuditCount, recoveryEffectCount)
	}

	// Gate B case 4: a post-pickup return decision races a valid customer-code
	// delivery completion on a separate isolated order. Both handlers contend
	// on the delivery_jobs row before either can decide the terminal direction.
	returnRaceOrderID, returnRaceQuoteID := newID(), newID()
	if _, err := db.ExecContext(ctx, `INSERT INTO platform_checkout_quotes(id,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,grand_total_minor,expires_at) SELECT $1,$2,'food',$3,CURRENT_DATE,$4,updated_at,$5,'[{}]'::jsonb,10000,10000,now()+interval '5 minutes' FROM customer_addresses WHERE id=$4`, returnRaceQuoteID, customerID, localityID, addressID, businessID); err != nil {
		t.Fatalf("create return/completion race quote: %v", err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,fulfillment_type,item_total,grand_total,reference_code,order_source,platform_vertical,delivery_locality_id,platform_checkout_quote_id,payment_status) VALUES($1,$2,$3,'platform_order','accepted','delivery',100,100,$4,'platform_catalog','food',$5,$6,'not_collected')`, returnRaceOrderID, customerID, businessID, "QA-RACE-RETURN-"+uuid.NewString(), localityID, returnRaceQuoteID); err != nil {
		t.Fatalf("create return/completion race order: %v", err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE platform_checkout_quotes SET consumed_order_id=$1 WHERE id=$2`, returnRaceOrderID, returnRaceQuoteID); err != nil {
		t.Fatalf("consume return/completion race quote: %v", err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE customer_orders SET status='preparing' WHERE id=$1`, returnRaceOrderID); err != nil {
		t.Fatalf("prepare return/completion race order: %v", err)
	}
	var returnRaceJobID, returnRaceAssignmentID string
	if err := db.GetContext(ctx, &returnRaceJobID, `SELECT id::text FROM delivery_jobs WHERE order_id=$1`, returnRaceOrderID); err != nil {
		t.Fatalf("load return/completion race delivery job: %v", err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE delivery_jobs SET state='assigned',execution_state='en_route' WHERE id=$1`, returnRaceJobID); err != nil {
		t.Fatalf("set return/completion race delivery state: %v", err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO delivery_assignments(job_id,rider_user_id) VALUES($1,$2)`, returnRaceJobID, riderOne); err != nil {
		t.Fatalf("assign return/completion race rider: %v", err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE customer_orders SET status='out_for_delivery' WHERE id=$1`, returnRaceOrderID); err != nil {
		t.Fatalf("prepare return/completion race state: %v", err)
	}
	if err := db.GetContext(ctx, &returnRaceAssignmentID, `SELECT id::text FROM delivery_assignments WHERE job_id=$1 AND state='active'`, returnRaceJobID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO delivery_execution_events(job_id,actor_user_id,actor_type,event_type,from_state,to_state) VALUES($1,$2,'rider','pickup_verified','at_pickup','picked_up'),($1,$2,'rider','en_route','picked_up','en_route')`, returnRaceJobID, riderOne); err != nil {
		t.Fatalf("seed truthful custody history for race: %v", err)
	}
	returnRaceCodeResponse := httptest.NewRecorder()
	returnRaceCodeRequest := httptest.NewRequest("POST", "/orders/"+returnRaceOrderID+"/delivery-code", nil)
	returnRaceCodeRequest.SetPathValue("id", returnRaceOrderID)
	service.IssueDeliveryCode(returnRaceCodeResponse, returnRaceCodeRequest, customerID)
	var returnRaceCodePayload struct {
		Data struct {
			Code string `json:"delivery_code"`
		} `json:"data"`
	}
	if returnRaceCodeResponse.Code != 200 || json.Unmarshal(returnRaceCodeResponse.Body.Bytes(), &returnRaceCodePayload) != nil {
		t.Fatalf("issue return/completion race customer code: HTTP %d %s", returnRaceCodeResponse.Code, returnRaceCodeResponse.Body.String())
	}
	unableForRace := httptest.NewRecorder()
	unableForRaceRequest := httptest.NewRequest("POST", "/rider/delivery-jobs/"+returnRaceJobID+"/unable-to-continue", strings.NewReader(`{"reason":"Rider cannot safely continue this delivery and requests operations review."}`))
	unableForRaceRequest.SetPathValue("jobId", returnRaceJobID)
	unableForRaceRequest.Header.Set("Idempotency-Key", "qa-return-complete-race-report")
	service.ReportUnableToContinue(unableForRace, unableForRaceRequest, riderOne)
	if unableForRace.Code != 201 {
		t.Fatalf("create return/completion race exception: HTTP %d %s", unableForRace.Code, unableForRace.Body.String())
	}
	var returnRaceExceptionID string
	if err := db.GetContext(ctx, &returnRaceExceptionID, `SELECT id::text FROM delivery_exceptions WHERE job_id=$1 AND state='open'`, returnRaceJobID); err != nil {
		t.Fatal(err)
	}
	requireReturnBody := `{"action":"require_return","reason":"Rider cannot continue; return the order to the partner for inspection.","expected_assignment_id":"` + returnRaceAssignmentID + `"}`
	requireReturnStatus := func() int {
		req := httptest.NewRequest("POST", "/admin/delivery-jobs/"+returnRaceJobID+"/exceptions/"+returnRaceExceptionID+"/resolve", strings.NewReader(requireReturnBody))
		req.SetPathValue("jobId", returnRaceJobID)
		req.SetPathValue("exceptionId", returnRaceExceptionID)
		req.Header.Set("Idempotency-Key", "qa-return-completion-admin")
		res := httptest.NewRecorder()
		service.ResolveException(res, req, adminID)
		return res.Code
	}
	completeDeliveryStatus := func() int {
		req := httptest.NewRequest("POST", "/rider/delivery-jobs/"+returnRaceJobID+"/delivery/confirm", strings.NewReader(`{"code":"`+returnRaceCodePayload.Data.Code+`"}`))
		req.SetPathValue("jobId", returnRaceJobID)
		res := httptest.NewRecorder()
		service.ConfirmDelivery(res, req, riderOne)
		return res.Code
	}
	returnVersusCompletion := raceWhileRowLocked(t, ctx, db, `SELECT id FROM delivery_jobs WHERE id=$1 FOR UPDATE`, []any{returnRaceJobID}, 2, requireReturnStatus, completeDeliveryStatus)
	if len(returnVersusCompletion) != 2 || !containsStatus(returnVersusCompletion, 200) || !containsStatus(returnVersusCompletion, 409) {
		t.Fatalf("Require Return versus delivery completion must yield one winner and one conflict: responses=%v", returnVersusCompletion)
	}
	var returnRaceExecution, returnRaceOrderStatus, returnRacePayment string
	var returnRaceActiveAssignments, returnRaceCompletionEarnings, returnRaceAdminEvents, returnRaceDeliveryEvents int
	if err := db.QueryRowxContext(ctx, `SELECT j.execution_state,o.status,o.payment_status,(SELECT count(*) FROM delivery_assignments a WHERE a.job_id=j.id AND a.state='active'),(SELECT count(*) FROM rider_earning_entries e WHERE e.delivery_job_id=j.id AND e.entry_type IN ('delivery_earning','unpriced')),(SELECT count(*) FROM delivery_execution_events e WHERE e.job_id=j.id AND e.event_type='admin_return_override'),(SELECT count(*) FROM delivery_execution_events e WHERE e.job_id=j.id AND e.event_type='customer_otp_verified') FROM delivery_jobs j JOIN customer_orders o ON o.id=j.order_id WHERE j.id=$1`, returnRaceJobID).Scan(&returnRaceExecution, &returnRaceOrderStatus, &returnRacePayment, &returnRaceActiveAssignments, &returnRaceCompletionEarnings, &returnRaceAdminEvents, &returnRaceDeliveryEvents); err != nil {
		t.Fatal(err)
	}
	if returnRacePayment != "not_collected" || returnRaceCompletionEarnings != 0 || !((returnRaceExecution == "return_required" && returnRaceOrderStatus == "out_for_delivery" && returnRaceActiveAssignments == 1 && returnRaceAdminEvents == 1 && returnRaceDeliveryEvents == 0) || (returnRaceExecution == "delivered" && returnRaceOrderStatus == "delivered" && returnRaceActiveAssignments == 0 && returnRaceAdminEvents == 0 && returnRaceDeliveryEvents == 1)) {
		t.Fatalf("Require Return/completion race violated terminal, custody or financial invariants: execution=%s order=%s payment=%s active_assignments=%d earnings=%d return_events=%d delivery_events=%d", returnRaceExecution, returnRaceOrderStatus, returnRacePayment, returnRaceActiveAssignments, returnRaceCompletionEarnings, returnRaceAdminEvents, returnRaceDeliveryEvents)
	}

	// Gate B case 3: authorized pre-pickup release races with a valid pickup
	// code. The exact assignment and partner no-handover evidence are scoped to
	// this disposable order; PostgreSQL serializes both real handler paths.
	pickupRaceOrderID, pickupRaceQuoteID := newID(), newID()
	if _, err := db.ExecContext(ctx, `INSERT INTO platform_checkout_quotes(id,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,grand_total_minor,expires_at) SELECT $1,$2,'food',$3,CURRENT_DATE,$4,updated_at,$5,'[{}]'::jsonb,10000,10000,now()+interval '5 minutes' FROM customer_addresses WHERE id=$4`, pickupRaceQuoteID, customerID, localityID, addressID, businessID); err != nil {
		t.Fatalf("create pickup race quote: %v", err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,fulfillment_type,item_total,grand_total,reference_code,order_source,platform_vertical,delivery_locality_id,platform_checkout_quote_id,payment_status) VALUES($1,$2,$3,'platform_order','accepted','delivery',100,100,$4,'platform_catalog','food',$5,$6,'not_collected')`, pickupRaceOrderID, customerID, businessID, "QA-RACE-PICKUP-"+uuid.NewString(), localityID, pickupRaceQuoteID); err != nil {
		t.Fatalf("create pickup race order: %v", err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE platform_checkout_quotes SET consumed_order_id=$1 WHERE id=$2`, pickupRaceOrderID, pickupRaceQuoteID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE customer_orders SET status='preparing' WHERE id=$1`, pickupRaceOrderID); err != nil {
		t.Fatalf("prepare pickup race order: %v", err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE customer_orders SET status='ready_for_pickup' WHERE id=$1`, pickupRaceOrderID); err != nil {
		t.Fatal(err)
	}
	var pickupRaceJobID string
	if err := db.GetContext(ctx, &pickupRaceJobID, `SELECT id::text FROM delivery_jobs WHERE order_id=$1`, pickupRaceOrderID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE delivery_jobs SET state='assigned',execution_state='at_pickup' WHERE id=$1`, pickupRaceJobID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO delivery_assignments(job_id,rider_user_id) VALUES($1,$2)`, pickupRaceJobID, riderTwo); err != nil {
		t.Fatalf("assign pickup race rider: %v", err)
	}
	var pickupRaceAssignmentID string
	if err := db.GetContext(ctx, &pickupRaceAssignmentID, `SELECT id::text FROM delivery_assignments WHERE job_id=$1 AND state='active'`, pickupRaceJobID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO delivery_recovery_partner_confirmations(job_id,assignment_id,business_id,confirmed_by,confirmation,reason) VALUES($1,$2,$3,$4,'goods_not_handed_over','QA fixture confirms no physical handover occurred.')`, pickupRaceJobID, pickupRaceAssignmentID, businessID, merchantID); err != nil {
		t.Fatalf("seed scoped no-handover evidence: %v", err)
	}
	pickupCodeResponse := httptest.NewRecorder()
	pickupCodeRequest := httptest.NewRequest("POST", "/merchant/businesses/"+businessID+"/delivery-jobs/"+pickupRaceJobID+"/pickup-code", nil)
	pickupCodeRequest.SetPathValue("businessId", businessID)
	pickupCodeRequest.SetPathValue("jobId", pickupRaceJobID)
	service.IssuePickupCode(pickupCodeResponse, pickupCodeRequest, merchantID)
	var pickupRaceCode struct {
		Data struct {
			Code string `json:"pickup_code"`
		} `json:"data"`
	}
	if pickupCodeResponse.Code != 200 || json.Unmarshal(pickupCodeResponse.Body.Bytes(), &pickupRaceCode) != nil {
		t.Fatalf("issue pickup race code: HTTP %d %s", pickupCodeResponse.Code, pickupCodeResponse.Body.String())
	}
	pickupRaceBody := `{"action":"release_and_reassign_before_pickup","reason":"Operations verified that no physical goods were handed to this rider.","expected_assignment_id":"` + pickupRaceAssignmentID + `","expected_execution_state":"at_pickup","partner_confirmed_no_handover":true}`
	pickupRelease := func() int {
		req := httptest.NewRequest("POST", "/admin/delivery-jobs/"+pickupRaceJobID+"/recovery", strings.NewReader(pickupRaceBody))
		req.SetPathValue("jobId", pickupRaceJobID)
		req.Header.Set("Idempotency-Key", "qa-release-pickup-race-1")
		res := httptest.NewRecorder()
		service.AdminRecover(res, req, adminID)
		return res.Code
	}
	pickupVerify := func() int {
		req := httptest.NewRequest("POST", "/rider/delivery-jobs/"+pickupRaceJobID+"/pickup/verify", strings.NewReader(`{"code":"`+pickupRaceCode.Data.Code+`"}`))
		req.SetPathValue("jobId", pickupRaceJobID)
		res := httptest.NewRecorder()
		service.VerifyPickup(res, req, riderTwo)
		return res.Code
	}
	releaseVersusPickup := raceWhileRowLocked(t, ctx, db, `SELECT id FROM delivery_jobs WHERE id=$1 FOR UPDATE`, []any{pickupRaceJobID}, 2, pickupRelease, pickupVerify)
	if len(releaseVersusPickup) != 2 || !containsStatus(releaseVersusPickup, 200) || !(containsStatus(releaseVersusPickup, 404) || containsStatus(releaseVersusPickup, 409)) {
		t.Fatalf("Admin release versus pickup must have one safe winner: responses=%v", releaseVersusPickup)
	}
	var pickupRaceExecution, pickupRaceAssignmentState string
	var pickupRaceVerifiedEvents, pickupRaceReleaseEvents, pickupRaceActive int
	if err := db.QueryRowxContext(ctx, `SELECT j.execution_state,a.state,(SELECT count(*) FROM delivery_execution_events e WHERE e.job_id=j.id AND e.event_type='pickup_verified'),(SELECT count(*) FROM delivery_recovery_events e WHERE e.job_id=j.id AND e.event_type='assignment_released_before_pickup'),(SELECT count(*) FROM delivery_assignments x WHERE x.job_id=j.id AND x.state='active') FROM delivery_jobs j JOIN delivery_assignments a ON a.job_id=j.id WHERE j.id=$1 ORDER BY a.assigned_at DESC LIMIT 1`, pickupRaceJobID).Scan(&pickupRaceExecution, &pickupRaceAssignmentState, &pickupRaceVerifiedEvents, &pickupRaceReleaseEvents, &pickupRaceActive); err != nil {
		t.Fatal(err)
	}
	if !((pickupRaceExecution == "picked_up" && pickupRaceAssignmentState == "active" && pickupRaceVerifiedEvents == 1 && pickupRaceReleaseEvents == 0 && pickupRaceActive == 1) || (pickupRaceExecution == "assigned" && pickupRaceAssignmentState == "released" && pickupRaceVerifiedEvents == 0 && pickupRaceReleaseEvents == 1 && pickupRaceActive == 0)) {
		t.Fatalf("release/pickup race violated custody invariant: execution=%s assignment=%s verified=%d releases=%d active=%d", pickupRaceExecution, pickupRaceAssignmentState, pickupRaceVerifiedEvents, pickupRaceReleaseEvents, pickupRaceActive)
	}

	// Gate B case 8: two recovery requests reference the same exact old
	// assignment while release advances dispatch. The winner releases the old
	// rider once; the stale request must not mutate the newly accepted rider.
	staleRider, fallbackRider := newID(), newID()
	if _, err := db.ExecContext(ctx, `INSERT INTO users(id,phone_e164,display_name,status) VALUES($1,$2,'QA Recovery Rider','active'),($3,$4,'QA Replacement Rider','active')`, staleRider, "+91"+phoneSuffix(), fallbackRider, "+91"+phoneSuffix()); err != nil {
		t.Fatalf("create reassignment race riders: %v", err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO user_roles(user_id,role) VALUES($1,'rider'),($2,'rider')`, staleRider, fallbackRider); err != nil {
		t.Fatalf("assign reassignment race rider roles: %v", err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO rider_profiles(user_id,display_name,vehicle_type,status) VALUES($1,'QA Recovery Rider','two_wheeler','approved'),($2,'QA Replacement Rider','bicycle','approved')`, staleRider, fallbackRider); err != nil {
		t.Fatalf("create reassignment race profiles: %v", err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO rider_profile_localities(rider_profile_id,locality_id,status) SELECT id,$2,'approved' FROM rider_profiles WHERE user_id IN ($1,$3)`, staleRider, localityID, fallbackRider); err != nil {
		t.Fatalf("approve reassignment race localities: %v", err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO rider_availability_sessions(rider_user_id,is_online,lease_expires_at,last_heartbeat_at) VALUES($1,true,now()+interval '5 minutes',now()),($2,true,now()+interval '5 minutes',now())`, staleRider, fallbackRider); err != nil {
		t.Fatalf("set reassignment race riders online: %v", err)
	}
	reassignmentOrderID, reassignmentQuoteID := newID(), newID()
	if _, err := db.ExecContext(ctx, `INSERT INTO platform_checkout_quotes(id,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,grand_total_minor,expires_at) SELECT $1,$2,'food',$3,CURRENT_DATE,$4,updated_at,$5,'[{}]'::jsonb,10000,10000,now()+interval '5 minutes' FROM customer_addresses WHERE id=$4`, reassignmentQuoteID, customerID, localityID, addressID, businessID); err != nil {
		t.Fatalf("create reassignment race quote: %v", err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,fulfillment_type,item_total,grand_total,reference_code,order_source,platform_vertical,delivery_locality_id,platform_checkout_quote_id,payment_status) VALUES($1,$2,$3,'platform_order','accepted','delivery',100,100,$4,'platform_catalog','food',$5,$6,'not_collected')`, reassignmentOrderID, customerID, businessID, "QA-RACE-REASSIGN-"+uuid.NewString(), localityID, reassignmentQuoteID); err != nil {
		t.Fatalf("create reassignment race order: %v", err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE platform_checkout_quotes SET consumed_order_id=$1 WHERE id=$2`, reassignmentOrderID, reassignmentQuoteID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE customer_orders SET status='preparing' WHERE id=$1`, reassignmentOrderID); err != nil {
		t.Fatalf("prepare reassignment race order: %v", err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE customer_orders SET status='ready_for_pickup' WHERE id=$1`, reassignmentOrderID); err != nil {
		t.Fatal(err)
	}
	var reassignmentJobID, oldAssignmentID string
	if err := db.GetContext(ctx, &reassignmentJobID, `SELECT id::text FROM delivery_jobs WHERE order_id=$1`, reassignmentOrderID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE delivery_jobs SET state='assigned',execution_state='assigned' WHERE id=$1`, reassignmentJobID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO delivery_assignments(job_id,rider_user_id) VALUES($1,$2)`, reassignmentJobID, staleRider); err != nil {
		t.Fatal(err)
	}
	if err := db.GetContext(ctx, &oldAssignmentID, `SELECT id::text FROM delivery_assignments WHERE job_id=$1 AND state='active'`, reassignmentJobID); err != nil {
		t.Fatal(err)
	}
	unableReassign := httptest.NewRecorder()
	tunableReassignRequest := httptest.NewRequest("POST", "/rider/delivery-jobs/"+reassignmentJobID+"/unable-to-continue", strings.NewReader(`{"reason":"Rider cannot continue and requests a safe replacement assignment."}`))
	tunableReassignRequest.SetPathValue("jobId", reassignmentJobID)
	tunableReassignRequest.Header.Set("Idempotency-Key", "qa-reassign-rider-report")
	service.ReportUnableToContinue(unableReassign, tunableReassignRequest, staleRider)
	if unableReassign.Code != 201 {
		t.Fatalf("create reassignment recovery case: %d %s", unableReassign.Code, unableReassign.Body.String())
	}
	reassignNoHandover := httptest.NewRecorder()
	noHandoverReq := httptest.NewRequest("POST", "/merchant/businesses/"+businessID+"/delivery-jobs/"+reassignmentJobID+"/recovery/no-handover", strings.NewReader(`{"assignment_id":"`+oldAssignmentID+`","reason":"Partner verifies the order was not handed to this rider."}`))
	noHandoverReq.SetPathValue("businessId", businessID)
	noHandoverReq.SetPathValue("jobId", reassignmentJobID)
	noHandoverReq.Header.Set("Idempotency-Key", "qa-reassign-no-handover")
	service.ConfirmNoHandover(reassignNoHandover, noHandoverReq, merchantID)
	if reassignNoHandover.Code != 200 {
		t.Fatalf("record reassignment no-handover evidence: %d %s", reassignNoHandover.Code, reassignNoHandover.Body.String())
	}
	recoveryPayload := `{"action":"release_and_reassign_before_pickup","reason":"Partner confirmed no handover; release the exact old assignment for reassignment.","expected_assignment_id":"` + oldAssignmentID + `","expected_execution_state":"assigned","partner_confirmed_no_handover":true}`
	releaseOldAssignment := func(key string) int {
		req := httptest.NewRequest("POST", "/admin/delivery-jobs/"+reassignmentJobID+"/recovery", strings.NewReader(recoveryPayload))
		req.SetPathValue("jobId", reassignmentJobID)
		req.Header.Set("Idempotency-Key", key)
		res := httptest.NewRecorder()
		service.AdminRecover(res, req, adminID)
		return res.Code
	}
	reassignmentRace := raceWhileRowLocked(t, ctx, db, `SELECT id FROM delivery_jobs WHERE id=$1 FOR UPDATE`, []any{reassignmentJobID}, 2, func() int { return releaseOldAssignment("qa-reassign-release-a") }, func() int { return releaseOldAssignment("qa-reassign-release-b") })
	if len(reassignmentRace) != 2 || !containsStatus(reassignmentRace, 200) || !(containsStatus(reassignmentRace, 404) || containsStatus(reassignmentRace, 409)) {
		t.Fatalf("reassignment versus stale recovery race must resolve one exact old reference: responses=%v", reassignmentRace)
	}
	var oldState string
	var oldReleaseEvents int
	if err := db.QueryRowxContext(ctx, `SELECT a.state,(SELECT count(*) FROM delivery_recovery_events e WHERE e.job_id=a.job_id AND e.assignment_id=a.id AND e.event_type='assignment_released_before_pickup') FROM delivery_assignments a WHERE a.id=$1`, oldAssignmentID).Scan(&oldState, &oldReleaseEvents); err != nil {
		t.Fatal(err)
	}
	if oldState != "released" || oldReleaseEvents != 1 {
		t.Fatalf("old assignment must be released exactly once: state=%s events=%d", oldState, oldReleaseEvents)
	}
	var replacementOfferID, replacementRiderID string
	if err := db.QueryRowxContext(ctx, `SELECT id::text,rider_user_id::text FROM delivery_offers WHERE job_id=$1 AND state='offered'`, reassignmentJobID).Scan(&replacementOfferID, &replacementRiderID); err != nil {
		t.Fatalf("replacement offer missing after recovery: %v", err)
	}
	replacementAccept := httptest.NewRecorder()
	replacementAcceptReq := httptest.NewRequest("POST", "/rider/offers/"+replacementOfferID+"/accept", nil)
	replacementAcceptReq.SetPathValue("offerId", replacementOfferID)
	service.RespondOffer(replacementAccept, replacementAcceptReq, replacementRiderID, "accept")
	if replacementAccept.Code != 200 {
		t.Fatalf("replacement rider could not accept after recovery: %d %s", replacementAccept.Code, replacementAccept.Body.String())
	}
	var replacementAssignmentID string
	if err := db.GetContext(ctx, &replacementAssignmentID, `SELECT id::text FROM delivery_assignments WHERE job_id=$1 AND state='active'`, reassignmentJobID); err != nil {
		t.Fatal(err)
	}
	if replacementAssignmentID == oldAssignmentID {
		t.Fatal("replacement reused the stale assignment identity")
	}
	staleReplay := httptest.NewRecorder()
	staleReplayReq := httptest.NewRequest("POST", "/admin/delivery-jobs/"+reassignmentJobID+"/recovery", strings.NewReader(recoveryPayload))
	staleReplayReq.SetPathValue("jobId", reassignmentJobID)
	staleReplayReq.Header.Set("Idempotency-Key", "qa-reassign-stale-after-new-owner")
	service.AdminRecover(staleReplay, staleReplayReq, adminID)
	var activeReplacementRider string
	if err := db.GetContext(ctx, &activeReplacementRider, `SELECT rider_user_id::text FROM delivery_assignments WHERE id=$1 AND state='active'`, replacementAssignmentID); err != nil {
		t.Fatalf("stale recovery modified replacement assignment: response=%d err=%v", staleReplay.Code, err)
	}
	if (staleReplay.Code != 404 && staleReplay.Code != 409) || activeReplacementRider != replacementRiderID {
		t.Fatalf("stale recovery must be denied without changing new owner: response=%d new_owner=%s expected=%s", staleReplay.Code, activeReplacementRider, replacementRiderID)
	}
}

func TestMerchantDispatchSummaryReportsRiderAtPickup(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_DSN")
	if dsn == "" {
		t.Skip("TEST_DATABASE_DSN is not set")
	}
	if !strings.HasSuffix(databaseNameFromDSN(dsn), "_qa") && !strings.HasSuffix(databaseNameFromDSN(dsn), "_test") {
		t.Fatal("refusing merchant dispatch projection test: database name must end in _qa or _test")
	}
	db, err := database.Open(dsn, 4, 4, time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	id := func() string { return uuid.NewString() }
	merchantID, customerID, riderID := id(), id(), id()
	businessID, orderID, jobID := id(), id(), id()
	addressID, quoteID := id(), id()
	localityID := "02200000-0000-4000-8000-000000000101"
	queries := []struct {
		query string
		args  []any
	}{
		{`INSERT INTO users(id,phone_e164,display_name,status) VALUES($1,$2,'QA Merchant','active'),($3,$4,'QA Customer','active'),($5,$6,'QA Rider','active')`, []any{merchantID, "+91" + phoneSuffix(), customerID, "+91" + phoneSuffix(), riderID, "+91" + phoneSuffix()}},
		{`INSERT INTO businesses(id,owner_user_id,name,slug,description,category_slug,phone_e164,address_text,locality,city,postal_code,location,status,verification_status) VALUES($1,$2,'QA Pickup Projection Partner',$3,'Disposable projection fixture','restaurant',$4,'QA partner pickup','Kuanpal','Cuttack','754082',ST_SetSRID(ST_MakePoint(85.75,20.45)::geography,4326),'approved','verified')`, []any{businessID, merchantID, "qa-pickup-projection-" + id(), "+91" + phoneSuffix()}},
		{`INSERT INTO customer_addresses(id,customer_user_id,label,recipient_name,address_line1,locality,city,state,postal_code,contact_phone,is_default,delivery_locality_id) VALUES($1,$2,'QA','QA Customer','QA House 1','Kuanpal','Cuttack','Odisha','754082',$3,true,$4)`, []any{addressID, customerID, "+91" + phoneSuffix(), localityID}},
		{`INSERT INTO platform_checkout_quotes(id,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,delivery_fee_minor,tax_minor,grand_total_minor,expires_at) SELECT $1,$2,'food',$3,CURRENT_DATE,$4,updated_at,$5,'[{}]'::jsonb,10000,0,0,10000,now()+interval '5 minutes' FROM customer_addresses WHERE id=$4`, []any{quoteID, customerID, localityID, addressID, businessID}},
		{`INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,fulfillment_type,item_total,grand_total,reference_code,order_source,platform_vertical,delivery_locality_id,platform_checkout_quote_id) VALUES($1,$2,$3,'platform_order','ready_for_pickup','delivery',100,100,$4,'platform_catalog','food',$5,$6)`, []any{orderID, customerID, businessID, "QA-" + id(), localityID, quoteID}},
		{`UPDATE platform_checkout_quotes SET consumed_order_id=$1 WHERE id=$2`, []any{orderID, quoteID}},
		{`INSERT INTO rider_profiles(user_id,display_name,vehicle_type,status) VALUES($1,'QA Rider','two_wheeler','approved')`, []any{riderID}},
		{`INSERT INTO delivery_jobs(id,order_id,business_id,locality_id,state,execution_state) VALUES($1,$2,$3,$4,'assigned','at_pickup')`, []any{jobID, orderID, businessID, localityID}},
		{`INSERT INTO delivery_assignments(job_id,rider_user_id,state) VALUES($1,$2,'active')`, []any{jobID, riderID}},
	}
	for _, item := range queries {
		if _, err := db.ExecContext(ctx, item.query, item.args...); err != nil {
			t.Fatalf("QA projection fixture failed: %v", err)
		}
	}
	service := NewService(db, nil, &config.Config{RiderDispatchEnabled: true})
	request := httptest.NewRequest("GET", "/merchant/businesses/"+businessID+"/delivery-dispatch", nil)
	request.SetPathValue("businessId", businessID)
	recorder := httptest.NewRecorder()
	service.MerchantSummary(recorder, request, merchantID)
	if recorder.Code != 200 ||
		!strings.Contains(recorder.Body.String(), `"order_id":"`+orderID+`"`) ||
		!strings.Contains(recorder.Body.String(), `"execution_state":"at_pickup"`) ||
		!strings.Contains(recorder.Body.String(), `"rider_assigned":true`) {
		t.Fatalf("Merchant summary must expose the current assigned rider pickup state: HTTP %d %s", recorder.Code, recorder.Body.String())
	}
}

func phoneSuffix() string { return strings.ReplaceAll(uuid.NewString(), "-", "")[:10] }

func databaseNameFromDSN(dsn string) string {
	for _, field := range strings.Fields(dsn) {
		if strings.HasPrefix(field, "dbname=") {
			return strings.TrimPrefix(field, "dbname=")
		}
	}
	return ""
}

// raceWhileRowLocked starts real service handlers while a disposable-database
// transaction owns their target row. It waits for the expected PostgreSQL lock
// waiters before releasing the row, proving the calls reached the DB boundary.
func raceWhileRowLocked(t *testing.T, ctx context.Context, db *database.DB, lockQuery string, lockArgs []any, expectedWaiters int, operations ...func() int) []int {
	t.Helper()
	lock, err := db.BeginTxx(ctx, nil)
	if err != nil {
		t.Fatalf("begin deterministic race barrier: %v", err)
	}
	defer lock.Rollback()
	var lockedID string
	if err := lock.QueryRowxContext(ctx, lockQuery, lockArgs...).Scan(&lockedID); err != nil {
		t.Fatalf("lock race target row: %v", err)
	}
	start := make(chan struct{})
	results := make(chan int, len(operations))
	for _, operation := range operations {
		operation := operation
		go func() { <-start; results <- operation() }()
	}
	close(start)
	if err := waitForDatabaseLockWaits(ctx, db, expectedWaiters); err != nil {
		t.Fatalf("operations did not reach the database lock boundary: %v", err)
	}
	if err := lock.Commit(); err != nil {
		t.Fatalf("release deterministic race barrier: %v", err)
	}
	statuses := make([]int, 0, len(operations))
	for range operations {
		select {
		case status := <-results:
			statuses = append(statuses, status)
		case <-time.After(8 * time.Second):
			t.Fatal("race operation exceeded the bounded 8-second deadline")
		}
	}
	return statuses
}

func waitForDatabaseLockWaits(ctx context.Context, db *database.DB, expected int) error {
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		var waiting int
		if err := db.GetContext(ctx, &waiting, `SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND pid<>pg_backend_pid() AND wait_event_type='Lock'`); err != nil {
			return err
		}
		if waiting >= expected {
			return nil
		}
		time.Sleep(5 * time.Millisecond)
	}
	return fmt.Errorf("timed out waiting for %d PostgreSQL lock waiters", expected)
}

func containsStatus(statuses []int, expected int) bool {
	for _, status := range statuses {
		if status == expected {
			return true
		}
	}
	return false
}
