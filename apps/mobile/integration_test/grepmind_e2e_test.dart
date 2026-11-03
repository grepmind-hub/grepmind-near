import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:grepmind_mobile/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  apiClient.init();
  group('Grepmind Near App Tests', () {
    setUp(() async {
      WidgetsFlutterBinding.ensureInitialized();
    });

    testWidgets('App launches and shows splash screen', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const ProviderScope(child: GrepmindNearApp()));
      await tester.pumpAndSettle();

      expect(find.byType(GrepmindNearApp), findsOneWidget);
    });

    testWidgets('Login flow - enter phone and verify OTP', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const ProviderScope(child: GrepmindNearApp()));
      await tester.pumpAndSettle();

      // Enter phone number
      await tester.tap(find.byKey(const Key('phoneInput')));
      final generatedDigits =
          (DateTime.now().millisecondsSinceEpoch % 10000000000)
              .toString()
              .padLeft(10, '0');
      await tester.enterText(
        find.byType(EditableText).last,
        '+91$generatedDigits',
      );

      // Send OTP
      await tester.tap(find.byKey(const Key('sendOTPButton')));
      await tester.pumpAndSettle();

      // Enter OTP code
      final localCodeLabel = tester.widget<Text>(
        find.textContaining('Local development code:'),
      );
      final code = localCodeLabel.data!.split(': ').last;
      await tester.tap(find.byKey(const Key('otpInput')));
      await tester.enterText(find.byType(EditableText).last, code);

      // Verify OTP
      await tester.tap(find.byKey(const Key('verifyOTPButton')));
      await tester.pumpAndSettle();

      // Verify home screen loads
      expect(find.text('Welcome to Grepmind Near'), findsOneWidget);
    });

    testWidgets('Search businesses', (WidgetTester tester) async {
      await tester.pumpWidget(const ProviderScope(child: GrepmindNearApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('searchInput')));
      await tester.enterText(find.byType(EditableText).last, 'restaurant');
      await tester.pumpAndSettle();

      expect(find.text('Spice Garden Restaurant'), findsOneWidget);
    });

    testWidgets('Service request flow', (WidgetTester tester) async {
      await tester.pumpWidget(const ProviderScope(child: GrepmindNearApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('requestServiceButton')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('serviceDropdown')));
      await tester.tap(find.text('Plumbing'));

      await tester.tap(find.byKey(const Key('descriptionInput')));
      await tester.enterText(
        find.byType(EditableText).last,
        'Leaking tap needs repair',
      );

      await tester.tap(find.byKey(const Key('submitRequestButton')));
      await tester.pumpAndSettle();

      expect(
        find.text('Service request submitted successfully'),
        findsOneWidget,
      );
    });

    testWidgets('Order history screen', (WidgetTester tester) async {
      await tester.pumpWidget(const ProviderScope(child: GrepmindNearApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('profileTab')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('myOrdersTab')));
      await tester.pumpAndSettle();

      expect(find.text('My Orders & Bookings'), findsOneWidget);
    });

    testWidgets('Order tracking screen', (WidgetTester tester) async {
      await tester.pumpWidget(const ProviderScope(child: GrepmindNearApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('profileTab')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('myOrdersTab')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('orderCard_GN-FD-07580')));
      await tester.pumpAndSettle();

      expect(find.text('Live Order Tracking'), findsOneWidget);
    });

    testWidgets('Merchant registration', (WidgetTester tester) async {
      await tester.pumpWidget(const ProviderScope(child: GrepmindNearApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('merchantRegistrationButton')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('merchantRegistrationPhoneInput')));
      await tester.enterText(find.byType(EditableText).last, '+919876543211');

      await tester.tap(find.byKey(const Key('merchantRegisterButton')));
      await tester.pumpAndSettle();

      expect(find.text('Merchant registration submitted'), findsOneWidget);
    });
  });
}
