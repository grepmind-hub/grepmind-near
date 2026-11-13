package payments

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
	"grepmind-near/backend/pkg/database"
)

var (
	ErrProviderUnavailable    = errors.New("payment provider is not configured")
	ErrInvalidProviderRequest = errors.New("invalid provider request")
)

// PaymentProvider is the provider-neutral boundary. Phase 4B-A deliberately
// ships no active provider implementation; session creation and callbacks are
// implemented only in the separately approved sandbox gate.
type PaymentProvider interface {
	Name() string
	CreateSession(context.Context, CreateSessionRequest) (ProviderSession, error)
	VerifyWebhook(context.Context, http.Header, []byte) (VerifiedProviderEvent, error)
	FetchPayment(context.Context, string) (ProviderPayment, error)
	CreateRefund(context.Context, CreateRefundRequest) (ProviderRefund, error)
	FetchRefund(context.Context, string) (ProviderRefund, error)
}

type CreateSessionRequest struct {
	OrderID, IntentID, IdempotencyKey, Currency string
	AmountMinor                                 int64
	ExpiresAt                                   time.Time
}

type ProviderSession struct {
	Reference string
	LaunchURL string
	ExpiresAt time.Time
}

type VerifiedProviderEvent struct {
	ObjectType        string    `json:"object_type,omitempty"`
	Provider          string    `json:"provider"`
	EventID           string    `json:"event_id"`
	ProviderReference string    `json:"provider_reference"`
	Status            string    `json:"status"`
	Currency          string    `json:"currency"`
	AmountMinor       int64     `json:"amount_minor"`
	EventAt           time.Time `json:"event_at"`
}

type CreateRefundRequest struct {
	RefundID, PaymentReference, IdempotencyKey, Currency string
	AmountMinor                                          int64
}

type ProviderRefund struct {
	Reference, PaymentReference, Status, Currency string
	AmountMinor                                   int64
}

type ProviderPayment struct {
	Reference, Status, Currency string
	AmountMinor                 int64
}

// UnconfiguredProvider fails closed. It is not a fake gateway and never
// creates network traffic or a customer payment session.
type UnconfiguredProvider struct{}

func (UnconfiguredProvider) Name() string { return "unconfigured" }
func (UnconfiguredProvider) CreateSession(context.Context, CreateSessionRequest) (ProviderSession, error) {
	return ProviderSession{}, ErrProviderUnavailable
}
func (UnconfiguredProvider) VerifyWebhook(context.Context, http.Header, []byte) (VerifiedProviderEvent, error) {
	return VerifiedProviderEvent{}, ErrProviderUnavailable
}
func (UnconfiguredProvider) FetchPayment(context.Context, string) (ProviderPayment, error) {
	return ProviderPayment{}, ErrProviderUnavailable
}
func (UnconfiguredProvider) CreateRefund(context.Context, CreateRefundRequest) (ProviderRefund, error) {
	return ProviderRefund{}, ErrProviderUnavailable
}
func (UnconfiguredProvider) FetchRefund(context.Context, string) (ProviderRefund, error) {
	return ProviderRefund{}, ErrProviderUnavailable
}

type Service struct {
	db       *database.DB
	provider PaymentProvider
}

func NewService(db *database.DB) *Service { return &Service{db: db, provider: UnconfiguredProvider{}} }

func NewServiceWithProvider(db *database.DB, provider PaymentProvider) *Service {
	if provider == nil {
		provider = UnconfiguredProvider{}
	}
	return &Service{db: db, provider: provider}
}

type intent struct {
	ID          string    `db:"id" json:"id"`
	OrderID     string    `db:"order_id" json:"order_id"`
	AmountMinor int64     `db:"amount_minor" json:"amount_minor"`
	Currency    string    `db:"currency" json:"currency"`
	Status      string    `db:"status" json:"status"`
	CreatedAt   time.Time `db:"created_at" json:"created_at"`
}

type apiFailure struct {
	status        int
	code, message string
}

func (e *apiFailure) Error() string { return e.message }

func writeFailure(w http.ResponseWriter, status int, code, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{"error": map[string]string{"code": code, "message": message}})
}

func (s *Service) CreateIntent(w http.ResponseWriter, r *http.Request, userID string) {
	allowed, err := s.customerAllowed(r.Context(), userID)
	if err != nil {
		writeFailure(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Customer access could not be verified.")
		return
	}
	if !allowed {
		writeFailure(w, http.StatusForbidden, "FORBIDDEN", "Customer access is required.")
		return
	}
	if r.ContentLength > 0 {
		writeFailure(w, http.StatusBadRequest, "VALIDATION_ERROR", "Payment intent creation does not accept a request body.")
		return
	}
	if r.Body != nil {
		body, bodyErr := io.ReadAll(http.MaxBytesReader(w, r.Body, 0))
		if len(body) != 0 || bodyErr != nil {
			writeFailure(w, http.StatusBadRequest, "VALIDATION_ERROR", "Payment intent creation does not accept a request body.")
			return
		}
	}
	orderID, err := uuid.Parse(r.PathValue("id"))
	if err != nil {
		writeFailure(w, 400, "VALIDATION_ERROR", "A valid order ID is required.")
		return
	}
	key, err := uuid.Parse(r.Header.Get("Idempotency-Key"))
	if err != nil {
		writeFailure(w, 400, "IDEMPOTENCY_KEY_REQUIRED", "A valid Idempotency-Key is required.")
		return
	}
	result, replay, err := s.createIntent(r.Context(), userID, orderID.String(), key.String())
	if err != nil {
		var failure *apiFailure
		if errors.As(err, &failure) {
			writeFailure(w, failure.status, failure.code, failure.message)
			return
		}
		writeFailure(w, 500, "INTERNAL_ERROR", "Payment intent could not be created.")
		return
	}
	status := http.StatusCreated
	if replay {
		status = http.StatusOK
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{"data": map[string]any{
		"id": result.ID, "order_id": result.OrderID, "amount_minor": result.AmountMinor, "currency": result.Currency,
		"status": result.Status, "payment_status": "not_collected", "provider_session_available": false,
		"created_at": result.CreatedAt.UTC(),
	}, "meta": map[string]bool{"idempotent_replay": replay}})
}

func (s *Service) createIntent(ctx context.Context, userID, orderID, key string) (intent, bool, error) {
	fingerprint := sha256.Sum256([]byte(userID + ":" + orderID))
	var result intent
	replay := false
	err := s.db.Transaction(ctx, func(tx *sqlx.Tx) error {
		var enabled bool
		if err := tx.GetContext(ctx, &enabled, `SELECT payment_intent_creation_enabled FROM financial_feature_config WHERE singleton=true`); err != nil {
			return err
		}
		if !enabled {
			return &apiFailure{http.StatusServiceUnavailable, "PAYMENT_UNAVAILABLE", "Payment initiation is not enabled."}
		}
		// Lock the account before checking an idempotency key so simultaneous
		// requests for this customer cannot create competing intents.
		var locked string
		if err := tx.QueryRowxContext(ctx, `SELECT id::text FROM users WHERE id=$1 AND status='active' FOR UPDATE`, userID).Scan(&locked); err != nil {
			return err
		}
		var prior intent
		var priorFingerprint []byte
		err := tx.QueryRowxContext(ctx, `SELECT id::text,order_id::text,amount_minor,currency,status,created_at,request_fingerprint FROM payment_intents WHERE customer_user_id=$1 AND idempotency_key=$2 FOR UPDATE`, userID, key).Scan(&prior.ID, &prior.OrderID, &prior.AmountMinor, &prior.Currency, &prior.Status, &prior.CreatedAt, &priorFingerprint)
		if err == nil {
			if prior.OrderID != orderID || len(priorFingerprint) != len(fingerprint) || string(priorFingerprint) != string(fingerprint[:]) {
				return &apiFailure{http.StatusConflict, "IDEMPOTENCY_CONFLICT", "This idempotency key was already used for another payment intent."}
			}
			result, replay = prior, true
			return nil
		}
		if !errors.Is(err, sql.ErrNoRows) {
			return err
		}
		var amount int64
		var currency string
		if err := tx.QueryRowxContext(ctx, `SELECT round(grand_total*100)::bigint,currency FROM customer_orders WHERE id=$1 AND customer_user_id=$2 AND order_source='platform_catalog' AND COALESCE(payment_method,'')<>'cash_on_delivery' AND payment_status='not_collected' AND status NOT IN ('cancelled','returned','delivered','completed') FOR UPDATE`, orderID, userID).Scan(&amount, &currency); err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return &apiFailure{404, "ORDER_NOT_PAYABLE", "An eligible unpaid platform order was not found."}
			}
			return err
		}
		if amount <= 0 || currency != "INR" {
			return &apiFailure{409, "PAYMENT_AMOUNT_INVALID", "This order does not have a supported payment amount."}
		}
		var existingOrder string
		err = tx.QueryRowxContext(ctx, `SELECT id::text FROM payment_intents WHERE order_id=$1 FOR UPDATE`, orderID).Scan(&existingOrder)
		if err == nil {
			return &apiFailure{http.StatusConflict, "PAYMENT_INTENT_EXISTS", "A payment intent already exists for this order. Read its current state."}
		}
		if !errors.Is(err, sql.ErrNoRows) {
			return err
		}
		err = tx.QueryRowxContext(ctx, `INSERT INTO payment_intents(order_id,customer_user_id,amount_minor,currency,idempotency_key,request_fingerprint) VALUES($1,$2,$3,$4,$5,$6) RETURNING id::text,order_id::text,amount_minor,currency,status,created_at`, orderID, userID, amount, currency, key, fingerprint[:]).Scan(&result.ID, &result.OrderID, &result.AmountMinor, &result.Currency, &result.Status, &result.CreatedAt)
		return err
	})
	return result, replay, err
}

func (s *Service) GetIntent(w http.ResponseWriter, r *http.Request, userID string) {
	allowed, err := s.customerAllowed(r.Context(), userID)
	if err != nil {
		writeFailure(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Customer access could not be verified.")
		return
	}
	if !allowed {
		writeFailure(w, 403, "FORBIDDEN", "Customer access is required.")
		return
	}
	orderID, err := uuid.Parse(r.PathValue("id"))
	if err != nil {
		writeFailure(w, 400, "VALIDATION_ERROR", "A valid order ID is required.")
		return
	}
	var result intent
	var paymentStatus string
	err = s.db.QueryRowxContext(r.Context(), `SELECT i.id::text,i.order_id::text,i.amount_minor,i.currency,i.status,i.created_at,o.payment_status FROM payment_intents i JOIN customer_orders o ON o.id=i.order_id WHERE i.order_id=$1 AND i.customer_user_id=$2 AND o.customer_user_id=$2`, orderID.String(), userID).Scan(&result.ID, &result.OrderID, &result.AmountMinor, &result.Currency, &result.Status, &result.CreatedAt, &paymentStatus)
	if errors.Is(err, sql.ErrNoRows) {
		writeFailure(w, 404, "PAYMENT_INTENT_NOT_FOUND", "No payment intent was found for this order.")
		return
	}
	if err != nil {
		writeFailure(w, 500, "INTERNAL_ERROR", "Payment intent could not be loaded.")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{"data": map[string]any{"id": result.ID, "order_id": result.OrderID, "amount_minor": result.AmountMinor, "currency": result.Currency, "status": result.Status, "payment_status": paymentStatus, "provider_session_available": result.Status == "pending" || result.Status == "paid", "created_at": result.CreatedAt.UTC()}})
}

func (s *Service) customerAllowed(ctx context.Context, userID string) (bool, error) {
	var allowed bool
	err := s.db.GetContext(ctx, &allowed, `SELECT EXISTS(SELECT 1 FROM users u JOIN user_roles r ON r.user_id=u.id WHERE u.id=$1 AND u.status='active' AND r.role='customer')`, userID)
	return allowed, err
}
