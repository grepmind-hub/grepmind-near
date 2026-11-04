package discovery

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestNearbyRejectsInvalidInputsBeforeDatabase(t *testing.T) {
	service := NewService(nil, nil)
	for _, query := range []string{
		"lat=NaN&lng=0", "lat=Inf&lng=0", "lat=0&lng=-Inf", "lat=91&lng=0", "lat=0&lng=181", "lat=0", "lat=0&lng=0&radius_m=50001", "lat=0&lng=0&city=" + strings.Repeat("a", 121), "lat=0&lng=0&category_slug=" + strings.Repeat("a", 101),
	} {
		t.Run(query, func(t *testing.T) {
			rec := httptest.NewRecorder()
			service.Nearby(rec, httptest.NewRequest(http.MethodGet, "/nearby?"+query, nil))
			if rec.Code != 400 {
				t.Fatalf("got %d want 400", rec.Code)
			}
		})
	}
}

func TestCityOffersRejectUnsupportedCityBeforeDatabase(t *testing.T) {
	service := NewService(nil, nil)
	for _, city := range []string{"", "Bhubaneswar", "Puri"} {
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodGet, "/api/v1/offers?city="+city, nil)
		service.ListCityOffers(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("city %q: got %d want %d", city, rec.Code, http.StatusBadRequest)
		}
	}
}

func TestNewCatalogFeedRejectsInvalidFiltersBeforeDatabase(t *testing.T) {
	service := NewService(nil, nil)
	for _, query := range []string{
		"", "city=Puri", "city=Cuttack&type=offers", "city=Jajpur&limit=0",
		"city=Cuttack&limit=51", "city=Cuttack&offset=-1", "city=Cuttack&offset=10001",
	} {
		rec := httptest.NewRecorder()
		service.ListNewCatalogItems(rec, httptest.NewRequest(http.MethodGet, "/api/v1/catalog/new-arrivals?"+query, nil))
		if rec.Code != http.StatusBadRequest {
			t.Errorf("query %q: got %d want 400", query, rec.Code)
		}
	}
}

func TestSupportedOfferCities(t *testing.T) {
	for _, city := range []string{"Cuttack", "cuttack", " Jajpur "} {
		if !isSupportedOfferCity(city) {
			t.Errorf("expected supported city %q", city)
		}
	}
	if isSupportedOfferCity("Bhubaneswar") {
		t.Fatal("Bhubaneswar must not be accepted for the city offers feed")
	}
}
