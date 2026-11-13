// Package qaotpinbox implements an isolated-QA-only, scoped OTP delivery and
// retrieval helper. It is intentionally separate from the public API process.
package qaotpinbox

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/google/uuid"
)

const maxRequestBytes = 4096

type Record struct {
	ChallengeID string    `json:"challenge_id"`
	PhoneE164   string    `json:"phone_e164"`
	Purpose     string    `json:"purpose"`
	Code        string    `json:"code"`
	CreatedAt   time.Time `json:"created_at"`
	ExpiresAt   time.Time `json:"expires_at"`
	RunID       string    `json:"run_id"`
}

type Scope struct {
	ChallengeID string `json:"challenge_id"`
	PhoneE164   string `json:"phone_e164"`
	Purpose     string `json:"purpose"`
	RunID       string `json:"run_id"`
	ExpiresAt   string `json:"expires_at"`
}

type Config struct {
	Directory    string
	RunID        string
	RunnerID     string
	RunnerSecret string
	WriterSecret string
	Allowlist    []string
	ExpectedUID  int
	Now          func() time.Time
}

type Inbox struct {
	cfg       Config
	allowlist map[string]struct{}
	mu        sync.Mutex // exactly one reader process is permitted for an inbox.
}

func New(cfg Config) (*Inbox, error) {
	cfg.Directory = strings.TrimSpace(cfg.Directory)
	if cfg.Directory == "" || !validRunID(cfg.RunID) || strings.TrimSpace(cfg.RunnerID) == "" || len(cfg.RunnerID) > 80 || len(cfg.RunnerSecret) < 32 || len(cfg.WriterSecret) < 32 || len(cfg.Allowlist) == 0 {
		return nil, errors.New("QA OTP inbox configuration is incomplete")
	}
	if cfg.Now == nil {
		cfg.Now = time.Now
	}
	if err := validateDirectory(cfg.Directory, cfg.ExpectedUID); err != nil {
		return nil, err
	}
	allowlist := make(map[string]struct{}, len(cfg.Allowlist))
	for _, phone := range cfg.Allowlist {
		if !validPhone(phone) {
			return nil, errors.New("QA OTP allowlist contains an invalid identity")
		}
		allowlist[phone] = struct{}{}
	}
	return &Inbox{cfg: cfg, allowlist: allowlist}, nil
}

// ValidateRuntime prevents accidental reuse as a shared or production service.
func ValidateRuntime(appEnv string, enabled bool, uid int) error {
	if !strings.EqualFold(appEnv, "qa") || !enabled || uid != 0 {
		return errors.New("QA OTP inbox requires isolated QA enablement and root-owned inbox process")
	}
	return nil
}

func (i *Inbox) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusNoContent) })
	mux.HandleFunc("POST /internal/v1/deliver", i.deliver)
	mux.HandleFunc("POST /v1/read", i.read)
	return noStore(mux)
}

func (i *Inbox) deliver(w http.ResponseWriter, r *http.Request) {
	if !constantToken(r.Header.Get("Authorization"), i.cfg.WriterSecret) {
		writeStatus(w, http.StatusUnauthorized)
		return
	}
	var record Record
	if !decodeBounded(w, r, &record) || !validRecord(record, i.cfg, i.allowlist) {
		writeStatus(w, http.StatusBadRequest)
		return
	}
	i.mu.Lock()
	defer i.mu.Unlock()
	if err := validateDirectory(i.cfg.Directory, i.cfg.ExpectedUID); err != nil {
		writeStatus(w, http.StatusServiceUnavailable)
		return
	}
	path := filepath.Join(i.cfg.Directory, filename(record.ChallengeID))
	if _, err := os.Lstat(path); err == nil || !errors.Is(err, os.ErrNotExist) {
		writeStatus(w, http.StatusConflict)
		return
	}
	tmp, err := os.CreateTemp(i.cfg.Directory, ".delivery-*")
	if err != nil {
		writeStatus(w, http.StatusServiceUnavailable)
		return
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if err = tmp.Chmod(0600); err == nil {
		var body []byte
		body, err = json.Marshal(record)
		if err == nil {
			_, err = tmp.Write(append(body, '\n'))
		}
	}
	if err == nil {
		err = tmp.Sync()
	}
	closeErr := tmp.Close()
	if err != nil || closeErr != nil {
		writeStatus(w, http.StatusServiceUnavailable)
		return
	}
	if err = os.Link(tmpName, path); err != nil {
		writeStatus(w, http.StatusConflict)
		return
	}
	w.WriteHeader(http.StatusCreated)
}

func (i *Inbox) read(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("X-QA-Runner-ID") != i.cfg.RunnerID {
		writeStatus(w, http.StatusUnauthorized)
		return
	}
	var scope Scope
	if !decodeBounded(w, r, &scope) || scope.Purpose != "login" || scope.RunID != i.cfg.RunID || !validPhone(scope.PhoneE164) {
		writeStatus(w, http.StatusBadRequest)
		return
	}
	if _, ok := i.allowlist[scope.PhoneE164]; !ok {
		writeStatus(w, http.StatusForbidden)
		return
	}
	capability := scopedCapability(i.cfg.RunnerSecret, i.cfg.RunnerID, scope)
	if !constantToken(r.Header.Get("Authorization"), capability) {
		writeStatus(w, http.StatusUnauthorized)
		return
	}
	if _, err := uuid.Parse(scope.ChallengeID); err != nil {
		writeStatus(w, http.StatusBadRequest)
		return
	}
	i.mu.Lock()
	defer i.mu.Unlock()
	if err := validateDirectory(i.cfg.Directory, i.cfg.ExpectedUID); err != nil {
		writeStatus(w, http.StatusServiceUnavailable)
		return
	}
	path := filepath.Join(i.cfg.Directory, filename(scope.ChallengeID))
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || info.Mode().Perm() != 0600 {
		writeStatus(w, http.StatusNotFound)
		return
	}
	file, err := os.OpenFile(path, os.O_RDONLY|syscall.O_NOFOLLOW, 0)
	if err != nil {
		writeStatus(w, http.StatusNotFound)
		return
	}
	defer file.Close()
	stat, err := file.Stat()
	if err != nil || !stat.Mode().IsRegular() || stat.Mode().Perm() != 0600 {
		writeStatus(w, http.StatusNotFound)
		return
	}
	data, err := io.ReadAll(io.LimitReader(file, maxRequestBytes+1))
	if err != nil || len(data) > maxRequestBytes {
		writeStatus(w, http.StatusNotFound)
		return
	}
	var record Record
	expiresAt, expiryErr := time.Parse(time.RFC3339Nano, scope.ExpiresAt)
	if expiryErr != nil || json.Unmarshal(data, &record) != nil || !validRecord(record, i.cfg, i.allowlist) || record.ChallengeID != scope.ChallengeID || record.PhoneE164 != scope.PhoneE164 || record.Purpose != scope.Purpose || record.RunID != scope.RunID || !record.ExpiresAt.Equal(expiresAt) || !record.ExpiresAt.After(i.cfg.Now()) {
		writeStatus(w, http.StatusGone)
		return
	}
	if err = os.Remove(path); err != nil {
		writeStatus(w, http.StatusConflict)
		return
	}
	phoneHash := sha256.Sum256([]byte(record.PhoneE164))
	log.Printf("qa_otp_reader_event outcome=consumed runner_id=%q run_id=%q challenge_id=%q phone_sha256=%x purpose=login", i.cfg.RunnerID, i.cfg.RunID, record.ChallengeID, phoneHash)
	// The only response containing the code is this private, authenticated,
	// challenge-scoped QA reader endpoint. Never log response bodies.
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]string{"code": record.Code})
}

func (i *Inbox) Capability(scope Scope) string {
	return scopedCapability(i.cfg.RunnerSecret, i.cfg.RunnerID, scope)
}

func scopedCapability(secret, runnerID string, scope Scope) string {
	message := strings.Join([]string{runnerID, scope.RunID, scope.ChallengeID, scope.PhoneE164, scope.Purpose, scope.ExpiresAt}, "\x00")
	mac := hmac.New(sha256.New, []byte(secret))
	_, _ = mac.Write([]byte(message))
	return hex.EncodeToString(mac.Sum(nil))
}

func validRecord(record Record, cfg Config, allowlist map[string]struct{}) bool {
	if _, err := uuid.Parse(record.ChallengeID); err != nil {
		return false
	}
	if _, ok := allowlist[record.PhoneE164]; !ok || record.Purpose != "login" || record.RunID != cfg.RunID || !record.CreatedAt.Before(record.ExpiresAt) || !record.ExpiresAt.After(cfg.Now()) || record.ExpiresAt.Sub(record.CreatedAt) > 15*time.Minute {
		return false
	}
	if len(record.Code) != 6 {
		return false
	}
	for _, digit := range record.Code {
		if digit < '0' || digit > '9' {
			return false
		}
	}
	return true
}

func validateDirectory(path string, expectedUID int) error {
	resolved, resolveErr := filepath.EvalSymlinks(path)
	info, err := os.Lstat(path)
	if resolveErr != nil || resolved != filepath.Clean(path) || err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 || info.Mode().Perm() != 0700 {
		return errors.New("QA OTP inbox must be a real mode-0700 directory")
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok || int(stat.Uid) != expectedUID {
		return fmt.Errorf("QA OTP inbox ownership does not match required UID")
	}
	return nil
}

func filename(challengeID string) string {
	id, err := uuid.Parse(challengeID)
	if err != nil {
		return ""
	}
	return strings.ReplaceAll(strings.ToLower(id.String()), "-", "") + ".json"
}

func validRunID(value string) bool {
	if len(value) < 16 || len(value) > 80 {
		return false
	}
	for _, c := range value {
		if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '-' || c == '_') {
			return false
		}
	}
	return true
}

func validPhone(phone string) bool {
	if len(phone) < 11 || len(phone) > 16 || phone[0] != '+' {
		return false
	}
	for _, c := range phone[1:] {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

func constantToken(header, expected string) bool {
	const prefix = "Bearer "
	if !strings.HasPrefix(header, prefix) {
		return false
	}
	got := []byte(strings.TrimPrefix(header, prefix))
	want := []byte(expected)
	return len(got) == len(want) && hmac.Equal(got, want)
}

func decodeBounded(w http.ResponseWriter, r *http.Request, dst any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, maxRequestBytes)
	defer r.Body.Close()
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if decoder.Decode(dst) != nil {
		return false
	}
	var trailing any
	return decoder.Decode(&trailing) == io.EOF
}

func writeStatus(w http.ResponseWriter, status int) { http.Error(w, http.StatusText(status), status) }

func noStore(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		next.ServeHTTP(w, r)
	})
}
