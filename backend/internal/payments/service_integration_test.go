package payments

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/jmoiron/sqlx"
	"grepmind-near/backend/pkg/database"
	"grepmind-near/backend/pkg/logger"
)

type ambiguousSandboxProvider struct {
	*SandboxProvider
	calls atomic.Int32
}

func (p *ambiguousSandboxProvider) CreateSession(ctx context.Context, request CreateSessionRequest) (ProviderSession, error) {
	session, err := p.SandboxProvider.CreateSession(ctx, request)
	if err != nil {
		return ProviderSession{}, err
	}
	if p.calls.Add(1) == 1 {
		return ProviderSession{}, errors.New("simulated ambiguous provider timeout after session creation")
	}
	return session, nil
}

func TestPaymentIntentPostGISAcceptance(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_DSN")
	if dsn == "" {
		t.Skip("TEST_DATABASE_DSN is not set; use scripts/qa/phase4b_a_payment_intents.sh")
	}
	db, err := sqlx.Connect("pgx", dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	var tables int
	if err := db.Get(&tables, `SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name IN ('payment_intents','payment_attempts')`); err != nil {
		t.Fatal(err)
	}
	if tables != 2 {
		t.Fatalf("migration 031 missing payment tables: %d", tables)
	}
	var intentEnabled, attemptsEnabled bool
	if err := db.QueryRowx(`SELECT payment_intent_creation_enabled,payment_attempt_creation_enabled FROM financial_feature_config WHERE singleton=true`).Scan(&intentEnabled, &attemptsEnabled); err != nil {
		t.Fatal(err)
	}
	if intentEnabled || attemptsEnabled {
		t.Fatalf("payment intent/provider attempt gates must default off; got intent=%t attempts=%t", intentEnabled, attemptsEnabled)
	}
	var rootID string
	if err := db.Get(&rootID, `SELECT id::text FROM users WHERE phone_e164='+910000000000' AND status='active'`); err != nil {
		t.Fatal(err)
	}
	customerID, otherID, businessID, addressID, quoteID, orderID := uuid.NewString(), uuid.NewString(), uuid.NewString(), uuid.NewString(), uuid.NewString(), uuid.NewString()
	for _, id := range []string{customerID, otherID} {
		phone := "+91" + uuid.NewString()[:10]
		if _, err := db.Exec(`INSERT INTO users(id,phone_e164,status) VALUES($1,$2,'active')`, id, phone); err != nil {
			t.Fatal(err)
		}
		if _, err := db.Exec(`INSERT INTO user_roles(user_id,role) VALUES($1,'customer')`, id); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := db.Exec(`INSERT INTO businesses(id,owner_user_id,name,slug,category_slug,address_text,locality,city,postal_code,location,status,verification_status) VALUES($1,$2,'QA Payment Partner',$3,'restaurant','QA address','Kuanpal','Cuttack','754082',ST_SetSRID(ST_MakePoint(85.8,20.5),4326)::geography,'approved','verified')`, businessID, rootID, "qa-payment-"+businessID); err != nil {
		t.Fatal(err)
	}
	localityID := "02200000-0000-4000-8000-000000000101"
	if _, err := db.Exec(`INSERT INTO customer_addresses(id,customer_user_id,label,recipient_name,address_line1,locality,city,state,postal_code,contact_phone,delivery_locality_id) VALUES($1,$2,'Home','QA Customer','QA Test Lane','Kuanpal','Cuttack','Odisha','754082','+919900000002',$3)`, addressID, customerID, localityID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO platform_checkout_quotes(id,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,grand_total_minor,expires_at) SELECT $1,$2,'food',$3,CURRENT_DATE,$4,updated_at,$5,'[{"name":"QA item","quantity":1}]'::jsonb,12950,12950,now()+interval '5 minutes' FROM customer_addresses WHERE id=$4`, quoteID, customerID, localityID, addressID, businessID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,fulfillment_type,delivery_address,delivery_address_id,delivery_address_snapshot,platform_checkout_quote_id,payment_status,item_total,grand_total,currency,reference_code,order_source,platform_vertical,delivery_locality_id) VALUES($1,$2,$3,'platform_order','placed','delivery','QA address',$4,'{}'::jsonb,$5,'not_collected',129.50,129.50,'INR',$6,'platform_catalog','food',$7)`, orderID, customerID, businessID, addressID, quoteID, "QA-PAY-"+orderID, localityID); err != nil {
		t.Fatal(err)
	}
	// Force a known fail-closed starting point even if a developer reuses this
	// disposable database; all config changes remain audited by migration 030.
	setIntentGate := func(enabled bool) {
		t.Helper()
		_, err := db.Exec(`UPDATE financial_feature_config SET payment_intent_creation_enabled=$1,updated_by=$2,change_reason=$3,updated_at=now() WHERE singleton=true`, enabled, rootID, fmt.Sprintf("Disposable payment intent QA gate enabled=%t", enabled))
		if err != nil {
			t.Fatal(err)
		}
	}
	setIntentGate(false)
	t.Cleanup(func() {
		_, _ = db.Exec(`UPDATE financial_feature_config SET payment_intent_creation_enabled=false,updated_by=$1,change_reason='Disposable payment intent QA cleanup disabled gate',updated_at=now() WHERE singleton=true`, rootID)
	})
	svc := NewService(&database.DB{DB: db})
	key := uuid.NewString()
	callBody := func(user, order, idem string, method, body string) *httptest.ResponseRecorder {
		t.Helper()
		req := httptest.NewRequest(method, "/api/v1/orders/"+order+"/payment-intents", bytes.NewBufferString(body))
		req.SetPathValue("id", order)
		if idem != "" {
			req.Header.Set("Idempotency-Key", idem)
		}
		rec := httptest.NewRecorder()
		if method == http.MethodGet {
			svc.GetIntent(rec, req, user)
		} else {
			svc.CreateIntent(rec, req, user)
		}
		return rec
	}
	call := func(user, order, idem string, method string) *httptest.ResponseRecorder {
		return callBody(user, order, idem, method, "")
	}
	if got := call(customerID, orderID, key, http.MethodPost); got.Code != 503 {
		t.Fatalf("disabled endpoint status %d: %s", got.Code, got.Body.String())
	}
	setIntentGate(true)
	if got := callBody(customerID, orderID, key, http.MethodPost, `{"amount_minor":1,"currency":"USD"}`); got.Code != 400 {
		t.Fatalf("payment intent accepted a client-supplied price body: %d %s", got.Code, got.Body.String())
	}
	created := call(customerID, orderID, key, http.MethodPost)
	if created.Code != 201 {
		t.Fatalf("create intent status %d: %s", created.Code, created.Body.String())
	}
	var payload struct {
		Data struct {
			ID                       string `json:"id"`
			OrderID                  string `json:"order_id"`
			AmountMinor              int64  `json:"amount_minor"`
			Currency                 string `json:"currency"`
			Status                   string `json:"status"`
			PaymentStatus            string `json:"payment_status"`
			ProviderSessionAvailable bool   `json:"provider_session_available"`
		} `json:"data"`
		Meta map[string]bool `json:"meta"`
	}
	if err := json.Unmarshal(created.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if payload.Data.ID == "" || payload.Data.OrderID != orderID || payload.Data.AmountMinor != 12950 || payload.Data.Currency != "INR" || payload.Data.Status != "created" || payload.Data.PaymentStatus != "not_collected" || payload.Data.ProviderSessionAvailable {
		t.Fatalf("intent response is not authoritative/fail-closed: %+v", payload.Data)
	}
	replay := call(customerID, orderID, key, http.MethodPost)
	if replay.Code != 200 {
		t.Fatalf("idempotent replay status %d: %s", replay.Code, replay.Body.String())
	}
	var replayPayload struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
		Meta map[string]bool `json:"meta"`
	}
	if err := json.Unmarshal(replay.Body.Bytes(), &replayPayload); err != nil {
		t.Fatal(err)
	}
	if replayPayload.Data.ID != payload.Data.ID || !replayPayload.Meta["idempotent_replay"] {
		t.Fatalf("retry created a different intent: %+v", replayPayload)
	}
	if got := call(otherID, orderID, uuid.NewString(), http.MethodPost); got.Code != 404 {
		t.Fatalf("other customer create status %d: %s", got.Code, got.Body.String())
	}
	if got := call(otherID, orderID, "", http.MethodGet); got.Code != 404 {
		t.Fatalf("other customer read status %d: %s", got.Code, got.Body.String())
	}
	if got := call(customerID, uuid.NewString(), key, http.MethodPost); got.Code != 409 {
		t.Fatalf("reused key with changed order status %d: %s", got.Code, got.Body.String())
	}
	if got := call(customerID, orderID, uuid.NewString(), http.MethodPost); got.Code != 409 {
		t.Fatalf("second intent for order status %d: %s", got.Code, got.Body.String())
	}
	if got := call(customerID, orderID, "", http.MethodGet); got.Code != 200 {
		t.Fatalf("owned intent read status %d: %s", got.Code, got.Body.String())
	}
	var paymentStatus string
	if err := db.Get(&paymentStatus, `SELECT payment_status FROM customer_orders WHERE id=$1`, orderID); err != nil {
		t.Fatal(err)
	}
	if paymentStatus != "not_collected" {
		t.Fatalf("intent creation mutated order payment status to %q", paymentStatus)
	}
	var attempts int
	if err := db.Get(&attempts, `SELECT count(*) FROM payment_attempts WHERE payment_intent_id=$1`, payload.Data.ID); err != nil {
		t.Fatal(err)
	}
	if attempts != 0 {
		t.Fatalf("Phase 4B-A unexpectedly created %d provider attempts", attempts)
	}
	// Database-level guards reject amount tampering and attempt creation while
	// the provider-attempt feature is still off.
	if _, err := db.Exec(`UPDATE payment_intents SET amount_minor=1 WHERE id=$1`, payload.Data.ID); err == nil {
		t.Fatal("database allowed payment intent amount mutation")
	}
	if _, err := db.Exec(`INSERT INTO payment_attempts(payment_intent_id,attempt_number,provider,amount_minor,currency,status,provider_idempotency_key) VALUES($1,1,'qa-provider',12950,'INR','initialized',$2)`, payload.Data.ID, "attempt-"+uuid.NewString()); err == nil {
		t.Fatal("database allowed provider attempt while disabled")
	}
	var audited int
	if err := db.Get(&audited, `SELECT count(*) FROM financial_audit_events WHERE event_type='configuration_changed' AND metadata ? 'payment_intent_creation_enabled'`); err != nil {
		t.Fatal(err)
	}
	if audited < 2 {
		t.Fatalf("intent feature gate changes were not audited: %d", audited)
	}

	// Concurrent retries with one customer/key serialize to one immutable intent.
	// A second order is prepared by cloning only the QA order's order row and quote
	// reference; its purpose is to exercise a distinct idempotency operation.
	order2, quote2 := uuid.NewString(), uuid.NewString()
	if _, err := db.Exec(`INSERT INTO platform_checkout_quotes(id,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,grand_total_minor,expires_at) SELECT $1,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,grand_total_minor,now()+interval '5 minutes' FROM platform_checkout_quotes WHERE id=$2`, quote2, quoteID); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,fulfillment_type,delivery_address,delivery_address_id,delivery_address_snapshot,platform_checkout_quote_id,payment_status,item_total,grand_total,currency,reference_code,order_source,platform_vertical,delivery_locality_id) SELECT $1,customer_user_id,business_id,'platform_order','placed','delivery','QA address',delivery_address_id,'{}'::jsonb,$2,'not_collected',item_total,grand_total,currency,$3,'platform_catalog','food',delivery_locality_id FROM customer_orders WHERE id=$4`, order2, quote2, "QA-PAY-"+order2, orderID); err != nil {
		t.Fatal(err)
	}
	concurrentKey := uuid.NewString()
	var wg sync.WaitGroup
	results := make(chan *httptest.ResponseRecorder, 8)
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() { defer wg.Done(); results <- call(customerID, order2, concurrentKey, http.MethodPost) }()
	}
	wg.Wait()
	close(results)
	var createdID string
	for response := range results {
		if response.Code != 200 && response.Code != 201 {
			t.Fatalf("concurrent create status %d: %s", response.Code, response.Body.String())
		}
		var body struct {
			Data struct{ ID string } `json:"data"`
		}
		if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil {
			t.Fatal(err)
		}
		if createdID == "" {
			createdID = body.Data.ID
		} else if createdID != body.Data.ID {
			t.Fatalf("concurrent retries returned multiple intents: %s / %s", createdID, body.Data.ID)
		}
	}
	var count int
	if err := db.Get(&count, `SELECT count(*) FROM payment_intents WHERE order_id=$1`, order2); err != nil {
		t.Fatal(err)
	}
	if count != 1 {
		t.Fatalf("concurrent same-key requests created %d intents", count)
	}
}

func TestSandboxPaymentWebhookAndLedgerPostGISAcceptance(t *testing.T) {
	logger.Init("info")
	dsn := os.Getenv("TEST_DATABASE_DSN")
	if dsn == "" {
		t.Skip("TEST_DATABASE_DSN is not set; use scripts/qa/phase4b_b_sandbox_provider_webhooks.sh")
	}
	db, err := sqlx.Connect("pgx", dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	var migration032 int
	if err := db.Get(&migration032, `SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name IN ('payment_provider_events','payment_reconciliation_events','payment_ledger_account_mappings')`); err != nil {
		t.Fatal(err)
	}
	if migration032 != 3 {
		t.Fatalf("migration 032 incomplete: %d tables", migration032)
	}
	var rootID string
	if err := db.Get(&rootID, `SELECT id::text FROM users WHERE phone_e164='+910000000000' AND status='active'`); err != nil {
		t.Fatal(err)
	}
	customerID, businessID, addressID, quoteID, orderID := uuid.NewString(), uuid.NewString(), uuid.NewString(), uuid.NewString(), uuid.NewString()
	if _, err = db.Exec(`INSERT INTO users(id,phone_e164,status) VALUES($1,$2,'active')`, customerID, "+91"+strings.ReplaceAll(uuid.NewString(), "-", "")[:10]); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(`INSERT INTO user_roles(user_id,role) VALUES($1,'customer')`, customerID); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(`INSERT INTO businesses(id,owner_user_id,name,slug,category_slug,address_text,locality,city,postal_code,location,status,verification_status) VALUES($1,$2,'QA Sandbox Partner',$3,'restaurant','QA address','Kuanpal','Cuttack','754082',ST_SetSRID(ST_MakePoint(85.8,20.5),4326)::geography,'approved','verified')`, businessID, rootID, "qa-sandbox-"+businessID); err != nil {
		t.Fatal(err)
	}
	localityID := "02200000-0000-4000-8000-000000000101"
	if _, err = db.Exec(`INSERT INTO customer_addresses(id,customer_user_id,label,recipient_name,address_line1,locality,city,state,postal_code,contact_phone,delivery_locality_id) VALUES($1,$2,'Home','QA Customer','QA Test Lane','Kuanpal','Cuttack','Odisha','754082','+919900000002',$3)`, addressID, customerID, localityID); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(`INSERT INTO platform_checkout_quotes(id,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,grand_total_minor,expires_at) SELECT $1,$2,'food',$3,CURRENT_DATE,$4,updated_at,$5,'[{"name":"QA item","quantity":1}]'::jsonb,12950,12950,now()+interval '5 minutes' FROM customer_addresses WHERE id=$4`, quoteID, customerID, localityID, addressID, businessID); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(`INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,fulfillment_type,delivery_address,delivery_address_id,delivery_address_snapshot,platform_checkout_quote_id,payment_status,item_total,grand_total,currency,reference_code,order_source,platform_vertical,delivery_locality_id) VALUES($1,$2,$3,'platform_order','placed','delivery','QA address',$4,'{}'::jsonb,$5,'not_collected',129.50,129.50,'INR',$6,'platform_catalog','food',$7)`, orderID, customerID, businessID, addressID, quoteID, "QA-4BB-"+orderID, localityID); err != nil {
		t.Fatal(err)
	}
	// The two chart accounts and mapping are synthetic and isolated to this QA DB.
	clearing, receipts := uuid.NewString(), uuid.NewString()
	if _, err = db.Exec(`INSERT INTO financial_accounts(id,account_code,display_name,account_class,currency,normal_side) VALUES($1,'qa_provider_clearing','QA provider clearing','asset','INR','debit'),($2,'qa_customer_receipts','QA unapplied customer receipts','liability','INR','credit')`, clearing, receipts); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(`INSERT INTO payment_ledger_account_mappings(purpose,account_id,configured_by) VALUES('provider_clearing',$1,$3),('customer_receipts_unapplied',$2,$3)`, clearing, receipts, rootID); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(`UPDATE financial_feature_config SET payment_intent_creation_enabled=true,payment_attempt_creation_enabled=true,sandbox_payment_enabled=true,financial_posting_enabled=true,updated_by=$1,change_reason='Enable disposable sandbox payment acceptance',updated_at=now() WHERE singleton=true`, rootID); err != nil {
		t.Fatal(err)
	}
	defer func() {
		_, _ = db.Exec(`UPDATE financial_feature_config SET payment_intent_creation_enabled=false,payment_attempt_creation_enabled=false,sandbox_payment_enabled=false,financial_posting_enabled=false,updated_by=$1,change_reason='Disable disposable sandbox payment acceptance',updated_at=now() WHERE singleton=true`, rootID)
	}()
	secret := []byte(strings.Repeat("q", 32))
	provider, err := NewSandboxProvider(secret, "qa-key", 5*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	svc := NewServiceWithProvider(&database.DB{DB: db}, provider)
	createIntent := func(order string) string {
		t.Helper()
		req := httptest.NewRequest(http.MethodPost, "/api/v1/orders/"+order+"/payment-intents", nil)
		req.SetPathValue("id", order)
		req.Header.Set("Idempotency-Key", uuid.NewString())
		rec := httptest.NewRecorder()
		svc.CreateIntent(rec, req, customerID)
		if rec.Code != 201 {
			t.Fatalf("intent create status=%d body=%s", rec.Code, rec.Body.String())
		}
		var out struct {
			Data struct {
				ID string `json:"id"`
			} `json:"data"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
			t.Fatal(err)
		}
		return out.Data.ID
	}
	createSession := func(order, idemKey string) (string, string, int) {
		t.Helper()
		req := httptest.NewRequest(http.MethodPost, "/api/v1/orders/"+order+"/payment-sessions", nil)
		req.SetPathValue("id", order)
		req.Header.Set("Idempotency-Key", idemKey)
		rec := httptest.NewRecorder()
		svc.CreateSandboxSession(rec, req, customerID)
		if rec.Code != 201 && rec.Code != 200 {
			t.Fatalf("session create status=%d body=%s", rec.Code, rec.Body.String())
		}
		var out struct {
			Data struct {
				AttemptID string `json:"attempt_id"`
				Reference string `json:"provider_reference"`
			} `json:"data"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
			t.Fatal(err)
		}
		return out.Data.AttemptID, out.Data.Reference, rec.Code
	}
	createIntent(orderID)
	sessionKey := uuid.NewString()
	otherCustomer := uuid.NewString()
	if _, err = db.Exec(`INSERT INTO users(id,phone_e164,status) VALUES($1,$2,'active')`, otherCustomer, "+91"+strings.ReplaceAll(uuid.NewString(), "-", "")[:10]); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(`INSERT INTO user_roles(user_id,role) VALUES($1,'customer')`, otherCustomer); err != nil {
		t.Fatal(err)
	}
	unauthorizedReq := httptest.NewRequest(http.MethodPost, "/api/v1/orders/"+orderID+"/payment-sessions", nil)
	unauthorizedReq.SetPathValue("id", orderID)
	unauthorizedReq.Header.Set("Idempotency-Key", uuid.NewString())
	unauthorizedRec := httptest.NewRecorder()
	svc.CreateSandboxSession(unauthorizedRec, unauthorizedReq, otherCustomer)
	if unauthorizedRec.Code != 404 {
		t.Fatalf("another customer session status=%d body=%s", unauthorizedRec.Code, unauthorizedRec.Body.String())
	}
	tamperedReq := httptest.NewRequest(http.MethodPost, "/api/v1/orders/"+orderID+"/payment-sessions", strings.NewReader(`{"amount_minor":1,"currency":"USD"}`))
	tamperedReq.SetPathValue("id", orderID)
	tamperedReq.Header.Set("Idempotency-Key", uuid.NewString())
	tamperedRec := httptest.NewRecorder()
	svc.CreateSandboxSession(tamperedRec, tamperedReq, customerID)
	if tamperedRec.Code != 400 {
		t.Fatalf("client-supplied payment fields accepted: %d %s", tamperedRec.Code, tamperedRec.Body.String())
	}
	attemptID, reference, firstSessionStatus := createSession(orderID, sessionKey)
	if firstSessionStatus != 201 {
		t.Fatalf("first session status=%d", firstSessionStatus)
	}
	var sessionWG sync.WaitGroup
	sessionResults := make(chan struct {
		attempt, reference string
		status             int
		body               string
	}, 8)
	for i := 0; i < 8; i++ {
		sessionWG.Add(1)
		go func() {
			defer sessionWG.Done()
			req := httptest.NewRequest(http.MethodPost, "/api/v1/orders/"+orderID+"/payment-sessions", nil)
			req.SetPathValue("id", orderID)
			req.Header.Set("Idempotency-Key", sessionKey)
			rec := httptest.NewRecorder()
			svc.CreateSandboxSession(rec, req, customerID)
			var out struct {
				Data struct {
					AttemptID string `json:"attempt_id"`
					Reference string `json:"provider_reference"`
				} `json:"data"`
			}
			_ = json.Unmarshal(rec.Body.Bytes(), &out)
			sessionResults <- struct {
				attempt, reference string
				status             int
				body               string
			}{out.Data.AttemptID, out.Data.Reference, rec.Code, rec.Body.String()}
		}()
	}
	sessionWG.Wait()
	close(sessionResults)
	for result := range sessionResults {
		if result.status != 200 || result.attempt != attemptID || result.reference != reference {
			t.Fatalf("idempotent concurrent session result=%+v expected attempt=%s ref=%s", result, attemptID, reference)
		}
	}
	event := VerifiedProviderEvent{Provider: sandboxProviderName, EventID: "evt-success-1", ProviderReference: reference, Status: "succeeded", AmountMinor: 12950, Currency: "INR", EventAt: time.Now().UTC()}
	provider.SetPayment(ProviderPayment{Reference: reference, Status: "succeeded", AmountMinor: 12950, Currency: "INR"})
	body, _ := json.Marshal(event)
	signed := provider.Sign(body, time.Now())
	callWebhook := func(raw []byte, signature string) *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodPost, "/api/v1/payments/webhooks/"+sandboxProviderName, bytes.NewReader(raw))
		req.SetPathValue("provider", sandboxProviderName)
		req.Header.Set("X-Grepmind-Sandbox-Signature", signature)
		rec := httptest.NewRecorder()
		svc.ReceiveSandboxWebhook(rec, req)
		return rec
	}
	if got := callWebhook(body, "t=1,kid=qa-key,v1=00"); got.Code != 401 {
		t.Fatalf("invalid signature status %d", got.Code)
	}
	var noEvents int
	if err := db.Get(&noEvents, `SELECT count(*) FROM payment_provider_events`); err != nil {
		t.Fatal(err)
	}
	if noEvents != 0 {
		t.Fatalf("invalid signature persisted %d events", noEvents)
	}
	const parallel = 8
	var wg sync.WaitGroup
	responses := make(chan *httptest.ResponseRecorder, parallel)
	for i := 0; i < parallel; i++ {
		wg.Add(1)
		go func() { defer wg.Done(); responses <- callWebhook(body, signed) }()
	}
	wg.Wait()
	close(responses)
	processed, duplicates := 0, 0
	for response := range responses {
		if response.Code != 200 {
			t.Fatalf("concurrent webhook status=%d body=%s", response.Code, response.Body.String())
		}
		var out struct {
			Data struct {
				State string `json:"processing_state"`
			} `json:"data"`
		}
		if err := json.Unmarshal(response.Body.Bytes(), &out); err != nil {
			t.Fatal(err)
		}
		if out.Data.State == "processed" {
			processed++
		}
		if out.Data.State == "duplicate" {
			duplicates++
		}
	}
	if processed != 1 || duplicates != parallel-1 {
		t.Fatalf("webhook race processed=%d duplicate=%d", processed, duplicates)
	}
	if got := callWebhook(body, signed); got.Code != 200 {
		t.Fatalf("duplicate webhook status=%d", got.Code)
	}
	conflictEvent := event
	conflictEvent.AmountMinor++
	conflictBody, _ := json.Marshal(conflictEvent)
	if got := callWebhook(conflictBody, provider.Sign(conflictBody, time.Now())); got.Code != 409 {
		t.Fatalf("event ID payload conflict status=%d body=%s", got.Code, got.Body.String())
	}
	var orderPayment, intentStatus, attemptStatus, orderState string
	if err := db.QueryRowx(`SELECT o.payment_status,i.status,a.status,o.status FROM customer_orders o JOIN payment_intents i ON i.order_id=o.id JOIN payment_attempts a ON a.payment_intent_id=i.id WHERE o.id=$1`, orderID).Scan(&orderPayment, &intentStatus, &attemptStatus, &orderState); err != nil {
		t.Fatal(err)
	}
	if orderPayment != "paid" || intentStatus != "paid" || attemptStatus != "succeeded" || orderState != "placed" {
		t.Fatalf("payment projection mismatch order=%s intent=%s attempt=%s fulfillment=%s", orderPayment, intentStatus, attemptStatus, orderState)
	}
	if _, err := db.Exec(`UPDATE customer_orders SET status='cancelled' WHERE id=$1`, orderID); err == nil {
		t.Fatal("paid platform order cancellation bypassed the future refund boundary")
	}
	var journals int
	if err := db.Get(&journals, `SELECT count(*) FROM financial_journals WHERE source_type='sandbox_payment_capture' AND source_id=$1 AND source_event='verified_capture'`, attemptID); err != nil {
		t.Fatal(err)
	}
	if journals != 1 {
		t.Fatalf("capture journals=%d want 1", journals)
	}
	var debit, credit int64
	if err := db.QueryRowx(`SELECT sum(amount_minor) FILTER(WHERE side='debit'),sum(amount_minor) FILTER(WHERE side='credit') FROM financial_postings p JOIN financial_journals j ON j.id=p.journal_id WHERE j.source_type='sandbox_payment_capture' AND j.source_id=$1`, attemptID).Scan(&debit, &credit); err != nil {
		t.Fatal(err)
	}
	if debit != 12950 || credit != 12950 {
		t.Fatalf("capture journal unbalanced debit=%d credit=%d", debit, credit)
	}
	var eventLinked bool
	if err := db.Get(&eventLinked, `SELECT EXISTS(SELECT 1 FROM payment_provider_events e JOIN payment_attempts a ON a.id=e.payment_attempt_id JOIN financial_journals j ON j.id=e.financial_journal_id WHERE e.provider_event_id=$1 AND a.id=$2 AND j.source_id=$2::text)`, event.EventID, attemptID); err != nil || !eventLinked {
		t.Fatalf("payment trace link missing: %v", err)
	}
	var refundSchemaReady bool
	if err := db.Get(&refundSchemaReady, `SELECT to_regclass('public.payment_refunds') IS NOT NULL`); err != nil {
		t.Fatal(err)
	}
	if refundSchemaReady {
		// Refund requests reserve only the selected verified capture amount. They
		// require distinct finance approval and provider-confirmed synthetic evidence.
		refundKey := uuid.NewString()
		refundRequest := httptest.NewRequest(http.MethodPost, "/api/v1/orders/"+orderID+"/refunds", strings.NewReader(`{"amount_minor":5000,"reason_code":"items_missing"}`))
		refundRequest.SetPathValue("id", orderID)
		refundRequest.Header.Set("Idempotency-Key", refundKey)
		refundRec := httptest.NewRecorder()
		svc.RequestRefund(refundRec, refundRequest, customerID)
		if refundRec.Code != http.StatusCreated {
			t.Fatalf("refund request status=%d body=%s", refundRec.Code, refundRec.Body.String())
		}
		var refundResponse struct {
			Data struct {
				ID     string `json:"id"`
				Status string `json:"status"`
			} `json:"data"`
		}
		if err := json.Unmarshal(refundRec.Body.Bytes(), &refundResponse); err != nil || refundResponse.Data.ID == "" || refundResponse.Data.Status != "requested" {
			t.Fatalf("invalid refund response: %s err=%v", refundRec.Body.String(), err)
		}
		refundID := refundResponse.Data.ID
		refundReplayReq := httptest.NewRequest(http.MethodPost, "/api/v1/orders/"+orderID+"/refunds", strings.NewReader(`{"amount_minor":5000,"reason_code":"items_missing"}`))
		refundReplayReq.SetPathValue("id", orderID)
		refundReplayReq.Header.Set("Idempotency-Key", refundKey)
		refundReplayRec := httptest.NewRecorder()
		svc.RequestRefund(refundReplayRec, refundReplayReq, customerID)
		if refundReplayRec.Code != http.StatusOK {
			t.Fatalf("exact refund retry status=%d body=%s", refundReplayRec.Code, refundReplayRec.Body.String())
		}
		changedRefundReq := httptest.NewRequest(http.MethodPost, "/api/v1/orders/"+orderID+"/refunds", strings.NewReader(`{"amount_minor":5001,"reason_code":"items_missing"}`))
		changedRefundReq.SetPathValue("id", orderID)
		changedRefundReq.Header.Set("Idempotency-Key", refundKey)
		changedRefundRec := httptest.NewRecorder()
		svc.RequestRefund(changedRefundRec, changedRefundReq, customerID)
		if changedRefundRec.Code != http.StatusConflict {
			t.Fatalf("changed refund payload reused idempotency key: %d %s", changedRefundRec.Code, changedRefundRec.Body.String())
		}
		refundRaceCodes := make(chan int, 2)
		var refundRace sync.WaitGroup
		for n := 0; n < 2; n++ {
			refundRace.Add(1)
			go func() {
				defer refundRace.Done()
				req := httptest.NewRequest(http.MethodPost, "/api/v1/orders/"+orderID+"/refunds", strings.NewReader(`{"amount_minor":4000,"reason_code":"other"}`))
				req.SetPathValue("id", orderID)
				req.Header.Set("Idempotency-Key", uuid.NewString())
				rec := httptest.NewRecorder()
				svc.RequestRefund(rec, req, customerID)
				refundRaceCodes <- rec.Code
			}()
		}
		refundRace.Wait()
		close(refundRaceCodes)
		createdRefunds, conflictedRefunds := 0, 0
		for code := range refundRaceCodes {
			if code == http.StatusCreated {
				createdRefunds++
			}
			if code == http.StatusConflict {
				conflictedRefunds++
			}
		}
		if createdRefunds != 1 || conflictedRefunds != 1 {
			t.Fatalf("concurrent refund balance reservation created=%d conflict=%d", createdRefunds, conflictedRefunds)
		}
		excessRequest := httptest.NewRequest(http.MethodPost, "/api/v1/orders/"+orderID+"/refunds", strings.NewReader(`{"amount_minor":8000,"reason_code":"other"}`))
		excessRequest.SetPathValue("id", orderID)
		excessRequest.Header.Set("Idempotency-Key", uuid.NewString())
		excessRec := httptest.NewRecorder()
		svc.RequestRefund(excessRec, excessRequest, customerID)
		if excessRec.Code != http.StatusConflict {
			t.Fatalf("concurrent balance reservation accepted excess request: %d %s", excessRec.Code, excessRec.Body.String())
		}
		unauthorizedRefunds := httptest.NewRecorder()
		unauthorizedRefundReq := httptest.NewRequest(http.MethodGet, "/api/v1/orders/"+orderID+"/refunds", nil)
		unauthorizedRefundReq.SetPathValue("id", orderID)
		svc.ListRefunds(unauthorizedRefunds, unauthorizedRefundReq, otherCustomer)
		if unauthorizedRefunds.Code != http.StatusNotFound {
			t.Fatalf("another customer's refund history status=%d", unauthorizedRefunds.Code)
		}
		unauthorizedReview := httptest.NewRecorder()
		unauthorizedReviewReq := httptest.NewRequest(http.MethodPost, "/api/v1/admin/payments/refunds/"+refundID+"/review", strings.NewReader(`{"decision":"approve","reason":"Unauthorized QA review attempt"}`))
		unauthorizedReviewReq.SetPathValue("id", refundID)
		svc.ReviewRefund(unauthorizedReview, unauthorizedReviewReq, otherCustomer)
		if unauthorizedReview.Code != http.StatusForbidden {
			t.Fatalf("unauthorized refund approval status=%d", unauthorizedReview.Code)
		}
		reviewReq := httptest.NewRequest(http.MethodPost, "/api/v1/admin/payments/refunds/"+refundID+"/review", strings.NewReader(`{"decision":"approve","reason":"Approved after isolated QA finance review."}`))
		reviewReq.SetPathValue("id", refundID)
		reviewRec := httptest.NewRecorder()
		svc.ReviewRefund(reviewRec, reviewReq, rootID)
		if reviewRec.Code != http.StatusOK {
			t.Fatalf("finance refund approval status=%d body=%s", reviewRec.Code, reviewRec.Body.String())
		}
		var refundRef string
		if err := db.Get(&refundRef, `SELECT provider_reference FROM payment_refunds WHERE id=$1`, refundID); err != nil || refundRef == "" {
			t.Fatalf("sandbox refund reference missing: %v", err)
		}
		providerRefund, err := provider.FetchRefund(context.Background(), refundRef)
		if err != nil {
			t.Fatal(err)
		}
		providerRefund.Status = "succeeded"
		provider.SetRefund(providerRefund)
		refundEvent := VerifiedProviderEvent{ObjectType: "refund", Provider: sandboxProviderName, EventID: "evt-refund-success-1", ProviderReference: refundRef, Status: "succeeded", AmountMinor: 5000, Currency: "INR", EventAt: time.Now().UTC()}
		refundBody, _ := json.Marshal(refundEvent)
		refundSignature := provider.Sign(refundBody, time.Now())
		if got := callWebhook(refundBody, refundSignature); got.Code != http.StatusOK {
			t.Fatalf("verified refund callback status=%d body=%s", got.Code, got.Body.String())
		}
		if got := callWebhook(refundBody, refundSignature); got.Code != http.StatusOK {
			t.Fatalf("duplicate refund callback status=%d body=%s", got.Code, got.Body.String())
		}
		var refundStatus string
		var refundJournalCount int
		if err := db.QueryRowx(`SELECT status,(SELECT count(*) FROM financial_journals WHERE source_type='sandbox_payment_refund' AND source_id=$1::text) FROM payment_refunds WHERE id=$1::uuid`, refundID).Scan(&refundStatus, &refundJournalCount); err != nil {
			t.Fatal(err)
		}
		if refundStatus != "succeeded" || refundJournalCount != 1 {
			t.Fatalf("refund state=%s journals=%d", refundStatus, refundJournalCount)
		}
		var refundDebit, refundCredit int64
		if err := db.QueryRowx(`SELECT sum(p.amount_minor) FILTER(WHERE p.side='debit'),sum(p.amount_minor) FILTER(WHERE p.side='credit') FROM financial_postings p JOIN financial_journals j ON j.id=p.journal_id WHERE j.source_type='sandbox_payment_refund' AND j.source_id=$1`, refundID).Scan(&refundDebit, &refundCredit); err != nil {
			t.Fatal(err)
		}
		if refundDebit != 5000 || refundCredit != 5000 {
			t.Fatalf("refund journal unbalanced debit=%d credit=%d", refundDebit, refundCredit)
		}
		var paymentProjection string
		if err := db.Get(&paymentProjection, `SELECT payment_status FROM customer_orders WHERE id=$1`, orderID); err != nil {
			t.Fatal(err)
		}
		if paymentProjection != "paid" {
			t.Fatalf("refund incorrectly erased captured payment projection: %s", paymentProjection)
		}
	}
	staleFailure := VerifiedProviderEvent{Provider: sandboxProviderName, EventID: "evt-stale-failure", ProviderReference: reference, Status: "failed", AmountMinor: 12950, Currency: "INR", EventAt: time.Now().UTC()}
	staleFailureBody, _ := json.Marshal(staleFailure)
	if got := callWebhook(staleFailureBody, provider.Sign(staleFailureBody, time.Now())); got.Code != 200 {
		t.Fatalf("stale failure event response=%d", got.Code)
	}
	var stillPaid string
	if err := db.Get(&stillPaid, `SELECT payment_status FROM customer_orders WHERE id=$1`, orderID); err != nil {
		t.Fatal(err)
	}
	if stillPaid != "paid" {
		t.Fatalf("stale failure regressed paid order to %s", stillPaid)
	}
	// A second order is cancelled after session creation. The late verified
	// capture is retained and posted, while the order's canceled state is intact.
	order2, quote2 := uuid.NewString(), uuid.NewString()
	if _, err = db.Exec(`INSERT INTO platform_checkout_quotes(id,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,grand_total_minor,expires_at) SELECT $1,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,grand_total_minor,now()+interval '5 minutes' FROM platform_checkout_quotes WHERE id=$2`, quote2, quoteID); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(`INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,fulfillment_type,delivery_address,delivery_address_id,delivery_address_snapshot,platform_checkout_quote_id,payment_status,item_total,grand_total,currency,reference_code,order_source,platform_vertical,delivery_locality_id) SELECT $1,customer_user_id,business_id,'platform_order','placed','delivery','QA address',delivery_address_id,'{}'::jsonb,$2,'not_collected',item_total,grand_total,currency,$3,'platform_catalog','food',delivery_locality_id FROM customer_orders WHERE id=$4`, order2, quote2, "QA-4BB-"+order2, orderID); err != nil {
		t.Fatal(err)
	}
	createIntent(order2)
	conflictReq := httptest.NewRequest(http.MethodPost, "/api/v1/orders/"+order2+"/payment-sessions", nil)
	conflictReq.SetPathValue("id", order2)
	conflictReq.Header.Set("Idempotency-Key", sessionKey)
	conflictRec := httptest.NewRecorder()
	svc.CreateSandboxSession(conflictRec, conflictReq, customerID)
	if conflictRec.Code != 409 {
		t.Fatalf("reusing payment session key across orders status=%d body=%s", conflictRec.Code, conflictRec.Body.String())
	}
	attempt2, reference2, _ := createSession(order2, uuid.NewString())
	mismatch := VerifiedProviderEvent{Provider: sandboxProviderName, EventID: "evt-mismatch-2", ProviderReference: reference2, Status: "succeeded", AmountMinor: 12951, Currency: "INR", EventAt: time.Now().UTC()}
	mismatchBody, _ := json.Marshal(mismatch)
	if got := callWebhook(mismatchBody, provider.Sign(mismatchBody, time.Now())); got.Code != 202 {
		t.Fatalf("amount mismatch response=%d %s", got.Code, got.Body.String())
	}
	failure := VerifiedProviderEvent{Provider: sandboxProviderName, EventID: "evt-failure-2", ProviderReference: reference2, Status: "failed", AmountMinor: 12950, Currency: "INR", EventAt: time.Now().UTC()}
	failureBody, _ := json.Marshal(failure)
	if got := callWebhook(failureBody, provider.Sign(failureBody, time.Now())); got.Code != 200 {
		t.Fatalf("failure event response=%d %s", got.Code, got.Body.String())
	}
	if _, err = db.Exec(`UPDATE customer_orders SET status='cancelled' WHERE id=$1`, order2); err != nil {
		t.Fatal(err)
	}
	late := VerifiedProviderEvent{Provider: sandboxProviderName, EventID: "evt-late-2", ProviderReference: reference2, Status: "succeeded", AmountMinor: 12950, Currency: "INR", EventAt: time.Now().UTC()}
	lateBody, _ := json.Marshal(late)
	if got := callWebhook(lateBody, provider.Sign(lateBody, time.Now())); got.Code != 202 {
		t.Fatalf("late success response=%d %s", got.Code, got.Body.String())
	}
	var latePayment, lateIntent string
	if err := db.QueryRowx(`SELECT o.status,o.payment_status,i.status FROM customer_orders o JOIN payment_intents i ON i.order_id=o.id WHERE o.id=$1`, order2).Scan(&orderState, &latePayment, &lateIntent); err != nil {
		t.Fatal(err)
	}
	if orderState != "cancelled" || latePayment != "paid" || lateIntent != "reconciliation_required" {
		t.Fatalf("late capture state order=%s payment=%s intent=%s", orderState, latePayment, lateIntent)
	}
	var lateJournal, lateRecon int
	if err := db.Get(&lateJournal, `SELECT count(*) FROM financial_journals WHERE source_type='sandbox_payment_capture' AND source_id=$1`, attempt2); err != nil {
		t.Fatal(err)
	}
	if err := db.Get(&lateRecon, `SELECT count(*) FROM payment_reconciliation_events WHERE payment_attempt_id=$1 AND outcome='late_success'`, attempt2); err != nil {
		t.Fatal(err)
	}
	if lateJournal != 1 || lateRecon != 1 {
		t.Fatalf("late success journal=%d reconciliation=%d", lateJournal, lateRecon)
	}
	// Reconciliation queries the fake provider server-to-server and requires a
	// finance principal; a customer cannot use the endpoint as an attempt oracle.
	order3, quote3 := uuid.NewString(), uuid.NewString()
	if _, err = db.Exec(`INSERT INTO platform_checkout_quotes(id,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,grand_total_minor,expires_at) SELECT $1,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,grand_total_minor,now()+interval '5 minutes' FROM platform_checkout_quotes WHERE id=$2`, quote3, quoteID); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(`INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,fulfillment_type,delivery_address,delivery_address_id,delivery_address_snapshot,platform_checkout_quote_id,payment_status,item_total,grand_total,currency,reference_code,order_source,platform_vertical,delivery_locality_id) SELECT $1,customer_user_id,business_id,'platform_order','placed','delivery','QA address',delivery_address_id,'{}'::jsonb,$2,'not_collected',item_total,grand_total,currency,$3,'platform_catalog','food',delivery_locality_id FROM customer_orders WHERE id=$4`, order3, quote3, "QA-4BB-"+order3, orderID); err != nil {
		t.Fatal(err)
	}
	createIntent(order3)
	attempt3, reference3, _ := createSession(order3, uuid.NewString())
	provider.SetPayment(ProviderPayment{Reference: reference3, Status: "succeeded", AmountMinor: 12950, Currency: "INR"})
	reconcileRequest := func(userID string) *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodPost, "/api/v1/admin/payments/attempts/"+attempt3+"/reconcile", nil)
		req.SetPathValue("id", attempt3)
		rec := httptest.NewRecorder()
		svc.ReconcileSandboxPayment(rec, req, userID)
		return rec
	}
	if got := reconcileRequest(customerID); got.Code != 403 {
		t.Fatalf("customer reconciliation authorization status=%d", got.Code)
	}
	reconciliationEvent := VerifiedProviderEvent{Provider: sandboxProviderName, EventID: "evt-reconcile-race", ProviderReference: reference3, Status: "succeeded", AmountMinor: 12950, Currency: "INR", EventAt: time.Now().UTC()}
	reconciliationBody, _ := json.Marshal(reconciliationEvent)
	startRace := make(chan struct{})
	raceResults := make(chan *httptest.ResponseRecorder, 2)
	var reconcileWG sync.WaitGroup
	reconcileWG.Add(2)
	go func() { defer reconcileWG.Done(); <-startRace; raceResults <- reconcileRequest(rootID) }()
	go func() {
		defer reconcileWG.Done()
		<-startRace
		raceResults <- callWebhook(reconciliationBody, provider.Sign(reconciliationBody, time.Now()))
	}()
	close(startRace)
	reconcileWG.Wait()
	close(raceResults)
	for response := range raceResults {
		if response.Code != 200 {
			t.Fatalf("provider success vs reconciliation race status=%d body=%s", response.Code, response.Body.String())
		}
	}
	// Provider expiry and success can arrive in either order. Both are signed
	// provider facts; final capture is retained exactly once.
	order4, quote4 := uuid.NewString(), uuid.NewString()
	if _, err = db.Exec(`INSERT INTO platform_checkout_quotes(id,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,grand_total_minor,expires_at) SELECT $1,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,grand_total_minor,now()+interval '5 minutes' FROM platform_checkout_quotes WHERE id=$2`, quote4, quoteID); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(`INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,fulfillment_type,delivery_address,delivery_address_id,delivery_address_snapshot,platform_checkout_quote_id,payment_status,item_total,grand_total,currency,reference_code,order_source,platform_vertical,delivery_locality_id) SELECT $1,customer_user_id,business_id,'platform_order','placed','delivery','QA address',delivery_address_id,'{}'::jsonb,$2,'not_collected',item_total,grand_total,currency,$3,'platform_catalog','food',delivery_locality_id FROM customer_orders WHERE id=$4`, order4, quote4, "QA-4BB-"+order4, orderID); err != nil {
		t.Fatal(err)
	}
	createIntent(order4)
	attempt4, reference4, _ := createSession(order4, uuid.NewString())
	expiryEvent := VerifiedProviderEvent{Provider: sandboxProviderName, EventID: "evt-expiry-race", ProviderReference: reference4, Status: "expired", AmountMinor: 12950, Currency: "INR", EventAt: time.Now().UTC()}
	expiryBody, _ := json.Marshal(expiryEvent)
	successEvent := expiryEvent
	successEvent.EventID = "evt-success-race"
	successEvent.Status = "succeeded"
	successBody, _ := json.Marshal(successEvent)
	expiryStart := make(chan struct{})
	expiryResults := make(chan *httptest.ResponseRecorder, 2)
	var expiryWG sync.WaitGroup
	expiryWG.Add(2)
	go func() {
		defer expiryWG.Done()
		<-expiryStart
		expiryResults <- callWebhook(expiryBody, provider.Sign(expiryBody, time.Now()))
	}()
	go func() {
		defer expiryWG.Done()
		<-expiryStart
		expiryResults <- callWebhook(successBody, provider.Sign(successBody, time.Now()))
	}()
	close(expiryStart)
	expiryWG.Wait()
	close(expiryResults)
	for response := range expiryResults {
		if response.Code != 200 && response.Code != 202 {
			t.Fatalf("success vs expiry race status=%d body=%s", response.Code, response.Body.String())
		}
	}
	var finalPayment, finalAttempt, finalOrder string
	if err := db.QueryRowx(`SELECT o.payment_status,a.status,o.status FROM customer_orders o JOIN payment_intents i ON i.order_id=o.id JOIN payment_attempts a ON a.payment_intent_id=i.id WHERE o.id=$1`, order4).Scan(&finalPayment, &finalAttempt, &finalOrder); err != nil {
		t.Fatal(err)
	}
	if finalPayment != "paid" || finalAttempt != "succeeded" || finalOrder != "placed" {
		t.Fatalf("success/expiry race final state payment=%s attempt=%s order=%s", finalPayment, finalAttempt, finalOrder)
	}
	var expiryJournals int
	if err := db.Get(&expiryJournals, `SELECT count(*) FROM financial_journals WHERE source_type='sandbox_payment_capture' AND source_id=$1`, attempt4); err != nil {
		t.Fatal(err)
	}
	if expiryJournals != 1 {
		t.Fatalf("success/expiry race journal count=%d", expiryJournals)
	}
	var reconciledPayment string
	if err := db.Get(&reconciledPayment, `SELECT payment_status FROM customer_orders WHERE id=$1`, order3); err != nil {
		t.Fatal(err)
	}
	if reconciledPayment != "paid" {
		t.Fatalf("server-fetched provider success projected as %s", reconciledPayment)
	}
	// A success on a later retry does not erase a distinct late capture on an
	// earlier attempt. Both facts are posted once and the extra capture is flagged.
	order5, quote5 := uuid.NewString(), uuid.NewString()
	if _, err = db.Exec(`INSERT INTO platform_checkout_quotes(id,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,grand_total_minor,expires_at) SELECT $1,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,grand_total_minor,now()+interval '5 minutes' FROM platform_checkout_quotes WHERE id=$2`, quote5, quoteID); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(`INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,fulfillment_type,delivery_address,delivery_address_id,delivery_address_snapshot,platform_checkout_quote_id,payment_status,item_total,grand_total,currency,reference_code,order_source,platform_vertical,delivery_locality_id) SELECT $1,customer_user_id,business_id,'platform_order','placed','delivery','QA address',delivery_address_id,'{}'::jsonb,$2,'not_collected',item_total,grand_total,currency,$3,'platform_catalog','food',delivery_locality_id FROM customer_orders WHERE id=$4`, order5, quote5, "QA-4BB-"+order5, orderID); err != nil {
		t.Fatal(err)
	}
	createIntent(order5)
	firstAttempt, firstReference, _ := createSession(order5, uuid.NewString())
	firstFailure := VerifiedProviderEvent{Provider: sandboxProviderName, EventID: "evt-retry-failed", ProviderReference: firstReference, Status: "failed", AmountMinor: 12950, Currency: "INR", EventAt: time.Now().UTC()}
	firstFailureBody, _ := json.Marshal(firstFailure)
	if got := callWebhook(firstFailureBody, provider.Sign(firstFailureBody, time.Now())); got.Code != 200 {
		t.Fatalf("first attempt failure status=%d", got.Code)
	}
	secondAttempt, secondReference, _ := createSession(order5, uuid.NewString())
	secondSuccess := VerifiedProviderEvent{Provider: sandboxProviderName, EventID: "evt-retry-success", ProviderReference: secondReference, Status: "succeeded", AmountMinor: 12950, Currency: "INR", EventAt: time.Now().UTC()}
	secondSuccessBody, _ := json.Marshal(secondSuccess)
	if got := callWebhook(secondSuccessBody, provider.Sign(secondSuccessBody, time.Now())); got.Code != 200 {
		t.Fatalf("retry success status=%d", got.Code)
	}
	firstLate := VerifiedProviderEvent{Provider: sandboxProviderName, EventID: "evt-first-late-success", ProviderReference: firstReference, Status: "succeeded", AmountMinor: 12950, Currency: "INR", EventAt: time.Now().UTC()}
	firstLateBody, _ := json.Marshal(firstLate)
	if got := callWebhook(firstLateBody, provider.Sign(firstLateBody, time.Now())); got.Code != 202 {
		t.Fatalf("second successful attempt reconciliation status=%d body=%s", got.Code, got.Body.String())
	}
	var attempts5, journals5, recons5 int
	if err := db.Get(&attempts5, `SELECT count(*) FROM payment_attempts WHERE payment_intent_id=(SELECT id FROM payment_intents WHERE order_id=$1) AND status='succeeded'`, order5); err != nil {
		t.Fatal(err)
	}
	if err := db.Get(&journals5, `SELECT count(*) FROM financial_journals WHERE source_type='sandbox_payment_capture' AND source_id IN ($1,$2)`, firstAttempt, secondAttempt); err != nil {
		t.Fatal(err)
	}
	if err := db.Get(&recons5, `SELECT count(*) FROM payment_reconciliation_events WHERE payment_attempt_id=$1 AND outcome='late_success'`, firstAttempt); err != nil {
		t.Fatal(err)
	}
	if attempts5 != 2 || journals5 != 2 || recons5 != 1 {
		t.Fatalf("multiple capture reconciliation attempts=%d journals=%d exception=%d", attempts5, journals5, recons5)
	}
	// Simulate an ambiguous provider timeout after the deterministic fake has
	// created its session. Retrying the same key must recover the same attempt.
	order6, quote6 := uuid.NewString(), uuid.NewString()
	if _, err = db.Exec(`INSERT INTO platform_checkout_quotes(id,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,grand_total_minor,expires_at) SELECT $1,customer_user_id,vertical,locality_id,service_date,address_id,address_updated_at,partner_business_id,items,item_subtotal_minor,grand_total_minor,now()+interval '5 minutes' FROM platform_checkout_quotes WHERE id=$2`, quote6, quoteID); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(`INSERT INTO customer_orders(id,customer_user_id,business_id,order_type,status,fulfillment_type,delivery_address,delivery_address_id,delivery_address_snapshot,platform_checkout_quote_id,payment_status,item_total,grand_total,currency,reference_code,order_source,platform_vertical,delivery_locality_id) SELECT $1,customer_user_id,business_id,'platform_order','placed','delivery','QA address',delivery_address_id,'{}'::jsonb,$2,'not_collected',item_total,grand_total,currency,$3,'platform_catalog','food',delivery_locality_id FROM customer_orders WHERE id=$4`, order6, quote6, "QA-4BB-"+order6, orderID); err != nil {
		t.Fatal(err)
	}
	createIntent(order6)
	flaky := &ambiguousSandboxProvider{SandboxProvider: provider}
	flakySvc := NewServiceWithProvider(&database.DB{DB: db}, flaky)
	sessionKey6 := uuid.NewString()
	callFlaky := func() *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodPost, "/api/v1/orders/"+order6+"/payment-sessions", nil)
		req.SetPathValue("id", order6)
		req.Header.Set("Idempotency-Key", sessionKey6)
		rec := httptest.NewRecorder()
		flakySvc.CreateSandboxSession(rec, req, customerID)
		return rec
	}
	if got := callFlaky(); got.Code != 503 {
		t.Fatalf("ambiguous session result status=%d", got.Code)
	}
	var retryAttemptID string
	if err := db.Get(&retryAttemptID, `SELECT id::text FROM payment_attempts WHERE payment_intent_id=(SELECT id FROM payment_intents WHERE order_id=$1)`, order6); err != nil {
		t.Fatal(err)
	}
	if got := callFlaky(); got.Code != 200 {
		t.Fatalf("session retry status=%d body=%s", got.Code, got.Body.String())
	}
	var retryCount int
	if err := db.Get(&retryCount, `SELECT count(*) FROM payment_attempts WHERE payment_intent_id=(SELECT id FROM payment_intents WHERE order_id=$1)`, order6); err != nil {
		t.Fatal(err)
	}
	if retryCount != 1 {
		t.Fatalf("ambiguous retry created %d attempts", retryCount)
	}
	var liveFlags, earnings int
	if err := db.Get(&liveFlags, `SELECT count(*) FROM financial_feature_config WHERE upi_enabled OR cod_enabled OR merchant_settlement_enabled OR real_money_enabled`); err != nil {
		t.Fatal(err)
	}
	if liveFlags != 0 {
		t.Fatal("sandbox acceptance enabled live payment feature")
	}
	if err := db.Get(&earnings, `SELECT count(*) FROM rider_earning_entries WHERE order_id IN ($1,$2,$3)`, orderID, order2, order3); err != nil {
		t.Fatal(err)
	}
	if earnings != 0 {
		t.Fatalf("sandbox payment created %d rider earnings", earnings)
	}
}
