import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:grepmind_mobile/main.dart';

void main() {
  group('Grepmind Near App Tests', () {
    setUp(() async {
      WidgetsFlutterBinding.ensureInitialized();
    });

    testWidgets('App launches and shows splash screen', (WidgetTester tester) async {
      await tester.pumpWidget(const GrepmindNearApp());
      await tester.pumpAndSettle();

      expect(find.byType(GrepmindNearApp), findsOneWidget);
    });

    testWidgets('Login flow - enter phone and verify OTP', (WidgetTester tester) async {
      await tester.pumpWidget(const GrepmindNearApp());
      await tester.pumpAndSettle();

      // Enter phone number
      await tester.tap(find.byKey('phoneInput'));
      await tester.enterText('+919876543210');

      // Send OTP
      await tester.tap(find.byKey('sendOTPButton'));
      await tester.pumpAndSettle();

      // Enter OTP code
      await tester.tap(find.byKey('otpInput'));
      await tester.enterText('123456');

      // Verify OTP
      await tester.tap(find.byKey('verifyOTPButton'));
      await tester.pumpAndSettle();

      // Verify home screen loads
      expect(find.text('Welcome to Grepmind Near'), findsOneWidget);
    });

    testWidgets('Search businesses', (WidgetTester tester) async {
      await tester.pumpWidget(const GrepmindNearApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey('searchInput'));
      await tester.enterText('restaurant');
      await tester.pumpAndSettle();

      expect(find.text('Spice Garden Restaurant'), findsOneWidget);
    });

    testWidgets('Service request flow', (WidgetTester tester) async {
      await tester.pumpWidget(const GrepmindNearApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey('requestServiceButton'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey('serviceDropdown'));
      await tester.tap(find.text('Plumbing'));

      await tester.tap(find.byKey('descriptionInput'));
      await tester.enterText('Leaking tap needs repair');

      await tester.tap(find.byKey('submitRequestButton'));
      await tester.pumpAndSettle();

      expect(find.text('Service request submitted successfully'), findsOneWidget);
    });

    testWidgets('Order history screen', (WidgetTester tester) async {
      await tester.pumpWidget(const GrepmindNearApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey('profileTab'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey('myOrdersTab'));
      await tester.pumpAndSettle();

      expect(find.text('My Orders & Bookings'), findsOneWidget);
    });

    testWidgets('Order tracking screen', (WidgetTester tester) async {
      await tester.pumpWidget(const GrepmindNearApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey('profileTab'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey('myOrdersTab'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey('orderCard_GN-FD-07580'));
      await tester.pumpAndSettle();

      expect(find.text('Live Order Tracking'), findsOneWidget);
    });

    testWidgets('Merchant registration', (WidgetTester tester) async {
      await tester.pumpWidget(const GrepmindNearApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey('merchantRegistrationButton'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey('merchantRegistrationPhoneInput'));
      await tester.enterText('+919876543211');

      await tester.tap(find.byKey('merchantRegisterButton'));
      await tester.pumpAndSettle();

      expect(find.text('Merchant registration submitted'), findsOneWidget);
    });
  });
}
