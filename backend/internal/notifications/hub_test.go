package notifications

import (
	"bufio"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestOrderClientMatchesOnlyItsOrder(t *testing.T) {
	client := &Client{orderID: "order-a", userID: "customer-a"}
	for _, tc := range []struct {
		name  string
		event Event
		want  bool
	}{
		{"matching order", Event{UserID: "customer-a", Payload: map[string]interface{}{"order_id": "order-a"}}, true},
		{"same customer different order", Event{UserID: "customer-a", Payload: map[string]interface{}{"order_id": "order-b"}}, false},
		{"missing order identity", Event{UserID: "customer-a", Payload: map[string]interface{}{"job_id": "job-a"}}, false},
		{"different user same order", Event{UserID: "customer-b", Payload: map[string]interface{}{"order_id": "order-a"}}, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := client.Matches(tc.event); got != tc.want {
				t.Fatalf("Matches()=%v want %v", got, tc.want)
			}
		})
	}
}

func TestServeSSEClosesWhenAuthorizationIsRevoked(t *testing.T) {
	hub := NewHub(nil)
	hub.heartbeatInterval = 5 * time.Millisecond
	var authorized atomic.Bool
	authorized.Store(true)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hub.ServeSSE(w, r, "customer-a", func(context.Context) bool { return authorized.Load() })
	}))
	defer server.Close()

	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, server.URL+"/events?order_id=order-a", nil)
	if err != nil {
		t.Fatal(err)
	}
	response, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	reader := bufio.NewReader(response.Body)
	connected := false
	for range 4 {
		line, readErr := reader.ReadString('\n')
		if readErr != nil {
			t.Fatalf("SSE connection ended before handshake: %v", readErr)
		}
		if strings.HasPrefix(line, "event: connected") {
			connected = true
		}
		if line == "\r\n" && connected {
			break
		}
	}
	if !connected {
		t.Fatal("SSE connection did not send its connected handshake")
	}
	authorized.Store(false)
	for {
		if _, err := reader.ReadString('\n'); err != nil {
			if err != io.EOF {
				t.Fatalf("reading revoked SSE stream: %v", err)
			}
			break
		}
	}
}
