package platformfulfillment

import (
	"context"
	"fmt"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"grepmind-near/backend/pkg/database"
)

func TestUnverifiedUPIIsBlockedFromMerchantFulfillmentPostGIS(t *testing.T) {
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
		t.Fatalf("refusing payment-gate integration test on non-disposable database %q", dbName)
	}

	ctx := context.Background()
	newID := func() string { return uuid.NewString() }
	merchantID, customerID, businessID, orderID, addressID, quoteID := newID(), newID(), newID(), newID(), newID(), newID()
	localityID := "02200000-0000-4000-8000-000000000101"
	phoneSuffix := func() string { return fmt.Sprintf("+9199%08d", time.Now().UnixNano()%100000000) }
	merchantPhone, customerPhone := phoneSuffix(), phoneSuffix()
	queries := []struct {
		query string
		args  []any
	}{
		{`INSERT INTO users(id,phone_e164,display_name,status) VALUES($1,$2,'QA payment-gate merchant','active')`, []any{merchantID, merchantPhone}},
		{`INSERT INTO user_roles(user_id,role) VALUES($1,'merchant')`, []any{merchantID}},
		{`INSERT INTO users(id,phone_e164,display_name,status) VALUES($1,$2,'QA payment-gate customer','active')`, []any{customerID, customerPhone}},
		{`INSERT INTO user_roles(user_id,role) VALUES($1,'customer')`, []any{customerID}},
		{`INSERT INTO businesses(id,owner_user_id,name,slug,description,category_slug,phone_e164,address_text,locality,city,postal_code,location,status,verification_status) VALUES($1,$2,'QA payment-gate partner',$3,'Disposable payment gate fixture','restaurant',$4,'QA pickup','Kuanpal','Cuttack','754082',ST_SetSRID(ST_MakePoint(85.75,20.45)::geography,4326),'approved','verified')`, []any{businessID, merchantID, "qa-payment-gate-" + newID(), merchantPhone}},
		{`INSERT INTO platform_partner_delivery_localities(business_id,locality_id,is_active) VALUES($1,$2,true)`, []any{businessID, localityID}},
		{`INSERT INTO customer_addresses(id,customer_user_id,label,recipient_name,address_line1,locality,delivery_locality_id,landmark,city,state,postal_code,contact_phone,is_default) VALUES($1,$2,'QA','QA Customer','QA Lane','Kuanpal',$3,'','Cuttack','Odisha','754082',$4,true)`, []any{addressID, customerID, localityID, customerPhone}},
		{`INSERT INTO platform_checkout_quotes(id,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,grand_total_minor,currency,expires_at) SELECT $1,$2,'food',$3,current_date,$4,updated_at,$5,'[{}]'::jsonb,10000,10000,'INR',now()+interval '5 minutes' FROM customer_addresses WHERE id=$4`, []any{quoteID, customerID, localityID, addressID, businessID}},
		{`INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,fulfillment_type,item_total,grand_total,reference_code,order_source,platform_vertical,delivery_locality_id,platform_checkout_quote_id,payment_status,payment_method,delivery_address_snapshot) VALUES($1,$2,$3,'platform_order','placed','delivery',10000,10000,$4,'platform_catalog','food',$5,$6,'not_collected','upi','{}'::jsonb)`, []any{orderID, customerID, businessID, "QA-PAYMENT-GATE-" + strings.ReplaceAll(orderID, "-", ""), localityID, quoteID}},
	}
	for _, item := range queries {
		if _, err := db.ExecContext(ctx, item.query, item.args...); err != nil {
			t.Fatalf("create isolated payment-gate fixtures: %v", err)
		}
	}

	service := NewService(db)
	transition := func(target string) *httptest.ResponseRecorder {
		recorder := httptest.NewRecorder()
		request := httptest.NewRequest("POST", "/merchant/businesses/"+businessID+"/platform-orders/"+orderID+"/accept", strings.NewReader(`{}`))
		request.SetPathValue("businessId", businessID)
		request.SetPathValue("orderId", orderID)
		switch target {
		case "accepted":
			service.Accept(recorder, request, merchantID)
		case "preparing":
			service.Prepare(recorder, request, merchantID)
		case "ready_for_pickup":
			service.Ready(recorder, request, merchantID)
		}
		return recorder
	}

	if got := transition("accepted"); got.Code != 409 || !strings.Contains(got.Body.String(), "PAYMENT_NOT_VERIFIED") {
		t.Fatalf("unverified UPI was accepted for fulfillment: HTTP %d %s", got.Code, got.Body.String())
	}
	var status string
	if err := db.GetContext(ctx, &status, `SELECT status FROM customer_orders WHERE id=$1`, orderID); err != nil || status != "placed" {
		t.Fatalf("blocked UPI transition changed order state: status=%s err=%v", status, err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE customer_orders SET payment_status='paid' WHERE id=$1`, orderID); err != nil {
		t.Fatal(err)
	}
	if got := transition("accepted"); got.Code != 200 {
		t.Fatalf("verified UPI order was not accepted: HTTP %d %s", got.Code, got.Body.String())
	}
	if _, err := db.ExecContext(ctx, `UPDATE customer_orders SET payment_status='not_collected' WHERE id=$1`, orderID); err != nil {
		t.Fatal(err)
	}
	if got := transition("preparing"); got.Code != 409 || !strings.Contains(got.Body.String(), "PAYMENT_NOT_VERIFIED") {
		t.Fatalf("payment state was not rechecked at preparation: HTTP %d %s", got.Code, got.Body.String())
	}
	if err := db.GetContext(ctx, &status, `SELECT status FROM customer_orders WHERE id=$1`, orderID); err != nil || status != "accepted" {
		t.Fatalf("blocked preparation changed order state: status=%s err=%v", status, err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE customer_orders SET payment_status='paid' WHERE id=$1`, orderID); err != nil {
		t.Fatal(err)
	}
	if got := transition("preparing"); got.Code != 200 {
		t.Fatalf("verified UPI order could not start preparation: HTTP %d %s", got.Code, got.Body.String())
	}
	if got := transition("ready_for_pickup"); got.Code != 200 {
		t.Fatalf("verified UPI order could not become ready: HTTP %d %s", got.Code, got.Body.String())
	}
}
