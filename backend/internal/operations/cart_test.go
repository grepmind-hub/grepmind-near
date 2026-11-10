package operations

import "testing"

func TestDecimalToMinorUnits(t *testing.T) {
	for _, tc := range []struct {
		input string
		want  int64
		ok    bool
	}{
		{"0", 0, true}, {"1.2", 120, true}, {"125.05", 12505, true}, {"-0.50", -50, true},
		{"", 0, false}, {"1.001", 0, false}, {"1.2.3", 0, false}, {"NaN", 0, false},
	} {
		got, ok := decimalToMinor(tc.input)
		if got != tc.want || ok != tc.ok {
			t.Errorf("decimalToMinor(%q)=(%d,%v), want (%d,%v)", tc.input, got, ok, tc.want, tc.ok)
		}
	}
}
