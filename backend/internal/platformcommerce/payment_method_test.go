package platformcommerce

import "testing"

func TestValidCheckoutPaymentMethodRequiresExplicitSupportedMethod(t *testing.T) {
	for _, method := range []string{"upi", "cash_on_delivery"} {
		if !validCheckoutPaymentMethod(method) {
			t.Errorf("validCheckoutPaymentMethod(%q) = false", method)
		}
	}
	for _, method := range []string{"", "cash", "cod", "UPI", "card"} {
		if validCheckoutPaymentMethod(method) {
			t.Errorf("validCheckoutPaymentMethod(%q) = true, want false", method)
		}
	}
}
