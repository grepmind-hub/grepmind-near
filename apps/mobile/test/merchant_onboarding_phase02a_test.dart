import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/merchant_welcome_screen.dart';
import 'package:grepmind_mobile/core/screens/merchant_registration_screen.dart';
import 'package:grepmind_mobile/core/screens/merchant_workspace_screen.dart';
import 'package:grepmind_mobile/core/screens/onboarding_screen.dart';

class _FakeMerchantNotifier extends MerchantNotifier {
  @override
  Future<void> loadRequests() async {
    state = state.copyWith(
      items: const [
        MerchantServiceRequest(
          id: 'qa-req-1',
          customerName: 'Suresh Kumar',
          customerPhone: '+919990000171',
          serviceName: 'Electrical Installation',
          description: 'Wiring check',
          status: 'accepted',
          createdAt: '2026-11-19T10:00:00Z',
          updatedAt: '2026-11-19T10:00:00Z',
        ),
      ],
      isLoading: false,
    );
  }
}

class _FakeMerchantProfileNotifier extends MerchantProfileNotifier {
  _FakeMerchantProfileNotifier() : super('');

  @override
  Future<void> load() async {
    state = state.copyWith(
      profile: {
        'id': 'merchant-biz-1',
        'name': 'Food Plaza',
        'category_name': 'Restaurant (Food)',
        'address_text': 'Station Square, Bhubaneswar',
        'city': 'Bhubaneswar',
        'phone_e164': '+919990000172',
        'status': 'approved',
        'verification_status': 'verified',
      },
      isLoading: false,
    );
  }
}

class _FakeMerchantAnalyticsNotifier extends MerchantAnalyticsNotifier {
  @override
  Future<void> load() async {
    state = const MerchantAnalyticsState(
      profileViews30d: 48,
      productCatalogViews30d: 92,
    );
  }
}

void main() {
  setUpAll(() => apiClient.init());

  group('Phase 02A Merchant Onboarding & Setup Tests', () {
    testWidgets(
      'MerchantWelcomeScreen renders branded value propositions and CTAs',
      (tester) async {
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(home: MerchantWelcomeScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // Heading & Value propositions from Screen 2 of Abashyaka Merchant Showcase
        expect(find.text('Abashyaka'), findsOneWidget);
        expect(find.text('Merchant Partner'), findsOneWidget);
        expect(find.text('Grow Your Business\nwith Abashyaka'), findsOneWidget);
        expect(
          find.text('Get more customers in your locality'),
          findsOneWidget,
        );
        expect(
          find.text('Manage catalog, stock & orders easily'),
          findsOneWidget,
        );
        expect(
          find.text('Increase your sales with zero hidden fees'),
          findsOneWidget,
        );

        // CTAs
        expect(
          find.byKey(const Key('merchantGetStartedButton')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('merchantSignInButton')), findsOneWidget);
        expect(find.text('Get Started'), findsOneWidget);
        expect(find.text('Already registered? Sign In'), findsOneWidget);
      },
    );

    testWidgets(
      'MerchantWelcomeScreen navigates to registration and login screens',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(home: MerchantWelcomeScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // Tap Get Started -> opens MerchantRegistrationScreen
        await tester.ensureVisible(
          find.byKey(const Key('merchantGetStartedButton')),
        );
        await tester.tap(find.byKey(const Key('merchantGetStartedButton')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(MerchantRegistrationScreen), findsOneWidget);

        // Back to welcome
        Navigator.pop(tester.element(find.byType(MerchantRegistrationScreen)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Tap Sign In -> opens OnboardingScreen in merchant mode
        await tester.ensureVisible(
          find.byKey(const Key('merchantSignInButton')),
        );
        await tester.tap(find.byKey(const Key('merchantSignInButton')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(OnboardingScreen), findsOneWidget);
        expect(find.text('Merchant Login'), findsOneWidget);
      },
    );

    testWidgets(
      'OnboardingScreen in merchant mode displays Merchant Login and Send OTP',
      (tester) async {
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: OnboardingScreen(initialMerchantMode: true),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Exact Screen 3 layout
        expect(find.text('Merchant Login'), findsOneWidget);
        expect(
          find.text('Enter your mobile number to continue'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('phoneInput')), findsOneWidget);
        expect(find.byKey(const Key('sendOTPButton')), findsOneWidget);
        expect(find.text('Send OTP'), findsOneWidget);
        expect(find.text('Switch to Customer Login'), findsOneWidget);
        expect(find.text('Continue with Google'), findsOneWidget);
      },
    );

    testWidgets(
      'MerchantWorkspaceScreen renders Today Summary card with 4 metrics and Store Open pill',
      (tester) async {
        final merchant = _FakeMerchantNotifier();
        final profile = _FakeMerchantProfileNotifier();
        final analytics = _FakeMerchantAnalyticsNotifier();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              merchantProvider.overrideWith((ref) => merchant),
              merchantProfileProvider('').overrideWith((ref) => profile),
              merchantAnalyticsProvider.overrideWith((ref) => analytics),
            ],
            child: const MaterialApp(home: MerchantWorkspaceScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // Screen 8 Header & Metrics
        expect(find.text("Today's Summary"), findsOneWidget);
        expect(find.text('Store Open'), findsOneWidget);
        expect(find.text('Orders'), findsWidgets);
        expect(find.text('Sales'), findsOneWidget);
        expect(find.text('Bookings'), findsOneWidget);
        expect(find.text('Fulfillment'), findsOneWidget);
        expect(find.text('98%'), findsOneWidget);

        // Quick Actions
        expect(find.text('View Requests'), findsOneWidget);
        expect(find.text('+ Add Item'), findsOneWidget);
        expect(find.text('Hours & Coverage'), findsOneWidget);
        expect(find.text('Earnings & Payouts'), findsOneWidget);
      },
    );
  });
}
