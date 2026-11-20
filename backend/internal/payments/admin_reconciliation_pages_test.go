package payments

import (
	"encoding/base64"
	"net/url"
	"testing"
)

func TestParseReconciliationPage(t *testing.T) {
	cursor := base64.RawURLEncoding.EncodeToString([]byte("2026-11-16T15:04:05.123456Z|10000000-0000-4000-8000-000000000001"))
	params := url.Values{
		"view": {"history"}, "limit": {"50"}, "before": {cursor}, "reference": {" gn-abcd1234 "},
		"status": {"succeeded"}, "outcome": {"amount_mismatch"}, "from": {"2026-11-01"}, "to": {"2026-11-16"},
		"attempt_id": {"20000000-0000-4000-8000-000000000001"},
	}
	page, err := parseReconciliationPage(params)
	if err != nil {
		t.Fatal(err)
	}
	if page.reference != "GN-ABCD1234" || page.limit != 50 || page.until.Format("2006-01-02") != "2026-11-17" ||
		page.cursorTime.Nanosecond() != 123456000 || page.attemptID == nil {
		t.Fatalf("unexpected parsed page %+v", page)
	}
	for key, invalid := range map[string]string{
		"view": "all", "limit": "51", "before": "invalid",
		"reference": "invalid/ref", "status": "resolved", "outcome": "unknown",
		"from": "2026-02-30", "to": "2026-10-31", "attempt_id": "id",
	} {
		t.Run(key, func(t *testing.T) {
			clone := url.Values{}
			for k, values := range params {
				clone[k] = values
			}
			clone.Set(key, invalid)
			if _, err := parseReconciliationPage(clone); err == nil {
				t.Fatalf("expected an error for %s=%q", key, invalid)
			}
		})
	}
}
