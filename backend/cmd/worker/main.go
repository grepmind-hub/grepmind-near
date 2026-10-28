package main

import (
	"os"
	"os/signal"
	"syscall"

	"grepmind-near/backend/pkg/logger"
)

func main() {
	logger.Init("info")
	logger.Log.Info().Msg("grepmind-near worker service started")

	// Block until termination signal
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	<-sigChan

	logger.Log.Info().Msg("grepmind-near worker service shutting down gracefully")
}
