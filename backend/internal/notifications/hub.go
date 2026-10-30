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
)

// Event represents a real-time event sent via SSE
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
}

// Client represents an active SSE subscriber
type Client struct {
	id         string
	events     chan Event
	businessID string
	requestID  string
	userID     string
}

// Matches checks if the client is interested in this event
func (c *Client) Matches(e Event) bool {
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
	db         *sqlx.DB
	clients    map[*Client]bool
	broadcast  chan Event
	register   chan *Client
	unregister chan *Client
	mu         sync.RWMutex
}

// NewHub creates and starts a new Event Hub
func NewHub(db *sqlx.DB) *Hub {
	h := &Hub{
		db:         db,
		clients:    make(map[*Client]bool),
		broadcast:  make(chan Event, 256),
		register:   make(chan *Client),
		unregister: make(chan *Client),
	}
	go h.run()
	return h
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
func (h *Hub) ServeSSE(w http.ResponseWriter, r *http.Request) {
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
	w.Header().Set("Access-Control-Allow-Origin", "*")

	bizID := r.URL.Query().Get("business_id")
	reqID := r.URL.Query().Get("request_id")
	userID := r.URL.Query().Get("user_id")

	client := &Client{
		id:         uuid.NewString(),
		events:     make(chan Event, 32),
		businessID: bizID,
		requestID:  reqID,
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
		"user_id":     userID,
		"server_time": time.Now().UTC().Format(time.RFC3339),
	})
	fmt.Fprintf(w, "event: connected\ndata: %s\n\n", initData)
	flusher.Flush()

	// Heartbeat ticker to keep connection alive through Nginx
	ticker := time.NewTicker(15 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-r.Context().Done():
			return

		case <-ticker.C:
			fmt.Fprintf(w, ": ping %d\n\n", time.Now().Unix())
			flusher.Flush()

		case event, ok := <-client.events:
			if !ok {
				return
			}
			eventData, err := json.Marshal(event)
			if err != nil {
				continue
			}
			fmt.Fprintf(w, "event: %s\ndata: %s\n\n", event.Type, eventData)
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
