package main

import (
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"grepmind-near/backend/internal/qaotpinbox"
)

func main() {
	if err := qaotpinbox.ValidateRuntime(os.Getenv("APP_ENV"), strings.EqualFold(os.Getenv("QA_OTP_READER_ENABLED"), "true"), os.Geteuid()); err != nil {
		log.Fatal(err)
	}
	inbox, err := qaotpinbox.New(qaotpinbox.Config{
		Directory:    os.Getenv("QA_OTP_INBOX_DIR"),
		RunID:        os.Getenv("QA_OTP_RUN_ID"),
		RunnerID:     os.Getenv("QA_OTP_RUNNER_ID"),
		RunnerSecret: os.Getenv("QA_OTP_RUNNER_SECRET"),
		WriterSecret: os.Getenv("QA_OTP_WRITER_SECRET"),
		Allowlist:    strings.Split(os.Getenv("QA_OTP_ALLOWLIST"), ","),
		ExpectedUID:  0,
	})
	if err != nil {
		log.Fatal("QA OTP inbox startup validation failed")
	}
	addr := os.Getenv("QA_OTP_LISTEN_ADDR")
	if addr == "" {
		addr = ":8090"
	}
	server := &http.Server{Addr: addr, Handler: inbox.Handler(), ReadHeaderTimeout: 3 * time.Second, ReadTimeout: 5 * time.Second, WriteTimeout: 5 * time.Second, IdleTimeout: 15 * time.Second, MaxHeaderBytes: 8192}
	log.Printf("isolated QA OTP inbox listening on %s for run %s", addr, os.Getenv("QA_OTP_RUN_ID"))
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatal("QA OTP inbox stopped")
	}
}
