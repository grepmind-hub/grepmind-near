import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/notifications/notification_manager.dart';
import 'package:grepmind_mobile/core/notifications/otp_notification_banner.dart';

void main() {
  testWidgets('copy fills the active field without submitting authentication', (
    tester,
  ) async {
    String? copied;
    final payload = FcmOtpPayload(
      otpCode: '123456',
      challengeId: 'challenge',
      phoneE164: '+919000000001',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      runId: 'test',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OtpNotificationBanner(
            payload: payload,
            onCopy: (value) => copied = value,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Copy OTP'));
    await tester.pump();
    expect(copied, '123456');
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'OTP payload must match the active challenge and phone and be unexpired',
    () {
      final now = DateTime.utc(2026, 1, 1);
      final data = <String, dynamic>{
        'otp_code': '123456',
        'challenge_id': 'challenge',
        'phone_e164': '+919000000001',
        'expires_at': now.add(const Duration(minutes: 5)).toIso8601String(),
      };
      final payload = FcmOtpPayload.fromMap(data);
      expect(
        payload.matchesChallenge('challenge', '+919000000001', now),
        isTrue,
      );
      expect(payload.matchesChallenge('other', '+919000000001', now), isFalse);
      expect(
        payload.matchesChallenge('challenge', '+919000000002', now),
        isFalse,
      );
      expect(payload.matchesChallenge(null, '+919000000001', now), isFalse);
      expect(
        payload.matchesChallenge(
          'challenge',
          '+919000000001',
          now.add(const Duration(minutes: 5)),
        ),
        isFalse,
      );
      data['expires_at'] = 'invalid';
      expect(
        FcmOtpPayload.fromMap(data)
            .matchesChallenge('challenge', '+919000000001', now),
        isFalse,
      );
      data['expires_at'] = now
          .add(const Duration(minutes: 5))
          .toIso8601String();
      data['otp_code'] = 'abc123';
      expect(
        FcmOtpPayload.fromMap(data)
            .matchesChallenge('challenge', '+919000000001', now),
        isFalse,
      );
    },
  );
}
