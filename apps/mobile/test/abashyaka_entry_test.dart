import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/onboarding_screen.dart';
import 'package:grepmind_mobile/core/screens/splash_screen.dart';
import 'package:grepmind_mobile/features/onboarding/introduction_preferences.dart';
import 'package:grepmind_mobile/features/onboarding/introduction_screen.dart';
import 'package:grepmind_mobile/main.dart';

class MemoryPreferences extends IntroductionPreferences {
  MemoryPreferences({this.seen = false, this.readFails = false});
  bool seen;
  bool readFails;
  bool writeFails = false;
  int writes = 0;

  @override
  Future<bool> isComplete() async {
    if (readFails) throw StateError('Preference unavailable');
    return seen;
  }

  @override
  Future<void> complete() async {
    writes++;
    if (writeFails) throw StateError('Preference unavailable');
    seen = true;
  }
}

class MemoryAuth extends AuthNotifier {
  MemoryAuth(AuthState initial) : super.forTesting() {
    state = initial;
  }
  int otpRequests = 0;

  void restore(AuthState value) => state = value;

  @override
  Future<AppUser?> refreshCurrentUser() async => state.user;

  @override
  Future<Map<String, dynamic>?> requestOTP(String phone) async {
    otpRequests++;
    return null;
  }
}

Widget entry(MemoryPreferences preferences) => ProviderScope(
  overrides: [introductionPreferencesProvider.overrideWithValue(preferences)],
  child: const MaterialApp(home: IntroductionScreen()),
);

void main() {
  setUpAll(() => apiClient.init());

  testWidgets('first welcome persists once and opens existing OTP entry', (
    tester,
  ) async {
    final preferences = MemoryPreferences();
    await tester.pumpWidget(entry(preferences));
    await tester.pumpAndSettle();
    expect(find.text('Get started'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('getStartedButton')));
    await tester.tap(find.byKey(const Key('getStartedButton')));
    await tester.tap(find.byKey(const Key('getStartedButton')));
    await tester.pumpAndSettle();
    expect(preferences.writes, 1);
    expect(find.byKey(const Key('phoneInput')), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed introduction returns directly to phone entry', (
    tester,
  ) async {
    await tester.pumpWidget(entry(MemoryPreferences(seen: true)));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('Get started'), findsNothing);
  });

  testWidgets('preference failure offers recovery without blocking sign in', (
    tester,
  ) async {
    final preferences = MemoryPreferences(readFails: true)..writeFails = true;
    await tester.pumpWidget(entry(preferences));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Could not load your welcome preference'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byKey(const Key('getStartedButton')));
    await tester.tap(find.byKey(const Key('getStartedButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('phoneInput')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('entry screens fit small Android screens at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final screen in [
      const SplashScreen(),
      const IntroductionScreen(),
      const OnboardingScreen(),
    ]) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            introductionPreferencesProvider.overrideWithValue(
              MemoryPreferences(),
            ),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: screen,
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester.takeException(),
        isNull,
        reason: '$screen should not overflow',
      );
    }
  });

  testWidgets('session loading never mounts introduction or requests OTP', (
    tester,
  ) async {
    final auth = MemoryAuth(const AuthState(isLoading: true));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => auth),
          introductionPreferencesProvider.overrideWithValue(
            MemoryPreferences(),
          ),
        ],
        child: const GrepmindNearApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(IntroductionScreen), findsNothing);
    expect(auth.otpRequests, 0);
    auth.restore(
      const AuthState(
        user: AppUser(
          id: 'qa-user',
          phoneE164: '+919990000171',
          status: 'active',
          preferredLanguage: 'en',
          roles: ['customer'],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(IntroductionScreen), findsNothing);
    expect(find.text('Select Portal Experience'), findsOneWidget);
    expect(auth.otpRequests, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
