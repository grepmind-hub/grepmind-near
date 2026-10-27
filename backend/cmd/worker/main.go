package main

import (
	"log/slog"
	"time"

	"grepmind-near/backend/pkg/config"
	"grepmind-near/backend/pkg/database"
	"grepmind-near/backend/pkg/logger"
)

func main() {
	_ = slog.New
	_ = config.Load
	_ = database.Open
	_ = logger.Init
	_ = time.Second
}
