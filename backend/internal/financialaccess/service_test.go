package financialaccess

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/google/uuid"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/jmoiron/sqlx"
	"grepmind-near/backend/pkg/database"
)

func TestAccessGrantWorkflowRequiresIndependentAuthorizedDecisionPostGIS(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_DSN")
	if dsn == "" {
		t.Skip("TEST_DATABASE_DSN is not set; run isolated Phase 4D PostGIS acceptance")
	}
	db, err := sqlx.Connect("pgx", dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	ctx := context.Background()
	var root string
	if err := db.Get(&root, `SELECT id::text FROM users WHERE phone_e164='+910000000000' AND status='active'`); err != nil {
		t.Fatal(err)
	}
	issuer, approver, target := uuid.NewString(), uuid.NewString(), uuid.NewString()
	for _, id := range []string{issuer, approver, target} {
		phone := "+1555" + strings.ReplaceAll(uuid.NewString(), "-", "")[:10]
		if _, err := db.ExecContext(ctx, `INSERT INTO users(id,phone_e164,status) VALUES($1,$2,'active')`, id, phone); err != nil {
			t.Fatal(err)
		}
		if _, err := db.ExecContext(ctx, `INSERT INTO user_roles(user_id,role) VALUES($1,'admin')`, id); err != nil {
			t.Fatal(err)
		}
	}
	// Test bootstrap uses the protected root account only inside the disposable
	// database; the runtime request and approval are made by separate actors.
	for _, entry := range []struct{ user, approver string }{{issuer, approver}, {approver, issuer}} {
		if _, err := db.ExecContext(ctx, `INSERT INTO financial_access_grants(user_id,permission,granted_by,approved_by,reason) VALUES($1,'finance.configure',$2,$3,'Disposable integration test setup')`, entry.user, root, entry.approver); err != nil {
			t.Fatal(err)
		}
	}
	svc := NewService(&database.DB{DB: db}, "qa")
	create := httptest.NewRequest("POST", "/api/v1/admin/finance/access-grant-requests", bytes.NewBufferString(`{"target_user_id":"`+target+`","permission":"finance.post","reason":"Temporary QA simulator access"}`))
	created := httptest.NewRecorder()
	svc.Create(created, create, issuer)
	if created.Code != 201 {
		t.Fatalf("create request status=%d body=%s", created.Code, created.Body.String())
	}
	var createdBody struct {
		Data struct {
			ID     string `json:"id"`
			Status string `json:"status"`
		} `json:"data"`
	}
	if err := json.Unmarshal(created.Body.Bytes(), &createdBody); err != nil {
		t.Fatal(err)
	}
	requestID := createdBody.Data.ID
	if requestID == "" || createdBody.Data.Status != "pending" {
		t.Fatalf("unexpected create response: %+v", createdBody.Data)
	}

	selfDecision := httptest.NewRequest("POST", "/decision", bytes.NewBufferString(`{"decision":"approve","reason":"Independent QA approval"}`))
	selfResult := httptest.NewRecorder()
	svc.Decide(selfResult, selfDecision, issuer, requestID)
	if selfResult.Code != 403 {
		t.Fatalf("requester self-approval status=%d, want 403", selfResult.Code)
	}

	approve := httptest.NewRequest("POST", "/decision", bytes.NewBufferString(`{"decision":"approve","reason":"Independent QA approval"}`))
	approved := httptest.NewRecorder()
	svc.Decide(approved, approve, approver, requestID)
	if approved.Code != 200 {
		t.Fatalf("approval status=%d body=%s", approved.Code, approved.Body.String())
	}
	var count int
	if err := db.Get(&count, `SELECT count(*) FROM financial_access_grants WHERE user_id=$1 AND permission='finance.post' AND revoked_at IS NULL`, target); err != nil {
		t.Fatal(err)
	}
	if count != 1 {
		t.Fatalf("active target grants=%d, want exactly one", count)
	}
	if err := db.Get(&count, `SELECT count(*) FROM financial_audit_events WHERE grant_request_id=$1 AND event_type IN ('access_grant_requested','access_grant_approved')`, requestID); err != nil {
		t.Fatal(err)
	}
	if count != 2 {
		t.Fatalf("request audit events=%d, want 2", count)
	}
	replay := httptest.NewRequest("POST", "/decision", bytes.NewBufferString(`{"decision":"approve","reason":"Duplicate approval attempt"}`))
	replayed := httptest.NewRecorder()
	svc.Decide(replayed, replay, approver, requestID)
	if replayed.Code != 409 {
		t.Fatalf("decision replay status=%d, want 409", replayed.Code)
	}
}

func TestFinanceGrantManagementUnavailableOutsideQA(t *testing.T) {
	svc := NewService(&database.DB{}, "production")
	w := httptest.NewRecorder()
	svc.List(w, httptest.NewRequest("GET", "/api/v1/admin/finance/access-grants", nil), uuid.NewString())
	if w.Code != 404 {
		t.Fatalf("production grant endpoint status=%d, want 404", w.Code)
	}
}
