import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/onboarding_screen.dart';
import 'package:grepmind_mobile/core/screens/splash_screen.dart';

class _FakeAuthNotifier extends AuthNotifier {
  int requestCount = 0;

  @override
  Future<Map<String, dynamic>?> requestOTP(String phone) async {
    requestCount++;
    return {
      'phone_e164': phone,
      'otp_code': '654321',
      'status': 'otp_requested',
    };
  }

  @override
  Future<bool> verifyOTP(String phone, String otpCode) async => true;
}

void main() {
  testWidgets('splash uses the local discovery illustration', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Everything nearby.\nOne tap away.'), findsOneWidget);
  });

  testWidgets('OTP step presents six cells and generated local code', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authProvider.overrideWith((ref) => _FakeAuthNotifier())],
        child: const MaterialApp(home: OnboardingScreen()),
      ),
    );

    await tester.enterText(find.byKey(const Key('phoneInput')), '9876543210');
    await tester.tap(find.byKey(const Key('sendOTPButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const Key('otpInput')), findsOneWidget);
    expect(find.text('Local development code: 654321'), findsOneWidget);
    expect(find.text('Resend code in 00:60'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('otpInput')), '123456');
    await tester.pump();
    for (final digit in '123456'.split('')) {
      expect(find.text(digit), findsOneWidget);
    }
  });

  testWidgets('welcome login shows branded artwork and Google option', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authProvider.overrideWith((ref) => _FakeAuthNotifier())],
        child: const MaterialApp(home: OnboardingScreen()),
      ),
    );

    expect(find.byKey(const Key('loginWelcomeImage')), findsOneWidget);
    expect(find.byKey(const Key('googleSignInButton')), findsOneWidget);
    expect(find.text('🇮🇳'), findsOneWidget);
    expect(find.text('+91'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('googleSignInButton')));
    await tester.tap(find.byKey(const Key('googleSignInButton')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining('Google sign-in will be available'),
      findsOneWidget,
    );
  });

  testWidgets('rejects invalid Indian mobile numbers before requesting OTP', (
    tester,
  ) async {
    final auth = _FakeAuthNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authProvider.overrideWith((ref) => auth)],
        child: const MaterialApp(home: OnboardingScreen()),
      ),
    );

    await tester.enterText(find.byKey(const Key('phoneInput')), '1234567890');
    await tester.tap(find.byKey(const Key('sendOTPButton')));
    await tester.pump();

    expect(auth.requestCount, 0);
    expect(
      find.text('Enter a valid 10-digit Indian mobile number'),
      findsOneWidget,
    );
  });
}
