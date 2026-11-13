package financialaccess

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
	"grepmind-near/backend/internal/financialledger"
	"grepmind-near/backend/pkg/database"
)

type Service struct {
	db *database.DB
	qa bool
}

func NewService(db *database.DB, env string) *Service {
	return &Service{db: db, qa: env == "qa" || env == "test"}
}

type apiError struct {
	status        int
	code, message string
}

func (e *apiError) Error() string { return e.message }

func fail(w http.ResponseWriter, err error) {
	var e *apiError
	if errors.As(err, &e) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(e.status)
		_ = json.NewEncoder(w).Encode(map[string]any{"error": map[string]string{"code": e.code, "message": e.message}})
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusInternalServerError)
	_ = json.NewEncoder(w).Encode(map[string]any{"error": map[string]string{"code": "INTERNAL_ERROR", "message": "Finance access request failed."}})
}

func write(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{"data": data})
}

func decode(w http.ResponseWriter, r *http.Request, dst any) error {
	r.Body = http.MaxBytesReader(w, r.Body, 16<<10)
	d := json.NewDecoder(r.Body)
	d.DisallowUnknownFields()
	if err := d.Decode(dst); err != nil {
		return &apiError{400, "VALIDATION_ERROR", "The finance access request is invalid."}
	}
	var extra any
	if err := d.Decode(&extra); err != io.EOF {
		return &apiError{400, "VALIDATION_ERROR", "The finance access request must contain one JSON value."}
	}
	return nil
}

func (s *Service) guard() error {
	if s == nil || s.db == nil || !s.qa {
		return &apiError{404, "NOT_FOUND", "Finance access management is available only in isolated QA."}
	}
	return nil
}

func authorize(ctx context.Context, tx *sqlx.Tx, actor string) error {
	if err := financialledger.AuthorizeTx(ctx, tx, actor, "finance.configure"); err != nil {
		return &apiError{403, "FORBIDDEN", "Finance configuration permission is required."}
	}
	return nil
}

func (s *Service) List(w http.ResponseWriter, r *http.Request, actor string) {
	if err := s.guard(); err != nil {
		fail(w, err)
		return
	}
	var rows []map[string]any
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := authorize(r.Context(), tx, actor); err != nil {
			return err
		}
		var err error
		rows, err = query(r.Context(), tx, `SELECT q.id::text,q.target_user_id::text,q.permission,q.requested_by::text,q.reason,q.status,q.decided_by::text,q.decision_reason,q.grant_id::text,q.created_at::text,q.decided_at::text FROM financial_access_grant_requests q ORDER BY q.created_at DESC LIMIT 200`)
		return err
	})
	if err != nil {
		fail(w, err)
		return
	}
	write(w, 200, rows)
}

type requestBody struct {
	TargetUserID string `json:"target_user_id"`
	Permission   string `json:"permission"`
	Reason       string `json:"reason"`
}

func (s *Service) Create(w http.ResponseWriter, r *http.Request, actor string) {
	if err := s.guard(); err != nil {
		fail(w, err)
		return
	}
	var body requestBody
	if err := decode(w, r, &body); err != nil {
		fail(w, err)
		return
	}
	body.TargetUserID = strings.TrimSpace(body.TargetUserID)
	body.Permission = strings.TrimSpace(body.Permission)
	body.Reason = strings.TrimSpace(body.Reason)
	if _, err := uuid.Parse(body.TargetUserID); err != nil || (body.Permission != "finance.read" && body.Permission != "finance.post") || len(body.Reason) < 10 || len(body.Reason) > 500 || actor == body.TargetUserID {
		fail(w, &apiError{400, "VALIDATION_ERROR", "Target, limited permission, or reason is invalid."})
		return
	}
	var id string
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := authorize(r.Context(), tx, actor); err != nil {
			return err
		}
		var targetAdmin bool
		if err := tx.GetContext(r.Context(), &targetAdmin, `SELECT EXISTS(SELECT 1 FROM users u JOIN user_roles r ON r.user_id=u.id AND r.role='admin' WHERE u.id=$1 AND u.status='active')`, body.TargetUserID); err != nil {
			return err
		}
		if !targetAdmin {
			return &apiError{404, "TARGET_NOT_FOUND", "The target must be an active Admin account."}
		}
		var active bool
		if err := tx.GetContext(r.Context(), &active, `SELECT EXISTS(SELECT 1 FROM financial_access_grants WHERE user_id=$1 AND permission=$2 AND revoked_at IS NULL)`, body.TargetUserID, body.Permission); err != nil {
			return err
		}
		if active {
			return &apiError{409, "ALREADY_GRANTED", "The target already has this active permission."}
		}
		if err := tx.QueryRowxContext(r.Context(), `INSERT INTO financial_access_grant_requests(target_user_id,permission,requested_by,reason) VALUES($1,$2,$3,$4) RETURNING id::text`, body.TargetUserID, body.Permission, actor, body.Reason).Scan(&id); err != nil {
			return err
		}
		_, err := tx.ExecContext(r.Context(), `INSERT INTO financial_audit_events(actor_user_id,event_type,grant_request_id,reason,metadata) VALUES($1,'access_grant_requested',$2,$3,jsonb_build_object('target_user_id',$4::text,'permission',$5::text))`, actor, id, body.Reason, body.TargetUserID, body.Permission)
		return err
	})
	if err != nil {
		fail(w, err)
		return
	}
	write(w, 201, map[string]string{"id": id, "status": "pending"})
}

type decisionBody struct {
	Decision string `json:"decision"`
	Reason   string `json:"reason"`
}

func (s *Service) Decide(w http.ResponseWriter, r *http.Request, actor, requestID string) {
	if err := s.guard(); err != nil {
		fail(w, err)
		return
	}
	var body decisionBody
	if err := decode(w, r, &body); err != nil {
		fail(w, err)
		return
	}
	body.Decision = strings.TrimSpace(body.Decision)
	body.Reason = strings.TrimSpace(body.Reason)
	if _, err := uuid.Parse(requestID); err != nil || (body.Decision != "approve" && body.Decision != "reject") || len(body.Reason) < 10 || len(body.Reason) > 500 {
		fail(w, &apiError{400, "VALIDATION_ERROR", "Decision or reason is invalid."})
		return
	}
	var grantID string
	err := s.db.Transaction(r.Context(), func(tx *sqlx.Tx) error {
		if err := authorize(r.Context(), tx, actor); err != nil {
			return err
		}
		var req struct {
			Target     string `db:"target_user_id"`
			Permission string `db:"permission"`
			Issuer     string `db:"requested_by"`
			Reason     string `db:"reason"`
			Status     string `db:"status"`
		}
		if err := tx.GetContext(r.Context(), &req, `SELECT target_user_id::text,permission,requested_by::text,reason,status FROM financial_access_grant_requests WHERE id=$1 FOR UPDATE`, requestID); err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return &apiError{404, "NOT_FOUND", "Finance access request was not found."}
			}
			return err
		}
		if req.Status != "pending" {
			return &apiError{409, "REQUEST_RESOLVED", "This access request was already resolved."}
		}
		if actor == req.Issuer || actor == req.Target {
			return &apiError{403, "SEPARATION_OF_DUTIES", "A different Finance administrator must decide this request."}
		}
		var targetAdmin bool
		if err := tx.GetContext(r.Context(), &targetAdmin, `SELECT EXISTS(SELECT 1 FROM users u JOIN user_roles r ON r.user_id=u.id AND r.role='admin' WHERE u.id=$1 AND u.status='active')`, req.Target); err != nil {
			return err
		}
		if !targetAdmin {
			return &apiError{409, "TARGET_INACTIVE", "The target is no longer an active Admin."}
		}
		status := "rejected"
		if body.Decision == "approve" {
			var active bool
			if err := tx.GetContext(r.Context(), &active, `SELECT EXISTS(SELECT 1 FROM financial_access_grants WHERE user_id=$1 AND permission=$2 AND revoked_at IS NULL)`, req.Target, req.Permission); err != nil {
				return err
			}
			if active {
				return &apiError{409, "ALREADY_GRANTED", "The target already has this active permission."}
			}
			if err := tx.QueryRowxContext(r.Context(), `INSERT INTO financial_access_grants(user_id,permission,granted_by,approved_by,reason) VALUES($1,$2,$3,$4,$5) RETURNING id::text`, req.Target, req.Permission, req.Issuer, actor, req.Reason).Scan(&grantID); err != nil {
				return err
			}
			status = "approved"
		}
		_, err := tx.ExecContext(r.Context(), `UPDATE financial_access_grant_requests SET status=$2,decided_by=$3,decision_reason=$4,grant_id=NULLIF($5,'')::uuid,decided_at=now() WHERE id=$1`, requestID, status, actor, body.Reason, grantID)
		if err != nil {
			return err
		}
		_, err = tx.ExecContext(r.Context(), `INSERT INTO financial_audit_events(actor_user_id,event_type,grant_request_id,grant_id,reason,metadata) VALUES($1,$2,$3,NULLIF($4,'')::uuid,$5,jsonb_build_object('target_user_id',$6::text,'permission',$7::text))`, actor, "access_grant_"+status, requestID, grantID, body.Reason, req.Target, req.Permission)
		return err
	})
	if err != nil {
		fail(w, err)
		return
	}
	write(w, 200, map[string]string{"request_id": requestID, "status": body.Decision, "grant_id": grantID})
}

func query(ctx context.Context, tx *sqlx.Tx, sql string) ([]map[string]any, error) {
	rows, err := tx.QueryxContext(ctx, sql)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]map[string]any, 0)
	for rows.Next() {
		row := map[string]any{}
		if err := rows.MapScan(row); err != nil {
			return nil, err
		}
		for k, v := range row {
			if b, ok := v.([]byte); ok {
				row[k] = string(b)
			}
		}
		out = append(out, row)
	}
	return out, rows.Err()
}
