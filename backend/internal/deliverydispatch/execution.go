package deliverydispatch

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"net/http"
	"strings"
	"time"

	"github.com/jmoiron/sqlx"
	"grepmind-near/backend/internal/platformfulfillment"
)

const verificationTTL = 5 * time.Minute
const verificationMaxAttempts = 5

// RiderTransition advances only the small set of non-evidence transitions. Pickup
// and delivery completion have dedicated code-verification endpoints.
func (s *Service) RiderTransition(w http.ResponseWriter, r *http.Request, riderID string) {
	if !s.requireEnabled(w) {
		return
	}
	var in struct {
		State string `json:"state"`
	}
	if decodeBody(w, r, &in, 2048) != nil {
		writeError(w, 400, "VALIDATION_ERROR", "A delivery state is required.")
		return
	}
	jobID := r.PathValue("jobId")
	allowed := map[string]map[string]bool{
		"assigned":           {"arriving_at_pickup": true},
		"arriving_at_pickup": {"at_pickup": true},
		"picked_up":          {"en_route": true},
		"return_required":    {"return_in_progress": true},
	}
	var customerID, businessID, from string
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var locality string
		err := tx.QueryRowxContext(r.Context(), `SELECT j.execution_state,j.locality_id::text,o.customer_user_id::text,o.business_id::text FROM delivery_jobs j JOIN customer_orders o ON o.id=j.order_id JOIN delivery_assignments a ON a.job_id=j.id AND a.state='active' WHERE j.id=$1 AND a.rider_user_id=$2 FOR UPDATE OF j,a`, jobID, riderID).Scan(&from, &locality, &customerID, &businessID)
		if errorsNoRows(err) {
			return failure(404, "NOT_FOUND", "Active rider assignment not found.")
		}
		if err != nil {
			return err
		}
		if err := requireActiveRider(r.Context(), tx, riderID, locality); err != nil {
			return err
		}
		if !allowed[from][in.State] {
			return failure(409, "INVALID_DELIVERY_TRANSITION", "This delivery state transition is not allowed.")
		}
		if in.State == "at_pickup" {
			if err := requireDispatchPaymentEligibility(r.Context(), tx, jobID); err != nil {
				return err
			}
			var ready bool
			if err := tx.GetContext(r.Context(), &ready, `SELECT status='ready_for_pickup' FROM customer_orders WHERE id=(SELECT order_id FROM delivery_jobs WHERE id=$1)`, jobID); err != nil {
				return err
			}
			if !ready {
				return failure(409, "ORDER_NOT_READY", "The partner has not marked this order ready for pickup.")
			}
		}
		return changeExecutionState(r.Context(), tx, jobID, riderID, "rider", "state_changed", from, in.State, "")
	})
	if err != nil {
		writeFailure(w, err)
		return
	}
	s.publishScoped(r.Context(), customerID, businessID, jobID, "delivery.status", "Delivery update", "Your delivery status was updated.")
	writeJSON(w, 200, map[string]any{"data": map[string]string{"job_id": jobID, "state": in.State}})
}

func (s *Service) IssuePickupCode(w http.ResponseWriter, r *http.Request, userID string) {
	if !s.requireEnabled(w) {
		return
	}
	jobID := r.PathValue("jobId")
	businessID := r.PathValue("businessId")
	code, err := randomVerificationCode()
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to issue pickup verification.")
		return
	}
	var customerID string
	err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var state, orderStatus string
		err := tx.QueryRowxContext(r.Context(), `SELECT j.execution_state,o.status,o.customer_user_id::text FROM delivery_jobs j JOIN customer_orders o ON o.id=j.order_id JOIN delivery_assignments a ON a.job_id=j.id AND a.state='active' WHERE j.id=$1 AND j.business_id=$2 FOR UPDATE OF j,a`, jobID, businessID).Scan(&state, &orderStatus, &customerID)
		if errorsNoRows(err) {
			return failure(404, "NOT_FOUND", "Delivery job not found for this business.")
		}
		if err != nil {
			return err
		}
		if !merchantCanOperateTx(r.Context(), tx, businessID, userID) {
			return failure(403, "FORBIDDEN", "Active business membership is required.")
		}
		if orderStatus != "ready_for_pickup" || state != "at_pickup" {
			return failure(409, "PICKUP_NOT_READY", "Pickup verification is available only when the order is ready and the assigned rider is at pickup.")
		}
		var recentlyIssued bool
		if err := tx.GetContext(r.Context(), &recentlyIssued, `SELECT EXISTS(SELECT 1 FROM delivery_verification_codes WHERE job_id=$1 AND purpose='pickup' AND issued_at>now()-interval '30 seconds')`, jobID); err != nil {
			return err
		}
		if recentlyIssued {
			return failure(429, "CODE_COOLDOWN", "Wait before requesting another pickup code.")
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_verification_codes SET invalidated_at=now() WHERE job_id=$1 AND purpose='pickup' AND consumed_at IS NULL AND invalidated_at IS NULL`, jobID); err != nil {
			return err
		}
		_, err = tx.ExecContext(r.Context(), `INSERT INTO delivery_verification_codes(job_id,purpose,code_hmac,issued_by,expires_at) VALUES($1,'pickup',$2,$3,now()+($4 * interval '1 second'))`, jobID, s.codeHMAC(jobID, "pickup", code), userID, int(verificationTTL.Seconds()))
		if err != nil {
			return err
		}
		_, err = tx.ExecContext(r.Context(), `INSERT INTO delivery_execution_events(job_id,actor_user_id,actor_type,event_type,from_state,to_state) VALUES($1,$2,'merchant','pickup_code_issued',$3,$3)`, jobID, userID, state)
		return err
	})
	if err != nil {
		writeFailure(w, err)
		return
	}
	writeJSON(w, 200, map[string]any{"data": map[string]any{"job_id": jobID, "pickup_code": code, "expires_in_seconds": int(verificationTTL.Seconds())}})
}

func (s *Service) VerifyPickup(w http.ResponseWriter, r *http.Request, riderID string) {
	if !s.requireEnabled(w) {
		return
	}
	jobID := r.PathValue("jobId")
	var in struct {
		Code string `json:"code"`
	}
	if decodeBody(w, r, &in, 2048) != nil || len(in.Code) != 8 {
		writeError(w, 400, "VALIDATION_ERROR", "Enter the 8-digit pickup code.")
		return
	}
	var state string
	var customerID, businessID string
	var invalid bool
	var idempotent bool
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var locality string
		err := tx.QueryRowxContext(r.Context(), `SELECT j.execution_state,j.locality_id::text,o.customer_user_id::text,o.business_id::text FROM delivery_jobs j JOIN customer_orders o ON o.id=j.order_id JOIN delivery_assignments a ON a.job_id=j.id AND a.state='active' WHERE j.id=$1 AND a.rider_user_id=$2 FOR UPDATE OF j,a`, jobID, riderID).Scan(&state, &locality, &customerID, &businessID)
		if errorsNoRows(err) {
			return failure(404, "NOT_FOUND", "Active rider assignment not found.")
		}
		if err != nil {
			return err
		}
		if err := requireActiveRider(r.Context(), tx, riderID, locality); err != nil {
			return err
		}
		if state == "picked_up" || state == "en_route" || state == "delivered" {
			idempotent = true
			return nil
		}
		if state != "at_pickup" {
			return failure(409, "INVALID_DELIVERY_TRANSITION", "Pickup can be verified only after arrival at the ready partner.")
		}
		if err := requireDispatchPaymentEligibility(r.Context(), tx, jobID); err != nil {
			return err
		}
		var id string
		var digest []byte
		var expires time.Time
		var attempts int
		err = tx.QueryRowxContext(r.Context(), `SELECT id::text,code_hmac,expires_at,attempts FROM delivery_verification_codes WHERE job_id=$1 AND purpose='pickup' AND consumed_at IS NULL AND invalidated_at IS NULL ORDER BY issued_at DESC LIMIT 1 FOR UPDATE`, jobID).Scan(&id, &digest, &expires, &attempts)
		if errorsNoRows(err) {
			return failure(409, "PICKUP_CODE_REQUIRED", "Ask the partner to issue a pickup code.")
		}
		if err != nil {
			return err
		}
		if !expires.After(time.Now().UTC()) || attempts >= verificationMaxAttempts {
			invalid = true
			_, err = tx.ExecContext(r.Context(), `UPDATE delivery_verification_codes SET invalidated_at=now() WHERE id=$1`, id)
			return err
		}
		if !hmac.Equal(digest, s.codeHMAC(jobID, "pickup", strings.TrimSpace(in.Code))) {
			invalid = true
			_, err = tx.ExecContext(r.Context(), `UPDATE delivery_verification_codes SET attempts=attempts+1,invalidated_at=CASE WHEN attempts+1 >= $2 THEN now() ELSE invalidated_at END WHERE id=$1`, id, verificationMaxAttempts)
			return err
		}
		if _, err = tx.ExecContext(r.Context(), `UPDATE delivery_verification_codes SET consumed_at=now() WHERE id=$1`, id); err != nil {
			return err
		}
		if err = changeExecutionState(r.Context(), tx, jobID, riderID, "rider", "pickup_verified", state, "picked_up", ""); err != nil {
			return err
		}
		if _, err = tx.ExecContext(r.Context(), `UPDATE customer_orders SET status='out_for_delivery',updated_at=now() WHERE id=(SELECT order_id FROM delivery_jobs WHERE id=$1) AND status='ready_for_pickup'`, jobID); err != nil {
			return err
		}
		if _, err = tx.ExecContext(r.Context(), `INSERT INTO customer_order_status_events(order_id,status,event_kind,actor_user_id) SELECT order_id,'out_for_delivery','status_change',$2 FROM delivery_jobs WHERE id=$1`, jobID, riderID); err != nil {
			return err
		}
		_, err = tx.ExecContext(r.Context(), `INSERT INTO audit_logs(actor_user_id,action,target_type,target_id) VALUES($1,'delivery.pickup_verified','delivery_job',$2)`, riderID, jobID)
		return err
	})
	if err != nil {
		writeFailure(w, err)
		return
	}
	if invalid {
		writeError(w, 401, "INVALID_OR_EXPIRED_CODE", "Pickup code is invalid, expired, or its attempt limit was reached.")
		return
	}
	if idempotent {
		writeJSON(w, 200, map[string]any{"data": map[string]any{"job_id": jobID, "state": state, "idempotent": true}})
		return
	}
	s.publishScoped(r.Context(), customerID, businessID, jobID, "delivery.pickup_confirmed", "Order picked up", "The partner handover was verified.")
	writeJSON(w, 200, map[string]any{"data": map[string]string{"job_id": jobID, "state": "picked_up"}})
}

func (s *Service) IssueDeliveryCode(w http.ResponseWriter, r *http.Request, customerID string) {
	if !s.requireEnabled(w) {
		return
	}
	orderID := r.PathValue("id")
	code, err := randomVerificationCode()
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to issue delivery verification.")
		return
	}
	var jobID, businessID string
	err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var state string
		err := tx.QueryRowxContext(r.Context(), `SELECT j.id::text,j.execution_state,j.business_id::text FROM customer_orders o JOIN delivery_jobs j ON j.order_id=o.id WHERE o.id=$1 AND o.customer_user_id=$2 FOR UPDATE OF j`, orderID, customerID).Scan(&jobID, &state, &businessID)
		if errorsNoRows(err) {
			return failure(404, "NOT_FOUND", "Delivery order not found.")
		}
		if err != nil {
			return err
		}
		if state != "en_route" {
			return failure(409, "DELIVERY_NOT_EN_ROUTE", "Delivery code is available only after the rider is en route.")
		}
		var recentlyIssued bool
		if err := tx.GetContext(r.Context(), &recentlyIssued, `SELECT EXISTS(SELECT 1 FROM delivery_verification_codes WHERE job_id=$1 AND purpose='delivery' AND issued_at>now()-interval '30 seconds')`, jobID); err != nil {
			return err
		}
		if recentlyIssued {
			return failure(429, "CODE_COOLDOWN", "Wait before requesting another delivery code.")
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_verification_codes SET invalidated_at=now() WHERE job_id=$1 AND purpose='delivery' AND consumed_at IS NULL AND invalidated_at IS NULL`, jobID); err != nil {
			return err
		}
		_, err = tx.ExecContext(r.Context(), `INSERT INTO delivery_verification_codes(job_id,purpose,code_hmac,issued_by,expires_at) VALUES($1,'delivery',$2,$3,now()+($4 * interval '1 second'))`, jobID, s.codeHMAC(jobID, "delivery", code), customerID, int(verificationTTL.Seconds()))
		return err
	})
	if err != nil {
		writeFailure(w, err)
		return
	}
	// The code is returned only to the owning customer and is never persisted in plaintext.
	writeJSON(w, 200, map[string]any{"data": map[string]any{"order_id": orderID, "delivery_code": code, "expires_in_seconds": int(verificationTTL.Seconds())}})
}

func (s *Service) ConfirmDelivery(w http.ResponseWriter, r *http.Request, riderID string) {
	if !s.requireEnabled(w) {
		return
	}
	jobID := r.PathValue("jobId")
	var in struct {
		Code                 string `json:"code"`
		ConfirmCODCollection bool   `json:"confirm_cod_collection"`
	}
	if decodeBody(w, r, &in, 2048) != nil || len(in.Code) != 8 {
		writeError(w, 400, "VALIDATION_ERROR", "Enter the 8-digit customer delivery code.")
		return
	}
	var state string
	var customerID, businessID, paymentMethod string
	var invalid, idempotent bool
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var locality string
		err := tx.QueryRowxContext(r.Context(), `SELECT j.execution_state,j.locality_id::text,o.customer_user_id::text,o.business_id::text,COALESCE(o.payment_method,'') FROM delivery_jobs j JOIN customer_orders o ON o.id=j.order_id JOIN delivery_assignments a ON a.job_id=j.id WHERE j.id=$1 AND a.rider_user_id=$2 AND (a.state='active' OR j.execution_state='delivered') ORDER BY a.assigned_at DESC LIMIT 1 FOR UPDATE OF j,a`, jobID, riderID).Scan(&state, &locality, &customerID, &businessID, &paymentMethod)
		if errorsNoRows(err) {
			return failure(404, "NOT_FOUND", "Rider assignment not found.")
		}
		if err != nil {
			return err
		}
		if state == "delivered" {
			idempotent = true
			return nil
		}
		if err := requireActiveRider(r.Context(), tx, riderID, locality); err != nil {
			return err
		}
		if state != "en_route" {
			return failure(409, "INVALID_DELIVERY_TRANSITION", "Delivery can be completed only after pickup and en-route confirmation.")
		}
		if paymentMethod == "cash_on_delivery" && !in.ConfirmCODCollection {
			return failure(409, "COD_COLLECTION_CONFIRMATION_REQUIRED", "Confirm the synthetic QA COD collection at customer handover.")
		}
		if paymentMethod != "cash_on_delivery" && in.ConfirmCODCollection {
			return failure(400, "COD_NOT_APPLICABLE", "This order does not have a Cash on Delivery obligation.")
		}
		var id string
		var digest []byte
		var expires time.Time
		var attempts int
		err = tx.QueryRowxContext(r.Context(), `SELECT id::text,code_hmac,expires_at,attempts FROM delivery_verification_codes WHERE job_id=$1 AND purpose='delivery' AND consumed_at IS NULL AND invalidated_at IS NULL ORDER BY issued_at DESC LIMIT 1 FOR UPDATE`, jobID).Scan(&id, &digest, &expires, &attempts)
		if errorsNoRows(err) {
			return failure(409, "DELIVERY_CODE_REQUIRED", "The customer must request a delivery code first.")
		}
		if err != nil {
			return err
		}
		if !expires.After(time.Now().UTC()) || attempts >= verificationMaxAttempts {
			invalid = true
			_, err = tx.ExecContext(r.Context(), `UPDATE delivery_verification_codes SET invalidated_at=now() WHERE id=$1`, id)
			return err
		}
		if !hmac.Equal(digest, s.codeHMAC(jobID, "delivery", strings.TrimSpace(in.Code))) {
			invalid = true
			_, err = tx.ExecContext(r.Context(), `UPDATE delivery_verification_codes SET attempts=attempts+1,invalidated_at=CASE WHEN attempts+1 >= $2 THEN now() ELSE invalidated_at END WHERE id=$1`, id, verificationMaxAttempts)
			return err
		}
		if _, err = tx.ExecContext(r.Context(), `UPDATE delivery_verification_codes SET consumed_at=now() WHERE id=$1`, id); err != nil {
			return err
		}
		if paymentMethod == "cash_on_delivery" {
			if s.codCollectionRecorder == nil {
				return failure(503, "SYNTHETIC_COD_UNAVAILABLE", "COD collection cannot be recorded in this environment.")
			}
			if err = s.codCollectionRecorder(r.Context(), tx, jobID, riderID); err != nil {
				return err
			}
		}
		if err = changeExecutionState(r.Context(), tx, jobID, riderID, "rider", "customer_otp_verified", state, "delivered", ""); err != nil {
			return err
		}
		if _, err = tx.ExecContext(r.Context(), `UPDATE customer_orders SET status='delivered',updated_at=now() WHERE id=(SELECT order_id FROM delivery_jobs WHERE id=$1) AND status='out_for_delivery'`, jobID); err != nil {
			return err
		}
		if _, err = tx.ExecContext(r.Context(), `INSERT INTO customer_order_status_events(order_id,status,event_kind,actor_user_id) SELECT order_id,'delivered','status_change',$2 FROM delivery_jobs WHERE id=$1`, jobID, riderID); err != nil {
			return err
		}
		if _, err = tx.ExecContext(r.Context(), `UPDATE delivery_assignments SET state='released',ended_at=now() WHERE job_id=$1 AND rider_user_id=$2 AND state='active'`, jobID, riderID); err != nil {
			return err
		}
		if s.completionRecorder != nil {
			if err = s.completionRecorder(r.Context(), tx, jobID, riderID); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		writeFailure(w, err)
		return
	}
	if invalid {
		writeError(w, 401, "INVALID_OR_EXPIRED_CODE", "Delivery code is invalid, expired, or its attempt limit was reached.")
		return
	}
	if idempotent {
		writeJSON(w, 200, map[string]any{"data": map[string]any{"job_id": jobID, "state": "delivered", "idempotent": true}})
		return
	}
	s.publishScoped(r.Context(), customerID, businessID, jobID, "delivery.delivered", "Delivery completed", "Your order was handed over using customer verification.")
	writeJSON(w, 200, map[string]string{"job_id": jobID, "state": "delivered"})
}

func (s *Service) ReportException(w http.ResponseWriter, r *http.Request, riderID string) {
	if !s.requireEnabled(w) {
		return
	}
	jobID := r.PathValue("jobId")
	var in struct {
		Type   string `json:"type"`
		Reason string `json:"reason"`
	}
	if decodeBody(w, r, &in, 4096) != nil {
		writeError(w, 400, "VALIDATION_ERROR", "Invalid delivery exception.")
		return
	}
	in.Reason = strings.TrimSpace(in.Reason)
	if len([]rune(in.Reason)) < 10 || len([]rune(in.Reason)) > 500 {
		writeError(w, 400, "VALIDATION_ERROR", "Provide a 10–500 character explanation.")
		return
	}
	var customerID, businessID, from string
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		var locality string
		err := tx.QueryRowxContext(r.Context(), `SELECT j.execution_state,j.locality_id::text,o.customer_user_id::text,o.business_id::text FROM delivery_jobs j JOIN customer_orders o ON o.id=j.order_id JOIN delivery_assignments a ON a.job_id=j.id AND a.state='active' WHERE j.id=$1 AND a.rider_user_id=$2 FOR UPDATE OF j,a`, jobID, riderID).Scan(&from, &locality, &customerID, &businessID)
		if errorsNoRows(err) {
			return failure(404, "NOT_FOUND", "Active rider assignment not found.")
		}
		if err != nil {
			return err
		}
		if err := requireActiveRider(r.Context(), tx, riderID, locality); err != nil {
			return err
		}
		valid := map[string]string{"pickup_failed": "assigned,arriving_at_pickup,at_pickup", "customer_unreachable": "en_route", "delivery_failed": "en_route", "return_required": "customer_unreachable,delivery_failed"}
		found := false
		for _, v := range strings.Split(valid[in.Type], ",") {
			if v == from {
				found = true
			}
		}
		if !found {
			return failure(409, "INVALID_EXCEPTION_TRANSITION", "This exception is not valid for the current delivery state.")
		}
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO delivery_exceptions(job_id,reported_by,exception_type,reason) VALUES($1,$2,$3,$4)`, jobID, riderID, in.Type, in.Reason); err != nil {
			return err
		}
		if in.Type == "pickup_failed" || in.Type == "customer_unreachable" || in.Type == "delivery_failed" || in.Type == "return_required" {
			if err := changeExecutionState(r.Context(), tx, jobID, riderID, "rider", in.Type, from, in.Type, in.Reason); err != nil {
				return err
			}
		}
		_, err = tx.ExecContext(r.Context(), `INSERT INTO audit_logs(actor_user_id,action,target_type,target_id,reason) VALUES($1,'delivery.exception_reported','delivery_job',$2,$3)`, riderID, jobID, in.Reason)
		return err
	})
	if err != nil {
		writeFailure(w, err)
		return
	}
	s.publishScoped(r.Context(), customerID, businessID, jobID, "delivery.exception", "Delivery exception", "The rider reported an issue; Grepmind operations will review it.")
	writeJSON(w, 201, map[string]string{"job_id": jobID, "state": in.Type})
}

func (s *Service) ConfirmReturn(w http.ResponseWriter, r *http.Request, userID string) {
	if !s.requireEnabled(w) {
		return
	}
	jobID := r.PathValue("jobId")
	businessID := r.PathValue("businessId")
	var state, from, customerID, orderID, orderStatus, inventoryDisposition string
	var idempotent bool
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		err := tx.QueryRowxContext(r.Context(), `SELECT j.execution_state,j.order_id::text FROM delivery_jobs j WHERE j.id=$1 AND j.business_id=$2 FOR UPDATE`, jobID, businessID).Scan(&from, &orderID)
		if errorsNoRows(err) {
			return failure(404, "NOT_FOUND", "Delivery job not found for this business.")
		}
		if err != nil {
			return err
		}
		if err := tx.GetContext(r.Context(), &customerID, `SELECT customer_user_id::text FROM customer_orders WHERE id=(SELECT order_id FROM delivery_jobs WHERE id=$1)`, jobID); err != nil {
			return err
		}
		if !merchantCanOperateTx(r.Context(), tx, businessID, userID) {
			return failure(403, "FORBIDDEN", "Active business membership is required.")
		}
		if from == "returned" {
			err := tx.QueryRowxContext(r.Context(), `SELECT r.inventory_disposition,o.status FROM delivery_return_receipts r JOIN customer_orders o ON o.id=r.order_id WHERE r.job_id=$1`, jobID).Scan(&inventoryDisposition, &orderStatus)
			if errors.Is(err, sql.ErrNoRows) {
				return failure(409, "RETURN_RECEIPT_MISSING", "Return execution is closed but the receipt record is missing; contact operations.")
			}
			if err != nil {
				return err
			}
			state = "returned"
			idempotent = true
			return nil
		}
		if from != "return_in_progress" {
			return failure(409, "INVALID_DELIVERY_TRANSITION", "A return can be confirmed only after a rider starts the return.")
		}
		state = "returned"
		if err := changeExecutionState(r.Context(), tx, jobID, userID, "merchant", "return_received", from, state, "Partner confirmed return handover."); err != nil {
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_assignments SET state='released',ended_at=now() WHERE job_id=$1 AND state='active'`, jobID); err != nil {
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO delivery_return_receipts(job_id,order_id,business_id,received_by) VALUES($1,$2,$3,$4)`, jobID, orderID, businessID, userID); err != nil {
			return err
		}
		orderStatus = "out_for_delivery"
		inventoryDisposition = "pending"
		var caseID string
		if err := tx.QueryRowxContext(r.Context(), `INSERT INTO delivery_recovery_cases(job_id,order_id,incident_type,reason,reported_by) VALUES($1,$2,'return_disposition_pending','Partner confirmed physical receipt; inventory condition and order disposition require review.',$3) RETURNING id::text`, jobID, orderID, userID).Scan(&caseID); err != nil {
			return err
		}
		if err := recoveryEvent(r.Context(), tx, caseID, jobID, "", userID, "merchant", "return_received_pending_disposition", "Partner confirmed physical receipt; inventory condition and order disposition require review."); err != nil {
			return err
		}
		_, err = tx.ExecContext(r.Context(), `INSERT INTO audit_logs(actor_user_id,action,target_type,target_id,reason) VALUES($1,'delivery.return_received','delivery_job',$2,'Partner confirmed physical return handover; disposition remains pending.')`, userID, jobID)
		return err
	})
	if err != nil {
		writeFailure(w, err)
		return
	}
	if !idempotent {
		s.publishScoped(r.Context(), customerID, businessID, jobID, "delivery.return_received", "Return received", "The partner confirmed receipt. Grepmind is reviewing the order and inventory disposition.")
	}
	writeJSON(w, 200, map[string]any{"data": map[string]any{"job_id": jobID, "order_id": orderID, "state": state, "order_status": orderStatus, "inventory_disposition": inventoryDisposition, "disposition_pending": orderStatus != "returned", "idempotent": idempotent}})
}

func (s *Service) AdminExceptions(w http.ResponseWriter, r *http.Request, _ string) {
	if !s.requireEnabled(w) {
		return
	}
	rows, err := queryMaps(r.Context(), s.db, `SELECT e.id::text,e.job_id::text,e.exception_type,e.state,e.reason,e.created_at::text,o.reference_code,j.execution_state,b.name business_name,l.name locality,COALESCE(a.id::text,'') assignment_id
		FROM delivery_exceptions e JOIN delivery_jobs j ON j.id=e.job_id JOIN customer_orders o ON o.id=j.order_id JOIN businesses b ON b.id=j.business_id JOIN platform_delivery_localities l ON l.id=j.locality_id
		LEFT JOIN delivery_assignments a ON a.job_id=j.id AND a.state='active'
		WHERE e.state='open' ORDER BY e.created_at DESC LIMIT 200`)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load delivery exceptions.")
		return
	}
	writeJSON(w, 200, map[string]any{"data": rows})
}

func (s *Service) ResolveException(w http.ResponseWriter, r *http.Request, adminID string) {
	if !s.requireEnabled(w) {
		return
	}
	jobID := r.PathValue("jobId")
	exceptionID := r.PathValue("exceptionId")
	var in struct {
		Action               string `json:"action"`
		Reason               string `json:"reason"`
		ExpectedAssignmentID string `json:"expected_assignment_id"`
	}
	if decodeBody(w, r, &in, 4096) != nil {
		writeError(w, 400, "VALIDATION_ERROR", "Invalid exception resolution.")
		return
	}
	in.Reason = strings.TrimSpace(in.Reason)
	if len([]rune(in.Reason)) < 10 || len([]rune(in.Reason)) > 500 {
		writeError(w, 400, "VALIDATION_ERROR", "Resolution reason must be 10–500 characters.")
		return
	}
	if in.Action == "require_return" && !validUUID(in.ExpectedAssignmentID) {
		writeError(w, 400, "VALIDATION_ERROR", "The exact active assignment ID is required to require a return.")
		return
	}
	key, keyErr := idempotencyKey(r)
	if keyErr != nil {
		writeFailure(w, keyErr)
		return
	}
	requestBody, _ := json.Marshal(struct {
		JobID       string `json:"job_id"`
		ExceptionID string `json:"exception_id"`
		Request     any    `json:"request"`
	}{jobID, exceptionID, in})
	var typ, from string
	var orderID, customerID, businessID string
	var replay bool
	var idempotencyHash []byte
	response := map[string]string{"job_id": jobID, "exception_id": exceptionID, "state": "resolved"}
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		storedHash, found, lockErr := lockIdempotency(r.Context(), tx, adminID, key, "admin_resolve_delivery_exception", requestBody)
		if lockErr != nil {
			return lockErr
		}
		idempotencyHash = storedHash
		if found {
			replay = true
			return json.Unmarshal(storedHash, &response)
		}
		var assignmentID, assignmentState, assignmentRider, reportedBy string
		var pickupVerified bool
		err := tx.QueryRowxContext(r.Context(), `SELECT e.exception_type,j.execution_state,o.id::text,o.customer_user_id::text,j.business_id::text,
			e.reported_by::text,
			EXISTS(SELECT 1 FROM delivery_execution_events x WHERE x.job_id=j.id AND x.event_type='pickup_verified')
			FROM delivery_exceptions e JOIN delivery_jobs j ON j.id=e.job_id JOIN customer_orders o ON o.id=j.order_id
			WHERE e.id=$1 AND e.job_id=$2 AND e.state='open' FOR UPDATE OF e,j,o`, exceptionID, jobID).Scan(&typ, &from, &orderID, &customerID, &businessID, &reportedBy, &pickupVerified)
		if errorsNoRows(err) {
			return failure(404, "NOT_FOUND", "Open delivery exception not found.")
		}
		if err != nil {
			return err
		}
		if in.Action == "require_return" {
			err = tx.QueryRowxContext(r.Context(), `SELECT id::text,state,rider_user_id::text FROM delivery_assignments WHERE job_id=$1 AND state='active' FOR UPDATE`, jobID).Scan(&assignmentID, &assignmentState, &assignmentRider)
			if errorsNoRows(err) {
				return failure(409, "ASSIGNMENT_CHANGED", "There is no active assignment for this recovery action.")
			}
			if err != nil {
				return err
			}
		}
		switch in.Action {
		case "require_return":
			if assignmentState != "active" || assignmentID != in.ExpectedAssignmentID {
				return failure(409, "ASSIGNMENT_CHANGED", "The active assignment changed; refresh the recovery record before requiring a return.")
			}
			if typ == "rider_unable_to_continue" {
				if assignmentRider != reportedBy || !pickupVerified || (from != "picked_up" && from != "en_route") {
					return failure(409, "CUSTODY_STATE_CONFLICT", "The rider report, verified pickup, active assignment, and post-pickup state must agree before requiring a return.")
				}
			} else if from != "customer_unreachable" && from != "delivery_failed" && from != "return_required" {
				return failure(409, "INVALID_EXCEPTION_RESOLUTION", "Return is not appropriate for this exception state.")
			}
			if from != "return_required" {
				if err := changeExecutionState(r.Context(), tx, jobID, adminID, "admin", "admin_return_override", from, "return_required", in.Reason); err != nil {
					return err
				}
			}
			if typ == "rider_unable_to_continue" {
				var caseID string
				if err := tx.QueryRowxContext(r.Context(), `SELECT id::text FROM delivery_recovery_cases WHERE job_id=$1 AND assignment_id=$2 AND incident_type='rider_reports_unable_to_continue' AND state IN ('open','investigating','action_pending','escalated') FOR UPDATE`, jobID, assignmentID).Scan(&caseID); err != nil {
					if errorsNoRows(err) {
						return failure(409, "RECOVERY_CASE_MISSING", "The rider recovery case is no longer open; refresh before resolving it.")
					}
					return err
				}
				if err := recoveryEvent(r.Context(), tx, caseID, jobID, assignmentID, adminID, "admin", "admin_required_return", in.Reason); err != nil {
					return err
				}
			}
		case "cancel_before_pickup":
			if typ != "pickup_failed" || from != "pickup_failed" {
				return failure(409, "INVALID_EXCEPTION_RESOLUTION", "Only a failed pre-pickup handover can be cancelled this way.")
			}
			res, err := tx.ExecContext(r.Context(), `UPDATE customer_orders SET status='cancelled',updated_at=now() WHERE id=$1 AND status IN ('preparing','ready_for_pickup')`, orderID)
			if err != nil {
				return err
			}
			changed, err := res.RowsAffected()
			if err != nil {
				return err
			}
			if changed != 1 {
				return failure(409, "ORDER_STATE_CONFLICT", "Order status changed; refresh before resolving this pickup issue.")
			}
			if err := platformfulfillment.ReleaseReservedInventory(r.Context(), tx, orderID); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `INSERT INTO customer_order_status_events(order_id,status,event_kind,actor_user_id,reason) VALUES($1,'cancelled','status_change',$2,$3)`, orderID, adminID, in.Reason); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_assignments SET state='cancelled',ended_at=now() WHERE job_id=$1 AND state='active'`, jobID); err != nil {
				return err
			}
		default:
			return failure(400, "VALIDATION_ERROR", "Unsupported exception resolution action.")
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_exceptions SET state='resolved',resolution=$2,resolved_by=$3,resolved_at=now() WHERE id=$1`, exceptionID, in.Reason, adminID); err != nil {
			return err
		}
		if _, err = tx.ExecContext(r.Context(), `INSERT INTO audit_logs(actor_user_id,action,target_type,target_id,reason) VALUES($1,'delivery.exception_resolved','delivery_job',$2,$3)`, adminID, jobID, in.Reason); err != nil {
			return err
		}
		encoded, _ := json.Marshal(response)
		return saveIdempotency(r.Context(), tx, adminID, key, "admin_resolve_delivery_exception", idempotencyHash, encoded)
	})
	if err != nil {
		writeFailure(w, err)
		return
	}
	if !replay {
		s.publishScoped(r.Context(), customerID, businessID, jobID, "delivery.exception_resolved", "Delivery issue reviewed", "Grepmind operations recorded a resolution for the delivery issue.")
	}
	writeJSON(w, 200, map[string]any{"data": response, "idempotent": replay})
}

func (s *Service) CustomerTimeline(w http.ResponseWriter, r *http.Request, userID string) {
	if !s.requireEnabled(w) {
		return
	}
	orderID := r.PathValue("id")
	var allowed bool
	if err := s.db.GetContext(r.Context(), &allowed, `SELECT EXISTS(SELECT 1 FROM customer_orders o WHERE o.id=$1 AND o.customer_user_id=$2)`, orderID, userID); err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to validate delivery ownership.")
		return
	}
	if !allowed {
		writeError(w, 404, "NOT_FOUND", "Delivery history not found.")
		return
	}
	rows, err := queryMaps(r.Context(), s.db, `
		SELECT id::text,event_type,to_state,created_at::text FROM (
			SELECT e.id,'order_status'::text event_type,e.status::text to_state,e.created_at
			FROM customer_order_status_events e
			WHERE e.order_id=$1 AND e.status NOT IN ('out_for_delivery','delivered','cancelled')
			UNION ALL
			SELECT a.id,'rider_assigned'::text event_type,'assigned'::text to_state,a.assigned_at created_at
			FROM delivery_assignments a
			WHERE a.job_id=(SELECT id FROM delivery_jobs WHERE order_id=$1)
			UNION ALL
			SELECT e.id,e.event_type,e.to_state,e.created_at
			FROM delivery_execution_events e
			WHERE e.job_id=(SELECT id FROM delivery_jobs WHERE order_id=$1)
			  AND e.event_type IN ('state_changed','pickup_verified','customer_otp_verified','pickup_failed','customer_unreachable','delivery_failed','return_required','return_received','admin_return_override','order_cancelled_before_pickup')
			UNION ALL
			SELECT x.id,'exception_resolved'::text event_type,'resolved'::text to_state,x.resolved_at created_at
			FROM delivery_exceptions x
			WHERE x.job_id=(SELECT id FROM delivery_jobs WHERE order_id=$1) AND x.state='resolved' AND x.resolved_at IS NOT NULL
		) timeline
		ORDER BY created_at,id`, orderID)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load delivery history.")
		return
	}
	writeJSON(w, 200, map[string]any{"data": rows})
}

// AdminExecutionHistory is intentionally behind the Admin middleware; it returns
// operational evidence without verification-code material.
func (s *Service) AdminExecutionHistory(w http.ResponseWriter, r *http.Request, _ string) {
	if !s.requireEnabled(w) {
		return
	}
	jobID := r.PathValue("jobId")
	rows, err := queryMaps(r.Context(), s.db, `SELECT e.id::text,e.event_type,e.from_state,e.to_state,e.reason,e.created_at::text,COALESCE(u.display_name,'System') actor_name,e.actor_type FROM delivery_execution_events e LEFT JOIN users u ON u.id=e.actor_user_id WHERE e.job_id=$1 ORDER BY e.created_at,e.id`, jobID)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load delivery execution history.")
		return
	}
	if len(rows) == 0 {
		var exists bool
		if err := s.db.GetContext(r.Context(), &exists, `SELECT EXISTS(SELECT 1 FROM delivery_jobs WHERE id=$1)`, jobID); err != nil {
			writeError(w, 500, "INTERNAL_ERROR", "Unable to validate delivery job.")
			return
		}
		if !exists {
			writeError(w, 404, "NOT_FOUND", "Delivery job not found.")
			return
		}
	}
	writeJSON(w, 200, map[string]any{"data": rows})
}

func changeExecutionState(ctx context.Context, tx *sqlx.Tx, jobID, actorID, actorType, event, from, to, reason string) error {
	res, err := tx.ExecContext(ctx, `UPDATE delivery_jobs SET execution_state=$2,updated_at=now() WHERE id=$1 AND execution_state=$3`, jobID, to, from)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n != 1 {
		return failure(409, "DELIVERY_STATE_CONFLICT", "Delivery state changed; refresh and retry.")
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO delivery_execution_events(job_id,actor_user_id,actor_type,event_type,from_state,to_state,reason) VALUES($1,NULLIF($2,'')::uuid,$3,$4,$5,$6,NULLIF($7,''))`, jobID, actorID, actorType, event, from, to, reason)
	return err
}

func (s *Service) codeHMAC(jobID, purpose, code string) []byte {
	m := hmac.New(sha256.New, s.verificationKey[:])
	_, _ = m.Write([]byte(jobID + ":" + purpose + ":" + code))
	return m.Sum(nil)
}

func randomVerificationCode() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(100_000_000))
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%08d", n.Int64()), nil
}

func merchantCanOperateTx(ctx context.Context, tx *sqlx.Tx, businessID, userID string) bool {
	var allowed bool
	err := tx.GetContext(ctx, &allowed, `SELECT EXISTS(SELECT 1 FROM businesses b WHERE b.id=$1 AND b.owner_user_id=$2 AND b.status='approved' UNION ALL SELECT 1 FROM business_members m WHERE m.business_id=$1 AND m.user_id=$2 AND m.status='active' AND m.role IN ('owner','manager','staff'))`, businessID, userID)
	return err == nil && allowed
}

func errorsNoRows(err error) bool { return err == sql.ErrNoRows }
