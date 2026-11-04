package main

import "testing"

func TestServiceRequestRescheduleUsesDedicatedWorkflow(t *testing.T) {
	tests := []struct {
		from string
		to   string
		want bool
	}{
		{from: "requested", to: "accepted", want: true},
		{from: "accepted", to: "in_progress", want: true},
		{from: "accepted", to: "rescheduled", want: false},
		{from: "rescheduled", to: "accepted", want: false},
		{from: "rescheduled", to: "cancelled", want: true},
		{from: "completed", to: "accepted", want: false},
	}
	for _, test := range tests {
		t.Run(test.from+"_to_"+test.to, func(t *testing.T) {
			if got := validServiceRequestTransition(test.from, test.to); got != test.want {
				t.Fatalf("validServiceRequestTransition(%q,%q)=%v, want %v", test.from, test.to, got, test.want)
			}
		})
	}
}
