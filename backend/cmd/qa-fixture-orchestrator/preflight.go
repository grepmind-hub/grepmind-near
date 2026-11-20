package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os/exec"
	"strings"

	_ "github.com/jackc/pgx/v5/stdlib"
	"grepmind-near/backend/internal/qafixtures"
)

const (
	apiName      = "grepmind_4c_qa_api"
	inboxName    = "grepmind_4c_qa_otp_inbox"
	dbName       = "grepmind_3e_qa_db"
	qaNetwork    = "grepmind_3e_qa_net"
	databaseName = "grepmind_3e_qa"
	apiOrigin    = "http://127.0.0.1:18083"
	inboxOrigin  = "http://127.0.0.1:18085"
)

type container struct {
	Name            string
	State           struct{ Running bool }
	Config          struct{ Env []string }
	HostConfig      struct{ Tmpfs map[string]string }
	Mounts          []struct{ Type, Destination string }
	NetworkSettings struct {
		Networks map[string]json.RawMessage
		Ports    map[string][]struct{ HostIP, HostPort string }
	}
}

func (c container) env() map[string]string {
	env := make(map[string]string, len(c.Config.Env))
	for _, entry := range c.Config.Env {
		key, value, ok := strings.Cut(entry, "=")
		if ok {
			env[key] = value
		}
	}
	return env
}

func (c container) verifyPort(port, hostPort string) bool {
	ports := c.NetworkSettings.Ports[port]
	return len(ports) == 1 && ports[0].HostIP == "127.0.0.1" && ports[0].HostPort == hostPort
}

func inspectQA(ctx context.Context) (*qafixtures.FullIsolationReport, error) {
	raw, err := exec.CommandContext(ctx, "docker", "inspect", "--type=container", apiName, inboxName, dbName).Output()
	if err != nil {
		return nil, errors.New("could not inspect the three isolated QA containers")
	}
	var containers []container
	if json.Unmarshal(raw, &containers) != nil || len(containers) != 3 {
		return nil, errors.New("unexpected QA container metadata")
	}
	for i, name := range []string{apiName, inboxName, dbName} {
		c := containers[i]
		if c.Name != "/"+name || !c.State.Running || len(c.NetworkSettings.Networks) != 1 || c.NetworkSettings.Networks[qaNetwork] == nil {
			return nil, fmt.Errorf("QA container %s is stopped or outside the expected QA network", name)
		}
	}
	raw, err = exec.CommandContext(ctx, "docker", "network", "inspect", qaNetwork).Output()
	if err != nil {
		return nil, errors.New("could not inspect isolated QA network membership")
	}
	var networks []struct {
		Containers map[string]struct{ Name string }
	}
	if json.Unmarshal(raw, &networks) != nil || len(networks) != 1 || len(networks[0].Containers) != 3 {
		return nil, errors.New("QA network must contain exactly the API, inbox, and database")
	}

	api, inbox, db := containers[0], containers[1], containers[2]
	if !api.verifyPort("8080/tcp", "18083") || !inbox.verifyPort("8090/tcp", "18085") || !db.verifyPort("5432/tcp", "55432") {
		return nil, errors.New("QA service ports must match their expected loopback bindings")
	}
	apiEnv, inboxEnv, dbEnv := api.env(), inbox.env(), db.env()
	dataDir := dbEnv["PGDATA"]
	if dataDir != "/var/lib/postgresql/data" || db.HostConfig.Tmpfs[dataDir] == "" {
		return nil, errors.New("PostgreSQL data directory must be on an inspected tmpfs")
	}
	for _, mount := range db.Mounts {
		if mount.Type != "tmpfs" {
			return nil, errors.New("persistent PostgreSQL mounts are prohibited")
		}
	}
	if apiEnv["APP_ENV"] != "qa" || inboxEnv["APP_ENV"] != "qa" || apiEnv["OTP_PROVIDER"] != "qa_http" ||
		apiEnv["QA_OTP_DELIVERY_ENABLED"] != "true" || inboxEnv["QA_OTP_READER_ENABLED"] != "true" ||
		apiEnv["QA_OTP_RUN_ID"] == "" || apiEnv["QA_OTP_RUN_ID"] != inboxEnv["QA_OTP_RUN_ID"] ||
		apiEnv["QA_OTP_DELIVERY_URL"] != "http://"+inboxName+":8090" {
		return nil, errors.New("QA API and protected OTP inbox configuration do not match")
	}
	if apiEnv["DB_HOST"] != dbName || apiEnv["DB_PORT"] != "5432" || apiEnv["DB_NAME"] != databaseName ||
		dbEnv["POSTGRES_DB"] != databaseName || apiEnv["DB_USER"] == "" || apiEnv["DB_PASSWORD"] == "" {
		return nil, errors.New("QA API database configuration does not match the isolated PostgreSQL target")
	}
	for _, key := range []string{"REAL_MONEY_ENABLED", "PAYOUT_ENABLED", "SETTLEMENT_LIVE_ENABLED"} {
		if value := apiEnv[key]; value != "" && value != "false" {
			return nil, fmt.Errorf("QA API setting %s must be disabled", key)
		}
	}
	dsn := url.URL{
		Scheme: "postgres", User: url.UserPassword(apiEnv["DB_USER"], apiEnv["DB_PASSWORD"]),
		Host: "127.0.0.1:55432", Path: "/" + databaseName, RawQuery: "sslmode=disable&default_transaction_read_only=on",
	}
	conn, err := sql.Open("pgx", dsn.String())
	if err != nil {
		return nil, errors.New("could not configure read-only QA PostgreSQL connection")
	}
	defer conn.Close()

	var liveDir string
	if err := conn.QueryRowContext(ctx, "SELECT current_setting('data_directory')").Scan(&liveDir); err != nil || liveDir != dataDir {
		return nil, errors.New("could not verify the live QA PostgreSQL data directory")
	}
	var live struct {
		upi, cod, settlement, money, payout bool
	}
	err = conn.QueryRowContext(ctx, `
		SELECT upi_enabled, cod_enabled, merchant_settlement_enabled, real_money_enabled, payout_enabled
		FROM financial_feature_config WHERE singleton = true
	`).Scan(&live.upi, &live.cod, &live.settlement, &live.money, &live.payout)
	if err != nil || live.upi || live.cod || live.settlement || live.money || live.payout {
		return nil, errors.New("live financial activity must be disabled in PostgreSQL")
	}
	inspector := &qafixtures.SQLDatabaseInspector{
		DB: conn, DBName: databaseName, DBHost: "127.0.0.1", DBPort: 55432,
		TmpfsBacked: true, APIBaseURL: apiOrigin, OTPInboxURL: inboxOrigin,
		Env: qafixtures.EnvironmentEvidence{
			AppEnv: apiEnv["APP_ENV"], OTPProvider: apiEnv["OTP_PROVIDER"],
			PaymentProvider: apiEnv["PAYMENT_PROVIDER_MODE"], PayoutProvider: apiEnv["PAYOUT_PROVIDER"],
			SMSProvider: apiEnv["SMS_PROVIDER"],
		},
	}
	report, err := qafixtures.VerifyAuthoritativeIsolation(ctx, inspector)
	if err != nil {
		// Driver errors can include connection details.
		return nil, errors.New("QA isolation check failed during schema, provider, or service verification")
	}
	return report, nil
}
