package auth

import (
	"sync"
	"time"
)

type rateWindow struct {
	startedAt time.Time
	count     int
}

const maxOTPWindowEntries = 50000

// otpRateLimiter provides bounded process-local OTP abuse controls. The edge
// proxy and PostgreSQL per-phone cooldown remain separate layers.
type otpRateLimiter struct {
	mu      sync.Mutex
	windows map[string]rateWindow
}

func newOTPRateLimiter() *otpRateLimiter {
	return &otpRateLimiter{windows: make(map[string]rateWindow)}
}

func (l *otpRateLimiter) allow(scope, key string, now time.Time, max int, window time.Duration) bool {
	if key == "" {
		key = "unknown"
	}
	name := scope + ":" + key
	l.mu.Lock()
	defer l.mu.Unlock()
	for k, v := range l.windows {
		if now.Sub(v.startedAt) >= 2*window || now.Before(v.startedAt) {
			delete(l.windows, k)
		}
	}
	entry, ok := l.windows[name]
	if !ok || now.Sub(entry.startedAt) >= window || now.Before(entry.startedAt) {
		if !ok && len(l.windows) >= maxOTPWindowEntries {
			return false
		}
		l.windows[name] = rateWindow{startedAt: now, count: 1}
		return true
	}
	if entry.count >= max {
		return false
	}
	entry.count++
	l.windows[name] = entry
	return true
}
