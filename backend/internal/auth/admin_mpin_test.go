package auth

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"
)

func TestAdminMPINLifecycle(t *testing.T) {
	const origin = "https://admin.example.test"
	t.Setenv("ADMIN_MPIN_ORIGIN", origin)
	svc, userID := newSessionIntegrationService(t)
	migration, err := os.ReadFile("../../migrations/041_admin_device_mpin.sql")
	if err != nil {
		t.Fatal(err)
	}
	if _, err = svc.db.Exec(string(migration)); err != nil {
		t.Fatal(err)
	}
	if _, err = svc.db.Exec("INSERT INTO user_roles(user_id,role) VALUES ($1,'admin')", userID); err != nil {
		t.Fatal(err)
	}
	type tokenResponse struct {
		Data struct {
			Access              string `json:"access_token"`
			EnrollmentAvailable bool   `json:"admin_mpin_enrollment_available"`
		} `json:"data"`
	}
	otpLogin := func(device *http.Cookie, wantEnrollment bool) string {
		t.Helper()
		challenge := uuid.NewString()
		hash, hashErr := bcrypt.GenerateFromPassword([]byte("183796"), bcrypt.MinCost)
		if hashErr != nil {
			t.Fatal(hashErr)
		}
		if _, err := svc.db.Exec(`INSERT INTO otp_codes(id,phone_e164,code_hash,expires_at) VALUES ($1,$2,$3,$4)`, challenge, "+919876543210", string(hash), time.Now().Add(time.Minute)); err != nil {
			t.Fatal(err)
		}
		request := httptest.NewRequest(http.MethodPost, origin+"/api/v1/auth/otp/verify", strings.NewReader(`{"phone_e164":"+919876543210","otp_code":"183796","challenge_id":"`+challenge+`"}`))
		request.Header.Set("Origin", origin)
		if device != nil {
			request.AddCookie(device)
		}
		response := httptest.NewRecorder()
		svc.VerifyOTP(response, request)
		var session tokenResponse
		if response.Code != http.StatusOK || json.Unmarshal(response.Body.Bytes(), &session) != nil || session.Data.Access == "" {
			t.Fatalf("OTP sign-in status %d", response.Code)
		}
		if session.Data.EnrollmentAvailable != wantEnrollment {
			t.Fatalf("enrollment offer=%t, want %t", session.Data.EnrollmentAvailable, wantEnrollment)
		}
		return session.Data.Access
	}
	call := func(handler http.HandlerFunc, from, pin, access string, device *http.Cookie) *httptest.ResponseRecorder {
		t.Helper()
		request := httptest.NewRequest(http.MethodPost, origin+"/api/v1/auth/admin-mpin", strings.NewReader(`{"pin":"`+pin+`"}`))
		request.Header.Set("Origin", from)
		if access != "" {
			request.Header.Set("Authorization", "Bearer "+access)
		}
		if device != nil {
			request.AddCookie(device)
		}
		response := httptest.NewRecorder()
		handler(response, request)
		return response
	}
	expectStatus := func(response *httptest.ResponseRecorder, status int) {
		t.Helper()
		if response.Code != status {
			t.Fatalf("status %d, want %d", response.Code, status)
		}
	}
	const pin = "726591"
	access := otpLogin(nil, true)
	expectStatus(call(svc.EnrollAdminMPIN, "https://other.example.test", pin, access, nil), http.StatusForbidden)
	enrollment := call(svc.EnrollAdminMPIN, origin, pin, access, nil)
	expectStatus(enrollment, http.StatusNoContent)
	cookies := enrollment.Result().Cookies()
	if len(cookies) != 1 || !cookies[0].HttpOnly || !cookies[0].Secure || cookies[0].SameSite != http.SameSiteStrictMode {
		t.Fatal("expected one secure enrolled-browser cookie")
	}
	device := cookies[0]
	returningOTP := otpLogin(device, false)
	expectStatus(call(svc.EnrollAdminMPIN, origin, pin, returningOTP, device), http.StatusUnauthorized)
	expectStatus(call(svc.EnrollAdminMPIN, origin, pin, access, nil), http.StatusUnauthorized)
	expectStatus(call(svc.VerifyAdminMPIN, origin, pin, "", nil), http.StatusUnauthorized)
	signedIn := call(svc.VerifyAdminMPIN, origin, pin, "", device)
	expectStatus(signedIn, http.StatusOK)
	var pinSession tokenResponse
	if err = json.Unmarshal(signedIn.Body.Bytes(), &pinSession); err != nil {
		t.Fatal(err)
	}
	expectStatus(call(svc.EnrollAdminMPIN, origin, pin, pinSession.Data.Access, device), http.StatusUnauthorized)

	for i := 0; i < adminMPINMaxFailures; i++ {
		expectStatus(call(svc.VerifyAdminMPIN, origin, "999000", "", device), http.StatusUnauthorized)
	}
	expectStatus(call(svc.VerifyAdminMPIN, origin, pin, "", device), http.StatusUnauthorized)
	replacement := call(svc.EnrollAdminMPIN, origin, pin, otpLogin(device, true), device)
	expectStatus(replacement, http.StatusNoContent)
	newDevice := replacement.Result().Cookies()[0]
	expectStatus(call(svc.VerifyAdminMPIN, origin, pin, "", device), http.StatusUnauthorized)
	expectStatus(call(svc.VerifyAdminMPIN, origin, pin, "", newDevice), http.StatusOK)
	removeAccess := otpLogin(newDevice, true)
	removeRequest := httptest.NewRequest(http.MethodPost, origin+"/api/v1/auth/admin-mpin/remove", strings.NewReader(`{}`))
	removeRequest.Header.Set("Origin", origin)
	removeRequest.Header.Set("Authorization", "Bearer "+removeAccess)
	removeRequest.AddCookie(newDevice)
	removeResponse := httptest.NewRecorder()
	svc.RemoveAdminMPIN(removeResponse, removeRequest)
	expectStatus(removeResponse, http.StatusNoContent)
	expectStatus(call(svc.VerifyAdminMPIN, origin, pin, "", newDevice), http.StatusUnauthorized)
	var auditCount int
	if err = svc.db.Get(&auditCount, `SELECT count(*) FROM audit_logs WHERE action IN ('admin_mpin.enrolled','admin_mpin.removed') AND actor_user_id=$1`, userID); err != nil || auditCount < 3 {
		t.Fatalf("expected audited PIN changes, count=%d err=%v", auditCount, err)
	}
	if _, err = svc.db.Exec("DELETE FROM user_roles WHERE user_id=$1 AND role='admin'", userID); err != nil {
		t.Fatal(err)
	}
	expectStatus(call(svc.VerifyAdminMPIN, origin, pin, "", newDevice), http.StatusUnauthorized)
}
