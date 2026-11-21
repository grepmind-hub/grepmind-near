package notifications

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"

	"grepmind-near/backend/internal/devices"
	"grepmind-near/backend/internal/fcm"
)

// Event represents a real-time event sent via SSE and/or FCM
type Event struct {
	ID         string                 `json:"id"`
	Type       string                 `json:"type"`
	BusinessID string                 `json:"business_id,omitempty"`
	RequestID  string                 `json:"request_id,omitempty"`
	UserID     string                 `json:"user_id,omitempty"`
	Title      string                 `json:"title"`
	Body       string                 `json:"body"`
	Payload    map[string]interface{} `json:"payload,omitempty"`
	CreatedAt  string                 `json:"created_at"`
	// FCMChannel is the Android notification channel for this event.
	FCMChannel string `json:"-"`
	// SendFCM controls whether this event is also delivered via FCM.
	SendFCM bool `json:"-"`
}

// Client represents an active SSE subscriber
type Client struct {
	id         string
	events     chan Event
	businessID string
	requestID  string
	orderID    string
	userID     string
}

// Matches checks if the client is interested in this event
func (c *Client) Matches(e Event) bool {
	// Order subscriptions are deliberately narrow: they do not also receive the
	// customer's other notifications, even when the event targets that user.
	if c.orderID != "" {
		if e.Payload == nil || (c.userID != "" && e.UserID != c.userID) {
			return false
		}
		orderID, ok := e.Payload["order_id"].(string)
		return ok && orderID == c.orderID
	}
	// If the client specified a business filter, check business match
	if c.businessID != "" && e.BusinessID != "" && c.businessID == e.BusinessID {
		return true
	}
	// If the client specified a request filter, check request match
	if c.requestID != "" && e.RequestID != "" && c.requestID == e.RequestID {
		return true
	}
	// If the client specified a user filter, check user match
	if c.userID != "" && e.UserID != "" && c.userID == e.UserID {
		return true
	}
	// If client didn't specify any specific filter, receive all public events
	if c.businessID == "" && c.requestID == "" && c.userID == "" {
		return true
	}
	return false
}

// Hub manages active SSE connections and broadcasts events
type Hub struct {
	db                *sqlx.DB
	clients           map[*Client]bool
	broadcast         chan Event
	register          chan *Client
	unregister        chan *Client
	mu                sync.RWMutex
	heartbeatInterval time.Duration
	fcmSvc            *fcm.Service
	deviceSvc         *devices.Service
	// publishedEventIDs tracks recently published event IDs to prevent
	// duplicate SSE+FCM delivery for the same logical event.
	publishedEventIDs map[string]time.Time
	eventIDMu         sync.RWMutex
}

// NewHub creates and starts a new Event Hub
func NewHub(db *sqlx.DB) *Hub {
	h := &Hub{
		db:                db,
		clients:           make(map[*Client]bool),
		broadcast:         make(chan Event, 256),
		register:          make(chan *Client),
		unregister:        make(chan *Client),
		heartbeatInterval: 15 * time.Second,
		publishedEventIDs: make(map[string]time.Time),
	}
	go h.run()
	// Cleanup old event IDs every minute.
	go h.cleanupEventIDs()
	return h
}

// SetPushServices configures FCM and device services for push delivery.
func (h *Hub) SetPushServices(fcmSvc *fcm.Service, deviceSvc *devices.Service) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.fcmSvc = fcmSvc
	h.deviceSvc = deviceSvc
}

func (h *Hub) cleanupEventIDs() {
	ticker := time.NewTicker(time.Minute)
	defer ticker.Stop()
	for range ticker.C {
		h.eventIDMu.Lock()
		now := time.Now()
		for id, ts := range h.publishedEventIDs {
			if now.Sub(ts) > 10*time.Minute {
				delete(h.publishedEventIDs, id)
			}
		}
		h.eventIDMu.Unlock()
	}
}

// isDuplicateEvent checks whether an event ID was recently published.
func (h *Hub) isDuplicateEvent(eventID string) bool {
	h.eventIDMu.RLock()
	defer h.eventIDMu.RUnlock()
	_, ok := h.publishedEventIDs[eventID]
	return ok
}

// recordEventID marks an event ID as recently published.
func (h *Hub) recordEventID(eventID string) {
	h.eventIDMu.Lock()
	defer h.eventIDMu.Unlock()
	h.publishedEventIDs[eventID] = time.Now()
}

func (h *Hub) run() {
	for {
		select {
		case client := <-h.register:
			h.mu.Lock()
			h.clients[client] = true
			h.mu.Unlock()
			log.Printf("[notifications/hub] Client connected: %s (biz: %s, req: %s, user: %s, total: %d)",
				client.id, client.businessID, client.requestID, client.userID, len(h.clients))

		case client := <-h.unregister:
			h.mu.Lock()
			if _, ok := h.clients[client]; ok {
				delete(h.clients, client)
				close(client.events)
				log.Printf("[notifications/hub] Client disconnected: %s (remaining: %d)", client.id, len(h.clients))
			}
			h.mu.Unlock()

		case event := <-h.broadcast:
			h.mu.RLock()
			for client := range h.clients {
				if client.Matches(event) {
					select {
					case client.events <- event:
					default:
						// Buffer full; skip or drop slow client
					}
				}
			}
			h.mu.RUnlock()

			// Deliver via FCM if enabled, non-blocking with bounded retries.
			if event.SendFCM && event.UserID != "" && h.fcmSvc != nil && h.deviceSvc != nil {
				go h.deliverFCM(event)
			}
		}
	}
}

// deliverFCM sends an event as an FCM data message to the user's active devices.
// Failures do not block the caller; errors are logged.
func (h *Hub) deliverFCM(event Event) {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	regs, err := h.deviceSvc.ListActive(ctx, event.UserID)
	if err != nil || len(regs) == 0 {
		log.Printf("[notifications/hub] FCM: no active devices for user %s: %v", event.UserID, err)
		return
	}

	data := map[string]string{
		"type":        event.Type,
		"title":       event.Title,
		"body":        event.Body,
		"event_id":    event.ID,
		"business_id": event.BusinessID,
		"request_id":  event.RequestID,
	}
	if event.Payload != nil {
		for k, v := range event.Payload {
			data[k] = fmt.Sprintf("%v", v)
		}
	}

	channel := event.FCMChannel
	if channel == "" {
		channel = "orders"
	}

	for _, reg := range regs {
		msg := fcm.Message{
			Token:           reg.FCMToken,
			Title:           event.Title,
			Body:            event.Body,
			Data:            data,
			AndroidChannel:  channel,
		}
		if _, err := h.fcmSvc.Send(ctx, msg); err != nil {
			if fcm.IsInvalidToken(err) {
				if revokeErr := h.deviceSvc.MarkTokenInvalid(ctx, reg.FCMToken); revokeErr != nil {
					log.Printf("[notifications/hub] FCM: failed to revoke invalid token: %v", revokeErr)
				}
			}
			log.Printf("[notifications/hub] FCM: send failed for device %s: %v", reg.InstallationID, err)
		}
	}
}

// Publish broadcasts an event to matching subscribers and persists to DB if needed
func (h *Hub) Publish(ctx context.Context, event Event) {
	if event.ID == "" {
		event.ID = uuid.NewString()
	}
	if event.CreatedAt == "" {
		event.CreatedAt = time.Now().UTC().Format(time.RFC3339)
	}

	// Prevent duplicate SSE+FCM delivery for the same logical event.
	if h.isDuplicateEvent(event.ID) {
		return
	}
	h.recordEventID(event.ID)

	// Persist to database if db is available
	if h.db != nil && (event.BusinessID != "" || event.UserID != "") {
		payloadJSON, _ := json.Marshal(event.Payload)
		var uid *uuid.UUID
		if parsed, err := uuid.Parse(event.UserID); err == nil {
			uid = &parsed
		}
		var bid *uuid.UUID
		if parsed, err := uuid.Parse(event.BusinessID); err == nil {
			bid = &parsed
		}
		var refID *string
		if event.RequestID != "" {
			refID = &event.RequestID
		}

		_, err := h.db.ExecContext(ctx, `
			INSERT INTO notifications (user_id, business_id, title, body, event_type, reference_id, payload, created_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7, now())
		`, uid, bid, event.Title, event.Body, event.Type, refID, payloadJSON)
		if err != nil {
			log.Printf("[notifications/hub] Failed to persist notification: %v", err)
		}
	}

	// Dispatch to in-memory channel
	select {
	case h.broadcast <- event:
	default:
		log.Printf("[notifications/hub] Broadcast channel saturated, event dropped")
	}
}

// ServeSSE handles the streaming HTTP request
func (h *Hub) ServeSSE(w http.ResponseWriter, r *http.Request, authenticatedUserID string, authorize func(context.Context) bool) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "Streaming unsupported", http.StatusInternalServerError)
		return
	}

	// Set headers for Server-Sent Events
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache, no-transform")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("X-Accel-Buffering", "no")

	bizID := r.URL.Query().Get("business_id")
	reqID := r.URL.Query().Get("request_id")
	orderID := r.URL.Query().Get("order_id")
	userID := r.URL.Query().Get("user_id")
	if orderID != "" {
		userID = authenticatedUserID
	}

	client := &Client{
		id:         uuid.NewString(),
		events:     make(chan Event, 32),
		businessID: bizID,
		requestID:  reqID,
		orderID:    orderID,
		userID:     userID,
	}

	h.register <- client
	defer func() {
		h.unregister <- client
	}()

	// Send initial connection handshake
	initData, _ := json.Marshal(map[string]interface{}{
		"status":      "connected",
		"client_id":   client.id,
		"business_id": bizID,
		"request_id":  reqID,
		"order_id":    orderID,
		"user_id":     userID,
		"server_time": time.Now().UTC().Format(time.RFC3339),
	})
	fmt.Fprintf(w, "event: connected\ndata: %s\n\n", initData)
	flusher.Flush()

	// Heartbeat ticker to keep connection alive through Nginx
	ticker := time.NewTicker(h.heartbeatInterval)
	defer ticker.Stop()

	for {
		select {
		case <-r.Context().Done():
			return

		case <-ticker.C:
			if authorize != nil && !authorize(r.Context()) {
				return
			}
			fmt.Fprintf(w, ": ping %d\n\n", time.Now().Unix())
			flusher.Flush()

		case event, ok := <-client.events:
			if !ok {
				return
			}
			if authorize != nil && !authorize(r.Context()) {
				return
			}
			eventData, err := json.Marshal(event)
			if err != nil {
				continue
			}
			fmt.Fprintf(w, "id: %s\nevent: %s\ndata: %s\n\n", event.ID, event.Type, eventData)
			flusher.Flush()
		}
	}
}

// NotificationItem represents a notification record from DB
type NotificationItem struct {
	ID          string          `json:"id" db:"id"`
	UserID      *string         `json:"user_id" db:"user_id"`
	BusinessID  *string         `json:"business_id" db:"business_id"`
	Title       string          `json:"title" db:"title"`
	Body        string          `json:"body" db:"body"`
	EventType   string          `json:"event_type" db:"event_type"`
	ReferenceID *string         `json:"reference_id" db:"reference_id"`
	Payload     json.RawMessage `json:"payload" db:"payload"`
	IsRead      bool            `json:"is_read" db:"is_read"`
	CreatedAt   time.Time       `json:"created_at" db:"created_at"`
}

// ListNotifications retrieves persistent notifications
func (h *Hub) ListNotifications(ctx context.Context, bizID, userID string, limit int) ([]NotificationItem, error) {
	if limit <= 0 || limit > 50 {
		limit = 20
	}

	var bUUID, uUUID *uuid.UUID
	if parsed, err := uuid.Parse(bizID); err == nil {
		bUUID = &parsed
	}
	if parsed, err := uuid.Parse(userID); err == nil {
		uUUID = &parsed
	}

	query := `
		SELECT id, user_id, business_id, title, body, event_type, reference_id, payload, is_read, created_at
		FROM notifications
		WHERE ($1::uuid IS NULL OR business_id = $1)
		  AND ($2::uuid IS NULL OR user_id = $2)
		ORDER BY created_at DESC
		LIMIT $3
	`
	var items []NotificationItem
	err := h.db.SelectContext(ctx, &items, query, bUUID, uUUID, limit)
	if err != nil {
		return nil, err
	}
	if items == nil {
		items = []NotificationItem{}
	}
	return items, nil
}

// MarkAsRead marks a notification as read
func (h *Hub) MarkAsRead(ctx context.Context, notificationID string) error {
	_, err := h.db.ExecContext(ctx, `UPDATE notifications SET is_read = true WHERE id = $1`, notificationID)
	return err
}
