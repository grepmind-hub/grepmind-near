package qafixtures

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// MerchantSettlementView represents read-only settlement status.
type MerchantSettlementView struct {
	ID             string `json:"id"`
	Status         string `json:"status"`
	TotalGross     int64  `json:"total_gross_minor"`
	TotalNet       int64  `json:"total_net_minor"`
	PayoutTransfer string `json:"payout_transfer_id,omitempty"`
}

// RiderSettlementView represents read-only rider settlement status.
type RiderSettlementView struct {
	ID         string `json:"id"`
	Status     string `json:"status"`
	TotalMinor int64  `json:"total_minor"`
}

// AuthWorkflowAdapter abstracts phone OTP authentication in isolated QA.
type AuthWorkflowAdapter interface {
	Login(ctx context.Context, phone string) (token string, err error)
}

// MerchantWorkflowAdapter abstracts merchant store and catalog actions.
type MerchantWorkflowAdapter interface {
	EnsureBusiness(ctx context.Context, token, name, category, localityID string) (businessID string, err error)
	AddProduct(ctx context.Context, token, businessID, name string, price float64) (productID string, err error)
	AcceptOrder(ctx context.Context, token, businessID, orderID, idempotency string) error
	PrepareOrder(ctx context.Context, token, businessID, orderID, idempotency string) error
	ReadyOrder(ctx context.Context, token, businessID, orderID, idempotency string) error
	IssuePickupCode(ctx context.Context, token, businessID, jobID string) (code string, err error)
	RegisterMerchantBeneficiary(ctx context.Context, token, businessID, accountNum, ifsc, holder string) (beneficiaryID string, err error)
	GetMerchantSettlements(ctx context.Context, token, businessID string) ([]MerchantSettlementView, error)
}

// CustomerWorkflowAdapter abstracts ordering and delivery code generation.
type CustomerWorkflowAdapter interface {
	EnsureDeliveryAddress(ctx context.Context, token, localityID, line1 string) (addressID string, err error)
	RequestQuote(ctx context.Context, token, vertical, addressID, variantID string) (quoteID string, grandTotalMinor int64, err error)
	PlaceOrder(ctx context.Context, token, quoteID, paymentMethod, idempotency string) (orderID, refCode string, err error)
	SimulatePaymentSuccess(ctx context.Context, token, orderID, idempotency string) error
	IssueDeliveryCode(ctx context.Context, token, orderID string) (code string, err error)
}

// RiderWorkflowAdapter abstracts rider dispatch, verification, and remittance.
type RiderWorkflowAdapter interface {
	EnsureApprovedRider(ctx context.Context, token, vehicleType string) (riderID string, err error)
	SetAvailability(ctx context.Context, token string, isOnline bool) error
	AcceptOffer(ctx context.Context, token, offerID, idempotency string) error
	TransitionJobState(ctx context.Context, token, jobID, state, idempotency string) error
	VerifyPickup(ctx context.Context, token, jobID, code string) error
	ConfirmDelivery(ctx context.Context, token, jobID, code string, confirmCOD bool) error
	SubmitRemittance(ctx context.Context, token string, amountMinor int64, notes, idempotency string) (remittanceID string, err error)
	RegisterRiderBeneficiary(ctx context.Context, token, accountNum, ifsc, holder string) (beneficiaryID string, err error)
	GetRiderSettlements(ctx context.Context, token string) ([]RiderSettlementView, error)
	GetEarnings(ctx context.Context, token string) (totalRecordedMinor int64, err error)
	GetCashAccountability(ctx context.Context, token string) (liabilityMinor int64, err error)
}

// AdminWorkflowAdapter abstracts finance governance and multi-person controls.
type AdminWorkflowAdapter interface {
	ReviewRiderApplication(ctx context.Context, token, applicationID, action string) error
	TriggerDispatchRun(ctx context.Context, token, localityID, idempotency string) error
	ReviewCashRemittance(ctx context.Context, token, remittanceID, action, notes string) error
	RequestFinancePostAccess(ctx context.Context, token, targetUserID, reason string) (requestID string, err error)
	DecideFinancePostAccess(ctx context.Context, token, requestID, decision, reason string) error
	AccrueMerchantPayable(ctx context.Context, token, orderID string) error
	CreateCommissionPolicy(ctx context.Context, token, category string, rateBps int) (policyID string, err error)
	DecideCommissionPolicy(ctx context.Context, token, policyID, decision string) error
	CreateMerchantSettlement(ctx context.Context, token, businessID, periodStart, periodEnd, idempotency string) (batchID string, err error)
	ReviewMerchantSettlement(ctx context.Context, token, batchID string) error
	ApproveMerchantSettlement(ctx context.Context, token, batchID string) error
	CreateRiderSettlement(ctx context.Context, token, riderID, periodStart, periodEnd string) (batchID string, err error)
	ApproveRiderSettlement(ctx context.Context, token, batchID, reason string) error
	VerifyBeneficiary(ctx context.Context, token, beneficiaryID string) error
	CreatePayoutTransfer(ctx context.Context, token, kind, batchID, idempotency string) (transferID string, err error)
	ApprovePayoutTransfer(ctx context.Context, token, transferID, reason, idempotency string) error
	ExecutePayoutTransfer(ctx context.Context, token, transferID, idempotency string) (bankUTR string, err error)
}

// DomainWorkflowAdapters aggregates all authenticated workflow adapters.
type DomainWorkflowAdapters struct {
	Auth     AuthWorkflowAdapter
	Merchant MerchantWorkflowAdapter
	Customer CustomerWorkflowAdapter
	Rider    RiderWorkflowAdapter
	Admin    AdminWorkflowAdapter
}

// HTTPClientWrapper provides authenticated JSON RPC over HTTP.
type HTTPClientWrapper struct {
	BaseURL    string
	HTTPClient *http.Client
}

func (h *HTTPClientWrapper) DoJSON(ctx context.Context, method, path, token, idempotency string, reqBody, respData any) (int, error) {
	var bodyReader io.Reader
	if reqBody != nil {
		buf, err := json.Marshal(reqBody)
		if err != nil {
			return 0, fmt.Errorf("marshal request: %w", err)
		}
		bodyReader = bytes.NewReader(buf)
	}

	url := strings.TrimRight(h.BaseURL, "/") + path
	req, err := http.NewRequestWithContext(ctx, method, url, bodyReader)
	if err != nil {
		return 0, fmt.Errorf("create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	if idempotency != "" {
		req.Header.Set("Idempotency-Key", idempotency)
	}

	client := h.HTTPClient
	if client == nil {
		client = &http.Client{Timeout: 10 * time.Second}
	}

	resp, err := client.Do(req)
	if err != nil {
		return 0, fmt.Errorf("execute request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		var errPayload struct {
			Error struct {
				Code    string `json:"code"`
				Message string `json:"message"`
			} `json:"error"`
		}
		_ = json.NewDecoder(resp.Body).Decode(&errPayload)
		msg := errPayload.Error.Message
		if msg == "" {
			msg = fmt.Sprintf("HTTP %d", resp.StatusCode)
		}
		return resp.StatusCode, fmt.Errorf("API error %s: %s", errPayload.Error.Code, msg)
	}

	if respData != nil && resp.StatusCode != http.StatusNoContent {
		if err := json.NewDecoder(resp.Body).Decode(respData); err != nil {
			return resp.StatusCode, fmt.Errorf("decode response: %w", err)
		}
	}
	return resp.StatusCode, nil
}

// HTTPDomainWorkflowAdapters implements domain adapters backed by the live QA API.
type HTTPDomainWorkflowAdapters struct {
	Client *HTTPClientWrapper
	otp    *ScopeOTPReader
}

func NewHTTPDomainWorkflowAdapters(apiBaseURL string, otp *ScopeOTPReader) *HTTPDomainWorkflowAdapters {
	return &HTTPDomainWorkflowAdapters{
		Client: &HTTPClientWrapper{BaseURL: apiBaseURL, HTTPClient: scopedHTTPClient()},
		otp:    otp,
	}
}

func (a *HTTPDomainWorkflowAdapters) Login(ctx context.Context, phone string) (string, error) {
	if a.otp == nil || !syntheticPhone.MatchString(phone) {
		return "", errors.New("scoped OTP reader and synthetic phone are required")
	}
	var response struct {
		Data otpChallenge `json:"data"`
	}
	_, err := a.Client.DoJSON(ctx, http.MethodPost, "/api/v1/auth/otp/request", "", "", map[string]string{"phone_e164": phone}, &response)
	if err != nil {
		return "", errors.New("QA OTP challenge request failed")
	}
	code, err := a.otp.read(ctx, phone, response.Data)
	if err != nil {
		return "", err
	}
	return a.verifyOTP(ctx, phone, code, response.Data.ID)
}

func (a *HTTPDomainWorkflowAdapters) verifyOTP(ctx context.Context, phone, otp, challengeID string) (string, error) {
	var resp struct {
		Data struct {
			AccessToken string `json:"access_token"`
		} `json:"data"`
	}
	_, err := a.Client.DoJSON(ctx, "POST", "/api/v1/auth/otp/verify", "", "", map[string]string{
		"phone_e164":   phone,
		"otp_code":     otp,
		"challenge_id": challengeID,
	}, &resp)
	if err != nil {
		return "", errors.New("QA OTP verification failed")
	}
	if resp.Data.AccessToken == "" {
		return "", errors.New("missing access_token in verify response")
	}
	return resp.Data.AccessToken, nil
}

// 2. Merchant Implementation
func (a *HTTPDomainWorkflowAdapters) EnsureBusiness(ctx context.Context, token, name, category, localityID string) (string, error) {
	var listResp struct {
		Data []struct {
			ID   string `json:"id"`
			Name string `json:"name"`
		} `json:"data"`
	}
	_, _ = a.Client.DoJSON(ctx, "GET", "/api/v1/merchant/businesses", token, "", nil, &listResp)
	for _, b := range listResp.Data {
		if b.Name == name {
			return b.ID, nil
		}
	}

	var createResp struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	_, err := a.Client.DoJSON(ctx, "POST", "/api/v1/merchant/businesses", token, "", map[string]any{
		"name": name, "category": category, "locality_id": localityID,
	}, &createResp)
	if err != nil {
		return "", err
	}
	return createResp.Data.ID, nil
}

func (a *HTTPDomainWorkflowAdapters) AddProduct(ctx context.Context, token, businessID, name string, price float64) (string, error) {
	var resp struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	_, err := a.Client.DoJSON(ctx, "POST", fmt.Sprintf("/api/v1/merchant/products?business_id=%s", businessID), token, "", map[string]any{
		"name": name, "price": price, "stock_status": "in_stock", "is_published": true,
	}, &resp)
	if err != nil {
		return "", err
	}
	return resp.Data.ID, nil
}

func (a *HTTPDomainWorkflowAdapters) AcceptOrder(ctx context.Context, token, businessID, orderID, idempotency string) error {
	_, err := a.Client.DoJSON(ctx, "POST", fmt.Sprintf("/api/v1/merchant/businesses/%s/platform-orders/%s/accept", businessID, orderID), token, idempotency, nil, nil)
	return err
}

func (a *HTTPDomainWorkflowAdapters) PrepareOrder(ctx context.Context, token, businessID, orderID, idempotency string) error {
	_, err := a.Client.DoJSON(ctx, "POST", fmt.Sprintf("/api/v1/merchant/businesses/%s/platform-orders/%s/prepare", businessID, orderID), token, idempotency, nil, nil)
	return err
}

func (a *HTTPDomainWorkflowAdapters) ReadyOrder(ctx context.Context, token, businessID, orderID, idempotency string) error {
	_, err := a.Client.DoJSON(ctx, "POST", fmt.Sprintf("/api/v1/merchant/businesses/%s/platform-orders/%s/ready", businessID, orderID), token, idempotency, nil, nil)
	return err
}

func (a *HTTPDomainWorkflowAdapters) IssuePickupCode(ctx context.Context, token, businessID, jobID string) (string, error) {
	var resp struct {
		Data struct {
			PickupCode string `json:"pickup_code"`
		} `json:"data"`
	}
	_, err := a.Client.DoJSON(ctx, "POST", fmt.Sprintf("/api/v1/merchant/businesses/%s/delivery-jobs/%s/pickup-code", businessID, jobID), token, "", nil, &resp)
	if err != nil {
		return "", err
	}
	return resp.Data.PickupCode, nil
}

func (a *HTTPDomainWorkflowAdapters) RegisterMerchantBeneficiary(ctx context.Context, token, businessID, accountNum, ifsc, holder string) (string, error) {
	var resp struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	_, err := a.Client.DoJSON(ctx, "POST", fmt.Sprintf("/api/v1/merchant/businesses/%s/bank-beneficiary", businessID), token, "", map[string]string{
		"account_number": accountNum, "ifsc_code": ifsc, "account_holder_name": holder,
	}, &resp)
	if err != nil {
		return "", err
	}
	return resp.Data.ID, nil
}

func (a *HTTPDomainWorkflowAdapters) GetMerchantSettlements(ctx context.Context, token, businessID string) ([]MerchantSettlementView, error) {
	var resp struct {
		Data []MerchantSettlementView `json:"data"`
	}
	_, err := a.Client.DoJSON(ctx, "GET", fmt.Sprintf("/api/v1/merchant/businesses/%s/finance/settlements", businessID), token, "", nil, &resp)
	if err != nil {
		return nil, err
	}
	return resp.Data, nil
}

// 3. Customer Implementation
func (a *HTTPDomainWorkflowAdapters) EnsureDeliveryAddress(ctx context.Context, token, localityID, line1 string) (string, error) {
	var listResp struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	_, _ = a.Client.DoJSON(ctx, "GET", "/api/v1/customer/addresses", token, "", nil, &listResp)
	if len(listResp.Data) > 0 {
		return listResp.Data[0].ID, nil
	}

	var createResp struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	_, err := a.Client.DoJSON(ctx, "POST", "/api/v1/customer/addresses", token, "", map[string]any{
		"locality_id": localityID, "address_line1": line1, "recipient_name": "QA Customer", "contact_phone": "+919990000185",
	}, &createResp)
	if err != nil {
		return "", err
	}
	return createResp.Data.ID, nil
}

func (a *HTTPDomainWorkflowAdapters) RequestQuote(ctx context.Context, token, vertical, addressID, variantID string) (string, int64, error) {
	var resp struct {
		Data struct {
			QuoteID         string `json:"quote_id"`
			GrandTotalMinor int64  `json:"grand_total_minor"`
		} `json:"data"`
	}
	_, err := a.Client.DoJSON(ctx, "POST", "/api/v1/platform/orders/quote", token, "", map[string]any{
		"vertical": vertical, "address_id": addressID, "items": []map[string]any{{"variant_id": variantID, "quantity": 1}},
	}, &resp)
	if err != nil {
		return "", 0, err
	}
	return resp.Data.QuoteID, resp.Data.GrandTotalMinor, nil
}

func (a *HTTPDomainWorkflowAdapters) PlaceOrder(ctx context.Context, token, quoteID, paymentMethod, idempotency string) (string, string, error) {
	var resp struct {
		Data struct {
			ID            string `json:"id"`
			ReferenceCode string `json:"reference_code"`
		} `json:"data"`
	}
	_, err := a.Client.DoJSON(ctx, "POST", "/api/v1/platform/orders", token, idempotency, map[string]string{
		"quote_id": quoteID, "payment_method": paymentMethod,
	}, &resp)
	if err != nil {
		return "", "", err
	}
	return resp.Data.ID, resp.Data.ReferenceCode, nil
}

func (a *HTTPDomainWorkflowAdapters) SimulatePaymentSuccess(ctx context.Context, token, orderID, idempotency string) error {
	_, err := a.Client.DoJSON(ctx, "POST", fmt.Sprintf("/api/v1/orders/%s/payment-intents", orderID), token, idempotency, nil, nil)
	if err != nil {
		return err
	}
	_, err = a.Client.DoJSON(ctx, "POST", fmt.Sprintf("/api/v1/orders/%s/payment-sessions", orderID), token, idempotency, nil, nil)
	if err != nil {
		return err
	}
	_, err = a.Client.DoJSON(ctx, "POST", fmt.Sprintf("/api/v1/orders/%s/sandbox-payment-outcomes", orderID), token, "", map[string]string{
		"status": "succeeded",
	}, nil)
	return err
}

func (a *HTTPDomainWorkflowAdapters) IssueDeliveryCode(ctx context.Context, token, orderID string) (string, error) {
	var resp struct {
		Data struct {
			DeliveryCode string `json:"delivery_code"`
		} `json:"data"`
	}
	_, err := a.Client.DoJSON(ctx, "POST", fmt.Sprintf("/api/v1/orders/%s/delivery-code", orderID), token, "", nil, &resp)
	if err != nil {
		return "", err
	}
	return resp.Data.DeliveryCode, nil
}

// 4. Rider Implementation
func (a *HTTPDomainWorkflowAdapters) EnsureApprovedRider(ctx context.Context, token, vehicleType string) (string, error) {
	var profResp struct {
		Data struct {
			ID     string `json:"id"`
			Status string `json:"status"`
		} `json:"data"`
	}
	_, _ = a.Client.DoJSON(ctx, "GET", "/api/v1/rider/profile", token, "", nil, &profResp)
	return profResp.Data.ID, nil
}

func (a *HTTPDomainWorkflowAdapters) SetAvailability(ctx context.Context, token string, isOnline bool) error {
	_, err := a.Client.DoJSON(ctx, "PUT", "/api/v1/rider/availability", token, "", map[string]bool{"is_online": isOnline}, nil)
	return err
}

func (a *HTTPDomainWorkflowAdapters) AcceptOffer(ctx context.Context, token, offerID, idempotency string) error {
	_, err := a.Client.DoJSON(ctx, "POST", fmt.Sprintf("/api/v1/rider/offers/%s/accept", offerID), token, idempotency, nil, nil)
	return err
}

func (a *HTTPDomainWorkflowAdapters) TransitionJobState(ctx context.Context, token, jobID, state, idempotency string) error {
	_, err := a.Client.DoJSON(ctx, "POST", fmt.Sprintf("/api/v1/rider/delivery-jobs/%s/state", jobID), token, idempotency, map[string]string{
		"state": state,
	}, nil)
	return err
}

func (a *HTTPDomainWorkflowAdapters) VerifyPickup(ctx context.Context, token, jobID, code string) error {
	_, err := a.Client.DoJSON(ctx, "POST", fmt.Sprintf("/api/v1/rider/delivery-jobs/%s/pickup/verify", jobID), token, "", map[string]string{
		"code": code,
	}, nil)
	return err
}

func (a *HTTPDomainWorkflowAdapters) ConfirmDelivery(ctx context.Context, token, jobID, code string, confirmCOD bool) error {
	_, err := a.Client.DoJSON(ctx, "POST", fmt.Sprintf("/api/v1/rider/delivery-jobs/%s/delivery/confirm", jobID), token, "", map[string]any{
		"code": code, "confirm_cod_collection": confirmCOD,
	}, nil)
	return err
}

func (a *HTTPDomainWorkflowAdapters) SubmitRemittance(ctx context.Context, token string, amountMinor int64, notes, idempotency string) (string, error) {
	var resp struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	_, err := a.Client.DoJSON(ctx, "POST", "/api/v1/rider/cash-remittances", token, idempotency, map[string]any{
		"amount_minor": amountMinor, "notes": notes, "method": "cash_deposit",
	}, &resp)
	if err != nil {
		return "", err
	}
	return resp.Data.ID, nil
}

func (a *HTTPDomainWorkflowAdapters) RegisterRiderBeneficiary(ctx context.Context, token, accountNum, ifsc, holder string) (string, error) {
	var resp struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	_, err := a.Client.DoJSON(ctx, "POST", "/api/v1/rider/bank-beneficiary", token, "", map[string]string{
		"account_number": accountNum, "ifsc_code": ifsc, "account_holder_name": holder,
	}, &resp)
	if err != nil {
		return "", err
	}
	return resp.Data.ID, nil
}

func (a *HTTPDomainWorkflowAdapters) GetRiderSettlements(ctx context.Context, token string) ([]RiderSettlementView, error) {
	var resp struct {
		Data []RiderSettlementView `json:"data"`
	}
	_, err := a.Client.DoJSON(ctx, "GET", "/api/v1/rider/settlements", token, "", nil, &resp)
	if err != nil {
		return nil, err
	}
	return resp.Data, nil
}

func (a *HTTPDomainWorkflowAdapters) GetEarnings(ctx context.Context, token string) (int64, error) {
	var resp struct {
		Data struct {
			TotalRecordedMinor int64 `json:"total_recorded_minor"`
		} `json:"data"`
	}
	_, err := a.Client.DoJSON(ctx, "GET", "/api/v1/rider/earnings/summary", token, "", nil, &resp)
	if err != nil {
		return 0, err
	}
	return resp.Data.TotalRecordedMinor, nil
}

func (a *HTTPDomainWorkflowAdapters) GetCashAccountability(ctx context.Context, token string) (int64, error) {
	var resp struct {
		Data struct {
			UnremittedLiabilityMinor int64 `json:"unremitted_liability_minor"`
		} `json:"data"`
	}
	_, err := a.Client.DoJSON(ctx, "GET", "/api/v1/rider/cash-accountability", token, "", nil, &resp)
	if err != nil {
		return 0, err
	}
	return resp.Data.UnremittedLiabilityMinor, nil
}

// 5. Admin Implementation
func (a *HTTPDomainWorkflowAdapters) ReviewRiderApplication(ctx context.Context, token, applicationID, action string) error {
	_, err := a.Client.DoJSON(ctx, "POST", fmt.Sprintf("/api/v1/admin/rider-applications/%s/review", applicationID), token, "", map[string]string{"action": action}, nil)
	return err
}

func (a *HTTPDomainWorkflowAdapters) TriggerDispatchRun(ctx context.Context, token, localityID, idempotency string) error {
	_, err := a.Client.DoJSON(ctx, "POST", "/api/v1/admin/delivery/dispatch/run", token, idempotency, map[string]string{"locality_id": localityID}, nil)
	return err
}

func (a *HTTPDomainWorkflowAdapters) ReviewCashRemittance(ctx context.Context, token, remittanceID, action, notes string) error {
	_, err := a.Client.DoJSON(ctx, "POST", fmt.Sprintf("/api/v1/admin/cod/remittances/%s/review", remittanceID), token, "", map[string]string{"action": action, "notes": notes}, nil)
	return err
}

func (a *HTTPDomainWorkflowAdapters) RequestFinancePostAccess(ctx context.Context, token, targetUserID, reason string) (string, error) {
	var resp struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	_, err := a.Client.DoJSON(ctx, "POST", "/api/v1/admin/finance/access-grant-requests", token, "", map[string]string{
		"target_user_id": targetUserID, "permission": "finance.post", "reason": reason,
	}, &resp)
	if err != nil {
		return "", err
	}
	return resp.Data.ID, nil
}

func (a *HTTPDomainWorkflowAdapters) DecideFinancePostAccess(ctx context.Context, token, requestID, decision, reason string) error {
	_, err := a.Client.DoJSON(ctx, "POST", fmt.Sprintf("/api/v1/admin/finance/access-grant-requests/%s/decision", requestID), token, "", map[string]string{
		"decision": decision, "reason": reason,
	}, nil)
	return err
}

func (a *HTTPDomainWorkflowAdapters) AccrueMerchantPayable(ctx context.Context, token, orderID string) error {
	_, err := a.Client.DoJSON(ctx, "POST", fmt.Sprintf("/api/v1/admin/finance/orders/%s/accrue-payable", orderID), token, "", nil, nil)
	return err
}

func (a *HTTPDomainWorkflowAdapters) CreateCommissionPolicy(ctx context.Context, token, category string, rateBps int) (string, error) {
	var resp struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	_, err := a.Client.DoJSON(ctx, "POST", "/api/v1/admin/finance/commission-policies", token, "", map[string]any{
		"category": category, "rate_bps": rateBps,
	}, &resp)
	if err != nil {
		return "", err
	}
	return resp.Data.ID, nil
}

func (a *HTTPDomainWorkflowAdapters) DecideCommissionPolicy(ctx context.Context, token, policyID, decision string) error {
	_, err := a.Client.DoJSON(ctx, "POST", fmt.Sprintf("/api/v1/admin/finance/commission-policies/%s/decision", policyID), token, "", map[string]string{
		"decision": decision,
	}, nil)
	return err
}

func (a *HTTPDomainWorkflowAdapters) CreateMerchantSettlement(ctx context.Context, token, businessID, periodStart, periodEnd, idempotency string) (string, error) {
	var resp struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	_, err := a.Client.DoJSON(ctx, "POST", "/api/v1/admin/finance/settlements", token, idempotency, map[string]string{
		"business_id": businessID, "period_start": periodStart, "period_end": periodEnd,
	}, &resp)
	if err != nil {
		return "", err
	}
	return resp.Data.ID, nil
}

func (a *HTTPDomainWorkflowAdapters) ReviewMerchantSettlement(ctx context.Context, token, batchID string) error {
	_, err := a.Client.DoJSON(ctx, "POST", fmt.Sprintf("/api/v1/admin/finance/settlements/%s/review", batchID), token, "", nil, nil)
	return err
}

func (a *HTTPDomainWorkflowAdapters) ApproveMerchantSettlement(ctx context.Context, token, batchID string) error {
	_, err := a.Client.DoJSON(ctx, "POST", fmt.Sprintf("/api/v1/admin/finance/settlements/%s/approve", batchID), token, "", nil, nil)
	return err
}

func (a *HTTPDomainWorkflowAdapters) CreateRiderSettlement(ctx context.Context, token, riderID, periodStart, periodEnd string) (string, error) {
	var resp struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	_, err := a.Client.DoJSON(ctx, "POST", fmt.Sprintf("/api/v1/admin/finance/riders/%s/settlement-batches", riderID), token, "", map[string]string{
		"period_start": periodStart, "period_end": periodEnd,
	}, &resp)
	if err != nil {
		return "", err
	}
	return resp.Data.ID, nil
}

func (a *HTTPDomainWorkflowAdapters) ApproveRiderSettlement(ctx context.Context, token, batchID, reason string) error {
	_, err := a.Client.DoJSON(ctx, "POST", fmt.Sprintf("/api/v1/admin/finance/rider-settlement-batches/%s/approve", batchID), token, "", map[string]string{
		"reason": reason,
	}, nil)
	return err
}

func (a *HTTPDomainWorkflowAdapters) VerifyBeneficiary(ctx context.Context, token, beneficiaryID string) error {
	_, err := a.Client.DoJSON(ctx, "POST", fmt.Sprintf("/api/v1/admin/finance/beneficiaries/%s/verify", beneficiaryID), token, "", nil, nil)
	return err
}

func (a *HTTPDomainWorkflowAdapters) CreatePayoutTransfer(ctx context.Context, token, kind, batchID, idempotency string) (string, error) {
	endpoint := fmt.Sprintf("/api/v1/admin/finance/settlements/%s/payout-transfer", batchID)
	if kind == "rider_earnings" {
		endpoint = fmt.Sprintf("/api/v1/admin/finance/rider-settlements/%s/payout-transfer", batchID)
	}
	var resp struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	_, err := a.Client.DoJSON(ctx, "POST", endpoint, token, idempotency, nil, &resp)
	if err != nil {
		return "", err
	}
	return resp.Data.ID, nil
}

func (a *HTTPDomainWorkflowAdapters) ApprovePayoutTransfer(ctx context.Context, token, transferID, reason, idempotency string) error {
	_, err := a.Client.DoJSON(ctx, "POST", fmt.Sprintf("/api/v1/admin/finance/payout-transfers/%s/approve", transferID), token, idempotency, map[string]string{
		"reason": reason,
	}, nil)
	return err
}

func (a *HTTPDomainWorkflowAdapters) ExecutePayoutTransfer(ctx context.Context, token, transferID, idempotency string) (string, error) {
	var resp struct {
		Data struct {
			BankUTR string `json:"bank_utr"`
		} `json:"data"`
	}
	_, err := a.Client.DoJSON(ctx, "POST", fmt.Sprintf("/api/v1/admin/finance/payout-transfers/%s/execute", transferID), token, idempotency, nil, &resp)
	if err != nil {
		return "", err
	}
	return resp.Data.BankUTR, nil
}
