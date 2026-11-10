import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/main.dart';

const _qaCustomerNationalNumber = '9990000171';
const _qaProductName = 'Phase 3E QA Chicken Biryani';

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 500));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for a required QA UI state.');
}

Future<void> _loginAsCustomer(WidgetTester tester) async {
  await tester.pumpWidget(const ProviderScope(child: GrepmindNearApp()));
  await _waitFor(tester, find.byKey(const Key('phoneInput')));
  await tester.enterText(
    find.byKey(const Key('phoneInput')),
    _qaCustomerNationalNumber,
  );
  await tester.tap(find.byKey(const Key('sendOTPButton')));
  await _waitFor(tester, find.textContaining('Local development code:'));
  final localCodeText = tester.widget<Text>(
    find.textContaining('Local development code:'),
  );
  final localCode = localCodeText.data!.split(':').last.trim();
  expect(localCode, matches(RegExp(r'^\d{6}$')));
  await tester.enterText(find.byKey(const Key('otpInput')), localCode);
  await tester.tap(find.byKey(const Key('verifyOTPButton')));
  final roleChoice = find.text('Customer / Explorer');
  if (await _waitFor(tester, roleChoice, timeout: const Duration(seconds: 8))
      .then((_) => true)
      .onError((_, _) => false)) {
    await tester.tap(roleChoice);
  }
  await _waitFor(tester, find.text('Order on Grepmind'));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  apiClient.init();

  testWidgets(
    'same QA customer order receives live delivery lifecycle updates',
    (tester) async {
      await _loginAsCustomer(tester);

      await tester.tap(find.text('Orders').last);
      await _waitFor(tester, find.text('Order on Grepmind'));
      await tester.tap(find.byKey(const ValueKey('orders_food_catalog')));
      await _waitFor(tester, find.text(_qaProductName));
      await tester.tap(find.text(_qaProductName).first);
      await _waitFor(tester, find.text('Available options'));
      await tester.tap(
        find.ancestor(
          of: find.text('Regular'),
          matching: find.byType(ListTile),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('platform_open_cart')));
      await _waitFor(
        tester,
        find.text('Choose address & get verified total'),
      );
      await tester.tap(find.text('Choose address & get verified total'));
      await _waitFor(tester, find.text('Home'));
      await tester.tap(find.text('Home').last);
      await _waitFor(tester, find.textContaining('Place order ·'));
      await tester.tap(find.textContaining('Place order ·'));
      await _waitFor(tester, find.text('Order request received'));

      final confirmation = tester.widget<Text>(
        find.textContaining('Reference:'),
      );
      final reference = confirmation.data!.split('Reference:').last.trim();
      expect(reference, startsWith('GN-'));
      // Safe, non-secret correlation marker for the QA operator.
      // Never print OTPs, access tokens, or delivery verification codes.
      // ignore: avoid_print
      print('PHASE3E_QA_ORDER_CREATED reference=$reference');

      await tester.tap(find.text('View My Orders'));
      await _waitFor(tester, find.text('Orders & bookings'));
      final orderRow = find.textContaining('Grepmind Food order');
      await _waitFor(tester, orderRow);
      await tester.tap(orderRow.first);
      await _waitFor(tester, find.text('Live order updates connected'));
      // ignore: avoid_print
      print('PHASE3E_CUSTOMER_TRACKING_CONNECTED reference=$reference');

      for (final milestone in const [
        'Partner accepted',
        'Partner is preparing',
        'Rider assigned',
        'Ready for pickup',
        'Rider arrived at partner',
        'Partner handover verified',
        'Order picked up',
        'On the way to you',
        'Delivered with your confirmation',
      ]) {
        await _waitFor(
          tester,
          find.text(milestone),
          timeout: const Duration(minutes: 8),
        );
        // ignore: avoid_print
        print('PHASE3E_CUSTOMER_MILESTONE reference=$reference state=$milestone');
      }

      expect(find.text('No live location or estimated arrival time is shown.'),
          findsOneWidget);
      expect(
        find.text(
          'Payment is unavailable. No payment was collected or confirmed for this order.',
        ),
        findsOneWidget,
      );
    },
    timeout: const Timeout(Duration(minutes: 80)),
  );
}
