package main

import (
	"context"
	"fmt"
	"os"
	"regexp"
	"time"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
	"grepmind-near/backend/pkg/config"
	"grepmind-near/backend/pkg/database"
)

var phonePattern = regexp.MustCompile(`^\+91[6-9][0-9]{9}$`)

func main() {
	if len(os.Args) != 2 || !phonePattern.MatchString(os.Args[1]) {
		fmt.Fprintln(os.Stderr, "usage: merchant-e2e-cleanup <generated-test-phone-e164>")
		os.Exit(2)
	}
	cfg := config.Load()
	if !cfg.IsLocal() {
		fmt.Fprintln(os.Stderr, "refusing cleanup outside APP_ENV=local")
		os.Exit(2)
	}
	db, err := database.Open(cfg.DBDSN(), 3, 1, time.Minute)
	if err != nil {
		fail(err)
	}
	defer db.Close()
	var userID string
	err = db.Get(&userID, `SELECT u.id::text FROM users u WHERE u.phone_e164=$1 AND u.created_at > now()-interval '2 hours' AND EXISTS(SELECT 1 FROM user_roles r WHERE r.user_id=u.id AND r.role='merchant') AND EXISTS(SELECT 1 FROM businesses b WHERE b.owner_user_id=u.id AND b.name LIKE 'QA %')`, os.Args[1])
	if err != nil {
		fmt.Println("No fresh QA merchant fixture found; nothing to clean.")
		return
	}
	type object struct {
		Bucket string `db:"bucket"`
		Key    string `db:"object_key"`
	}
	var objects []object
	if err = db.Select(&objects, `SELECT bucket,object_key FROM media_uploads WHERE user_id=$1 AND purpose IN ('avatar','storefront','product')`, userID); err != nil {
		fail(err)
	}
	endpoint := cfg.S3Endpoint
	secure := cfg.S3UseSSL
	if len(endpoint) >= 7 && endpoint[:7] == "http://" {
		endpoint = endpoint[7:]
	}
	if len(endpoint) >= 8 && endpoint[:8] == "https://" {
		endpoint = endpoint[8:]
		secure = true
	}
	client, err := minio.New(endpoint, &minio.Options{Creds: credentials.NewStaticV4(cfg.S3AccessKey, cfg.S3SecretKey, ""), Secure: secure})
	if err != nil {
		fail(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	for _, item := range objects {
		if err := client.RemoveObject(ctx, item.Bucket, item.Key, minio.RemoveObjectOptions{}); err != nil {
			fail(fmt.Errorf("remove generated image: %w", err))
		}
	}
	tx, err := db.BeginTxx(ctx, nil)
	if err != nil {
		fail(err)
	}
	if _, err = tx.ExecContext(ctx, `DELETE FROM media_uploads WHERE user_id=$1`, userID); err != nil {
		_ = tx.Rollback()
		fail(err)
	}
	result, err := tx.ExecContext(ctx, `DELETE FROM users WHERE id=$1 AND phone_e164=$2`, userID, os.Args[1])
	if err != nil {
		fail(err)
	}
	count, _ := result.RowsAffected()
	if count != 1 {
		fail(fmt.Errorf("expected to remove one generated user, removed %d", count))
	}
	if err = tx.Commit(); err != nil {
		fail(err)
	}
	fmt.Printf("Cleaned generated merchant account, listing, product/media metadata and %d uploaded objects.\n", len(objects))
}

func fail(err error) { fmt.Fprintln(os.Stderr, err); os.Exit(1) }
