package deliverydispatch

import (
	"context"
	"fmt"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"grepmind-near/backend/pkg/config"
	"grepmind-near/backend/pkg/database"
)

func TestUPIDispatchWaitsForVerifiedPaymentPostGIS(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_DSN")
	if dsn == "" {
		t.Skip("TEST_DATABASE_DSN is not set; use an isolated disposable PostGIS database")
	}
	db, err := database.Open(dsn, 4, 4, time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	var dbName string
	if err := db.GetContext(context.Background(), &dbName, `SELECT current_database()`); err != nil {
		t.Fatal(err)
	}
	if !strings.HasSuffix(dbName, "_qa") && !strings.HasSuffix(dbName, "_test") {
		t.Fatalf("refusing dispatch payment-gate integration test on non-disposable database %q", dbName)
	}
	ctx := context.Background()
	newID := func() string { return uuid.NewString() }
	phone := func() string { return fmt.Sprintf("+9198%08d", time.Now().UnixNano()%100000000) }
	customerID, merchantID, riderID, businessID, orderID, addressID, quoteID := newID(), newID(), newID(), newID(), newID(), newID(), newID()
	localityID := "02200000-0000-4000-8000-000000000101"
	fixtures := []struct {
		query string
		args  []any
	}{
		{`INSERT INTO users(id,phone_e164,display_name,status) VALUES($1,$2,'QA dispatch payment customer','active')`, []any{customerID, phone()}},
		{`INSERT INTO user_roles(user_id,role) VALUES($1,'customer')`, []any{customerID}},
		{`INSERT INTO users(id,phone_e164,display_name,status) VALUES($1,$2,'QA dispatch payment merchant','active')`, []any{merchantID, phone()}},
		{`INSERT INTO user_roles(user_id,role) VALUES($1,'merchant')`, []any{merchantID}},
		{`INSERT INTO users(id,phone_e164,display_name,status) VALUES($1,$2,'QA dispatch payment rider','active')`, []any{riderID, phone()}},
		{`INSERT INTO user_roles(user_id,role) VALUES($1,'rider')`, []any{riderID}},
		{`INSERT INTO businesses(id,owner_user_id,name,slug,description,category_slug,phone_e164,address_text,locality,city,postal_code,location,status,verification_status) VALUES($1,$2,'QA dispatch payment partner',$3,'Disposable dispatch payment fixture','restaurant',$4,'QA pickup','Kuanpal','Cuttack','754082',ST_SetSRID(ST_MakePoint(85.75,20.45)::geography,4326),'approved','verified')`, []any{businessID, merchantID, "qa-dispatch-payment-" + newID(), phone()}},
		{`INSERT INTO platform_partner_delivery_localities(business_id,locality_id,is_active) VALUES($1,$2,true)`, []any{businessID, localityID}},
		{`INSERT INTO customer_addresses(id,customer_user_id,label,recipient_name,address_line1,locality,delivery_locality_id,landmark,city,state,postal_code,contact_phone,is_default) VALUES($1,$2,'QA','QA Customer','QA Lane','Kuanpal',$3,'','Cuttack','Odisha','754082',$4,true)`, []any{addressID, customerID, localityID, phone()}},
		{`INSERT INTO platform_checkout_quotes(id,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,grand_total_minor,currency,expires_at) SELECT $1,$2,'food',$3,current_date,$4,updated_at,$5,'[{}]'::jsonb,10000,10000,'INR',now()+interval '5 minutes' FROM customer_addresses WHERE id=$4`, []any{quoteID, customerID, localityID, addressID, businessID}},
		{`INSERT INTO rider_profiles(user_id,display_name,vehicle_type,status) VALUES($1,'QA dispatch payment rider','two_wheeler','approved')`, []any{riderID}},
		{`INSERT INTO rider_profile_localities(rider_profile_id,locality_id,status) SELECT id,$2,'approved' FROM rider_profiles WHERE user_id=$1`, []any{riderID, localityID}},
		{`INSERT INTO rider_availability_sessions(rider_user_id,is_online,lease_expires_at,last_heartbeat_at) VALUES($1,true,now()+interval '10 minutes',now())`, []any{riderID}},
		{`INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,fulfillment_type,item_total,grand_total,reference_code,order_source,platform_vertical,delivery_locality_id,platform_checkout_quote_id,payment_status,payment_method,delivery_address_snapshot) VALUES($1,$2,$3,'platform_order','accepted','delivery',10000,10000,$4,'platform_catalog','food',$5,$6,'not_collected','upi','{}'::jsonb)`, []any{orderID, customerID, businessID, "QA-DISPATCH-PAYMENT-" + strings.ReplaceAll(orderID, "-", ""), localityID, quoteID}},
	}
	for _, fixture := range fixtures {
		if _, err := db.ExecContext(ctx, fixture.query, fixture.args...); err != nil {
			t.Fatalf("create isolated dispatch payment fixtures: %v", err)
		}
	}
	if _, err := db.ExecContext(ctx, `UPDATE customer_orders SET status='preparing' WHERE id=$1`, orderID); err != nil {
		t.Fatalf("create delivery job: %v", err)
	}
	var jobID string
	if err := db.GetContext(ctx, &jobID, `SELECT id::text FROM delivery_jobs WHERE order_id=$1`, orderID); err != nil {
		t.Fatal(err)
	}
	service := NewService(db, nil, &config.Config{RiderDispatchEnabled: true})
	if err := service.advanceJob(ctx, jobID); err != nil {
		t.Fatal(err)
	}
	var offerCount int
	if err := db.GetContext(ctx, &offerCount, `SELECT count(*) FROM delivery_offers WHERE job_id=$1`, jobID); err != nil {
		t.Fatal(err)
	}
	if offerCount != 0 {
		t.Fatalf("unverified UPI order received %d rider offers", offerCount)
	}
	if _, err := db.ExecContext(ctx, `UPDATE customer_orders SET payment_status='paid' WHERE id=$1`, orderID); err != nil {
		t.Fatal(err)
	}
	if err := service.advanceJob(ctx, jobID); err != nil {
		t.Fatal(err)
	}
	offers := httptest.NewRecorder()
	service.Offers(offers, httptest.NewRequest("GET", "/rider/offers", nil), riderID)
	if offers.Code != 200 || !strings.Contains(offers.Body.String(), `"payment_method":"upi"`) || !strings.Contains(offers.Body.String(), `"payment_status":"paid"`) {
		t.Fatalf("verified UPI rider offer did not expose truthful payment method/status: HTTP %d %s", offers.Code, offers.Body.String())
	}
	if !strings.Contains(offers.Body.String(), jobID) {
		t.Fatalf("verified UPI order offer was not created after capture: %s", offers.Body.String())
	}
	var offerID string
	if err := db.GetContext(ctx, &offerID, `SELECT id::text FROM delivery_offers WHERE job_id=$1 AND state='offered'`, jobID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE customer_orders SET payment_status='not_collected' WHERE id=$1`, orderID); err != nil {
		t.Fatal(err)
	}
	accept := func() *httptest.ResponseRecorder {
		recorder := httptest.NewRecorder()
		request := httptest.NewRequest("POST", "/rider/offers/"+offerID+"/accept", nil)
		request.SetPathValue("offerId", offerID)
		service.RespondOffer(recorder, request, riderID, "accept")
		return recorder
	}
	if got := accept(); got.Code != 409 || !strings.Contains(got.Body.String(), "PAYMENT_NOT_VERIFIED") {
		t.Fatalf("payment change after offer did not block rider acceptance: HTTP %d %s", got.Code, got.Body.String())
	}
	var assignments int
	if err := db.GetContext(ctx, &assignments, `SELECT count(*) FROM delivery_assignments WHERE job_id=$1 AND state='active'`, jobID); err != nil || assignments != 0 {
		t.Fatalf("blocked payment race created active assignment count=%d err=%v", assignments, err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE customer_orders SET payment_status='paid' WHERE id=$1`, orderID); err != nil {
		t.Fatal(err)
	}
	if got := accept(); got.Code != 200 {
		t.Fatalf("eligible paid offer could not be accepted: HTTP %d %s", got.Code, got.Body.String())
	}
}
