package deliverydispatch

import (
	"context"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"grepmind-near/backend/pkg/config"
	"grepmind-near/backend/pkg/database"
)

func TestAvailabilityReturnAutomaticallyReopensEligibleDispatch(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_DSN")
	if dsn == "" {
		t.Skip("TEST_DATABASE_DSN is not set")
	}
	if !strings.HasSuffix(databaseNameFromDSN(dsn), "_qa") && !strings.HasSuffix(databaseNameFromDSN(dsn), "_test") {
		t.Fatal("refusing dispatch recovery integration test: database name must end in _qa or _test")
	}
	db, err := database.Open(dsn, 8, 8, time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	newID := func() string { return uuid.NewString() }
	customerID, merchantID, riderID := newID(), newID(), newID()
	businessID, orderID, jobID := newID(), newID(), newID()
	localityID := "02200000-0000-4000-8000-000000000101" // Cuttack → Kuanpal
	phone := func() string { return "+91" + phoneSuffix() }

	fixtures := []struct {
		query string
		args  []any
	}{
		{`INSERT INTO users(id,phone_e164,display_name,status) VALUES($1,$2,'QA Availability Customer','active')`, []any{customerID, phone()}},
		{`INSERT INTO user_roles(user_id,role) VALUES($1,'customer')`, []any{customerID}},
		{`INSERT INTO users(id,phone_e164,display_name,status) VALUES($1,$2,'QA Availability Merchant','active')`, []any{merchantID, phone()}},
		{`INSERT INTO user_roles(user_id,role) VALUES($1,'merchant')`, []any{merchantID}},
		{`INSERT INTO users(id,phone_e164,display_name,status) VALUES($1,$2,'QA Availability Rider','active')`, []any{riderID, phone()}},
		{`INSERT INTO user_roles(user_id,role) VALUES($1,'rider')`, []any{riderID}},
		{`INSERT INTO businesses(id,owner_user_id,name,slug,description,category_slug,phone_e164,address_text,locality,city,postal_code,location,status,verification_status)
			VALUES($1,$2,'QA Availability Partner',$3,'Disposable dispatch recovery partner','restaurant',$4,'QA pickup','Kuanpal','Cuttack','754082',ST_SetSRID(ST_MakePoint(85.75,20.45)::geography,4326),'approved','verified')`, []any{businessID, merchantID, "qa-availability-" + uuid.NewString(), phone()}},
		{`INSERT INTO rider_profiles(user_id,display_name,vehicle_type,status) VALUES($1,'QA Availability Rider','bicycle','approved')`, []any{riderID}},
		{`INSERT INTO rider_profile_localities(rider_profile_id,locality_id,status) SELECT id,$2,'approved' FROM rider_profiles WHERE user_id=$1`, []any{riderID, localityID}},
		{`INSERT INTO rider_availability_sessions(rider_user_id,is_online,lease_expires_at,last_heartbeat_at) VALUES($1,false,now(),now())`, []any{riderID}},
		{`INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,fulfillment_type,item_total,grand_total,reference_code,delivery_locality_id)
			VALUES($1,$2,$3,'food_delivery','preparing','delivery',100,100,$4,$5)`, []any{orderID, customerID, businessID, "QA-AVAILABILITY-" + uuid.NewString(), localityID}},
		{`INSERT INTO delivery_jobs(id,order_id,business_id,locality_id,state) VALUES($1,$2,$3,$4,'no_rider_available')`, []any{jobID, orderID, businessID, localityID}},
		{`INSERT INTO delivery_dispatch_runs(job_id,run_number,state,completed_at) VALUES($1,1,'no_rider_available',now())`, []any{jobID}},
	}
	for _, fixture := range fixtures {
		if _, err := db.ExecContext(ctx, fixture.query, fixture.args...); err != nil {
			t.Fatalf("create isolated availability fixture: %v", err)
		}
	}

	service := NewService(db, nil, &config.Config{RiderDispatchEnabled: true, RiderAvailabilityLease: 2 * time.Minute})
	if err := service.Process(ctx); err != nil {
		t.Fatalf("process with no online rider: %v", err)
	}
	var runCount int
	if err := db.GetContext(ctx, &runCount, `SELECT count(*) FROM delivery_dispatch_runs WHERE job_id=$1`, jobID); err != nil {
		t.Fatal(err)
	}
	if runCount != 1 {
		t.Fatalf("unavailable capacity should not churn dispatch runs; runs=%d", runCount)
	}

	response := httptest.NewRecorder()
	service.SetAvailability(response, httptest.NewRequest("PUT", "/rider/availability", strings.NewReader(`{"online":true}`)), riderID)
	if response.Code != 200 {
		t.Fatalf("eligible rider could not come online: HTTP %d %s", response.Code, response.Body.String())
	}
	var jobState, offeredRider string
	if err := db.QueryRowxContext(ctx, `SELECT j.state,o.rider_user_id::text FROM delivery_jobs j
		JOIN delivery_offers o ON o.job_id=j.id AND o.state='offered' WHERE j.id=$1`, jobID).Scan(&jobState, &offeredRider); err != nil {
		t.Fatalf("online availability did not issue a waiting job offer: %v", err)
	}
	if jobState != "offered" || offeredRider != riderID {
		t.Fatalf("waiting job was not offered to the newly available eligible rider: state=%s rider=%s", jobState, offeredRider)
	}
	if err := db.GetContext(ctx, &runCount, `SELECT count(*) FROM delivery_dispatch_runs WHERE job_id=$1`, jobID); err != nil {
		t.Fatal(err)
	}
	if runCount != 2 {
		t.Fatalf("expected one recovery dispatch run after availability returned; runs=%d", runCount)
	}
	if err := db.GetContext(ctx, &runCount, `SELECT count(*) FROM delivery_offers WHERE job_id=$1 AND state='offered'`, jobID); err != nil {
		t.Fatal(err)
	}
	if runCount != 1 {
		t.Fatalf("expected exactly one active offer after rider availability, got %d", runCount)
	}
}
