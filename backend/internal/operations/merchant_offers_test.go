package operations

import (
	"strings"
	"testing"
	"time"
)

func TestValidateOffer(t *testing.T) {
	start := time.Date(2026, 11, 10, 9, 0, 0, 0, time.FixedZone("IST", 5*3600+1800))
	end := start.Add(24 * time.Hour)
	title := "Diwali service offer"
	description := "Seasonal discount for local customers"
	discount := 15
	valid := offerInput{Title: &title, Description: &description, StartsAt: &start, EndsAt: &end, DiscountPercent: &discount}
	if err := validateOffer(valid, true); err != nil {
		t.Fatalf("valid offer rejected: %v", err)
	}

	badEnd := start
	invalidWindow := valid
	invalidWindow.EndsAt = &badEnd
	if err := validateOffer(invalidWindow, true); err == nil {
		t.Fatal("expected non-positive offer window to fail")
	}

	badDiscount := 101
	invalidDiscount := valid
	invalidDiscount.DiscountPercent = &badDiscount
	if err := validateOffer(invalidDiscount, true); err == nil {
		t.Fatal("expected out-of-range discount to fail")
	}

	badURL := "http://example.test/offer.png"
	invalidURL := valid
	invalidURL.ImageURL = &badURL
	if err := validateOffer(invalidURL, true); err == nil {
		t.Fatal("expected non-HTTPS image URL to fail")
	}

	longTitle := strings.Repeat("x", 101)
	invalidTitle := valid
	invalidTitle.Title = &longTitle
	if err := validateOffer(invalidTitle, true); err == nil {
		t.Fatal("expected excessive title length to fail")
	}
}

func TestValidateOfferPatchAllowsPartialChanges(t *testing.T) {
	title := "Updated offer"
	if err := validateOffer(offerInput{Title: &title}, false); err != nil {
		t.Fatalf("valid partial update rejected: %v", err)
	}
	if err := validateOffer(offerInput{}, false); err != nil {
		t.Fatalf("empty patch validation should leave empty-patch rejection to handler: %v", err)
	}
}
