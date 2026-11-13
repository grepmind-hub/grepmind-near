import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/screens/rider_workspace_screen.dart';

void main() {
  setUpAll(() => apiClient.init(baseUrl: 'https://rider-cod.test/api/v1'));
  setUp(() => apiClient.dio.interceptors.clear());

  testWidgets(
    'remittance submission closes safely and refreshes liability history',
    (tester) async {
      final remittances = <Map<String, dynamic>>[];
      apiClient.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/rider/cash-accountability') {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'collected_minor': 34500,
                      'verified_remitted_minor': remittances.fold<int>(
                        0,
                        (total, item) =>
                            total +
                            (item['state'] == 'verified'
                                ? item['amount_minor'] as int
                                : 0),
                      ),
                      'outstanding_liability_minor': 34500,
                      'pending_remittance_minor': remittances.fold<int>(
                        0,
                        (total, item) =>
                            total +
                            (item['state'] == 'submitted'
                                ? item['amount_minor'] as int
                                : 0),
                      ),
                      'disputed_remittance_minor': 0,
                    },
                  },
                ),
              );
              return;
            }
            if (options.path == '/rider/cash-remittances' &&
                options.method == 'GET') {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'data': remittances},
                ),
              );
              return;
            }
            if (options.path == '/rider/cash-remittances' &&
                options.method == 'POST') {
              final body = options.data as Map<String, dynamic>;
              remittances.add({
                'amount_minor': body['amount_minor'],
                'submission_reference': body['submission_reference'],
                'state': 'submitted',
                'submitted_at': '2026-11-11T12:00:00Z',
              });
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 201,
                  data: const {
                    'data': {'id': 'qa-remittance'},
                  },
                ),
              );
              return;
            }
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(home: RiderCashAccountabilityScreen()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit synthetic remittance'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '345');
      await tester.enterText(find.byType(TextField).at(1), 'QA-remit-01');
      await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(remittances, hasLength(1));
      expect(find.textContaining('QA-remit-01'), findsOneWidget);
      expect(find.text('submitted'), findsOneWidget);
      expect(find.text('Pending verification'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
