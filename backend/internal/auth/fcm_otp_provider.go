package auth

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"grepmind-near/backend/internal/devices"
	"grepmind-near/backend/internal/fcm"
)

// fcmOTPDeliveryProvider sends OTP codes via FCM data messages.
// It is restricted to isolated QA environments and must never be enabled
// in production. FCM test OTP does not verify phone ownership.
type fcmOTPDeliveryProvider struct {
	deviceSvc *devices.Service
	fcmSvc    *fcm.Service
	env       string
	enabled   bool
	channelID string
}

// FCMOTPConfig configures the FCM test OTP delivery provider.
type FCMOTPConfig struct {
	DeviceService  *devices.Service
	FCMService     *fcm.Service
	Environment    string
	Enabled        bool
	AndroidChannel string
}

// NewFCMOTPDeliveryProvider creates an FCM test OTP provider.
// It returns an error if enabled outside a QA environment, enforcing fail-closed.
func NewFCMOTPDeliveryProvider(cfg FCMOTPConfig) (OTPDeliveryProvider, error) {
	if cfg.Enabled && !strings.EqualFold(cfg.Environment, "qa") {
		return nil, errors.New("FCM test OTP provider is restricted to isolated QA environments; production startup is rejected")
	}
	if cfg.Enabled && cfg.DeviceService == nil {
		return nil, errors.New("FCM test OTP provider requires a device registration service")
	}
	if cfg.Enabled && cfg.FCMService == nil {
		return nil, errors.New("FCM test OTP provider requires an FCM service")
	}
	if cfg.Enabled && cfg.AndroidChannel == "" {
		cfg.AndroidChannel = "verification"
	}
	return &fcmOTPDeliveryProvider{
		deviceSvc: cfg.DeviceService,
		fcmSvc:    cfg.FCMService,
		env:       cfg.Environment,
		enabled:   cfg.Enabled,
		channelID: cfg.AndroidChannel,
	}, nil
}

// SendOTP delivers the OTP code to the registered installation via FCM data message.
// The code is never logged or returned through this method.
func (p *fcmOTPDeliveryProvider) SendOTP(ctx context.Context, delivery OTPDelivery) error {
	if !p.enabled {
		return errors.New("FCM test OTP provider is not enabled")
	}
	if !strings.EqualFold(p.env, "qa") {
		return errors.New("FCM test OTP provider is restricted to isolated QA environments")
	}
	if p.deviceSvc == nil || p.fcmSvc == nil {
		return errors.New("FCM test OTP provider is not fully configured")
	}
	if delivery.RunID == "" {
		return errors.New("QA OTP run ID is required")
	}
	if delivery.InstallationID == "" {
		return errors.New("installation ID is required for FCM OTP delivery")
	}

	// Look up the active registration by installation ID. This supports
	// pre-login test installations where the user may not exist yet.
	reg, err := p.deviceSvc.GetByInstallationID(ctx, delivery.InstallationID)
	if err != nil {
		return fmt.Errorf("device lookup: %w", err)
	}

	// Send a data-only FCM message so the OTP is not displayed on the lock screen.
	// The Flutter app receives the data message and displays the verification banner.
	msg := fcmOTPMessage(reg.FCMToken, delivery, reg.NotificationPermission)
	result, sendErr := p.fcmSvc.Send(ctx, msg)
	if sendErr != nil {
		if fcm.IsInvalidToken(sendErr) {
			if revokeErr := p.deviceSvc.MarkTokenInvalid(ctx, reg.FCMToken); revokeErr != nil {
				return revokeErr
			}
		}
		return fmt.Errorf("FCM send: %w", sendErr)
	}
	_ = result
	return nil
}

func fcmOTPMessage(token string, delivery OTPDelivery, permission bool) fcm.Message {
	return fcm.Message{
		Token: token,
		Data: map[string]string{
			"type":                    "otp",
			"otp_code":                delivery.Code,
			"challenge_id":            delivery.ChallengeID,
			"phone_e164":              delivery.PhoneE164,
			"expires_at":              delivery.ExpiresAt.UTC().Format(time.RFC3339),
			"run_id":                  delivery.RunID,
			"channel":                 "verification",
			"notification_permission": fmt.Sprintf("%v", permission),
		},
	}
}
