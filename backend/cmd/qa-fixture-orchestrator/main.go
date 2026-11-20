package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"time"

	"grepmind-near/backend/internal/qafixtures"
)

func main() {
	var runID string
	var dryRun, verifyIsolation, execute, confirm bool
	flag.StringVar(&runID, "run-id", "phase5b-dry-run", "non-secret QA run identifier")
	flag.BoolVar(&dryRun, "dry-run", false, "print a non-mutating fixture plan (default)")
	flag.BoolVar(&verifyIsolation, "verify-isolation", false, "perform authoritative read-only inspection of QA isolation boundaries")
	flag.BoolVar(&execute, "execute", false, "request fixture execution; requires verified isolation and Phase 5B.4C authorization")
	flag.BoolVar(&confirm, "confirm-isolated-qa", false, "explicitly confirm disposable isolated QA target")
	flag.Parse()

	if !execute && !verifyIsolation && !dryRun {
		dryRun = true
	}
	if execute && (dryRun || verifyIsolation) {
		fail("choose only one of --dry-run, --verify-isolation, or --execute")
	}

	// 1. Authoritative Isolation Inspection (Read-Only)
	if verifyIsolation {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()

		report, err := inspectQA(ctx)
		if err != nil {
			fail(fmt.Sprintf("isolation verification failed: %v", err))
		}
		encoded, _ := json.MarshalIndent(report, "", "  ")
		fmt.Println(string(encoded))
		return
	}

	// 2. Build Plan
	plan, err := qafixtures.BuildPlan(runID)
	if err != nil {
		fail(err.Error())
	}

	// 3. Execution Guard
	if execute {
		if err := qafixtures.ValidateExecutionFromEnvironment(os.Getenv("APP_ENV"), confirm); err != nil {
			fail(err.Error())
		}
		fail("execution refused: authenticated domain workflow adapters are implemented, but Phase 5B.4C live execution authorization gate is required; no data was changed")
	}

	// 4. Default: Output Dry-Run Plan
	encoded, err := json.MarshalIndent(plan, "", "  ")
	if err != nil {
		fail("could not encode dry-run plan")
	}
	fmt.Println(string(encoded))
}

func fail(message string) {
	fmt.Fprintln(os.Stderr, qafixtures.Redact(message))
	os.Exit(2)
}
