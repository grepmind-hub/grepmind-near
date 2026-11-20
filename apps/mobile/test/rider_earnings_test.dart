import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/screens/rider_earnings_screen.dart';

void main() {
  setUpAll(() => apiClient.init(baseUrl: 'https://rider-earnings.test/api/v1'));
  setUp(() => apiClient.dio.interceptors.clear());

  testWidgets('shows backend ledger amounts and clearly disables payouts', (
    tester,
  ) async {
    apiClient.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final data = options.path.endsWith('/summary')
              ? {
                  'data': {
                    'total_recorded_minor': '1299',
                    'currency': 'INR',
                    'completed_deliveries': 1,
                    'unpriced_deliveries': 0,
                  },
                }
              : {
                  'data': [
                    {
                      'id': 'entry-1',
                      'entry_type': 'delivery_earning',
                      'amount_minor': '1299',
                      'currency': 'INR',
                      'effective_at': '2026-11-09T10:00:00Z',
                    },
                  ],
                };
          handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: data),
          );
        },
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: RiderEarningsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('INR 12.99'), findsNWidgets(2));
    expect(
      find.textContaining('QA transfer simulations are not bank payments'),
      findsOneWidget,
    );
    expect(find.text('Completed delivery'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'shows policy review instead of inventing an amount for unpriced work',
    (tester) async {
      apiClient.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final data = options.path.endsWith('/summary')
                ? {
                    'data': {
                      'total_recorded_minor': '0',
                      'currency': 'INR',
                      'completed_deliveries': 0,
                      'unpriced_deliveries': 1,
                    },
                  }
                : {
                    'data': [
                      {
                        'id': 'unpriced-1',
                        'entry_type': 'unpriced',
                        'amount_minor': null,
                        'currency': 'INR',
                        'effective_at': '2026-11-09T10:00:00Z',
                      },
                    ],
                  };
            handler.resolve(
              Response(requestOptions: options, statusCode: 200, data: data),
            );
          },
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: RiderEarningsScreen()));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('awaiting an approved compensation policy'),
        findsOneWidget,
      );
      expect(find.text('Awaiting policy review'), findsNWidgets(2));
      expect(find.textContaining('Paid'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('preserves exact large integer minor-unit amounts', (
    tester,
  ) async {
    apiClient.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final data = options.path.endsWith('/summary')
              ? {
                  'data': {
                    'total_recorded_minor': '9223372036854775807',
                    'currency': 'INR',
                    'completed_deliveries': 1,
                    'unpriced_deliveries': 0,
                  },
                }
              : {
                  'data': [
                    {
                      'id': 'large-entry',
                      'entry_type': 'delivery_earning',
                      'amount_minor': '9223372036854775807',
                      'currency': 'INR',
                      'effective_at': '2026-11-09T10:00:00Z',
                    },
                  ],
                };
          handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: data),
          );
        },
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: RiderEarningsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('INR 92233720368547758.07'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'keeps summary totals separate when more than one currency exists',
    (tester) async {
      apiClient.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final data = options.path.endsWith('/summary')
                ? {
                    'data': {
                      'currency_totals': [
                        {
                          'currency': 'INR',
                          'total_recorded_minor': '500',
                          'completed_deliveries': 1,
                          'unpriced_deliveries': 0,
                        },
                        {
                          'currency': 'USD',
                          'total_recorded_minor': '250',
                          'completed_deliveries': 1,
                          'unpriced_deliveries': 0,
                        },
                      ],
                      'total_recorded_minor': null,
                      'currency': null,
                    },
                  }
                : {'data': []};
            handler.resolve(
              Response(requestOptions: options, statusCode: 200, data: data),
            );
          },
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: RiderEarningsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('INR 5.00'), findsOneWidget);
      expect(find.text('USD 2.50'), findsOneWidget);
      expect(find.textContaining('2 completed deliveries'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
