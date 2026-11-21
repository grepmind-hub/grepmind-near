package fcm

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"golang.org/x/oauth2"
)

func TestIsInvalidToken(t *testing.T) {
	if !IsInvalidToken(errInvalidToken) {
		t.Fatal("expected errInvalidToken to be recognized")
	}
	if IsInvalidToken(errors.New("some other error")) {
		t.Fatal("expected unrelated error to not be recognized")
	}
	if IsInvalidToken(nil) {
		t.Fatal("expected nil error to not be recognized")
	}
}

func TestInvalidTokenMarkers(t *testing.T) {
	cases := []struct {
		errMsg string
		want   bool
	}{
		{`{"error":{"details":[{"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError","errorCode":"UNREGISTERED"}]}}`, true},
		{`{"error":{"status":"INVALID_ARGUMENT"}}`, false},
		{"some other error", false},
		{"", false},
	}
	for _, c := range cases {
		if got := isInvalidTokenError(c.errMsg); got != c.want {
			t.Errorf("isInvalidTokenError(%q) = %v, want %v", c.errMsg, got, c.want)
		}
	}
}

func TestSendUsesOAuthAndPreservesDataOnlyMessage(t *testing.T) {
	var message map[string]interface{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer test-access-token" {
			t.Error("expected OAuth bearer token")
		}
		if err := json.NewDecoder(r.Body).Decode(&message); err != nil {
			t.Error(err)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"name":"projects/test/messages/1"}`))
	}))
	defer server.Close()
	svc := &Service{httpClient: server.Client(), tokenSource: oauth2.StaticTokenSource(&oauth2.Token{AccessToken: "test-access-token"}), sendURL: server.URL}
	result, err := svc.Send(context.Background(), Message{Token: "device", Data: map[string]string{"type": "otp", "otp_code": "123456"}})
	if err != nil || !result.Success {
		t.Fatalf("send failed: %v", err)
	}
	payload := message["message"].(map[string]interface{})
	if _, ok := payload["notification"]; ok {
		t.Fatal("OTP was sent as a notification")
	}
	if payload["data"].(map[string]interface{})["otp_code"] != "123456" {
		t.Fatal("OTP data missing")
	}
}

func TestSendDoesNotLeakFCMResponseOrRevokeOnGenericError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"error":{"status":"INVALID_ARGUMENT","message":"sensitive"}}`))
	}))
	defer server.Close()
	svc := &Service{httpClient: server.Client(), tokenSource: oauth2.StaticTokenSource(&oauth2.Token{AccessToken: "test"}), sendURL: server.URL}
	_, err := svc.Send(context.Background(), Message{Token: "device"})
	if err == nil || IsInvalidToken(err) || err.Error() != "FCM HTTP v1 error: status 400" {
		t.Fatalf("unexpected sanitized error: %v", err)
	}
}
