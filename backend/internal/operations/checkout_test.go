package operations

import "testing"

func TestNormalizeCustomerAddress(t *testing.T) {
	valid := addressInput{
		Label: " Home ", RecipientName: " Customer ", AddressLine1: " 12 Main Road ",
		Locality: " Badambadi ", City: "cuttack", State: " Odisha ", PostalCode: "753001",
		ContactPhone: "9876543210", IsDefault: true,
	}
	got, err := normalizeAddress(valid)
	if err != nil {
		t.Fatalf("valid manual Cuttack address rejected: %v", err)
	}
	if got.City != "Cuttack" || got.ContactPhone != "+919876543210" || got.RecipientName != "Customer" {
		t.Fatalf("address was not normalized: %+v", got)
	}

	jajpur := valid
	jajpur.City = "JAJPUR"
	if got, err := normalizeAddress(jajpur); err != nil || got.City != "Jajpur" {
		t.Errorf("Jajpur address normalization=(%+v,%v)", got, err)
	}

	badCases := []struct {
		name  string
		input addressInput
	}{
		{"unsupported city", addressInput{Label: "Home", RecipientName: "A", AddressLine1: "123 Road", Locality: "Area", City: "Bhubaneswar", State: "Odisha", PostalCode: "751001", ContactPhone: "9876543210"}},
		{"invalid PIN", addressInput{Label: "Home", RecipientName: "A", AddressLine1: "123 Road", Locality: "Area", City: "Cuttack", State: "Odisha", PostalCode: "123", ContactPhone: "9876543210"}},
		{"invalid phone", addressInput{Label: "Home", RecipientName: "A", AddressLine1: "123 Road", Locality: "Area", City: "Cuttack", State: "Odisha", PostalCode: "753001", ContactPhone: "12345"}},
		{"coordinate pair required", addressInput{Label: "Home", RecipientName: "A", AddressLine1: "123 Road", Locality: "Area", City: "Cuttack", State: "Odisha", PostalCode: "753001", ContactPhone: "9876543210", Latitude: func() *float64 { v := 20.5; return &v }()}},
		{"coordinate range", addressInput{Label: "Home", RecipientName: "A", AddressLine1: "123 Road", Locality: "Area", City: "Cuttack", State: "Odisha", PostalCode: "753001", ContactPhone: "9876543210", Latitude: func() *float64 { v := 91.0; return &v }(), Longitude: func() *float64 { v := 85.9; return &v }()}},
	}
	for _, tc := range badCases {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := normalizeAddress(tc.input); err == nil {
				t.Fatal("invalid address was accepted")
			}
		})
	}
}
