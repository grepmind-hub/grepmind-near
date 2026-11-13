package qaotpinbox

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

const testRun = "qa-test-run-7f21d974"

func newTestInbox(t *testing.T) (*Inbox, string) {
	t.Helper()
	dir := t.TempDir()
	if err := os.Chmod(dir, 0700); err != nil {
		t.Fatal(err)
	}
	uid := os.Getuid()
	i, err := New(Config{Directory: dir, RunID: testRun, RunnerID: "codex-local-runner", RunnerSecret: "runner-secret-that-is-long-enough-001", WriterSecret: "writer-secret-that-is-long-enough-001", Allowlist: []string{"+919000000001", "+919000000002"}, ExpectedUID: uid})
	if err != nil {
		t.Fatal(err)
	}
	return i, dir
}

func testRecord() Record {
	now := time.Now().UTC()
	return Record{ChallengeID: "9d43b8e0-0000-4000-8000-000000000001", PhoneE164: "+919000000001", Purpose: "login", Code: "012345", CreatedAt: now, ExpiresAt: now.Add(time.Minute), RunID: testRun}
}

func testScope(record Record) Scope {
	return Scope{ChallengeID: record.ChallengeID, PhoneE164: record.PhoneE164, Purpose: record.Purpose, RunID: record.RunID, ExpiresAt: record.ExpiresAt.Format(time.RFC3339Nano)}
}

func request(t *testing.T, handler http.Handler, method, path, token, runner string, body any) *httptest.ResponseRecorder {
	t.Helper()
	data, err := json.Marshal(body)
	if err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest(method, path, bytes.NewReader(data))
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	if runner != "" {
		req.Header.Set("X-QA-Runner-ID", runner)
	}
	res := httptest.NewRecorder()
	handler.ServeHTTP(res, req)
	return res
}

func TestScopedReaderRequiresWriterAndAllowsOneChallengeRead(t *testing.T) {
	inbox, dir := newTestInbox(t)
	handler := inbox.Handler()
	record := testRecord()
	if got := request(t, handler, http.MethodPost, "/internal/v1/deliver", "wrong", "", record).Code; got != http.StatusUnauthorized {
		t.Fatalf("unauthorized writer status=%d", got)
	}
	nonAllowlisted := record
	nonAllowlisted.PhoneE164 = "+919000000099"
	if got := request(t, handler, http.MethodPost, "/internal/v1/deliver", inbox.cfg.WriterSecret, "", nonAllowlisted).Code; got != http.StatusBadRequest {
		t.Fatalf("non-allowlisted delivery status=%d", got)
	}
	if got := request(t, handler, http.MethodPost, "/internal/v1/deliver", inbox.cfg.WriterSecret, "", record).Code; got != http.StatusCreated {
		t.Fatalf("deliver status=%d", got)
	}
	entries, err := os.ReadDir(dir)
	if err != nil || len(entries) != 1 {
		t.Fatalf("inbox entries=%d err=%v", len(entries), err)
	}
	info, err := os.Stat(filepath.Join(dir, filename(record.ChallengeID)))
	if err != nil || info.Mode().Perm() != 0600 {
		t.Fatalf("OTP record mode not private: info=%v err=%v", info, err)
	}
	scope := testScope(record)
	capability := inbox.Capability(scope)
	if got := request(t, handler, http.MethodPost, "/v1/read", capability, "codex-local-runner", scope).Code; got != http.StatusOK {
		t.Fatalf("read status=%d body=%s", got, "redacted")
	}
	if got := request(t, handler, http.MethodPost, "/v1/read", capability, "codex-local-runner", scope).Code; got != http.StatusNotFound {
		t.Fatalf("second read status=%d, want 404", got)
	}
}

func TestReaderRejectsWrongScopeRunnerAndCapability(t *testing.T) {
	inbox, _ := newTestInbox(t)
	handler := inbox.Handler()
	record := testRecord()
	request(t, handler, http.MethodPost, "/internal/v1/deliver", inbox.cfg.WriterSecret, "", record)
	scope := testScope(record)
	for name, tc := range map[string]struct {
		scope         Scope
		token, runner string
	}{
		"wrong run":        {func() Scope { s := scope; s.RunID = "other-run-12345678"; return s }(), inbox.Capability(scope), inbox.cfg.RunnerID},
		"wrong phone":      {func() Scope { s := scope; s.PhoneE164 = "+919000000002"; return s }(), inbox.Capability(scope), inbox.cfg.RunnerID},
		"wrong challenge":  {func() Scope { s := scope; s.ChallengeID = "9d43b8e0-0000-4000-8000-000000000002"; return s }(), inbox.Capability(scope), inbox.cfg.RunnerID},
		"wrong purpose":    {func() Scope { s := scope; s.Purpose = "password_reset"; return s }(), inbox.Capability(scope), inbox.cfg.RunnerID},
		"wrong runner":     {scope, inbox.Capability(scope), "other-runner"},
		"wrong capability": {scope, "invalid-capability", inbox.cfg.RunnerID},
	} {
		t.Run(name, func(t *testing.T) {
			res := request(t, handler, http.MethodPost, "/v1/read", tc.token, tc.runner, tc.scope)
			if res.Code == http.StatusOK {
				t.Fatal("mismatched scope was accepted")
			}
		})
	}
	if got := request(t, handler, http.MethodPost, "/v1/read", inbox.Capability(scope), inbox.cfg.RunnerID, map[string]any{"challenge_id": "../etc/passwd", "phone_e164": scope.PhoneE164, "purpose": "login", "run_id": testRun}).Code; got == http.StatusOK {
		t.Fatal("path traversal was accepted")
	}
}

func TestExpiredMissingAndSymlinkRecordsCannotBeRead(t *testing.T) {
	inbox, dir := newTestInbox(t)
	handler := inbox.Handler()
	for _, tc := range []struct {
		name    string
		record  Record
		symlink bool
	}{
		{name: "expired", record: func() Record {
			r := testRecord()
			r.CreatedAt = time.Now().Add(-2 * time.Minute)
			r.ExpiresAt = time.Now().Add(-time.Second)
			return r
		}()},
		{name: "missing", record: testRecord()},
		{name: "symlink", record: testRecord(), symlink: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r := tc.record
			path := filepath.Join(dir, filename(r.ChallengeID))
			if tc.symlink {
				target := filepath.Join(t.TempDir(), "target")
				if err := os.WriteFile(target, []byte("{}"), 0600); err != nil {
					t.Fatal(err)
				}
				if err := os.Symlink(target, path); err != nil {
					t.Skip(err)
				}
			} else if tc.name == "expired" {
				data, _ := json.Marshal(r)
				if err := os.WriteFile(path, data, 0600); err != nil {
					t.Fatal(err)
				}
			} else if tc.name != "missing" {
				request(t, handler, http.MethodPost, "/internal/v1/deliver", inbox.cfg.WriterSecret, "", r)
			}
			scope := testScope(r)
			res := request(t, handler, http.MethodPost, "/v1/read", inbox.Capability(scope), inbox.cfg.RunnerID, scope)
			if res.Code == http.StatusOK {
				t.Fatal("expired/missing/symlink OTP was returned")
			}
		})
	}
}

func TestConcurrentReaderConsumesChallengeAtMostOnce(t *testing.T) {
	inbox, _ := newTestInbox(t)
	handler := inbox.Handler()
	record := testRecord()
	request(t, handler, http.MethodPost, "/internal/v1/deliver", inbox.cfg.WriterSecret, "", record)
	scope := testScope(record)
	token := inbox.Capability(scope)
	var successes atomic.Int32
	var wg sync.WaitGroup
	for n := 0; n < 12; n++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if request(t, handler, http.MethodPost, "/v1/read", token, inbox.cfg.RunnerID, scope).Code == http.StatusOK {
				successes.Add(1)
			}
		}()
	}
	wg.Wait()
	if successes.Load() != 1 {
		t.Fatalf("successful concurrent reads=%d, want exactly one", successes.Load())
	}
}

func TestInboxRequiresOwnerOnlyDirectory(t *testing.T) {
	dir := t.TempDir()
	_ = os.Chmod(dir, 0750)
	_, err := New(Config{Directory: dir, RunID: testRun, RunnerID: "runner", RunnerSecret: "runner-secret-that-is-long-enough-001", WriterSecret: "writer-secret-that-is-long-enough-001", Allowlist: []string{"+919000000001"}, ExpectedUID: os.Getuid()})
	if err == nil {
		t.Fatal("group-readable directory was accepted")
	}
}

func TestReaderRuntimeRejectsNonQAAndUnprivilegedInboxOwner(t *testing.T) {
	for _, tc := range []struct {
		name    string
		env     string
		enabled bool
		uid     int
	}{
		{name: "production", env: "production", enabled: true, uid: 0},
		{name: "not enabled", env: "qa", enabled: false, uid: 0},
		{name: "not root owned", env: "qa", enabled: true, uid: 100},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if err := ValidateRuntime(tc.env, tc.enabled, tc.uid); err == nil {
				t.Fatal("unsafe reader runtime was accepted")
			}
		})
	}
	if err := ValidateRuntime("qa", true, 0); err != nil {
		t.Fatalf("isolated root-owned QA runtime rejected: %v", err)
	}
}
