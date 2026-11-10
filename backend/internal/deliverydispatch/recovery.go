package deliverydispatch

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jmoiron/sqlx"
	"grepmind-near/backend/internal/platformfulfillment"
)

type recoveryResponse struct {
	JobID        string `json:"job_id"`
	CaseID       string `json:"case_id,omitempty"`
	AssignmentID string `json:"assignment_id,omitempty"`
	State        string `json:"state"`
	Idempotent   bool   `json:"idempotent,omitempty"`
}

func idempotencyKey(r *http.Request) (string, error) {
	key := strings.TrimSpace(r.Header.Get("Idempotency-Key"))
	if len(key) < 8 || len(key) > 128 {
		return "", failure(400, "IDEMPOTENCY_KEY_REQUIRED", "Provide an Idempotency-Key between 8 and 128 characters.")
	}
	return key, nil
}

func lockIdempotency(ctx context.Context, tx *sqlx.Tx, actorID, key, operation string, request []byte) ([]byte, bool, error) {
	if _, err := tx.ExecContext(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1,0))`, actorID+":"+key); err != nil {
		return nil, false, err
	}
	hash := sha256.Sum256(append(append([]byte(operation), 0), request...))
	var storedHash, response []byte
	err := tx.QueryRowxContext(ctx, `SELECT request_hash,response FROM delivery_recovery_idempotency WHERE actor_user_id=$1 AND idempotency_key=$2`, actorID, key).Scan(&storedHash, &response)
	if errors.Is(err, sql.ErrNoRows) {
		return hash[:], false, nil
	}
	if err != nil {
		return nil, false, err
	}
	if !bytes.Equal(storedHash, hash[:]) {
		return nil, false, failure(409, "IDEMPOTENCY_CONFLICT", "This idempotency key was already used for a different request.")
	}
	return response, true, nil
}

// ConfirmNoHandover is a merchant-authored custody assertion bound to one
// active assignment. Admin recovery will require this durable evidence.
func (s *Service) ConfirmNoHandover(w http.ResponseWriter, r *http.Request, userID string) {
	if !s.requireEnabled(w) {
		return
	}
	var in struct {
		AssignmentID string `json:"assignment_id"`
		Reason       string `json:"reason"`
	}
	if decodeBody(w, r, &in, 2048) != nil || !validUUID(in.AssignmentID) || runeLen(strings.TrimSpace(in.Reason)) < 10 || runeLen(in.Reason) > 500 {
		writeError(w, 400, "VALIDATION_ERROR", "Provide an assignment ID and a 10–500 character reason.")
		return
	}
	jobID, businessID := r.PathValue("jobId"), r.PathValue("businessId")
	key, err := idempotencyKey(r)
	if err != nil {
		writeFailure(w, err)
		return
	}
	body, _ := json.Marshal(struct {
		BusinessID string `json:"business_id"`
		JobID      string `json:"job_id"`
		Request    any    `json:"request"`
	}{businessID, jobID, in})
	var result recoveryResponse
	var replay bool
	err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if !merchantCanOperateTx(r.Context(), tx, businessID, userID) {
			return failure(403, "FORBIDDEN", "Active business membership is required.")
		}
		hash, found, err := lockIdempotency(r.Context(), tx, userID, key, "merchant_no_handover", body)
		if err != nil {
			return err
		}
		if found {
			replay = true
			return json.Unmarshal(hash, &result)
		}
		var caseID, orderID string
		var executionState string
		err = tx.QueryRowxContext(r.Context(), `SELECT j.execution_state,j.order_id::text FROM delivery_jobs j JOIN delivery_assignments a ON a.job_id=j.id AND a.id=$3 AND a.state='active' WHERE j.id=$1 AND j.business_id=$2 FOR UPDATE OF j,a`, jobID, businessID, in.AssignmentID).Scan(&executionState, &orderID)
		if errors.Is(err, sql.ErrNoRows) {
			return failure(404, "NOT_FOUND", "Active delivery assignment not found for this business.")
		}
		if err != nil {
			return err
		}
		if executionState != "assigned" && executionState != "arriving_at_pickup" && executionState != "at_pickup" && executionState != "pickup_failed" {
			return failure(409, "CUSTODY_ACTIVE", "A no-handover confirmation is not valid after pickup.")
		}
		var pickupVerified bool
		if err := tx.GetContext(r.Context(), &pickupVerified, `SELECT EXISTS(SELECT 1 FROM delivery_execution_events WHERE job_id=$1 AND event_type='pickup_verified')`, jobID); err != nil {
			return err
		}
		if pickupVerified {
			return failure(409, "CUSTODY_ACTIVE", "Pickup verification history prevents pre-pickup recovery.")
		}
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO delivery_recovery_partner_confirmations(job_id,assignment_id,business_id,confirmed_by,confirmation,reason) VALUES($1,$2,$3,$4,'goods_not_handed_over',$5)`, jobID, in.AssignmentID, businessID, userID, strings.TrimSpace(in.Reason)); err != nil {
			var pgErr *pgconn.PgError
			if errors.As(err, &pgErr) && pgErr.Code == "23505" {
				return failure(409, "CONFIRMATION_EXISTS", "A handover confirmation already exists for this assignment.")
			}
			return err
		}
		if err := tx.QueryRowxContext(r.Context(), `INSERT INTO delivery_recovery_cases(job_id,order_id,assignment_id,incident_type,reason,reported_by) VALUES($1,$2,$3,'partner_handover_not_completed',$4,$5) ON CONFLICT(job_id,assignment_id,incident_type) WHERE state IN ('open','investigating','action_pending','escalated') DO UPDATE SET updated_at=now() RETURNING id::text`, jobID, orderID, in.AssignmentID, strings.TrimSpace(in.Reason), userID).Scan(&caseID); err != nil {
			return err
		}
		if err := recoveryEvent(r.Context(), tx, caseID, jobID, in.AssignmentID, userID, "merchant", "partner_confirmed_no_handover", in.Reason); err != nil {
			return err
		}
		_, err = tx.ExecContext(r.Context(), `INSERT INTO audit_logs(actor_user_id,action,target_type,target_id,reason) VALUES($1,'delivery.partner_confirmed_no_handover','delivery_job',$2,$3)`, userID, jobID, strings.TrimSpace(in.Reason))
		if err != nil {
			return err
		}
		result = recoveryResponse{JobID: jobID, CaseID: caseID, AssignmentID: in.AssignmentID, State: "confirmed_no_handover"}
		encoded, _ := json.Marshal(result)
		return saveIdempotency(r.Context(), tx, userID, key, "merchant_no_handover", hash, encoded)
	})
	if err != nil {
		writeFailure(w, err)
		return
	}
	if replay {
		result.Idempotent = true
	}
	writeJSON(w, 200, map[string]any{"data": result})
}

func saveIdempotency(ctx context.Context, tx *sqlx.Tx, actorID, key, operation string, requestHash, response []byte) error {
	_, err := tx.ExecContext(ctx, `INSERT INTO delivery_recovery_idempotency(actor_user_id,idempotency_key,operation,request_hash,response) VALUES($1,$2,$3,$4,$5::jsonb)`, actorID, key, operation, requestHash, response)
	return err
}

func recoveryEvent(ctx context.Context, tx *sqlx.Tx, caseID, jobID, assignmentID, actorID, actorType, event, reason string) error {
	_, err := tx.ExecContext(ctx, `INSERT INTO delivery_recovery_events(case_id,job_id,assignment_id,actor_user_id,actor_type,event_type,reason) VALUES($1,$2,NULLIF($3,'')::uuid,NULLIF($4,'')::uuid,$5,$6,NULLIF($7,''))`, caseID, jobID, assignmentID, actorID, actorType, event, reason)
	return err
}

// recordStaleAssignments opens an operational case but never releases an
// accepted assignment. A lease timeout is evidence of lost heartbeat, not proof
// the rider abandoned physical custody.
func (s *Service) recordStaleAssignments(ctx context.Context) error {
	var hasSchema bool
	if err := s.db.GetContext(ctx, &hasSchema, `SELECT to_regclass('delivery_recovery_cases') IS NOT NULL`); err != nil || !hasSchema {
		return err
	}
	_, err := s.db.ExecContext(ctx, `WITH stale AS (
		SELECT j.id job_id,j.order_id,a.id assignment_id,a.rider_user_id
		FROM delivery_jobs j
		JOIN delivery_assignments a ON a.job_id=j.id AND a.state='active'
		LEFT JOIN rider_availability_sessions av ON av.rider_user_id=a.rider_user_id
		WHERE j.state='assigned' AND (av.rider_user_id IS NULL OR NOT av.is_online OR av.lease_expires_at<=now())
	), inserted AS (
		INSERT INTO delivery_recovery_cases(job_id,order_id,assignment_id,rider_user_id,incident_type,reason)
		SELECT job_id,order_id,assignment_id,rider_user_id,'assignment_heartbeat_stale','Rider availability lease expired while an assignment remains active.' FROM stale
		ON CONFLICT(job_id,assignment_id,incident_type) WHERE state IN ('open','investigating','action_pending','escalated') DO NOTHING
		RETURNING id,job_id,assignment_id
	)
	INSERT INTO delivery_recovery_events(case_id,job_id,assignment_id,actor_type,event_type,reason)
	SELECT id,job_id,assignment_id,'system','stale_assignment_detected','Lease expiry recorded for operator review; assignment retained.' FROM inserted`)
	return err
}

// ReportUnableToContinue creates an auditable recovery case for the rider's
// current assignment. It does not release the assignment or change custody.
func (s *Service) ReportUnableToContinue(w http.ResponseWriter, r *http.Request, riderID string) {
	if !s.requireEnabled(w) {
		return
	}
	var in struct {
		Reason string `json:"reason"`
	}
	if decodeBody(w, r, &in, 2048) != nil {
		writeError(w, 400, "VALIDATION_ERROR", "A recovery reason is required.")
		return
	}
	in.Reason = strings.TrimSpace(in.Reason)
	if runeLen(in.Reason) < 10 || runeLen(in.Reason) > 500 {
		writeError(w, 400, "VALIDATION_ERROR", "Recovery reason must be 10 to 500 characters.")
		return
	}
	key, err := idempotencyKey(r)
	if err != nil {
		writeFailure(w, err)
		return
	}
	jobID := r.PathValue("jobId")
	requestBody, _ := json.Marshal(struct {
		JobID   string `json:"job_id"`
		Request any    `json:"request"`
	}{jobID, in})
	var response recoveryResponse
	var replay bool
	err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		hash, found, err := lockIdempotency(r.Context(), tx, riderID, key, "rider_unable_to_continue", requestBody)
		if err != nil {
			return err
		}
		if found {
			replay = true
			return json.Unmarshal(hash, &response)
		}
		var assignmentID, locality, executionState string
		err = tx.QueryRowxContext(r.Context(), `SELECT a.id::text,j.locality_id::text,j.execution_state FROM delivery_assignments a JOIN delivery_jobs j ON j.id=a.job_id WHERE a.job_id=$1 AND a.rider_user_id=$2 AND a.state='active' FOR UPDATE OF a,j`, jobID, riderID).Scan(&assignmentID, &locality, &executionState)
		if errors.Is(err, sql.ErrNoRows) {
			return failure(404, "NOT_FOUND", "Active rider assignment not found.")
		}
		if err != nil {
			return err
		}
		if err := requireActiveRider(r.Context(), tx, riderID, locality); err != nil {
			return err
		}
		var orderID string
		if err := tx.GetContext(r.Context(), &orderID, `SELECT order_id::text FROM delivery_jobs WHERE id=$1`, jobID); err != nil {
			return err
		}
		var caseID string
		err = tx.QueryRowxContext(r.Context(), `INSERT INTO delivery_recovery_cases(job_id,order_id,assignment_id,rider_user_id,incident_type,reason,reported_by) VALUES($1,$2,$3,$4,'rider_reports_unable_to_continue',$5,$4) ON CONFLICT(job_id,assignment_id,incident_type) WHERE state IN ('open','investigating','action_pending','escalated') DO UPDATE SET updated_at=delivery_recovery_cases.updated_at RETURNING id::text`, jobID, orderID, assignmentID, riderID, in.Reason).Scan(&caseID)
		if err != nil {
			return err
		}
		var existing bool
		if err := tx.GetContext(r.Context(), &existing, `SELECT EXISTS(SELECT 1 FROM delivery_recovery_events WHERE case_id=$1 AND event_type='rider_reported_unable_to_continue')`, caseID); err != nil {
			return err
		}
		if !existing {
			if err := recoveryEvent(r.Context(), tx, caseID, jobID, assignmentID, riderID, "rider", "rider_reported_unable_to_continue", in.Reason); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `INSERT INTO delivery_exceptions(job_id,reported_by,exception_type,reason) VALUES($1,$2,'rider_unable_to_continue',$3)`, jobID, riderID, in.Reason); err != nil {
				return err
			}
		}
		response = recoveryResponse{JobID: jobID, CaseID: caseID, AssignmentID: assignmentID, State: "open"}
		encoded, _ := json.Marshal(response)
		return saveIdempotency(r.Context(), tx, riderID, key, "rider_unable_to_continue", hash, encoded)
	})
	if err != nil {
		writeFailure(w, err)
		return
	}
	if replay {
		response.Idempotent = true
	}
	writeJSON(w, 201, map[string]any{"data": response})
}

type adminRecoveryRequest struct {
	Action                     string `json:"action"`
	Reason                     string `json:"reason"`
	ExpectedAssignmentID       string `json:"expected_assignment_id"`
	ExpectedExecutionState     string `json:"expected_execution_state"`
	PartnerConfirmedNoHandover bool   `json:"partner_confirmed_no_handover"`
}

// AdminRecover performs only safe pre-pickup recovery. Post-pickup custody is
// never released through this endpoint.
func (s *Service) AdminRecover(w http.ResponseWriter, r *http.Request, adminID string) {
	if !s.requireEnabled(w) {
		return
	}
	var in adminRecoveryRequest
	if decodeBody(w, r, &in, 4096) != nil || (in.Action != "release_and_reassign_before_pickup" && in.Action != "cancel_before_pickup") || !validUUID(in.ExpectedAssignmentID) || runeLen(strings.TrimSpace(in.Reason)) < 10 || runeLen(in.Reason) > 500 {
		writeError(w, 400, "VALIDATION_ERROR", "Provide a supported recovery action, active assignment ID, expected execution state, and 10–500 character reason.")
		return
	}
	if !in.PartnerConfirmedNoHandover {
		writeError(w, 422, "HANDOVER_UNCONFIRMED", "Partner confirmation that goods were not handed over is required before pre-pickup recovery.")
		return
	}
	if in.ExpectedExecutionState != "assigned" && in.ExpectedExecutionState != "arriving_at_pickup" && in.ExpectedExecutionState != "at_pickup" && in.ExpectedExecutionState != "pickup_failed" {
		writeError(w, 422, "INVALID_RECOVERY_STATE", "Pre-pickup recovery is not allowed after custody has transferred.")
		return
	}
	key, err := idempotencyKey(r)
	if err != nil {
		writeFailure(w, err)
		return
	}
	jobID := r.PathValue("jobId")
	body, _ := json.Marshal(struct {
		JobID   string `json:"job_id"`
		Request any    `json:"request"`
	}{jobID, in})
	var result recoveryResponse
	var replay bool
	var customerID, businessID string
	err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		hash, found, err := lockIdempotency(r.Context(), tx, adminID, key, "admin_delivery_recovery", body)
		if err != nil {
			return err
		}
		if found {
			replay = true
			return json.Unmarshal(hash, &result)
		}
		var orderID, assignmentID, riderID, currentState, orderStatus string
		err = tx.QueryRowxContext(r.Context(), `SELECT j.order_id::text,a.id::text,a.rider_user_id::text,j.execution_state,o.status,o.customer_user_id::text,o.business_id::text
			FROM delivery_jobs j JOIN delivery_assignments a ON a.job_id=j.id AND a.state='active' JOIN customer_orders o ON o.id=j.order_id
			WHERE j.id=$1 FOR UPDATE OF j,a,o`, jobID).Scan(&orderID, &assignmentID, &riderID, &currentState, &orderStatus, &customerID, &businessID)
		if errors.Is(err, sql.ErrNoRows) {
			return failure(404, "NOT_FOUND", "Active delivery assignment not found.")
		}
		if err != nil {
			return err
		}
		if assignmentID != in.ExpectedAssignmentID || currentState != in.ExpectedExecutionState {
			return failure(409, "STALE_RECOVERY_STATE", "Assignment or delivery state changed. Reload the case before retrying.")
		}
		if currentState == "picked_up" || currentState == "en_route" || currentState == "return_required" || currentState == "return_in_progress" || currentState == "delivered" || currentState == "returned" {
			return failure(409, "CUSTODY_ACTIVE", "This recovery action cannot transfer or cancel an order after verified pickup.")
		}
		if orderStatus != "ready_for_pickup" && orderStatus != "preparing" {
			return failure(409, "ORDER_STATE_CONFLICT", "The partner order is no longer in a recoverable pre-pickup state.")
		}
		var partnerConfirmed bool
		if err := tx.GetContext(r.Context(), &partnerConfirmed, `SELECT EXISTS(SELECT 1 FROM delivery_recovery_partner_confirmations WHERE job_id=$1 AND assignment_id=$2 AND business_id=$3 AND confirmation='goods_not_handed_over')`, jobID, assignmentID, businessID); err != nil {
			return err
		}
		if !partnerConfirmed {
			return failure(422, "HANDOVER_UNCONFIRMED", "The assigned partner must confirm that the goods were not handed over.")
		}
		incidentType := "rider_reports_unable_to_continue"
		if currentState == "pickup_failed" {
			incidentType = "pickup_failed"
		}
		var caseID string
		if err := tx.QueryRowxContext(r.Context(), `INSERT INTO delivery_recovery_cases(job_id,order_id,assignment_id,rider_user_id,incident_type,state,reason,reported_by) VALUES($1,$2,$3,$4,$5,'investigating',$6,$7) ON CONFLICT(job_id,assignment_id,incident_type) WHERE state IN ('open','investigating','action_pending','escalated') DO UPDATE SET updated_at=now() RETURNING id::text`, jobID, orderID, assignmentID, riderID, incidentType, in.Reason, adminID).Scan(&caseID); err != nil {
			return err
		}
		if in.Action == "cancel_before_pickup" {
			var verified bool
			if err := tx.GetContext(r.Context(), &verified, `SELECT EXISTS(SELECT 1 FROM delivery_execution_events WHERE job_id=$1 AND event_type='pickup_verified')`, jobID); err != nil {
				return err
			}
			if verified {
				return failure(409, "CUSTODY_ACTIVE", "Pickup verification history prevents cancellation.")
			}
			if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_verification_codes SET invalidated_at=now() WHERE job_id=$1 AND consumed_at IS NULL AND invalidated_at IS NULL`, jobID); err != nil {
				return err
			}
			res, err := tx.ExecContext(r.Context(), `UPDATE customer_orders SET status='cancelled',cancelled_at=now(),updated_at=now() WHERE id=$1 AND status IN ('preparing','ready_for_pickup')`, orderID)
			if err != nil {
				return err
			}
			n, _ := res.RowsAffected()
			if n != 1 {
				return failure(409, "ORDER_STATE_CONFLICT", "Order state changed; reload before cancellation.")
			}
			if err := platformfulfillment.ReleaseReservedInventory(r.Context(), tx, orderID); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_assignments SET state='cancelled',ended_at=now() WHERE job_id=$1 AND state='active'`, jobID); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_offers SET state='cancelled',responded_at=now() WHERE job_id=$1 AND state='offered'`, jobID); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_dispatch_runs SET state='cancelled',completed_at=now() WHERE job_id=$1 AND state='searching'`, jobID); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_jobs SET state='cancelled',updated_at=now() WHERE id=$1`, jobID); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `INSERT INTO customer_order_status_events(order_id,status,event_kind,actor_user_id,reason) VALUES($1,'cancelled','status_change',$2,$3)`, orderID, adminID, in.Reason); err != nil {
				return err
			}
			if err := recoveryEvent(r.Context(), tx, caseID, jobID, assignmentID, adminID, "admin", "cancelled_before_pickup", in.Reason); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `INSERT INTO delivery_recovery_events(case_id,job_id,assignment_id,actor_user_id,actor_type,event_type,reason) SELECT id,$1,$2,$3,'admin','case_resolved_cancelled', $4 FROM delivery_recovery_cases WHERE job_id=$1 AND assignment_id=$2 AND state IN ('open','investigating','action_pending','escalated')`, jobID, assignmentID, adminID, in.Reason); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_recovery_cases SET state='resolved',resolution_code='cancelled_before_pickup',resolution_reason=$3,resolved_by=$4,resolved_at=now(),updated_at=now() WHERE job_id=$1 AND assignment_id=$2 AND state IN ('open','investigating','action_pending','escalated')`, jobID, assignmentID, in.Reason, adminID); err != nil {
				return err
			}
			result = recoveryResponse{JobID: jobID, CaseID: caseID, AssignmentID: assignmentID, State: "cancelled"}
		} else {
			if orderStatus != "ready_for_pickup" {
				return failure(409, "ORDER_NOT_READY", "Partner must mark the order ready before assignment recovery.")
			}
			var verified bool
			if err := tx.GetContext(r.Context(), &verified, `SELECT EXISTS(SELECT 1 FROM delivery_execution_events WHERE job_id=$1 AND event_type='pickup_verified')`, jobID); err != nil {
				return err
			}
			if verified {
				return failure(409, "CUSTODY_ACTIVE", "Pickup verification history prevents pre-pickup reassignment.")
			}
			if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_verification_codes SET invalidated_at=now() WHERE job_id=$1 AND purpose='pickup' AND consumed_at IS NULL AND invalidated_at IS NULL`, jobID); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_assignments SET state='released',ended_at=now() WHERE id=$1 AND state='active'`, assignmentID); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_jobs SET state='pending_dispatch',updated_at=now() WHERE id=$1 AND state='assigned'`, jobID); err != nil {
				return err
			}
			if err := changeExecutionState(r.Context(), tx, jobID, adminID, "admin", "assignment_released_before_pickup", currentState, "assigned", in.Reason); err != nil {
				return err
			}
			if err := recoveryEvent(r.Context(), tx, caseID, jobID, assignmentID, adminID, "admin", "assignment_released_before_pickup", in.Reason); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `WITH changed AS (UPDATE rider_availability_sessions SET is_online=false,lease_expires_at=NULL,updated_at=now() WHERE rider_user_id=$1 AND is_online RETURNING rider_user_id) INSERT INTO rider_availability_events(rider_user_id,event_type) SELECT rider_user_id,'offline' FROM changed`, riderID); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_exceptions SET state='resolved',resolution=$2,resolved_by=$3,resolved_at=now() WHERE job_id=$1 AND state='open' AND exception_type IN ('pickup_failed','rider_unable_to_continue')`, jobID, in.Reason, adminID); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `INSERT INTO delivery_recovery_events(case_id,job_id,assignment_id,actor_user_id,actor_type,event_type,reason) SELECT id,$1,$2,$3,'admin','case_resolved_released_for_dispatch',$4 FROM delivery_recovery_cases WHERE job_id=$1 AND assignment_id=$2 AND state IN ('open','investigating','action_pending','escalated')`, jobID, assignmentID, adminID, in.Reason); err != nil {
				return err
			}
			if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_recovery_cases SET state='resolved',resolution_code='released_for_dispatch',resolution_reason=$3,resolved_by=$4,resolved_at=now(),updated_at=now() WHERE job_id=$1 AND assignment_id=$2 AND state IN ('open','investigating','action_pending','escalated')`, jobID, assignmentID, in.Reason, adminID); err != nil {
				return err
			}
			result = recoveryResponse{JobID: jobID, CaseID: caseID, AssignmentID: assignmentID, State: "dispatching"}
		}
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO audit_logs(actor_user_id,action,target_type,target_id,reason) VALUES($1,$2,'delivery_job',$3,$4)`, adminID, "delivery.recovery."+in.Action, jobID, in.Reason); err != nil {
			return err
		}
		encoded, _ := json.Marshal(result)
		return saveIdempotency(r.Context(), tx, adminID, key, "admin_delivery_recovery", hash, encoded)
	})
	if err != nil {
		writeFailure(w, err)
		return
	}
	if replay {
		result.Idempotent = true
	}
	if result.State == "dispatching" {
		if err := s.advanceJob(r.Context(), jobID); err != nil {
			writeError(w, 500, "INTERNAL_ERROR", "Assignment was safely released, but dispatch could not be advanced.")
			return
		}
	}
	if !replay {
		s.publishScoped(r.Context(), customerID, businessID, jobID, "delivery.recovery", "Delivery update", "Grepmind is resolving a delivery issue.")
	}
	writeJSON(w, 200, map[string]any{"data": result})
}

func (s *Service) AdminRecoveryCases(w http.ResponseWriter, r *http.Request, _ string) {
	if !s.requireEnabled(w) {
		return
	}
	rows, err := queryMaps(r.Context(), s.db, `SELECT c.id::text,c.job_id::text,c.order_id::text,o.reference_code,c.assignment_id::text,c.rider_user_id::text,
		COALESCE(rp.display_name,'') rider_name,c.incident_type,c.state,c.reason,c.opened_at::text,c.updated_at::text,l.name locality,d.name district,
		j.execution_state,o.status order_status,COALESCE(a.state='active',false) assignment_active,
		EXISTS(SELECT 1 FROM delivery_execution_events x WHERE x.job_id=j.id AND x.event_type='pickup_verified') custody_transferred,
		EXISTS(SELECT 1 FROM delivery_recovery_partner_confirmations pc WHERE pc.job_id=j.id AND pc.assignment_id=c.assignment_id AND pc.confirmation='goods_not_handed_over') partner_confirmed_no_handover,
		COALESCE(rr.inventory_disposition,'') inventory_disposition,rr.received_at::text return_received_at,rr.finalized_at::text return_finalized_at,b.name business_name
		FROM delivery_recovery_cases c JOIN delivery_jobs j ON j.id=c.job_id JOIN customer_orders o ON o.id=c.order_id
		JOIN businesses b ON b.id=j.business_id JOIN platform_delivery_localities l ON l.id=j.locality_id JOIN platform_districts d ON d.id=l.district_id
		LEFT JOIN delivery_assignments a ON a.id=c.assignment_id LEFT JOIN delivery_return_receipts rr ON rr.job_id=j.id
		LEFT JOIN rider_profiles rp ON rp.user_id=c.rider_user_id
		WHERE c.state IN ('open','investigating','action_pending','escalated') ORDER BY c.opened_at,id LIMIT 200`)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load delivery recovery cases.")
		return
	}
	writeJSON(w, 200, map[string]any{"data": rows})
}

// AdminRecoveryCaseEvents returns immutable, sanitized history for one case.
func (s *Service) AdminRecoveryCaseEvents(w http.ResponseWriter, r *http.Request, _ string) {
	if !s.requireEnabled(w) {
		return
	}
	caseID := r.PathValue("caseId")
	if !validUUID(caseID) {
		writeError(w, 400, "VALIDATION_ERROR", "Recovery case ID must be a UUID.")
		return
	}
	rows, err := queryMaps(r.Context(), s.db, `SELECT e.id::text,e.actor_type,e.event_type,COALESCE(e.reason,'') reason,e.created_at::text,
		COALESCE(u.display_name,'System') actor_name
		FROM delivery_recovery_events e LEFT JOIN users u ON u.id=e.actor_user_id
		WHERE e.case_id=$1 ORDER BY e.created_at,e.id LIMIT 500`, caseID)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load recovery case history.")
		return
	}
	if len(rows) == 0 {
		var exists bool
		if err := s.db.GetContext(r.Context(), &exists, `SELECT EXISTS(SELECT 1 FROM delivery_recovery_cases WHERE id=$1)`, caseID); err != nil {
			writeError(w, 500, "INTERNAL_ERROR", "Unable to load recovery case history.")
			return
		}
		if !exists {
			writeError(w, 404, "NOT_FOUND", "Recovery case not found.")
			return
		}
	}
	writeJSON(w, 200, map[string]any{"data": rows})
}

// RecordReturnDisposition is called by an authorized member of the assigned
// business after the merchant physically receives and inspects the return.
func (s *Service) RecordReturnDisposition(w http.ResponseWriter, r *http.Request, userID string) {
	if !s.requireEnabled(w) {
		return
	}
	var in struct {
		InventoryDisposition string `json:"inventory_disposition"`
		Reason               string `json:"reason"`
	}
	if decodeBody(w, r, &in, 2048) != nil || (in.InventoryDisposition != "restockable" && in.InventoryDisposition != "not_restockable") || runeLen(strings.TrimSpace(in.Reason)) < 10 || runeLen(in.Reason) > 500 {
		writeError(w, 400, "VALIDATION_ERROR", "Choose a return inventory disposition and provide a 10–500 character inspection reason.")
		return
	}
	jobID, businessID := r.PathValue("jobId"), r.PathValue("businessId")
	key, err := idempotencyKey(r)
	if err != nil {
		writeFailure(w, err)
		return
	}
	body, _ := json.Marshal(struct {
		BusinessID string `json:"business_id"`
		JobID      string `json:"job_id"`
		Request    any    `json:"request"`
	}{businessID, jobID, in})
	var orderID string
	var replay bool
	err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if !merchantCanOperateTx(r.Context(), tx, businessID, userID) {
			return failure(403, "FORBIDDEN", "Active business membership is required.")
		}
		hash, found, err := lockIdempotency(r.Context(), tx, userID, key, "merchant_return_disposition", body)
		if err != nil {
			return err
		}
		if found {
			replay = true
			var stored struct {
				OrderID string `json:"order_id"`
			}
			if err := json.Unmarshal(hash, &stored); err != nil {
				return err
			}
			orderID = stored.OrderID
			return nil
		}
		var caseID string
		var state string
		if err := tx.QueryRowxContext(r.Context(), `SELECT j.execution_state,j.order_id::text FROM delivery_jobs j WHERE j.id=$1 AND j.business_id=$2 FOR UPDATE`, jobID, businessID).Scan(&state, &orderID); errors.Is(err, sql.ErrNoRows) {
			return failure(404, "NOT_FOUND", "Delivery job not found for this business.")
		} else if err != nil {
			return err
		}
		if state != "returned" {
			return failure(409, "RETURN_NOT_RECEIVED", "The partner must confirm physical return receipt before inventory disposition.")
		}
		if !merchantCanOperateTx(r.Context(), tx, businessID, userID) {
			return failure(403, "FORBIDDEN", "Active business membership is required.")
		}
		res, err := tx.ExecContext(r.Context(), `UPDATE delivery_return_receipts SET inventory_disposition=$2,disposition_reason=$3,disposition_by=$4,disposition_at=now() WHERE job_id=$1 AND inventory_disposition='pending' AND finalized_at IS NULL`, jobID, in.InventoryDisposition, strings.TrimSpace(in.Reason), userID)
		if err != nil {
			return err
		}
		n, _ := res.RowsAffected()
		if n != 1 {
			return failure(409, "RETURN_DISPOSITION_CONFLICT", "Return disposition was already recorded or the return is not awaiting inspection.")
		}
		if err := tx.GetContext(r.Context(), &caseID, `SELECT id::text FROM delivery_recovery_cases WHERE job_id=$1 AND incident_type='return_disposition_pending' AND state IN ('open','investigating','action_pending','escalated') ORDER BY opened_at DESC LIMIT 1 FOR UPDATE`, jobID); err != nil {
			return err
		}
		if err := recoveryEvent(r.Context(), tx, caseID, jobID, "", userID, "merchant", "return_inventory_inspected", in.Reason); err != nil {
			return err
		}
		response, _ := json.Marshal(map[string]string{"order_id": orderID})
		return saveIdempotency(r.Context(), tx, userID, key, "merchant_return_disposition", hash, response)
	})
	if err != nil {
		writeFailure(w, err)
		return
	}
	writeJSON(w, 200, map[string]any{"data": map[string]any{"job_id": jobID, "order_id": orderID, "inventory_disposition": in.InventoryDisposition, "state": "awaiting_admin_finalization", "idempotent": replay}})
}

func (s *Service) AdminFinalizeReturn(w http.ResponseWriter, r *http.Request, adminID string) {
	if !s.requireEnabled(w) {
		return
	}
	jobID := r.PathValue("jobId")
	var in struct {
		Reason string `json:"reason"`
	}
	if decodeBody(w, r, &in, 2048) != nil || runeLen(strings.TrimSpace(in.Reason)) < 10 || runeLen(in.Reason) > 500 {
		writeError(w, 400, "VALIDATION_ERROR", "A 10–500 character finalization reason is required.")
		return
	}
	var customerID, businessID, orderID string
	key, err := idempotencyKey(r)
	if err != nil {
		writeFailure(w, err)
		return
	}
	body, _ := json.Marshal(struct {
		JobID   string `json:"job_id"`
		Request any    `json:"request"`
	}{jobID, in})
	var replay bool
	err = s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		hash, found, err := lockIdempotency(r.Context(), tx, adminID, key, "admin_finalize_return", body)
		if err != nil {
			return err
		}
		if found {
			replay = true
			var stored struct {
				OrderID string `json:"order_id"`
			}
			if err := json.Unmarshal(hash, &stored); err != nil {
				return err
			}
			orderID = stored.OrderID
			return tx.GetContext(r.Context(), &customerID, `SELECT customer_user_id::text FROM customer_orders WHERE id=$1`, orderID)
		}
		var state, orderStatus, disposition string
		err = tx.QueryRowxContext(r.Context(), `SELECT j.execution_state,o.status,r.inventory_disposition,o.id::text,o.customer_user_id::text,o.business_id::text
			FROM delivery_jobs j JOIN customer_orders o ON o.id=j.order_id JOIN delivery_return_receipts r ON r.job_id=j.id
			WHERE j.id=$1 FOR UPDATE OF j,o,r`, jobID).Scan(&state, &orderStatus, &disposition, &orderID, &customerID, &businessID)
		if errors.Is(err, sql.ErrNoRows) {
			return failure(404, "NOT_FOUND", "Pending delivery return disposition not found.")
		}
		if err != nil {
			return err
		}
		if state != "returned" || orderStatus == "returned" || disposition == "pending" {
			return failure(409, "RETURN_NOT_READY", "Physical return and merchant inventory inspection must be recorded before finalization.")
		}
		if disposition == "restockable" {
			if err := platformfulfillment.ReleaseReservedInventory(r.Context(), tx, orderID); err != nil {
				return err
			}
		} else if _, err := tx.ExecContext(r.Context(), `UPDATE platform_inventory_reservations SET status='consumed',updated_at=now() WHERE order_id=$1 AND status='reserved'`, orderID); err != nil {
			return err
		}
		res, err := tx.ExecContext(r.Context(), `UPDATE customer_orders SET status='returned',updated_at=now() WHERE id=$1 AND status='out_for_delivery'`, orderID)
		if err != nil {
			return err
		}
		n, _ := res.RowsAffected()
		if n != 1 {
			return failure(409, "ORDER_STATE_CONFLICT", "Order state changed; refresh before finalizing the return.")
		}
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO customer_order_status_events(order_id,status,event_kind,actor_user_id,reason) VALUES($1,'returned','delivery_returned',$2,$3)`, orderID, adminID, strings.TrimSpace(in.Reason)); err != nil {
			return err
		}
		var caseID string
		if err := tx.QueryRowxContext(r.Context(), `SELECT id::text FROM delivery_recovery_cases WHERE job_id=$1 AND incident_type='return_disposition_pending' AND state IN ('open','investigating','action_pending','escalated') ORDER BY opened_at DESC LIMIT 1 FOR UPDATE`, jobID).Scan(&caseID); err != nil {
			return err
		}
		if err := recoveryEvent(r.Context(), tx, caseID, jobID, "", adminID, "admin", "return_finalized", in.Reason); err != nil {
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `INSERT INTO delivery_recovery_events(case_id,job_id,assignment_id,actor_user_id,actor_type,event_type,reason)
			SELECT id,job_id,assignment_id,$2,'admin','return_finalized',$3 FROM delivery_recovery_cases
			WHERE job_id=$1 AND incident_type='rider_reports_unable_to_continue' AND state IN ('open','investigating','action_pending','escalated')`, jobID, adminID, strings.TrimSpace(in.Reason)); err != nil {
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_recovery_cases SET state='resolved',resolution_code='returned_to_partner',resolution_reason=$2,resolved_by=$3,resolved_at=now(),updated_at=now()
			WHERE job_id=$1 AND incident_type='rider_reports_unable_to_continue' AND state IN ('open','investigating','action_pending','escalated')`, jobID, strings.TrimSpace(in.Reason), adminID); err != nil {
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_return_receipts SET finalized_by=$2,finalized_at=now() WHERE job_id=$1 AND finalized_at IS NULL`, jobID, adminID); err != nil {
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_recovery_cases SET state='resolved',resolution_code='returned_to_partner',resolution_reason=$2,resolved_by=$3,resolved_at=now(),updated_at=now() WHERE id=$1`, caseID, in.Reason, adminID); err != nil {
			return err
		}
		if _, err := tx.ExecContext(r.Context(), `UPDATE delivery_exceptions SET state='resolved',resolution=$2,resolved_by=$3,resolved_at=now() WHERE job_id=$1 AND state='open'`, jobID, in.Reason, adminID); err != nil {
			return err
		}
		if _, err = tx.ExecContext(r.Context(), `INSERT INTO audit_logs(actor_user_id,action,target_type,target_id,reason) VALUES($1,'delivery.return_finalized','delivery_job',$2,$3)`, adminID, jobID, in.Reason); err != nil {
			return err
		}
		response, _ := json.Marshal(map[string]string{"order_id": orderID})
		return saveIdempotency(r.Context(), tx, adminID, key, "admin_finalize_return", hash, response)
	})
	if err != nil {
		writeFailure(w, err)
		return
	}
	if !replay {
		s.publishScoped(r.Context(), customerID, businessID, jobID, "delivery.returned", "Order returned to partner", "The return was received and its outcome was recorded. The order was not marked delivered or paid.")
	}
	writeJSON(w, 200, map[string]any{"data": map[string]any{"job_id": jobID, "order_id": orderID, "execution_state": "returned", "order_status": "returned", "payment_status": "not_collected", "idempotent": replay}})
}

func runeLen(value string) int { return len([]rune(value)) }
