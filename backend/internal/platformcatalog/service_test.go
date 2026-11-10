package platformcatalog

import (
	"encoding/json"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestNormalizeCityRestrictsPlatformCatalogToLaunchCities(t *testing.T) {
	for _, city := range []string{"Cuttack", "cuttack", " Jajpur "} {
		if _, ok := normalizeCity(city); !ok {
			t.Errorf("normalizeCity(%q) rejected a supported launch city", city)
		}
	}
	for _, city := range []string{"Bhubaneswar", "Puri", ""} {
		if _, ok := normalizeCity(city); ok {
			t.Errorf("normalizeCity(%q) accepted an unsupported city", city)
		}
	}
}

func TestCleanAreasRejectsDuplicatesAndUnknownCities(t *testing.T) {
	if _, ok := cleanAreas([]Area{{City: "Cuttack"}, {City: "cuttack"}}); ok {
		t.Fatal("duplicate city areas should be rejected")
	}
	if _, ok := cleanAreas([]Area{{City: "Bhubaneswar"}}); ok {
		t.Fatal("unsupported city should be rejected")
	}
	if areas, ok := cleanAreas([]Area{{City: "Jajpur", Locality: stringPtr("Town")}}); !ok || len(areas) != 1 || areas[0].City != "Jajpur" {
		t.Fatalf("valid locality area rejected: %#v", areas)
	}
}

func TestCleanAreasAcceptsStableDistrictAndLocalityIDs(t *testing.T) {
	area := Area{DistrictID: "02200000-0000-4000-8000-000000000001", LocalityID: "02200000-0000-4000-8000-000000000101"}
	cleaned, ok := cleanAreas([]Area{area})
	if !ok || len(cleaned) != 1 || cleaned[0].DistrictID != area.DistrictID || cleaned[0].LocalityID != area.LocalityID {
		t.Fatalf("stable locality references rejected or changed: %#v, %v", cleaned, ok)
	}
	if _, ok := cleanAreas([]Area{{DistrictID: area.DistrictID, LocalityID: "not-a-uuid"}}); ok {
		t.Fatal("invalid locality ID accepted")
	}
}

func TestCleanVariantsRequiresINRAndNonNegativeMinorUnits(t *testing.T) {
	valid := variantInput{SKU: "RICE-1", Name: "Rice", UnitLabel: "1 kg", PriceMinor: 12000, Currency: "INR"}
	if _, ok := cleanVariants([]variantInput{valid}); !ok {
		t.Fatal("valid INR variant rejected")
	}
	invalid := valid
	invalid.PriceMinor = -1
	if _, ok := cleanVariants([]variantInput{invalid}); ok {
		t.Fatal("negative price was accepted")
	}
	invalid = valid
	invalid.Currency = "USD"
	if _, ok := cleanVariants([]variantInput{invalid}); ok {
		t.Fatal("non-INR currency was accepted")
	}
}

func TestValidImageURLsAcceptsOwnedMediaPathsAndRejectsTraversal(t *testing.T) {
	if !validImageURLs([]string{"/media/catalog/abc123.png", "https://cdn.example.test/item.jpg"}) {
		t.Fatal("valid image references rejected")
	}
	for _, value := range []string{"/media/../private/key", "/media/%2e%2e/private", "/media\\..\\private", "http://cdn.example.test/item.jpg"} {
		if validImageURLs([]string{value}) {
			t.Errorf("unsafe or unsupported image URL accepted: %q", value)
		}
	}
}

func TestFinishProductDecodesImageURLJSON(t *testing.T) {
	for _, tc := range []struct {
		name string
		json string
		want []string
	}{
		{name: "empty", json: `[]`, want: []string{}},
		{name: "one image", json: `["/media/catalog/item.png"]`, want: []string{"/media/catalog/item.png"}},
		{name: "multiple images", json: `["/media/catalog/one.png","https://cdn.example.test/two.png"]`, want: []string{"/media/catalog/one.png", "https://cdn.example.test/two.png"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			row := productRow{ID: "product-id", ImageURLsJSON: []byte(tc.json), VariantsJSON: []byte(`[]`), AreasJSON: []byte(`[]`)}
			product, err := finishProduct(row)
			if err != nil {
				t.Fatalf("finishProduct returned error: %v", err)
			}
			if len(product.ImageURLs) != len(tc.want) {
				t.Fatalf("got %v, want %v", product.ImageURLs, tc.want)
			}
			for i := range tc.want {
				if product.ImageURLs[i] != tc.want[i] {
					t.Fatalf("got %v, want %v", product.ImageURLs, tc.want)
				}
			}
			if !json.Valid(row.ImageURLsJSON) {
				t.Fatal("test fixture must be valid JSON")
			}
		})
	}
}

func TestMappingValidationRequiresOneInventoryModel(t *testing.T) {
	base := mappingInput{BusinessID: "3fa85f64-5717-4562-b3fc-2c963f66afa6", VariantID: "3fa85f64-5717-4562-b3fc-2c963f66afa7", InventoryMode: "finite"}
	qty := 4
	base.AvailableQuantity = &qty
	if !validateMappingInput(&base) {
		t.Fatal("valid finite inventory mapping rejected")
	}
	capacity := 8
	base.CapacityPerDay = &capacity
	if validateMappingInput(&base) {
		t.Fatal("mapping with both finite stock and capacity accepted")
	}
}

func TestDecodeJSONRejectsSecondValueAndTrailingGarbage(t *testing.T) {
	for _, body := range []string{`{"name":"Rice"} {"name":"Dal"}`, `{"name":"Rice"} trailing`} {
		recorder := httptest.NewRecorder()
		request := httptest.NewRequest("POST", "/", strings.NewReader(body))
		var target struct {
			Name string `json:"name"`
		}
		if decodeJSON(recorder, request, &target) {
			t.Errorf("decodeJSON accepted trailing content %q", body)
		}
		if recorder.Code != 400 {
			t.Errorf("expected 400 for %q, got %d", body, recorder.Code)
		}
	}
}

func stringPtr(value string) *string { return &value }
