package deliverydispatch

import (
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"grepmind-near/backend/pkg/config"
)

func TestDispatchFeatureGateDefaultsClosed(t *testing.T) {
	service := NewService(nil, nil, &config.Config{})
	if service.Enabled() {
		t.Fatal("dispatch must remain disabled unless explicitly enabled")
	}
	recorder := httptest.NewRecorder()
	if service.requireEnabled(recorder) {
		t.Fatal("disabled dispatch passed its feature gate")
	}
	if recorder.Code != 503 || !strings.Contains(recorder.Body.String(), "DISPATCH_DISABLED") {
		t.Fatalf("unexpected disabled response: %d %s", recorder.Code, recorder.Body.String())
	}
}

func TestDispatchConfigBounds(t *testing.T) {
	cfg := &config.Config{RiderDispatchEnabled: true, RiderOfferTimeout: time.Hour, RiderAvailabilityLease: time.Second}
	service := NewService(nil, nil, cfg)
	if !service.Enabled() {
		t.Fatal("explicit dispatch feature gate was ignored")
	}
	if service.offerTimeout != defaultOfferTimeout {
		t.Fatalf("unbounded offer timeout accepted: %s", service.offerTimeout)
	}
	if service.availabilityLease != defaultAvailabilityLease {
		t.Fatalf("unbounded availability lease accepted: %s", service.availabilityLease)
	}
}

func TestDecodeBodyRejectsUnknownFieldsAndTrailingJSON(t *testing.T) {
	for _, body := range []string{`{"online":true,"role":"admin"}`, `{"online":true} {"online":false}`} {
		recorder := httptest.NewRecorder()
		request := httptest.NewRequest("POST", "/", strings.NewReader(body))
		var value struct {
			Online bool `json:"online"`
		}
		if err := decodeBody(recorder, request, &value, 2048); err == nil {
			t.Fatalf("accepted invalid request body %q", body)
		}
	}
}
