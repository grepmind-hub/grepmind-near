package codcash

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"

	"github.com/google/uuid"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/jmoiron/sqlx"
	"grepmind-near/backend/pkg/database"
)

func TestCODSyntheticCollectionAndRemittancePostGIS(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_DSN")
	if dsn == "" {
		t.Skip("TEST_DATABASE_DSN is not set; run scripts/qa/phase4c_cod_cash_accountability.sh")
	}
	db, err := sqlx.Connect("pgx", dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	var rootID, localityID, localityName, districtName string
	if err := db.Get(&rootID, `SELECT id::text FROM users WHERE phone_e164='+910000000000' AND status='active'`); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRowx(`SELECT l.id::text,l.name,d.name FROM platform_delivery_localities l JOIN platform_districts d ON d.id=l.district_id WHERE l.delivery_enabled ORDER BY l.name LIMIT 1`).Scan(&localityID, &localityName, &districtName); err != nil {
		t.Fatal(err)
	}
	_, err = db.Exec(`UPDATE financial_feature_config SET financial_posting_enabled=true,sandbox_cod_enabled=true,updated_by=$1,change_reason='Enable synthetic COD for isolated integration test',updated_at=now() WHERE singleton=true`, rootID)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_, _ = db.Exec(`UPDATE financial_feature_config SET financial_posting_enabled=false,sandbox_cod_enabled=false,updated_by=$1,change_reason='Disable synthetic COD after isolated integration test',updated_at=now() WHERE singleton=true`, rootID)
	})
	newUser := func(role string) string {
		t.Helper()
		id := uuid.NewString()
		phone := fmt.Sprintf("+9198%010d", len(id)+int(id[0]))
		if _, e := db.Exec(`INSERT INTO users(id,phone_e164,status) VALUES($1,$2,'active')`, id, phone); e != nil {
			t.Fatal(e)
		}
		if _, e := db.Exec(`INSERT INTO user_roles(user_id,role) VALUES($1,$2)`, id, role); e != nil {
			t.Fatal(e)
		}
		return id
	}
	customerID := newUser("customer")
	otherCustomerID := newUser("customer")
	riderID := newUser("rider")
	businessID := uuid.NewString()
	orderID := uuid.NewString()
	jobID := uuid.NewString()
	assignmentID := uuid.NewString()
	obligationID := uuid.NewString()
	if _, err = db.Exec(`INSERT INTO rider_profiles(user_id,display_name,vehicle_type,status) VALUES($1,'QA COD Rider','two_wheeler','approved')`, riderID); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(`INSERT INTO businesses(id,owner_user_id,name,slug,category_slug,address_text,locality,city,postal_code,location,status,verification_status) VALUES($1,$2,'QA COD Partner',$3,'restaurant','QA partner lane','Kuanpal','Cuttack','754082',ST_SetSRID(ST_MakePoint(85.8,20.5),4326)::geography,'approved','verified')`, businessID, rootID, "qa-cod-"+businessID); err != nil {
		t.Fatal(err)
	}
	addressID, quoteID := uuid.NewString(), uuid.NewString()
	if _, err = db.Exec(`INSERT INTO customer_addresses(id,customer_user_id,label,recipient_name,address_line1,locality,landmark,city,state,postal_code,contact_phone,is_default,delivery_locality_id) VALUES($1,$2,'QA Home','QA Customer','Synthetic COD test lane',$3,'QA landmark',$4,'Odisha','754082','+919999000001',true,$5)`, addressID, customerID, localityName, districtName, localityID); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(`INSERT INTO platform_checkout_quotes(id,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,grand_total_minor,expires_at) SELECT $1,$2,'food',$3,CURRENT_DATE,$4,updated_at,$5,'[{"product":"QA Synthetic COD","quantity":1}]'::jsonb,500,500,now()+interval '5 minutes' FROM customer_addresses WHERE id=$4`, quoteID, customerID, localityID, addressID, businessID); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(`INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,fulfillment_type,item_total,grand_total,currency,reference_code,order_source,platform_vertical,delivery_locality_id,platform_checkout_quote_id,payment_status,payment_method) VALUES($1,$2,$3,'platform_order','out_for_delivery','delivery',5,5,'INR',$4,'platform_catalog','food',$5,$6,'not_collected','cash_on_delivery')`, orderID, customerID, businessID, "QA-COD-"+orderID, localityID, quoteID); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(`UPDATE platform_checkout_quotes SET consumed_order_id=$1 WHERE id=$2`, orderID, quoteID); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(`INSERT INTO delivery_jobs(id,order_id,business_id,locality_id,state,execution_state) VALUES($1,$2,$3,$4,'assigned','en_route')`, jobID, orderID, businessID, localityID); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(`INSERT INTO delivery_assignments(id,job_id,rider_user_id,state) VALUES($1,$2,$3,'active')`, assignmentID, jobID, riderID); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(`INSERT INTO delivery_verification_codes(job_id,purpose,code_hmac,issued_by,expires_at,consumed_at) VALUES($1,'delivery',decode(repeat('a',64),'hex'),$2,now()+interval '1 minute',now())`, jobID, customerID); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(`INSERT INTO cod_obligations(id,order_id,customer_user_id,amount_minor,currency,policy_version) VALUES($1,$2,$3,500,'INR','synthetic-qa-v1')`, obligationID, orderID, customerID); err != nil {
		t.Fatal(err)
	}
	svc := NewService(&database.DB{DB: db}, true)
	collectionTx, err := db.BeginTxx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.RecordCollectionTx(ctx, collectionTx, jobID, riderID); err != nil {
		_ = collectionTx.Rollback()
		t.Fatalf("record verified collection: %v", err)
	}
	if err := collectionTx.Commit(); err != nil {
		t.Fatalf("commit collection: %v", err)
	}
	var journalCount int
	if err := db.Get(&journalCount, `SELECT count(*) FROM financial_journals WHERE source_type='sandbox_cod_collection' AND source_id=$1 AND status='posted'`, obligationID); err != nil {
		t.Fatal(err)
	}
	if journalCount != 1 {
		t.Fatalf("expected one balanced collection journal, got %d", journalCount)
	}
	var orderPayment string
	if err := db.Get(&orderPayment, `SELECT payment_status FROM customer_orders WHERE id=$1`, orderID); err != nil {
		t.Fatal(err)
	}
	if orderPayment != "not_collected" {
		t.Fatalf("synthetic cash incorrectly changed electronic payment projection: %q", orderPayment)
	}
	statusRequest := httptest.NewRequest("GET", "/api/v1/orders/"+orderID+"/cod-status", nil)
	statusRequest.SetPathValue("id", orderID)
	statusResponse := httptest.NewRecorder()
	svc.CustomerStatus(statusResponse, statusRequest, otherCustomerID)
	if statusResponse.Code != 404 {
		t.Fatalf("another customer read COD order status: HTTP %d", statusResponse.Code)
	}
	duplicateTx, err := db.BeginTxx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.RecordCollectionTx(ctx, duplicateTx, jobID, riderID); err == nil {
		_ = duplicateTx.Rollback()
		t.Fatal("duplicate synthetic COD collection was accepted")
	}
	_ = duplicateTx.Rollback()
	key := uuid.NewString()
	type submitResult struct {
		status int
		body   string
	}
	results := make(chan submitResult, 2)
	var submitters sync.WaitGroup
	for range 2 {
		submitters.Add(1)
		go func() {
			defer submitters.Done()
			request := httptest.NewRequest("POST", "/api/v1/rider/cash-remittances", strings.NewReader(`{"amount_minor":300,"submission_reference":"QA counter handoff"}`))
			request.Header.Set("Idempotency-Key", key)
			response := httptest.NewRecorder()
			svc.SubmitRemittance(response, request, riderID)
			results <- submitResult{status: response.Code, body: response.Body.String()}
		}()
	}
	submitters.Wait()
	close(results)
	var payload struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	accepted, replayed := 0, 0
	for result := range results {
		switch result.status {
		case http.StatusCreated:
			accepted++
		case http.StatusOK:
			replayed++
		default:
			t.Fatalf("concurrent idempotent remittance HTTP %d: %s", result.status, result.body)
		}
		var candidate struct {
			Data struct {
				ID string `json:"id"`
			} `json:"data"`
		}
		if err := json.Unmarshal([]byte(result.body), &candidate); err != nil {
			t.Fatal(err)
		}
		if payload.Data.ID != "" && payload.Data.ID != candidate.Data.ID {
			t.Fatalf("concurrent idempotent submissions produced different IDs: %s and %s", payload.Data.ID, candidate.Data.ID)
		}
		payload = candidate
	}
	if accepted != 1 || replayed != 1 {
		t.Fatalf("concurrent idempotent submissions: created=%d replayed=%d", accepted, replayed)
	}
	if payload.Data.ID == "" {
		t.Fatal("submission did not return a remittance ID")
	}
	replay := httptest.NewRequest("POST", "/api/v1/rider/cash-remittances", strings.NewReader(`{"amount_minor":300,"submission_reference":"QA counter handoff"}`))
	replay.Header.Set("Idempotency-Key", key)
	replayResponse := httptest.NewRecorder()
	svc.SubmitRemittance(replayResponse, replay, riderID)
	if replayResponse.Code != 200 {
		t.Fatalf("idempotent remittance retry HTTP %d: %s", replayResponse.Code, replayResponse.Body.String())
	}
	var replayPayload struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(replayResponse.Body.Bytes(), &replayPayload); err != nil || replayPayload.Data.ID != payload.Data.ID {
		t.Fatalf("idempotent remittance retry changed identity: payload=%+v err=%v", replayPayload, err)
	}
	over := httptest.NewRequest("POST", "/api/v1/rider/cash-remittances", strings.NewReader(`{"amount_minor":300,"submission_reference":"Over liability"}`))
	over.Header.Set("Idempotency-Key", uuid.NewString())
	overResponse := httptest.NewRecorder()
	svc.SubmitRemittance(overResponse, over, riderID)
	if overResponse.Code != 409 {
		t.Fatalf("remittance over unverified liability HTTP %d: %s", overResponse.Code, overResponse.Body.String())
	}
	unauthorizedReview := httptest.NewRequest("POST", "/api/v1/admin/cod/remittances/"+payload.Data.ID+"/review", strings.NewReader(`{"decision":"verify","reason":"Unauthorized customer review"}`))
	unauthorizedReview.SetPathValue("remittanceId", payload.Data.ID)
	unauthorizedResponse := httptest.NewRecorder()
	svc.ReviewRemittance(unauthorizedResponse, unauthorizedReview, otherCustomerID)
	if unauthorizedResponse.Code != 403 {
		t.Fatalf("unauthorized finance review HTTP %d", unauthorizedResponse.Code)
	}
	review := httptest.NewRequest("POST", "/api/v1/admin/cod/remittances/"+payload.Data.ID+"/review", strings.NewReader(`{"decision":"verify","reason":"QA finance verified synthetic remittance"}`))
	review.SetPathValue("remittanceId", payload.Data.ID)
	reviewResponse := httptest.NewRecorder()
	svc.ReviewRemittance(reviewResponse, review, rootID)
	if reviewResponse.Code != 200 {
		t.Fatalf("verify remittance HTTP %d: %s", reviewResponse.Code, reviewResponse.Body.String())
	}
	var remitted, liability int64
	if err := db.QueryRowx(`SELECT COALESCE(sum(amount_minor),0) FROM cod_remittances WHERE rider_user_id=$1 AND state='verified'`, riderID).Scan(&remitted); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRowx(`SELECT COALESCE((SELECT sum(amount_minor) FROM cod_collections WHERE rider_user_id=$1),0)-COALESCE((SELECT sum(amount_minor) FROM cod_remittances WHERE rider_user_id=$1 AND state='verified'),0)`, riderID).Scan(&liability); err != nil {
		t.Fatal(err)
	}
	if remitted != 300 || liability != 200 {
		t.Fatalf("unexpected synthetic cash reconciliation: remitted=%d liability=%d", remitted, liability)
	}
	var remittanceJournalCount int
	if err := db.Get(&remittanceJournalCount, `SELECT count(*) FROM financial_journals WHERE source_type='sandbox_cod_remittance' AND source_id=$1 AND source_event='verified' AND status='posted'`, payload.Data.ID); err != nil {
		t.Fatal(err)
	}
	if remittanceJournalCount != 1 {
		t.Fatalf("expected one remittance journal, got %d", remittanceJournalCount)
	}
	secondRemittance := httptest.NewRequest("POST", "/api/v1/rider/cash-remittances", strings.NewReader(`{"amount_minor":200,"submission_reference":"QA final balance"}`))
	secondRemittance.Header.Set("Idempotency-Key", uuid.NewString())
	secondRemittanceResponse := httptest.NewRecorder()
	svc.SubmitRemittance(secondRemittanceResponse, secondRemittance, riderID)
	if secondRemittanceResponse.Code != http.StatusCreated {
		t.Fatalf("submit final remittance balance HTTP %d: %s", secondRemittanceResponse.Code, secondRemittanceResponse.Body.String())
	}
	var secondPayload struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(secondRemittanceResponse.Body.Bytes(), &secondPayload); err != nil || secondPayload.Data.ID == "" {
		t.Fatalf("decode final remittance: payload=%+v err=%v", secondPayload, err)
	}
	secondReview := httptest.NewRequest("POST", "/api/v1/admin/cod/remittances/"+secondPayload.Data.ID+"/review", strings.NewReader(`{"decision":"verify","reason":"QA finance verified final synthetic balance"}`))
	secondReview.SetPathValue("remittanceId", secondPayload.Data.ID)
	secondReviewResponse := httptest.NewRecorder()
	svc.ReviewRemittance(secondReviewResponse, secondReview, rootID)
	if secondReviewResponse.Code != http.StatusOK {
		t.Fatalf("verify final remittance HTTP %d: %s", secondReviewResponse.Code, secondReviewResponse.Body.String())
	}
	if err := db.QueryRowx(`SELECT COALESCE(sum(amount_minor),0) FROM cod_remittances WHERE rider_user_id=$1 AND state='verified'`, riderID).Scan(&remitted); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRowx(`SELECT COALESCE((SELECT sum(amount_minor) FROM cod_collections WHERE rider_user_id=$1),0)-COALESCE((SELECT sum(amount_minor) FROM cod_remittances WHERE rider_user_id=$1 AND state='verified'),0)`, riderID).Scan(&liability); err != nil {
		t.Fatal(err)
	}
	if remitted != 500 || liability != 0 {
		t.Fatalf("unexpected final synthetic cash reconciliation: remitted=%d liability=%d", remitted, liability)
	}
	var unauthorized int
	if err := db.Get(&unauthorized, `SELECT count(*) FROM financial_journals WHERE source_type='sandbox_cod_collection' AND source_id=$1 AND (SELECT COALESCE(sum(amount_minor) FILTER(WHERE side='debit'),0)=COALESCE(sum(amount_minor) FILTER(WHERE side='credit'),0) FROM financial_postings WHERE journal_id=financial_journals.id)`, obligationID); err != nil {
		t.Fatal(err)
	}
	if unauthorized != 1 {
		t.Fatal("collection journal was not balanced")
	}
}
