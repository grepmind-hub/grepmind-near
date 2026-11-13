package deliverydispatch

import "testing"

func TestDispatchPaymentEligible(t *testing.T) {
	tests := []struct {
		name, source, method, status string
		hasCOD                       bool
		want                         bool
	}{
		{"verified platform UPI", "platform_catalog", "upi", "paid", false, true},
		{"pending platform UPI", "platform_catalog", "upi", "pending", false, false},
		{"failed platform UPI", "platform_catalog", "upi", "failed", false, false},
		{"COD obligation", "platform_catalog", "cash_on_delivery", "not_collected", true, true},
		{"COD obligation missing", "platform_catalog", "cash_on_delivery", "not_collected", false, false},
		{"legacy platform order", "platform_catalog", "", "not_collected", false, true},
		{"legacy non-platform order", "merchant_order", "upi", "not_collected", false, true},
		{"unsupported platform method", "platform_catalog", "unknown", "paid", true, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := dispatchPaymentEligible(tt.source, tt.method, tt.status, tt.hasCOD); got != tt.want {
				t.Fatalf("dispatchPaymentEligible(%q, %q, %q, %t) = %t, want %t", tt.source, tt.method, tt.status, tt.hasCOD, got, tt.want)
			}
		})
	}
}
