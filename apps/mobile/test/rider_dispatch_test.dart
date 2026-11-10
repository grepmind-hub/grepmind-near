import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/screens/rider_workspace_screen.dart';

void main() {
  setUpAll(() => apiClient.init(baseUrl: 'https://rider.test/api/v1'));
  setUp(() => apiClient.dio.interceptors.clear());

  test('availability conflict is not reported as a network failure', () {
    final request = RequestOptions(path: '/rider/availability');
    final error = DioException(
      requestOptions: request,
      response: Response(
        requestOptions: request,
        statusCode: 409,
        data: {
          'error': {'code': 'RIDER_UNAVAILABLE'},
        },
      ),
    );

    expect(
      riderAvailabilityErrorMessage(error),
      contains('active delivery or offer'),
    );
    expect(riderAvailabilityErrorMessage(error), isNot(contains('Network')));
  });

  test('availability connection failure gives a retryable network message', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/rider/availability'),
      type: DioExceptionType.connectionError,
    );

    expect(
      riderAvailabilityErrorMessage(error),
      'Network interruption. Reconnect and try again.',
    );
  });

  testWidgets('approved rider sees real availability and offer controls', (
    tester,
  ) async {
    apiClient.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final data = switch (options.path) {
            '/rider/profile' => {
              'data': {
                'display_name': 'QA Rider',
                'vehicle_type': 'two_wheeler',
                'approved_localities': [
                  {'name': 'Kuanpal', 'district': 'Cuttack'},
                ],
              },
            },
            '/rider/availability' => {
              'data': {
                'online': true,
                'lease_expires_at': '2026-11-07T10:00:00Z',
              },
            },
            '/rider/offers' => {
              'data': [
                {
                  'id': 'qa-offer',
                  'pickup_business': 'QA Partner',
                  'vertical': 'food',
                  'destination_locality': 'Kuanpal',
                  'destination_district': 'Cuttack',
                  'items': [
                    {
                      'quantity': 1,
                      'product_name': 'QA Meal',
                      'variant_name': 'Regular',
                    },
                  ],
                  'expires_at': '2026-11-07T10:00:00Z',
                },
              ],
            },
            _ => {'data': <dynamic>[]},
          };
          handler.resolve(
            Response(requestOptions: options, statusCode: 200, data: data),
          );
        },
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: RiderDashboardScreen()));
    await tester.pumpAndSettle();
    expect(find.text('QA Rider'), findsOneWidget);
    expect(find.text('Delivery availability'), findsOneWidget);
    expect(find.text('Incoming offers'), findsOneWidget);
    expect(find.text('QA Partner'), findsOneWidget);
    expect(find.text('1 × QA Meal Regular'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('offer errors distinguish backend rejection from network loss', () {
    final request = RequestOptions(path: '/rider/offers/qa/accept');
    final rejection = DioException(
      requestOptions: request,
      response: Response(
        requestOptions: request,
        statusCode: 409,
        data: {
          'error': {
            'code': 'RIDER_UNAVAILABLE',
            'message': 'An active delivery is already assigned to this rider.',
          },
        },
      ),
    );
    expect(
      riderOfferErrorMessage(rejection),
      'You cannot accept this offer while another delivery or rider offer is active.',
    );
    final networkFailure = DioException(
      requestOptions: request,
      type: DioExceptionType.connectionError,
    );
    expect(
      riderOfferErrorMessage(networkFailure),
      'Network interruption. Reconnect and refresh before accepting the offer.',
    );
  });

  testWidgets('assigned rider verifies partner handover before delivery', (
    tester,
  ) async {
    var executionState = 'at_pickup';
    final transitions = <String>[];
    apiClient.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.method == 'POST' &&
              options.path.endsWith('/pickup/verify')) {
            executionState = 'picked_up';
            transitions.add('pickup_verified');
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'data': {'state': executionState},
                },
              ),
            );
            return;
          }
          if (options.method == 'POST' && options.path.endsWith('/state')) {
            transitions.add(
              (options.data as Map<String, dynamic>)['state'] as String,
            );
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'data': {'state': executionState},
                },
              ),
            );
            return;
          }
          if (options.path == '/rider/assignments/active') {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'data': {
                    'job_id': 'qa-job',
                    'order_id': 'qa-order',
                    'reference_code': 'QA-ORDER',
                    'pickup_business': 'QA Partner',
                    'pickup_address': 'QA Market Road',
                    'destination_address': 'QA House, Kuanpal',
                    'destination_locality': 'Kuanpal',
                    'destination_district': 'Cuttack',
                    'recipient_name': 'QA Customer',
                    'execution_state': executionState,
                    'items': [
                      {
                        'quantity': 1,
                        'product_name': 'QA food',
                        'variant_name': 'Regular',
                      },
                    ],
                  },
                },
              ),
            );
            return;
          }
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {'data': {}},
            ),
          );
        },
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: RiderDeliveriesScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pickup · QA Market Road'), findsOneWidget);
    expect(find.text('Verify partner handover'), findsOneWidget);
    await tester.tap(find.text('Verify partner handover'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '12345678');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    expect(transitions, contains('pickup_verified'));
    expect(find.textContaining('Status · picked up'), findsOneWidget);
    expect(find.text('Start delivery'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'recovery report is idempotent and does not release the assignment',
    (tester) async {
      var activeAssignmentReads = 0;
      String? recoveryKey;
      apiClient.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/rider/assignments/active') {
              activeAssignmentReads++;
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'job_id': 'qa-recovery-job',
                      'order_id': 'qa-recovery-order',
                      'reference_code': 'QA-RECOVERY',
                      'pickup_business': 'QA Partner',
                      'destination_locality': 'Kuanpal',
                      'destination_district': 'Cuttack',
                      'execution_state': 'assigned',
                      'items': <dynamic>[],
                    },
                  },
                ),
              );
              return;
            }
            if (options.path.endsWith('/unable-to-continue')) {
              recoveryKey = options.headers['Idempotency-Key']?.toString();
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 201,
                  data: {
                    'data': {'state': 'open'},
                  },
                ),
              );
              return;
            }
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'data': {}},
              ),
            );
          },
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: RiderDeliveriesScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unable to continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vehicle issue'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'The vehicle cannot continue safely.',
      );
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(recoveryKey, isNotNull);
      expect(recoveryKey!.length, greaterThanOrEqualTo(8));
      expect(activeAssignmentReads, 2);
      expect(find.textContaining('You remain assigned'), findsOneWidget);
      expect(find.textContaining('Status · assigned'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'authoritative return state replaces the stale recovery report banner',
    (tester) async {
      var executionState = 'assigned';
      apiClient.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/rider/assignments/active') {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'data': {
                      'job_id': 'qa-return-job',
                      'order_id': 'qa-return-order',
                      'reference_code': 'QA-RETURN',
                      'pickup_business': 'QA Partner',
                      'destination_locality': 'Kuanpal',
                      'destination_district': 'Cuttack',
                      'execution_state': executionState,
                      'items': <dynamic>[],
                    },
                  },
                ),
              );
              return;
            }
            if (options.path.endsWith('/unable-to-continue')) {
              executionState = 'return_required';
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 201,
                  data: {
                    'data': {'state': 'open'},
                  },
                ),
              );
              return;
            }
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'data': {}},
              ),
            );
          },
        ),
      );

      await tester.pumpWidget(const MaterialApp(home: RiderDeliveriesScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unable to continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vehicle issue'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'The vehicle cannot continue safely.',
      );
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Status · return required'), findsOneWidget);
      expect(find.text('Start return to partner'), findsOneWidget);
      expect(find.textContaining('Report received'), findsNothing);
      expect(find.textContaining('You remain assigned'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
