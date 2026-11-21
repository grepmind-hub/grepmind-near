package devices

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestPreLoginRegistrationFailsClosed(t *testing.T) {
	req := httptest.NewRequest(http.MethodPost, "/api/v1/devices/register-prelogin", strings.NewReader(`{"installation_id":"attacker","fcm_token":"token","platform":"android","environment":"qa"}`))
	w := httptest.NewRecorder()
	var service *Service
	service.HandlePreLoginRegister(w, req)
	if w.Code != http.StatusForbidden {
		t.Fatalf("unauthorized pre-login registration returned %d", w.Code)
	}
}
