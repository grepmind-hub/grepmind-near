package operations

import (
	"testing"
	"time"
)

func TestValidateSlotWindowUsesBusinessTimeZone(t *testing.T) {
	date := time.Now().In(mustLoadLocation("Asia/Kolkata")).AddDate(0, 0, 7).Format("2006-01-02")
	start, end, _, err := validateSlotWindow(slotMutation{
		Date: date, StartsAt: "10:00", EndsAt: "11:00", Capacity: 1,
	}, "Asia/Kolkata")
	if err != nil {
		t.Fatal(err)
	}
	if start.Hour() != 4 || start.Minute() != 30 || end.Sub(start) != time.Hour {
		t.Fatalf("India local time conversion incorrect: start=%s end=%s", start, end)
	}
}

func TestValidateSlotWindowRejectsInvalidAndAmbiguousWallTimes(t *testing.T) {
	for _, tc := range []struct {
		name, date, start, end, zone string
	}{
		{"nonexistent DST time", "2026-03-08", "02:30", "03:30", "America/New_York"},
		{"ambiguous DST time", "2026-11-01", "01:30", "02:30", "America/New_York"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			date, err := time.Parse("2006-01-02", tc.date)
			if err != nil {
				t.Fatal(err)
			}
			location, err := time.LoadLocation(tc.zone)
			if err != nil {
				t.Fatal(err)
			}
			_, err = localWallTime(date, tc.start, location)
			if err == nil {
				t.Fatal("expected invalid/ambiguous local time to be rejected")
			}
		})
	}
}
