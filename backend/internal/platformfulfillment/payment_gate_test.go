package platformfulfillment

import "testing"

func TestPaymentEligibleForFulfillment(t *testing.T) {
	tests := []struct {
		name, method, paymentStatus, codState string
		want                                  bool
	}{
		{"verified UPI", "upi", "paid", "not_applicable", true},
		{"pending UPI", "upi", "pending", "not_applicable", false},
		{"uncollected UPI", "upi", "not_collected", "not_applicable", false},
		{"failed UPI", "upi", "failed", "not_applicable", false},
		{"COD due", "cash_on_delivery", "not_collected", "due", true},
		{"COD collected projection", "cash_on_delivery", "not_collected", "collected", true},
		{"COD missing obligation", "cash_on_delivery", "not_collected", "not_applicable", false},
		{"legacy order", "", "not_collected", "not_applicable", true},
		{"unknown method", "bitcoin", "paid", "not_applicable", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := paymentEligibleForFulfillment(tt.method, tt.paymentStatus, tt.codState); got != tt.want {
				t.Fatalf("paymentEligibleForFulfillment(%q, %q, %q) = %t, want %t", tt.method, tt.paymentStatus, tt.codState, got, tt.want)
			}
		})
	}
}
