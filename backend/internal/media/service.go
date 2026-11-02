package media

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"path/filepath"
	"strings"
	"time"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
	"github.com/rs/zerolog/log"

	"grepmind-near/backend/pkg/config"
	"grepmind-near/backend/pkg/database"
)

// Allowed MIME types for media upload
var allowedMIMEs = map[string]string{
	"image/jpeg": ".jpg",
	"image/jpg":  ".jpg",
	"image/png":  ".png",
	"image/webp": ".webp",
}

type MediaUpload struct {
	ID           string    `json:"id" db:"id"`
	UserID       *string   `json:"user_id,omitempty" db:"user_id"`
	Purpose      string    `json:"purpose" db:"purpose"`
	Bucket       string    `json:"bucket" db:"bucket"`
	ObjectKey    string    `json:"object_key" db:"object_key"`
	URL          string    `json:"url"`
	PublicURL    string    `json:"public_url" db:"public_url"`
	ContentType  string    `json:"content_type" db:"content_type"`
	SizeBytes    int64     `json:"size_bytes" db:"size_bytes"`
	OriginalName string    `json:"original_name" db:"original_name"`
	CreatedAt    time.Time `json:"created_at" db:"created_at"`
}

type Service struct {
	db     *database.DB
	cfg    *config.Config
	client *minio.Client
}

type envelope map[string]interface{}

func writeJSON(w http.ResponseWriter, code int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, code int, errCode, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"error": map[string]interface{}{
			"code":       errCode,
			"message":    message,
			"request_id": "err",
		},
	})
}

func NewService(db *database.DB, cfg *config.Config) (*Service, error) {
	endpoint := strings.TrimPrefix(cfg.S3Endpoint, "http://")
	endpoint = strings.TrimPrefix(endpoint, "https://")

	client, err := minio.New(endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(cfg.S3AccessKey, cfg.S3SecretKey, ""),
		Secure: cfg.S3UseSSL,
	})
	if err != nil {
		log.Error().Err(err).Msg("failed to initialize minio client")
		return nil, err
	}

	svc := &Service{
		db:     db,
		cfg:    cfg,
		client: client,
	}

	// Ensure bucket exists in background / startup
	if cfg.IsLocal() {
		go svc.ensureBucket()
	}

	return svc, nil
}

func (s *Service) ensureBucket() {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	exists, err := s.client.BucketExists(ctx, s.cfg.S3Bucket)
	if err != nil {
		log.Warn().Err(err).Str("bucket", s.cfg.S3Bucket).Msg("could not verify minio bucket existence")
		return
	}

	if !exists {
		err = s.client.MakeBucket(ctx, s.cfg.S3Bucket, minio.MakeBucketOptions{Region: s.cfg.S3Region})
		if err != nil {
			log.Warn().Err(err).Str("bucket", s.cfg.S3Bucket).Msg("failed to create minio bucket")
			return
		}
		log.Info().Str("bucket", s.cfg.S3Bucket).Msg("created minio bucket")
	}

	// Set public read bucket policy so /media/ proxy can serve images
	policy := fmt.Sprintf(`{
		"Version": "2012-10-17",
		"Statement": [
			{
				"Effect": "Allow",
				"Principal": {"AWS": ["*"]},
				"Action": ["s3:GetObject"],
				"Resource": ["arn:aws:s3:::%s/*"]
			}
		]
	}`, s.cfg.S3Bucket)
	_ = s.client.SetBucketPolicy(ctx, s.cfg.S3Bucket, policy)
}

// Upload handles multipart photo uploads from mobile and web clients.
func (s *Service) Upload(w http.ResponseWriter, r *http.Request, userID string) {
	// Restrict file upload to 10MB
	r.Body = http.MaxBytesReader(w, r.Body, 10<<20)
	if err := r.ParseMultipartForm(10 << 20); err != nil {
		writeError(w, http.StatusBadRequest, "FILE_TOO_LARGE", "Maximum file size is 10 MB.")
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_FILE", "Missing 'file' field in multipart body.")
		return
	}
	defer file.Close()

	// Sniff first 512 bytes for genuine MIME type
	buf := make([]byte, 512)
	n, _ := file.Read(buf)
	detectedMIME := http.DetectContentType(buf[:n])
	// Reset reader to start
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to process image buffer.")
		return
	}

	// Match extension and validate MIME
	ext, ok := allowedMIMEs[detectedMIME]
	if !ok {
		writeError(w, http.StatusBadRequest, "UNSUPPORTED_MEDIA_TYPE",
			"Unsupported image format. Allowed formats: JPEG, PNG, WebP.")
		return
	}

	// Purpose routing (storefront, product, kyc, avatar, general)
	purpose := r.FormValue("purpose")
	if purpose == "" {
		purpose = "general"
	}
	purpose = strings.ToLower(strings.TrimSpace(purpose))

	// Generate safe, unique object key
	randomID := generateRandomHex(8)
	objectKey := fmt.Sprintf("%s/%s_%s%s", purpose, time.Now().Format("20060102"), randomID, ext)

	// Stream upload directly to MinIO S3
	info, err := s.client.PutObject(r.Context(), s.cfg.S3Bucket, objectKey, file, header.Size, minio.PutObjectOptions{
		ContentType: detectedMIME,
	})
	if err != nil {
		log.Error().Err(err).Msg("minio put object failed")
		writeError(w, http.StatusInternalServerError, "STORAGE_ERROR", "Failed to store image in object storage.")
		return
	}

	// Relative URL proxied by Nginx
	assetURL := fmt.Sprintf("/media/%s", objectKey)
	publicURL := fmt.Sprintf("http://localhost/media/%s", objectKey)

	// Record in database
	var uploadID string
	var userNull sql.NullString
	if userID != "" {
		userNull = sql.NullString{String: userID, Valid: true}
	}

	err = s.db.QueryRowxContext(r.Context(), `
		INSERT INTO media_uploads (
			user_id, purpose, bucket, object_key, public_url, content_type, size_bytes, original_name
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		RETURNING id
	`, userNull, purpose, s.cfg.S3Bucket, objectKey, publicURL, detectedMIME, info.Size, filepath.Base(header.Filename)).Scan(&uploadID)

	if err != nil {
		log.Warn().Err(err).Msg("failed to log media upload in postgres (ignoring to allow asset return)")
		uploadID = randomID
	}

	writeJSON(w, http.StatusCreated, envelope{
		"data": map[string]interface{}{
			"id":            uploadID,
			"purpose":       purpose,
			"object_key":    objectKey,
			"url":           assetURL,
			"public_url":    publicURL,
			"content_type":  detectedMIME,
			"size_bytes":    info.Size,
			"original_name": header.Filename,
			"created_at":    time.Now().Format(time.RFC3339),
		},
		"meta": map[string]string{"request_id": "media-upload"},
	})
}

// ListMedia returns recent media uploads for the caller.
func (s *Service) ListMedia(w http.ResponseWriter, r *http.Request, userID string) {
	purpose := r.URL.Query().Get("purpose")

	var rows *sql.Rows
	var err error

	if purpose != "" {
		rows, err = s.db.QueryContext(r.Context(), `
			SELECT id, user_id, purpose, bucket, object_key, public_url, content_type, size_bytes, original_name, created_at
			FROM media_uploads
			WHERE purpose = $1 AND user_id = $2
			ORDER BY created_at DESC
			LIMIT 50
		`, purpose, userID)
	} else {
		rows, err = s.db.QueryContext(r.Context(), `
			SELECT id, user_id, purpose, bucket, object_key, public_url, content_type, size_bytes, original_name, created_at
			FROM media_uploads
			WHERE user_id = $1
			ORDER BY created_at DESC
			LIMIT 50
		`, userID)
	}

	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Failed to retrieve media records.")
		return
	}

	var uploads []MediaUpload
	if rows != nil {
		defer rows.Close()
		for rows.Next() {
			var u MediaUpload
			var uid sql.NullString
			if err := rows.Scan(
				&u.ID, &uid, &u.Purpose, &u.Bucket, &u.ObjectKey, &u.PublicURL,
				&u.ContentType, &u.SizeBytes, &u.OriginalName, &u.CreatedAt,
			); err == nil {
				if uid.Valid {
					u.UserID = &uid.String
				}
				u.URL = fmt.Sprintf("/media/%s", u.ObjectKey)
				uploads = append(uploads, u)
			}
		}
	}

	if uploads == nil {
		uploads = []MediaUpload{}
	}

	writeJSON(w, http.StatusOK, envelope{
		"data": uploads,
		"meta": map[string]string{"request_id": "media-list"},
	})
}

func generateRandomHex(n int) string {
	bytes := make([]byte, n)
	if _, err := rand.Read(bytes); err != nil {
		return fmt.Sprintf("%d", time.Now().UnixNano())
	}
	return hex.EncodeToString(bytes)
}
