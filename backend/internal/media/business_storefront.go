package media

import (
	"database/sql"
	"errors"
	"io"
	"net/http"
	"strconv"

	"github.com/google/uuid"
	"github.com/minio/minio-go/v7"
)

// BusinessStorefront streams the listing's uploaded image to the Admin review.
func (s *Service) BusinessStorefront(w http.ResponseWriter, r *http.Request) {
	id, err := uuid.Parse(r.PathValue("id"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION_ERROR", "Invalid business ID.")
		return
	}
	var key, mime string
	var size int64
	err = s.db.QueryRowxContext(r.Context(), `
		SELECT m.object_key, m.content_type, m.size_bytes
		FROM businesses b
		JOIN media_uploads m ON m.user_id = b.owner_user_id
		  AND b.cover_photo_url = '/media/' || m.object_key
		WHERE b.id = $1 AND m.purpose = 'storefront' AND m.bucket = $2
		LIMIT 1
	`, id, s.cfg.S3Bucket).Scan(&key, &mime, &size)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "No storefront photo is attached.")
		return
	}
	if err != nil || allowedMIMEs[mime] == "" || size <= 0 || size > 10<<20 {
		writeError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load the storefront photo.")
		return
	}
	object, err := s.client.GetObject(r.Context(), s.cfg.S3Bucket, key, minio.GetObjectOptions{})
	if err != nil {
		writeError(w, http.StatusBadGateway, "UNAVAILABLE", "Unable to load the storefront photo.")
		return
	}
	defer object.Close()
	info, err := object.Stat()
	if err != nil || info.Size != size {
		writeError(w, http.StatusBadGateway, "UNAVAILABLE", "Unable to load the storefront photo.")
		return
	}
	w.Header().Set("Content-Type", mime)
	w.Header().Set("Content-Length", strconv.FormatInt(size, 10))
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Cache-Control", "private, no-store")
	_, _ = io.CopyN(w, object, size)
}
