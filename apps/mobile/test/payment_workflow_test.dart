import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/providers/cod_cash_provider.dart';
import 'package:grepmind_mobile/core/providers/payment_workflow_provider.dart';
import 'package:grepmind_mobile/core/screens/order_payment_card.dart';

class _FakePaymentRepository implements PaymentRepository {
  Map<String, dynamic> payment = {
    'order_id': 'order-1',
    'payment_status': 'not_collected',
    'payment_intent_id': '',
    'intent_status': '',
    'amount_minor': 12950,
    'currency': 'INR',
    'latest_attempt_id': '',
    'latest_attempt_status': '',
    'eligible': true,
    'refundable_amount_minor': 0,
    'refunds': <Map<String, dynamic>>[],
  };
  final intentKeys = <String>[];
  final sessionKeys = <String>[];
  final refundRequests = <({String key, int amount, String reason})>[];
  Completer<void>? sessionGate;

  @override
  Future<Map<String, dynamic>> getPayment(String orderId) async => payment;
  @override
  Future<Map<String, dynamic>> createIntent(String orderId, String key) async {
    intentKeys.add(key);
    return {'id': 'intent-1'};
  }

  @override
  Future<Map<String, dynamic>> createSession(String orderId, String key) async {
    sessionKeys.add(key);
    await sessionGate?.future;
    payment = {
      ...payment,
      'payment_intent_id': 'intent-1',
      'latest_attempt_status': 'pending',
    };
    return {'attempt_id': 'attempt-1'};
  }

  @override
  Future<Map<String, dynamic>> simulatePayment(
    String orderId,
    String status,
  ) async => {'status': status};
  @override
  Future<Map<String, dynamic>> requestRefund(
    String orderId,
    String key,
    int amountMinor,
    String reasonCode,
  ) async {
    refundRequests.add((key: key, amount: amountMinor, reason: reasonCode));
    payment = {
      ...payment,
      'refundable_amount_minor': 0,
      'refunds': [
        {
          'id': 'refund-1',
          'amount_minor': amountMinor,
          'currency': 'INR',
          'status': 'requested',
          'reason_code': reasonCode,
        },
      ],
    };
    return {'id': 'refund-1'};
  }

  @override
  Future<Map<String, dynamic>> simulateRefund(
    String orderId,
    String refundId,
    String status,
  ) async => {'status': status};
}

class _FakeCODStatusRepository implements CODStatusRepository {
  int calls = 0;

  @override
  Future<Map<String, dynamic>> getCustomerStatus(String orderId) async {
    calls++;
    expect(orderId, 'cod-order-1');
    return {
      'order_id': orderId,
      'payment_method': 'cash_on_delivery',
      'payment_status': 'not_collected',
      'cod': {
        'amount_minor': 12950,
        'currency': 'INR',
        'collection_state': 'due',
        'collected': false,
        'mode': 'synthetic_qa',
      },
    };
  }
}

void main() {
  const user = AppUser(
    id: 'qa-customer',
    phoneE164: '+919000000001',
    status: 'active',
    preferredLanguage: 'en',
    roles: ['customer'],
  );

  testWidgets(
    'COD status is synthetic, server-backed, and has no UPI actions',
    (tester) async {
      final repository = _FakeCODStatusRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            codStatusRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: OrderPaymentCard(
                orderId: 'cod-order-1',
                paymentStatus: 'not_collected',
                paymentMethod: 'cash_on_delivery',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.calls, 1);
      expect(find.text('Cash on Delivery'), findsOneWidget);
      expect(find.textContaining('SYNTHETIC QA ONLY'), findsOneWidget);
      expect(find.text('₹129.50'), findsOneWidget);
      expect(find.text('Not collected'), findsOneWidget);
      expect(find.text('Electronic payment status'), findsOneWidget);
      expect(find.text('Start sandbox payment'), findsNothing);
      expect(find.text('Request sandbox refund'), findsNothing);
    },
  );

  testWidgets(
    'shows sandbox disclosure and disables duplicate session submits',
    (tester) async {
      final repository = _FakePaymentRepository()
        ..sessionGate = Completer<void>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(user),
            paymentRepositoryProvider.overrideWith((ref) => repository),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: OrderPaymentCard(
                orderId: 'order-1',
                paymentStatus: 'not_collected',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('SANDBOX PAYMENT — No real money will be charged.'),
        findsOneWidget,
      );
      expect(find.text('₹129.50'), findsOneWidget);
      final pay = find.text('Start sandbox payment');
      expect(pay, findsOneWidget);
      await tester.tap(pay);
      await tester.pump();
      expect(find.text('Preparing sandbox session…'), findsOneWidget);
      final disabledButton = tester.widget<FilledButton>(
        find.byType(FilledButton).first,
      );
      expect(disabledButton.onPressed, isNull);
      expect(repository.sessionKeys, hasLength(1));
      repository.sessionGate!.complete();
      await tester.pumpAndSettle();
      expect(repository.intentKeys, hasLength(1));
      expect(repository.sessionKeys, hasLength(1));
    },
  );

  testWidgets(
    'refund request requires confirmation and uses server refundable amount',
    (tester) async {
      final repository = _FakePaymentRepository()
        ..payment = {
          ..._FakePaymentRepository().payment,
          'payment_status': 'paid',
          'refundable_amount_minor': 5000,
        };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(user),
            paymentRepositoryProvider.overrideWith((ref) => repository),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: OrderPaymentCard(orderId: 'order-1', paymentStatus: 'paid'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request sandbox refund'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Items missing'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Request finance review for ₹50.00'),
        findsOneWidget,
      );
      expect(repository.refundRequests, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repository.refundRequests, isEmpty);

      await tester.tap(find.text('Request sandbox refund'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Items missing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit request'));
      await tester.pumpAndSettle();
      expect(repository.refundRequests, hasLength(1));
      expect(repository.refundRequests.single.amount, 5000);
      expect(repository.refundRequests.single.reason, 'items_missing');
      expect(find.textContaining('Awaiting finance review'), findsOneWidget);
    },
  );

  test(
    'retains the idempotency key when session result is ambiguous',
    () async {
      final repository = _AmbiguousPaymentRepository();
      final notifier = PaymentWorkflowNotifier('order-1', repository);
      await notifier.load();
      await notifier.startPayment();
      await notifier.startPayment();
      expect(repository.sessionKeys, hasLength(2));
      expect(repository.sessionKeys.first, repository.sessionKeys.last);
      expect(repository.clientAmounts, isEmpty);
      notifier.dispose();
    },
  );
}

class _AmbiguousPaymentRepository extends _FakePaymentRepository {
  int calls = 0;
  final clientAmounts = <Object>[];
  @override
  Future<Map<String, dynamic>> createSession(String orderId, String key) async {
    sessionKeys.add(key);
    calls++;
    if (calls == 1) throw StateError('simulated lost session response');
    payment = {
      ...payment,
      'payment_intent_id': 'intent-1',
      'latest_attempt_status': 'pending',
    };
    return {'attempt_id': 'attempt-1'};
  }
}
