package auth

import (
	"testing"
	"time"
)

func TestFCMOTPMessageIsDataOnly(t *testing.T) {
	msg := fcmOTPMessage("device", OTPDelivery{Code: "123456", ChallengeID: "challenge", ExpiresAt: time.Now()}, true)
	if msg.Title != "" || msg.Body != "" || msg.AndroidChannel != "" {
		t.Fatal("OTP must not be sent as an Android notification")
	}
	if msg.Data["otp_code"] != "123456" || msg.Data["challenge_id"] != "challenge" {
		t.Fatal("OTP data must be bound to its challenge")
	}
}
