package riders

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"

	"github.com/google/uuid"
	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"

	"grepmind-near/backend/pkg/config"
	"grepmind-near/backend/pkg/database"
)

const maxDocumentBytes = 8 << 20

type Service struct {
	db     *database.DB
	store  *minio.Client
	bucket string
}

func NewService(db *database.DB, cfg *config.Config) (*Service, error) {
	s := &Service{db: db, bucket: cfg.S3PrivateBucket}
	if s.bucket == "" || s.bucket == cfg.S3Bucket {
		return nil, fmt.Errorf("rider document bucket must be configured separately from public media bucket")
	}
	endpoint := strings.TrimPrefix(strings.TrimPrefix(cfg.S3Endpoint, "http://"), "https://")
	c, err := minio.New(endpoint, &minio.Options{Creds: credentials.NewStaticV4(cfg.S3AccessKey, cfg.S3SecretKey, ""), Secure: cfg.S3UseSSL})
	if err != nil {
		return nil, err
	}
	s.store = c
	return s, nil
}

type envelope map[string]any

func write(w http.ResponseWriter, code int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(body)
}
func fail(w http.ResponseWriter, code int, message string) {
	write(w, code, envelope{"error": envelope{"code": "REQUEST_FAILED", "message": message}})
}

func (s *Service) OwnApplication(w http.ResponseWriter, r *http.Request, userID string) {
	var raw string
	err := s.db.GetContext(r.Context(), &raw, `SELECT (to_jsonb(p) || jsonb_build_object('field_executive_code', COALESCE(fe.executive_code,''), 'field_executive_name', COALESCE(fe.display_name,''), 'localities', COALESCE((SELECT jsonb_agg(jsonb_build_object('locality_id',l.locality_id,'name',d.name,'status',l.status)) FROM rider_profile_localities l JOIN platform_delivery_localities d ON d.id=l.locality_id WHERE l.rider_profile_id=p.id),'[]'::jsonb), 'documents', COALESCE((SELECT jsonb_agg(jsonb_build_object('id',x.id,'requirement_id',x.requirement_id,'review_status',x.review_status,'rejection_reason',x.rejection_reason,'uploaded_at',x.uploaded_at)) FROM rider_documents x WHERE x.rider_profile_id=p.id),'[]'::jsonb)))::text FROM rider_profiles p LEFT JOIN field_executives fe ON fe.id=p.field_executive_id WHERE p.user_id=$1`, userID)
	if err == sql.ErrNoRows {
		write(w, 200, envelope{"data": nil})
		return
	}
	if err != nil {
		fail(w, 500, "Unable to load rider application.")
		return
	}
	var out map[string]any
	if json.Unmarshal([]byte(raw), &out) != nil {
		fail(w, 500, "Unable to read rider application.")
		return
	}
	write(w, 200, envelope{"data": out})
}

func (s *Service) Requirements(w http.ResponseWriter, r *http.Request, _ string) {
	rows, err := queryMaps(r.Context(), s.db, `SELECT id,code,label,vehicle_type,is_required FROM rider_document_requirements WHERE is_active ORDER BY label`)
	if err != nil {
		fail(w, 500, "Unable to load verification requirements.")
		return
	}
	write(w, 200, envelope{"data": rows})
}

func (s *Service) Localities(w http.ResponseWriter, r *http.Request, _ string) {
	rows, err := queryMaps(r.Context(), s.db, `SELECT l.id,l.name,d.name AS district FROM platform_delivery_localities l JOIN platform_districts d ON d.id=l.district_id WHERE l.is_active AND l.delivery_enabled ORDER BY d.name,l.name`)
	if err != nil {
		fail(w, 500, "Unable to load supported service localities.")
		return
	}
	write(w, 200, envelope{"data": rows})
}

func (s *Service) SaveDraft(w http.ResponseWriter, r *http.Request, userID string) {
	var in struct {
		DisplayName        string   `json:"display_name"`
		VehicleType        string   `json:"vehicle_type"`
		VehicleDetails     string   `json:"vehicle_details"`
		Address            string   `json:"address"`
		OnboardingSource   string   `json:"onboarding_source"`
		FieldExecutiveCode string   `json:"field_executive_code"`
		LocalityIDs        []string `json:"locality_ids"`
	}
	if json.NewDecoder(http.MaxBytesReader(w, r.Body, 32<<10)).Decode(&in) != nil || len(in.LocalityIDs) == 0 || len(in.LocalityIDs) > 10 || len(strings.TrimSpace(in.DisplayName)) < 2 || len(in.DisplayName) > 120 || len(in.VehicleDetails) > 500 || len(in.Address) > 500 {
		fail(w, 400, "Provide a name, vehicle type, valid address, and one to ten supported localities.")
		return
	}
	if !oneOf(in.VehicleType, "bicycle", "two_wheeler", "three_wheeler", "other") {
		fail(w, 400, "Unsupported vehicle type.")
		return
	}
	source := strings.TrimSpace(in.OnboardingSource)
	if source == "" {
		source = "self"
	}
	if !oneOf(source, "self", "field_executive") {
		fail(w, 400, "Unsupported onboarding source.")
		return
	}
	var fieldExecID *string
	if source == "field_executive" {
		code := strings.ToUpper(strings.TrimSpace(in.FieldExecutiveCode))
		if code == "" {
			fail(w, 400, "Enter or select a valid Field Executive ID (AFE-1000).")
			return
		}
		var feID string
		if err := s.db.GetContext(r.Context(), &feID, `SELECT id::text FROM field_executives WHERE UPPER(executive_code)=$1 AND is_active=true`, code); err != nil {
			fail(w, 400, "Active Field Executive ID not found.")
			return
		}
		fieldExecID = &feID
	}
	tx, err := s.db.BeginTxx(r.Context(), nil)
	if err != nil {
		fail(w, 500, "Unable to save application.")
		return
	}
	defer tx.Rollback()
	var id, status string
	err = tx.QueryRowxContext(r.Context(), `INSERT INTO rider_profiles(user_id,display_name,vehicle_type,vehicle_details,address,onboarding_source,field_executive_id,status) VALUES($1,$2,$3,$4,$5,$6,$7,'draft') ON CONFLICT(user_id) DO UPDATE SET display_name=EXCLUDED.display_name,vehicle_type=EXCLUDED.vehicle_type,vehicle_details=EXCLUDED.vehicle_details,address=EXCLUDED.address,onboarding_source=EXCLUDED.onboarding_source,field_executive_id=EXCLUDED.field_executive_id,updated_at=now() WHERE rider_profiles.status IN ('draft','changes_requested','rejected') RETURNING id,status`, userID, strings.TrimSpace(in.DisplayName), in.VehicleType, strings.TrimSpace(in.VehicleDetails), strings.TrimSpace(in.Address), source, fieldExecID).Scan(&id, &status)
	if err != nil {
		fail(w, 409, "This application cannot be edited in its current state.")
		return
	}
	if _, err = tx.ExecContext(r.Context(), `DELETE FROM rider_profile_localities WHERE rider_profile_id=$1 AND status<>'approved'`, id); err != nil {
		fail(w, 500, "Unable to update localities.")
		return
	}
	for _, raw := range in.LocalityIDs {
		loc, parseErr := uuid.Parse(raw)
		if parseErr != nil {
			fail(w, 400, "Invalid locality identifier.")
			return
		}
		res, e := tx.ExecContext(r.Context(), `INSERT INTO rider_profile_localities(rider_profile_id,locality_id,status) SELECT $1,id,'requested' FROM platform_delivery_localities WHERE id=$2 AND delivery_enabled=true ON CONFLICT(rider_profile_id,locality_id) DO UPDATE SET status='requested' WHERE rider_profile_localities.status<>'approved'`, id, loc)
		if e != nil {
			fail(w, 400, "Locality is not currently enabled for delivery.")
			return
		}
		n, _ := res.RowsAffected()
		if n == 0 {
			fail(w, 400, "Locality is not currently enabled for delivery.")
			return
		}
	}
	_, _ = tx.ExecContext(r.Context(), `INSERT INTO rider_application_events(rider_profile_id,actor_user_id,event_type) VALUES($1,$2,'created')`, id, userID)
	if err = tx.Commit(); err != nil {
		fail(w, 500, "Unable to save application.")
		return
	}
	s.OwnApplication(w, r, userID)
}

func (s *Service) Submit(w http.ResponseWriter, r *http.Request, userID string) {
	tx, err := s.db.BeginTxx(r.Context(), nil)
	if err != nil {
		fail(w, 500, "Unable to submit application.")
		return
	}
	defer tx.Rollback()
	var id string
	if err = tx.GetContext(r.Context(), &id, `SELECT id FROM rider_profiles WHERE user_id=$1 AND status IN ('draft','changes_requested','rejected') FOR UPDATE`, userID); err != nil {
		fail(w, 409, "Save a draft before submitting.")
		return
	}
	var localityCount int
	_ = tx.GetContext(r.Context(), &localityCount, `SELECT count(*) FROM rider_profile_localities WHERE rider_profile_id=$1 AND status='requested'`, id)
	if localityCount == 0 {
		fail(w, 400, "Select at least one supported locality.")
		return
	}
	var missing int
	err = tx.GetContext(r.Context(), &missing, `SELECT count(*) FROM rider_document_requirements q WHERE q.is_active AND q.is_required AND q.vehicle_type IN ('any',(SELECT vehicle_type FROM rider_profiles WHERE id=$1)) AND NOT EXISTS(SELECT 1 FROM rider_documents d WHERE d.rider_profile_id=$1 AND d.requirement_id=q.id AND d.review_status IN ('pending','accepted'))`, id)
	if err != nil {
		fail(w, 500, "Unable to validate documents.")
		return
	}
	if missing > 0 {
		fail(w, 400, "Upload each configured required document before submitting.")
		return
	}
	_, err = tx.ExecContext(r.Context(), `UPDATE rider_profiles SET status='submitted',submitted_at=now(),updated_at=now() WHERE id=$1`, id)
	if err == nil {
		_, err = tx.ExecContext(r.Context(), `INSERT INTO rider_application_events(rider_profile_id,actor_user_id,event_type) VALUES($1,$2,'submitted')`, id, userID)
	}
	if err != nil || tx.Commit() != nil {
		fail(w, 500, "Unable to submit application.")
		return
	}
	s.OwnApplication(w, r, userID)
}

func (s *Service) UploadDocument(w http.ResponseWriter, r *http.Request, userID string) {
	r.Body = http.MaxBytesReader(w, r.Body, maxDocumentBytes+64<<10)
	if err := r.ParseMultipartForm(maxDocumentBytes); err != nil {
		fail(w, 413, "Document exceeds the 8 MB limit.")
		return
	}
	f, h, err := r.FormFile("file")
	if err != nil {
		fail(w, 400, "Choose a document image.")
		return
	}
	defer f.Close()
	body, err := io.ReadAll(io.LimitReader(f, maxDocumentBytes+1))
	if err != nil || len(body) == 0 || len(body) > maxDocumentBytes {
		fail(w, 413, "Document exceeds the 8 MB limit.")
		return
	}
	content := http.DetectContentType(body[:min(len(body), 512)])
	ext := map[string]string{"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp"}[content]
	if ext == "" {
		fail(w, 415, "Only JPEG, PNG, or WebP document images are supported.")
		return
	}
	var profileID, requirementID string
	err = s.db.QueryRowxContext(r.Context(), `SELECT p.id,q.id FROM rider_profiles p JOIN rider_document_requirements q ON q.code=$2 AND q.is_active AND q.vehicle_type IN ('any',p.vehicle_type) WHERE p.user_id=$1 AND p.status IN ('draft','changes_requested','rejected')`, userID, r.FormValue("requirement_code")).Scan(&profileID, &requirementID)
	if err != nil {
		fail(w, 400, "Unknown requirement or application is not editable.")
		return
	}
	if s.store == nil {
		fail(w, 503, "Private document storage is unavailable.")
		return
	}
	if err = s.ensurePrivateBucket(r.Context()); err != nil {
		fail(w, 503, "Private document storage is not safely configured.")
		return
	}
	key := fmt.Sprintf("rider-kyc/%s/%s%s", profileID, uuid.NewString(), ext)
	digest := sha256.Sum256(body)
	if _, err = s.store.PutObject(r.Context(), s.bucket, key, strings.NewReader(string(body)), int64(len(body)), minio.PutObjectOptions{ContentType: content}); err != nil {
		fail(w, 503, "Unable to store verification document.")
		return
	}
	tx, err := s.db.BeginTxx(r.Context(), nil)
	if err != nil {
		_ = s.store.RemoveObject(r.Context(), s.bucket, key, minio.RemoveObjectOptions{})
		fail(w, 500, "Unable to save document record.")
		return
	}
	defer tx.Rollback()
	_, err = tx.ExecContext(r.Context(), `UPDATE rider_documents SET review_status='superseded' WHERE rider_profile_id=$1 AND requirement_id=$2 AND review_status IN ('pending','rejected','accepted')`, profileID, requirementID)
	if err == nil {
		_, err = tx.ExecContext(r.Context(), `INSERT INTO rider_documents(rider_profile_id,requirement_id,bucket,object_key,content_type,size_bytes,sha256) VALUES($1,$2,$3,$4,$5,$6,$7)`, profileID, requirementID, s.bucket, key, content, int64(len(body)), digest[:])
	}
	if err != nil {
		_ = s.store.RemoveObject(r.Context(), s.bucket, key, minio.RemoveObjectOptions{})
		fail(w, 500, "Unable to save document record.")
		return
	}
	if err = tx.Commit(); err != nil {
		_ = s.store.RemoveObject(r.Context(), s.bucket, key, minio.RemoveObjectOptions{})
		fail(w, 500, "Unable to save document record.")
		return
	}
	_ = h
	s.OwnApplication(w, r, userID)
}

func (s *Service) ensurePrivateBucket(ctx context.Context) error {
	exists, err := s.store.BucketExists(ctx, s.bucket)
	if err != nil {
		return err
	}
	if !exists {
		if err = s.store.MakeBucket(ctx, s.bucket, minio.MakeBucketOptions{}); err != nil {
			return err
		}
	}
	policy, err := s.store.GetBucketPolicy(ctx, s.bucket)
	if err == nil && strings.Contains(strings.ToLower(policy), `"principal"`) && strings.Contains(policy, "*") {
		return fmt.Errorf("private bucket policy permits public access")
	}
	if err != nil {
		lower := strings.ToLower(err.Error())
		if !strings.Contains(lower, "policy") && !strings.Contains(lower, "not found") && !strings.Contains(lower, "access denied") {
			return err
		}
	}
	return nil
}

func (s *Service) AdminList(w http.ResponseWriter, r *http.Request, _ string) {
	status := r.URL.Query().Get("status")
	if status != "" && !oneOf(status, "draft", "submitted", "under_review", "changes_requested", "approved", "rejected", "suspended") {
		fail(w, 400, "Invalid rider status filter.")
		return
	}
	rows, err := queryMaps(r.Context(), s.db, `SELECT p.id,p.rider_code,p.user_id,p.display_name,p.vehicle_type,p.vehicle_details,p.address,p.onboarding_source,COALESCE(fe.executive_code,'') AS field_executive_code,COALESCE(fe.display_name,'') AS field_executive_name,p.status,p.review_notes,p.submitted_at,p.approved_at,p.created_at,u.phone_e164,COALESCE(ra.is_online AND ra.lease_expires_at > now(), false) AS is_online,ra.lease_expires_at AS availability_expires_at,ra.last_heartbeat_at FROM rider_profiles p JOIN users u ON u.id=p.user_id LEFT JOIN field_executives fe ON fe.id=p.field_executive_id LEFT JOIN rider_availability_sessions ra ON ra.rider_user_id=p.user_id WHERE ($1='' OR p.status=$1) ORDER BY p.updated_at DESC LIMIT 200`, status)
	if err != nil {
		fail(w, 500, "Unable to list rider applications.")
		return
	}
	write(w, 200, envelope{"data": rows})
}

func (s *Service) AdminDetail(w http.ResponseWriter, r *http.Request, _ string) {
	id := r.PathValue("id")
	rows, err := queryMaps(r.Context(), s.db, `SELECT p.id,p.rider_code,p.user_id,p.display_name,p.vehicle_type,p.vehicle_details,p.address,p.onboarding_source,COALESCE(fe.executive_code,'') AS field_executive_code,COALESCE(fe.display_name,'') AS field_executive_name,p.status,p.review_notes,p.submitted_at,p.approved_at,p.created_at,u.phone_e164,COALESCE(ra.is_online AND ra.lease_expires_at > now(), false) AS is_online,ra.lease_expires_at AS availability_expires_at,ra.last_heartbeat_at FROM rider_profiles p JOIN users u ON u.id=p.user_id LEFT JOIN field_executives fe ON fe.id=p.field_executive_id LEFT JOIN rider_availability_sessions ra ON ra.rider_user_id=p.user_id WHERE p.id=$1`, id)
	if err != nil || len(rows) == 0 {
		fail(w, 404, "Rider application not found.")
		return
	}
	data := rows[0]
	data["localities"], err = queryMaps(r.Context(), s.db, `SELECT rl.locality_id,l.name,d.name AS district,rl.status FROM rider_profile_localities rl JOIN platform_delivery_localities l ON l.id=rl.locality_id JOIN platform_districts d ON d.id=l.district_id WHERE rl.rider_profile_id=$1 ORDER BY d.name,l.name`, id)
	if err == nil {
		data["documents"], err = queryMaps(r.Context(), s.db, `SELECT d.id,q.code,q.label,d.content_type,d.size_bytes,d.review_status,d.rejection_reason,d.uploaded_at FROM rider_documents d JOIN rider_document_requirements q ON q.id=d.requirement_id WHERE d.rider_profile_id=$1 ORDER BY d.uploaded_at DESC`, id)
	}
	if err == nil {
		data["history"], err = queryMaps(r.Context(), s.db, `SELECT e.event_type,e.reason,e.created_at,u.display_name AS actor_name FROM rider_application_events e LEFT JOIN users u ON u.id=e.actor_user_id WHERE e.rider_profile_id=$1 ORDER BY e.created_at DESC LIMIT 100`, id)
	}
	if err != nil {
		fail(w, 500, "Unable to load rider review.")
		return
	}
	write(w, 200, envelope{"data": data})
}

func (s *Service) AdminReviewDocument(w http.ResponseWriter, r *http.Request, adminID string) {
	id := r.PathValue("id")
	var in struct {
		Status string `json:"status"`
		Reason string `json:"reason"`
	}
	if json.NewDecoder(http.MaxBytesReader(w, r.Body, 8<<10)).Decode(&in) != nil || !oneOf(in.Status, "accepted", "rejected") || (in.Status == "rejected" && (len(strings.TrimSpace(in.Reason)) < 10 || len(in.Reason) > 500)) {
		fail(w, 400, "Choose accepted or rejected and provide a reason for rejection.")
		return
	}
	tx, e := s.db.BeginTxx(r.Context(), nil)
	if e != nil {
		fail(w, 500, "Unable to review document.")
		return
	}
	defer tx.Rollback()
	var profileID string
	e = tx.QueryRowxContext(r.Context(), `UPDATE rider_documents SET review_status=$1,rejection_reason=NULLIF($2,''),reviewed_by=$3,reviewed_at=now() WHERE id=$4 AND review_status IN ('pending','rejected') RETURNING rider_profile_id`, in.Status, strings.TrimSpace(in.Reason), adminID, id).Scan(&profileID)
	if e != nil {
		fail(w, 404, "Pending rider document not found.")
		return
	}
	_, e = tx.ExecContext(r.Context(), `INSERT INTO rider_application_events(rider_profile_id,actor_user_id,event_type,reason,metadata) VALUES($1,$2,'document_reviewed',NULLIF($3,''),jsonb_build_object('document_id',$4::text,'status',$5::text))`, profileID, adminID, in.Reason, id, in.Status)
	if e != nil {
		fail(w, 500, "Unable to record document review history.")
		return
	}
	if e == nil {
		_, e = tx.ExecContext(r.Context(), `INSERT INTO audit_logs(actor_user_id,action,target_type,target_id,reason) VALUES($1,$2,'rider_profile',$3,NULLIF($4,''))`, adminID, "rider.document."+in.Status, profileID, in.Reason)
	}
	if e != nil {
		fail(w, 500, "Unable to write document audit record.")
		return
	}
	if tx.Commit() != nil {
		fail(w, 500, "Unable to commit document review.")
		return
	}
	write(w, 200, envelope{"data": envelope{"id": id, "review_status": in.Status}})
}

func (s *Service) AdminRequirement(w http.ResponseWriter, r *http.Request, adminID string) {
	var in struct {
		Code        string `json:"code"`
		Label       string `json:"label"`
		VehicleType string `json:"vehicle_type"`
		Required    bool   `json:"is_required"`
		Active      bool   `json:"is_active"`
	}
	if json.NewDecoder(http.MaxBytesReader(w, r.Body, 8<<10)).Decode(&in) != nil || !oneOf(in.VehicleType, "any", "bicycle", "two_wheeler", "three_wheeler", "other") || len(strings.TrimSpace(in.Code)) < 2 || len(in.Code) > 64 || len(strings.TrimSpace(in.Label)) < 2 || len(in.Label) > 120 {
		fail(w, 400, "Provide a code, label, and valid vehicle type.")
		return
	}
	tx, err := s.db.BeginTxx(r.Context(), nil)
	if err != nil {
		fail(w, 500, "Unable to save verification requirement.")
		return
	}
	defer tx.Rollback()
	var id string
	err = tx.QueryRowxContext(r.Context(), `INSERT INTO rider_document_requirements(code,label,vehicle_type,is_required,is_active,created_by) VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT(code) DO UPDATE SET label=EXCLUDED.label,vehicle_type=EXCLUDED.vehicle_type,is_required=EXCLUDED.is_required,is_active=EXCLUDED.is_active,updated_at=now() RETURNING id`, strings.ToLower(strings.TrimSpace(in.Code)), strings.TrimSpace(in.Label), in.VehicleType, in.Required, in.Active, adminID).Scan(&id)
	if err != nil {
		fail(w, 400, "Unable to save verification requirement.")
		return
	}
	_, err = tx.ExecContext(r.Context(), `INSERT INTO audit_logs(actor_user_id,action,target_type,target_id) VALUES($1,'rider.requirement.updated','rider_document_requirement',$2)`, adminID, id)
	if err != nil || tx.Commit() != nil {
		fail(w, 500, "Unable to record verification policy change.")
		return
	}
	write(w, 200, envelope{"data": envelope{"id": id, "code": in.Code}})
}

func (s *Service) AdminRequirements(w http.ResponseWriter, r *http.Request, _ string) {
	rows, err := queryMaps(r.Context(), s.db, `SELECT id,code,label,vehicle_type,is_required,is_active,updated_at FROM rider_document_requirements ORDER BY label`)
	if err != nil {
		fail(w, 500, "Unable to load verification requirements.")
		return
	}
	write(w, 200, envelope{"data": rows})
}

func (s *Service) AdminReview(w http.ResponseWriter, r *http.Request, adminID string) {
	profileID := r.PathValue("id")
	var in struct {
		Decision    string   `json:"decision"`
		Reason      string   `json:"reason"`
		LocalityIDs []string `json:"approved_locality_ids"`
	}
	if json.NewDecoder(http.MaxBytesReader(w, r.Body, 16<<10)).Decode(&in) != nil || !oneOf(in.Decision, "under_review", "changes_requested", "approved", "rejected") {
		fail(w, 400, "Invalid review decision.")
		return
	}
	if (in.Decision == "changes_requested" || in.Decision == "rejected") && (len(strings.TrimSpace(in.Reason)) < 10 || len(in.Reason) > 500) {
		fail(w, 400, "A review reason of 10 to 500 characters is required.")
		return
	}
	if in.Decision == "approved" && len(in.LocalityIDs) == 0 {
		fail(w, 400, "Approve at least one requested locality.")
		return
	}
	tx, err := s.db.BeginTxx(r.Context(), nil)
	if err != nil {
		fail(w, 500, "Unable to review application.")
		return
	}
	defer tx.Rollback()
	var owner, status string
	if err = tx.QueryRowxContext(r.Context(), `SELECT user_id,status FROM rider_profiles WHERE id=$1 FOR UPDATE`, profileID).Scan(&owner, &status); err != nil {
		fail(w, 404, "Rider application not found.")
		return
	}
	if owner == adminID {
		fail(w, 403, "An administrator cannot review their own rider application.")
		return
	}
	if !oneOf(status, "submitted", "under_review", "changes_requested") {
		fail(w, 409, "Application is not reviewable.")
		return
	}
	if in.Decision == "approved" {
		var pending, locCount, missing int
		_ = tx.GetContext(r.Context(), &pending, `SELECT count(*) FROM rider_documents WHERE rider_profile_id=$1 AND review_status IN ('pending','rejected')`, profileID)
		if pending > 0 {
			fail(w, 409, "Review all submitted documents before approval.")
			return
		}
		_ = tx.GetContext(r.Context(), &missing, `SELECT count(*) FROM rider_document_requirements q JOIN rider_profiles p ON p.id=$1 WHERE q.is_active AND q.is_required AND q.vehicle_type IN ('any',p.vehicle_type) AND NOT EXISTS(SELECT 1 FROM rider_documents d WHERE d.rider_profile_id=p.id AND d.requirement_id=q.id AND d.review_status='accepted')`, profileID)
		if missing > 0 {
			fail(w, 409, "Required verification documents have not been accepted.")
			return
		}
		for _, raw := range in.LocalityIDs {
			loc, e := uuid.Parse(raw)
			if e != nil {
				fail(w, 400, "Invalid locality identifier.")
				return
			}
			res, e := tx.ExecContext(r.Context(), `UPDATE rider_profile_localities rl SET status='approved',reviewed_by=$3,reviewed_at=now() FROM platform_delivery_localities l WHERE rl.rider_profile_id=$1 AND rl.locality_id=$2 AND l.id=rl.locality_id AND l.delivery_enabled AND rl.status='requested'`, profileID, loc, adminID)
			if e != nil {
				fail(w, 400, "Unable to approve requested locality.")
				return
			}
			n, _ := res.RowsAffected()
			if n != 1 {
				fail(w, 400, "Only enabled localities requested by this rider can be approved.")
				return
			}
			locCount++
		}
		if locCount == 0 {
			fail(w, 400, "Approve at least one locality.")
			return
		}
	}
	// Once an application is approved, any requested locality omitted by the
	// reviewer is explicitly denied instead of being left pending indefinitely.
	_, err = tx.ExecContext(r.Context(), `UPDATE rider_profile_localities SET status='rejected',reviewed_by=$2,reviewed_at=now() WHERE rider_profile_id=$1 AND status='requested' AND $3 IN ('approved','rejected','changes_requested')`, profileID, adminID, in.Decision)
	if err == nil {
		_, err = tx.ExecContext(r.Context(), `UPDATE rider_profiles SET status=$1,review_notes=NULLIF($2,''),reviewed_by=$3,approved_at=CASE WHEN $1='approved' THEN now() ELSE approved_at END,updated_at=now() WHERE id=$4`, in.Decision, strings.TrimSpace(in.Reason), adminID, profileID)
	}
	if err == nil && in.Decision == "approved" {
		_, err = tx.ExecContext(r.Context(), `INSERT INTO user_roles(user_id,role) SELECT $1,'rider' WHERE NOT EXISTS(SELECT 1 FROM user_roles WHERE user_id=$1 AND role='rider')`, owner)
	}
	eventType := in.Decision
	if eventType == "under_review" {
		eventType = "review_started"
	}
	if err == nil {
		_, err = tx.ExecContext(r.Context(), `INSERT INTO rider_application_events(rider_profile_id,actor_user_id,event_type,reason) VALUES($1,$2,$3,NULLIF($4,''))`, profileID, adminID, eventType, in.Reason)
	}
	if err == nil {
		_, err = tx.ExecContext(r.Context(), `INSERT INTO audit_logs(actor_user_id,action,target_type,target_id,reason) VALUES($1,$2,'rider_profile',$3,NULLIF($4,''))`, adminID, "rider."+in.Decision, profileID, in.Reason)
	}
	if err != nil {
		fail(w, 500, "Review transaction failed.")
		return
	}
	if err = tx.Commit(); err != nil {
		fail(w, 500, "Review transaction failed.")
		return
	}
	write(w, 200, envelope{"data": envelope{"id": profileID, "status": in.Decision}})
}

func (s *Service) AdminSuspend(w http.ResponseWriter, r *http.Request, adminID string) {
	var in struct {
		Reason string `json:"reason"`
	}
	if json.NewDecoder(http.MaxBytesReader(w, r.Body, 8<<10)).Decode(&in) != nil || len(strings.TrimSpace(in.Reason)) < 10 || len(in.Reason) > 500 {
		fail(w, 400, "A suspension reason of 10 to 500 characters is required.")
		return
	}
	id := r.PathValue("id")
	tx, e := s.db.BeginTxx(r.Context(), nil)
	if e != nil {
		fail(w, 500, "Unable to suspend rider.")
		return
	}
	defer tx.Rollback()
	var userID string
	if e = tx.QueryRowxContext(r.Context(), `UPDATE rider_profiles SET status='suspended',review_notes=$1,reviewed_by=$2,suspended_at=now(),updated_at=now() WHERE id=$3 AND status='approved' RETURNING user_id`, strings.TrimSpace(in.Reason), adminID, id).Scan(&userID); e != nil {
		fail(w, 409, "Only an approved rider can be suspended.")
		return
	}
	_, e = tx.ExecContext(r.Context(), `DELETE FROM user_roles WHERE user_id=$1 AND role='rider'`, userID)
	if e == nil {
		_, e = tx.ExecContext(r.Context(), `UPDATE sessions SET revoked_at=now() WHERE user_id=$1 AND revoked_at IS NULL`, userID)
	}
	if e == nil {
		_, e = tx.ExecContext(r.Context(), `INSERT INTO rider_application_events(rider_profile_id,actor_user_id,event_type,reason) VALUES($1,$2,'suspended',$3)`, id, adminID, in.Reason)
	}
	if e == nil {
		_, e = tx.ExecContext(r.Context(), `INSERT INTO audit_logs(actor_user_id,action,target_type,target_id,reason) VALUES($1,'rider.suspended','rider_profile',$2,$3)`, adminID, id, in.Reason)
	}
	if e != nil || tx.Commit() != nil {
		fail(w, 500, "Unable to suspend rider.")
		return
	}
	write(w, 200, envelope{"data": envelope{"id": id, "status": "suspended"}})
}

func (s *Service) AdminReactivate(w http.ResponseWriter, r *http.Request, adminID string) {
	id := r.PathValue("id")
	tx, e := s.db.BeginTxx(r.Context(), nil)
	if e != nil {
		fail(w, 500, "Unable to reactivate rider.")
		return
	}
	defer tx.Rollback()
	var owner string
	if e = tx.QueryRowxContext(r.Context(), `SELECT user_id FROM rider_profiles WHERE id=$1 AND status='suspended' FOR UPDATE`, id).Scan(&owner); e != nil {
		fail(w, 409, "Rider cannot be reactivated.")
		return
	}
	var areas int
	if e = tx.GetContext(r.Context(), &areas, `SELECT count(*) FROM rider_profile_localities WHERE rider_profile_id=$1 AND status='approved'`, id); e != nil || areas == 0 {
		fail(w, 409, "Rider has no approved locality.")
		return
	}
	_, e = tx.ExecContext(r.Context(), `UPDATE rider_profiles SET status='approved',reviewed_by=$1,suspended_at=NULL,review_notes=NULL,updated_at=now() WHERE id=$2`, adminID, id)
	if e == nil {
		_, e = tx.ExecContext(r.Context(), `INSERT INTO user_roles(user_id,role) SELECT $1,'rider' WHERE NOT EXISTS(SELECT 1 FROM user_roles WHERE user_id=$1 AND role='rider')`, owner)
	}
	if e == nil {
		_, e = tx.ExecContext(r.Context(), `INSERT INTO rider_application_events(rider_profile_id,actor_user_id,event_type) VALUES($1,$2,'reactivated')`, id, adminID)
	}
	if e == nil {
		_, e = tx.ExecContext(r.Context(), `INSERT INTO audit_logs(actor_user_id,action,target_type,target_id) VALUES($1,'rider.reactivated','rider_profile',$2)`, adminID, id)
	}
	if e != nil || tx.Commit() != nil {
		fail(w, 500, "Unable to reactivate rider.")
		return
	}
	write(w, 200, envelope{"data": envelope{"id": id, "status": "approved"}})
}

func (s *Service) RiderProfile(w http.ResponseWriter, r *http.Request, userID string) {
	var raw string
	err := s.db.GetContext(r.Context(), &raw, `SELECT jsonb_build_object('id',p.id,'rider_code',p.rider_code,'display_name',p.display_name,'vehicle_type',p.vehicle_type,'vehicle_details',p.vehicle_details,'address',p.address,'onboarding_source',p.onboarding_source,'field_executive_code',COALESCE(fe.executive_code,''),'status',p.status,'approved_localities',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',l.id,'name',l.name,'district',d.name)) FROM rider_profile_localities rl JOIN platform_delivery_localities l ON l.id=rl.locality_id JOIN platform_districts d ON d.id=l.district_id WHERE rl.rider_profile_id=p.id AND rl.status='approved'),'[]'::jsonb))::text FROM rider_profiles p JOIN user_roles ur ON ur.user_id=p.user_id AND ur.role='rider' JOIN users u ON u.id=p.user_id AND u.status='active' LEFT JOIN field_executives fe ON fe.id=p.field_executive_id WHERE p.user_id=$1 AND p.status='approved'`, userID)
	if err != nil {
		fail(w, 403, "Approved rider access is required.")
		return
	}
	var out map[string]any
	if json.Unmarshal([]byte(raw), &out) != nil {
		fail(w, 500, "Unable to load rider profile.")
		return
	}
	write(w, 200, envelope{"data": out})
}

func (s *Service) CanUseRider(ctx context.Context, userID string) bool {
	var ok bool
	err := s.db.GetContext(ctx, &ok, `SELECT EXISTS(SELECT 1 FROM users u JOIN user_roles r ON r.user_id=u.id AND r.role='rider' JOIN rider_profiles p ON p.user_id=u.id AND p.status='approved' WHERE u.id=$1 AND u.status='active')`, userID)
	return err == nil && ok
}
func oneOf(v string, values ...string) bool {
	for _, x := range values {
		if v == x {
			return true
		}
	}
	return false
}
func queryMaps(ctx context.Context, db *database.DB, query string, args ...any) ([]map[string]any, error) {
	rows, err := db.QueryxContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		row := map[string]any{}
		if err = rows.MapScan(row); err != nil {
			return nil, err
		}
		for key, value := range row {
			if bytes, ok := value.([]byte); ok {
				row[key] = string(bytes)
			}
		}
		out = append(out, row)
	}
	return out, rows.Err()
}

// DocumentContent streams the original only to an authenticated admin handler.
func (s *Service) DocumentContent(w http.ResponseWriter, r *http.Request, adminID string) {
	id := r.PathValue("id")
	var bucket, key, content, profileID string
	var size int64
	err := s.db.QueryRowxContext(r.Context(), `SELECT bucket,object_key,content_type,size_bytes,rider_profile_id FROM rider_documents WHERE id=$1`, id).Scan(&bucket, &key, &content, &size, &profileID)
	if err != nil || bucket != s.bucket || s.store == nil {
		fail(w, 404, "Document not found.")
		return
	}
	// KYC document views are sensitive reads. Record the administrator and
	// document ID before streaming content; fail closed if the audit write fails.
	if _, err = s.db.ExecContext(r.Context(), `INSERT INTO audit_logs(actor_user_id,action,target_type,target_id) VALUES($1,'rider.document.accessed','rider_document',$2)`, adminID, id); err != nil {
		fail(w, 500, "Unable to record document access.")
		return
	}
	object, err := s.store.GetObject(r.Context(), bucket, key, minio.GetObjectOptions{})
	if err != nil {
		fail(w, 404, "Document not found.")
		return
	}
	defer object.Close()
	w.Header().Set("Content-Type", content)
	w.Header().Set("Content-Length", fmt.Sprint(size))
	w.Header().Set("Cache-Control", "private, no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	_, _ = io.Copy(w, object)
}
