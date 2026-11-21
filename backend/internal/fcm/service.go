package fcm

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/jwt"
)

var (
	errNotInitialized    = errors.New("FCM service is not initialized")
	errInvalidToken      = errors.New("invalid FCM registration token")
	errMissingCredential = errors.New("Firebase service account credential is required")
	errMissingProjectID  = errors.New("Firebase project ID is required")
)

// serviceAccount represents the relevant fields of a Firebase service account key.
type serviceAccount struct {
	ProjectID   string `json:"project_id"`
	ClientEmail string `json:"client_email"`
	PrivateKey  string `json:"private_key"`
}

// fcmSendURL is the FCM HTTP v1 send endpoint.
func fcmSendURL(projectID string) string {
	return "https://fcm.googleapis.com/v1/projects/" + projectID + "/messages:send"
}

// Message represents a downstream FCM message to a single device.
type Message struct {
	Token          string
	Title          string
	Body           string
	Data           map[string]string
	AndroidChannel string
}

// Result represents the outcome of a send attempt.
type Result struct {
	Success   bool
	MessageID string
	Error     error
}

// Config holds FCM service configuration.
type Config struct {
	ServiceAccountPath string
	ProjectID          string
	HTTPTimeout        time.Duration
	MaxRetries         int
}

// Service sends FCM messages via the HTTP v1 API using OAuth2 JWT tokens.
type Service struct {
	projectID   string
	httpClient  *http.Client
	maxRetries  int
	timeout     time.Duration
	tokenSource oauth2.TokenSource
}

// NewService creates an FCM service from a service account file.
func NewService(cfg Config) (*Service, error) {
	if cfg.ServiceAccountPath == "" {
		return nil, errMissingCredential
	}
	if cfg.ProjectID == "" {
		return nil, errMissingProjectID
	}
	if cfg.HTTPTimeout <= 0 {
		cfg.HTTPTimeout = 10 * time.Second
	}
	if cfg.MaxRetries <= 0 {
		cfg.MaxRetries = 3
	}

	credData, err := os.ReadFile(cfg.ServiceAccountPath)
	if err != nil {
		return nil, fmt.Errorf("read service account: %w", err)
	}

	var sa serviceAccount
	if err := json.Unmarshal(credData, &sa); err != nil {
		return nil, fmt.Errorf("parse service account: %w", err)
	}
	if sa.ClientEmail == "" || sa.PrivateKey == "" {
		return nil, errors.New("service account missing client_email or private_key")
	}

	projectID := cfg.ProjectID
	if projectID == "" {
		projectID = sa.ProjectID
	}
	if projectID == "" {
		return nil, errMissingProjectID
	}

	jwtConfig := &jwt.Config{
		Email:      sa.ClientEmail,
		PrivateKey: []byte(sa.PrivateKey),
		Scopes:     []string{"https://www.googleapis.com/auth/firebase.messaging"},
		TokenURL:   "https://oauth2.googleapis.com/token",
	}

	return &Service{
		projectID:   projectID,
		httpClient:  &http.Client{Timeout: cfg.HTTPTimeout},
		maxRetries:  cfg.MaxRetries,
		timeout:     cfg.HTTPTimeout,
		tokenSource: jwtConfig.TokenSource(context.Background()),
	}, nil
}

// Close is a no-op kept for API compatibility.
func (s *Service) Close() error { return nil }

// Send sends a data-only or notification FCM message to a single device token.
func (s *Service) Send(ctx context.Context, msg Message) (*Result, error) {
	if s.tokenSource == nil {
		return nil, errNotInitialized
	}
	if msg.Token == "" {
		return nil, errInvalidToken
	}

	body := map[string]interface{}{
		"message": map[string]interface{}{
			"token": msg.Token,
		},
	}
	if msg.Title != "" || msg.Body != "" {
		body["message"].(map[string]interface{})["notification"] = map[string]interface{}{
			"title": msg.Title,
			"body":  msg.Body,
		}
	}
	if len(msg.Data) > 0 {
		body["message"].(map[string]interface{})["data"] = msg.Data
	}
	android := map[string]interface{}{"priority": "high"}
	if msg.AndroidChannel != "" {
		android["notification"] = map[string]interface{}{
			"channel_id": msg.AndroidChannel,
		}
	}
	body["message"].(map[string]interface{})["android"] = android

	payload, err := json.Marshal(body)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	var lastErr error
	for attempt := 0; attempt <= s.maxRetries; attempt++ {
		if attempt > 0 {
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-time.After(time.Duration(attempt) * 500 * time.Millisecond):
			}
		}

		token, err := s.tokenSource.Token()
		if err != nil {
			lastErr = fmt.Errorf("oauth token: %w", err)
			continue
		}

		req, err := http.NewRequestWithContext(ctx, http.MethodPost, fcmSendURL(s.projectID), bytes.NewReader(payload))
		if err != nil {
			return nil, fmt.Errorf("create request: %w", err)
		}
		req.Header.Set("Content-Type", "application/json; charset=UTF-8")
		req.Header.Set("Authorization", "Bearer "+token.AccessToken)

		resp, err := s.httpClient.Do(req)
		if err != nil {
			lastErr = err
			continue
		}
		respBody, _ := io.ReadAll(resp.Body)
		resp.Body.Close()

		if resp.StatusCode >= 200 && resp.StatusCode < 300 {
			var parsed struct {
				Name string `json:"name"`
			}
			_ = json.Unmarshal(respBody, &parsed)
			return &Result{Success: true, MessageID: parsed.Name}, nil
		}

		lastErr = fmt.Errorf("FCM HTTP v1 error: %d %s", resp.StatusCode, string(respBody))
		if isInvalidTokenError(string(respBody)) {
			return &Result{Success: false, Error: errInvalidToken}, errInvalidToken
		}
	}

	return &Result{Success: false, Error: lastErr}, lastErr
}

// SendHTTPV1 sends a raw FCM HTTP v1 request directly with a fresh OAuth token.
func (s *Service) SendHTTPV1(ctx context.Context, path string, body interface{}) (*Result, error) {
	if s.tokenSource == nil {
		return nil, errNotInitialized
	}
	payload, err := json.Marshal(body)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	token, err := s.tokenSource.Token()
	if err != nil {
		return nil, fmt.Errorf("oauth token: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, path, bytes.NewReader(payload))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json; charset=UTF-8")
	req.Header.Set("Authorization", "Bearer "+token.AccessToken)

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("send request: %w", err)
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		var parsed struct {
			Name string `json:"name"`
		}
		_ = json.Unmarshal(respBody, &parsed)
		return &Result{Success: true, MessageID: parsed.Name}, nil
	}

	return nil, fmt.Errorf("FCM HTTP v1 error: %d %s", resp.StatusCode, string(respBody))
}

// IsInvalidToken reports whether an error indicates the device token is invalid.
func IsInvalidToken(err error) bool {
	return errors.Is(err, errInvalidToken)
}

// isInvalidTokenError checks whether an FCM error response indicates an invalid
// or unregistered registration token.
func isInvalidTokenError(msg string) bool {
	for _, marker := range []string{
		"registration token is not registered",
		"InvalidRegistration",
		"NotRegistered",
		"APNAuthKeyInvalid",
		"DeviceTokenNotForTopic",
	} {
		if contains(msg, marker) {
			return true
		}
	}
	return false
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && indexOf(s, substr) >= 0
}

func indexOf(s, substr string) int {
	for i := 0; i+len(substr) <= len(s); i++ {
		if s[i:i+len(substr)] == substr {
			return i
		}
	}
	return -1
}
