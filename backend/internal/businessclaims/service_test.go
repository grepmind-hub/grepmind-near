package businessclaims

import "testing"

func TestClaimSearchQueryBounds(t *testing.T) {
	for _, tc := range []struct {
		value string
		valid bool
	}{
		{"", false}, {"a", false}, {"  a ", false}, {"ac", true}, {"Cuttack Market", true},
		{string(make([]byte, 81)), false},
	} {
		if got := validateSearchQuery(tc.value); got != tc.valid {
			t.Errorf("validateSearchQuery(%q) = %v, want %v", tc.value, got, tc.valid)
		}
	}
}

func TestClaimSearchEscapesWildcards(t *testing.T) {
	if got, want := escapeLike(`a%_\b`), `a\%\_\\b`; got != want {
		t.Fatalf("escapeLike() = %q, want %q", got, want)
	}
}

func TestClaimableCityScope(t *testing.T) {
	for _, city := range []string{"Cuttack", " Jajpur ", "Jajpur Town"} {
		if !claimableCity(city) {
			t.Errorf("expected %q in claimable city scope", city)
		}
	}
	for _, city := range []string{"Bhubaneswar", "Puri", "Jajpur Road"} {
		if claimableCity(city) {
			t.Errorf("unexpected claimable city %q", city)
		}
	}
}

func TestClaimSubmissionRateLimit(t *testing.T) {
	for _, tc := range []struct {
		recent  int
		allowed bool
	}{{0, true}, {2, true}, {3, false}, {4, false}} {
		if got := claimRateLimitAllows(tc.recent); got != tc.allowed {
			t.Errorf("claimRateLimitAllows(%d) = %v, want %v", tc.recent, got, tc.allowed)
		}
	}
}
