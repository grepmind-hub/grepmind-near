import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/merchant_platform_orders_screen.dart';

void main() {
  setUpAll(
    () => apiClient.init(baseUrl: 'https://merchant-orders.test/api/v1'),
  );
  setUp(() => apiClient.dio.interceptors.clear());

  testWidgets('unverified UPI order cannot be accepted from Merchant Android', (
    tester,
  ) async {
    final unverifiedUpiOrder = {
      ..._order,
      'status': 'placed',
      'payment_method': 'upi',
      'payment_status': 'not_collected',
      'cod_collection_state': 'not_applicable',
    };
    apiClient.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path.endsWith('/platform-orders')) {
            return handler.resolve(
              _response(options, {
                'data': [unverifiedUpiOrder],
              }),
            );
          }
          if (options.path.endsWith('/delivery-dispatch')) {
            return handler.resolve(_response(options, {'data': []}));
          }
          return handler.reject(
            DioException(
              requestOptions: options,
              message: 'Unexpected request',
            ),
          );
        },
      ),
    );

    await _pumpScreen(tester);

    expect(find.text('Sandbox UPI'), findsOneWidget);
    expect(
      find.text('Payment is not verified; fulfillment actions are blocked.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Accept'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('pickup code is available only for a ready order at partner', (
    tester,
  ) async {
    apiClient.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path.endsWith('/platform-orders')) {
            return handler.resolve(
              _response(options, {
                'data': [_order],
              }),
            );
          }
          if (options.path.endsWith('/delivery-dispatch')) {
            return handler.resolve(
              _response(options, {
                'data': [
                  {
                    'job_id': 'qa-job-1',
                    'order_id': 'qa-order-1',
                    'execution_state': 'assigned',
                    'rider_assigned': true,
                    'rider_name': 'QA Rider',
                  },
                ],
              }),
            );
          }
          return handler.reject(
            DioException(
              requestOptions: options,
              message: 'Unexpected request',
            ),
          );
        },
      ),
    );

    await _pumpScreen(tester);

    expect(find.text('Delivery progress: assigned · QA Rider'), findsOneWidget);
    expect(find.text('Issue pickup code'), findsNothing);
  });

  testWidgets('merchant issues and clears a short-lived pickup code in app', (
    tester,
  ) async {
    var issued = false;
    final requestedPaths = <String>[];
    apiClient.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requestedPaths.add('${options.method} ${options.path}');
          if (options.path.endsWith('/platform-orders')) {
            return handler.resolve(
              _response(options, {
                'data': [_order],
              }),
            );
          }
          if (options.path.endsWith('/delivery-dispatch')) {
            return handler.resolve(
              _response(options, {
                'data': [
                  {
                    'job_id': 'qa-job-1',
                    'order_id': 'qa-order-1',
                    'execution_state': 'at_pickup',
                    'rider_assigned': true,
                    'rider_name': 'QA Rider',
                  },
                ],
              }),
            );
          }
          if (options.method == 'POST' &&
              options.path.endsWith('/delivery-jobs/qa-job-1/pickup-code')) {
            issued = true;
            return handler.resolve(
              _response(options, {
                'data': {
                  'job_id': 'qa-job-1',
                  'pickup_code': '58127463',
                  'expires_in_seconds': 300,
                },
              }),
            );
          }
          return handler.reject(
            DioException(
              requestOptions: options,
              message: 'Unexpected request',
            ),
          );
        },
      ),
    );

    await _pumpScreen(tester);

    final issueButton = find.byKey(
      const ValueKey('issue_pickup_code_qa-order-1'),
    );
    expect(issueButton, findsOneWidget);
    await tester.tap(issueButton);
    await tester.pumpAndSettle();
    expect(find.text('Issue pickup code?'), findsOneWidget);
    expect(find.textContaining('GN-QA-COD-1'), findsNWidgets(2));

    await tester.tap(find.widgetWithText(FilledButton, 'Issue code'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(issued, isTrue, reason: requestedPaths.join('\n'));
    expect(find.text('Partner-to-rider handover'), findsOneWidget);
    expect(find.text('58127463'), findsOneWidget);
    expect(find.textContaining('Expires in 300 seconds'), findsOneWidget);

    await tester.tap(find.text('Close and clear'));
    await tester.pumpAndSettle();
    expect(find.text('58127463'), findsNothing);
  });

  testWidgets('refreshes dispatch after rider arrives at pickup', (
    tester,
  ) async {
    var dispatchRequests = 0;
    apiClient.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path.endsWith('/platform-orders')) {
            return handler.resolve(
              _response(options, {
                'data': [_order],
              }),
            );
          }
          if (options.path.endsWith('/delivery-dispatch')) {
            dispatchRequests++;
            return handler.resolve(
              _response(options, {
                'data': [
                  {
                    'job_id': 'qa-job-1',
                    'order_id': 'qa-order-1',
                    'execution_state': dispatchRequests == 1
                        ? 'assigned'
                        : 'at_pickup',
                    'rider_assigned': true,
                    'rider_name': 'QA Rider',
                  },
                ],
              }),
            );
          }
          return handler.reject(
            DioException(
              requestOptions: options,
              message: 'Unexpected request',
            ),
          );
        },
      ),
    );

    await _pumpScreen(tester);
    expect(find.text('Delivery progress: assigned · QA Rider'), findsOneWidget);
    expect(find.text('Issue pickup code'), findsNothing);

    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();

    expect(dispatchRequests, greaterThanOrEqualTo(2));
    expect(
      find.text('Delivery progress: at pickup · QA Rider'),
      findsOneWidget,
    );
    expect(find.text('Issue pickup code'), findsOneWidget);
  });

  testWidgets('backend denial is shown and does not expose a pickup code', (
    tester,
  ) async {
    apiClient.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path.endsWith('/platform-orders')) {
            return handler.resolve(
              _response(options, {
                'data': [_order],
              }),
            );
          }
          if (options.path.endsWith('/delivery-dispatch')) {
            return handler.resolve(
              _response(options, {
                'data': [
                  {
                    'job_id': 'qa-job-1',
                    'order_id': 'qa-order-1',
                    'execution_state': 'at_pickup',
                    'rider_assigned': true,
                  },
                ],
              }),
            );
          }
          if (options.method == 'POST' &&
              options.path.endsWith('/delivery-jobs/qa-job-1/pickup-code')) {
            return handler.reject(
              DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: 409,
                  data: {
                    'error': {
                      'code': 'INVALID_PICKUP_STATE',
                      'message': 'The rider is no longer at pickup.',
                    },
                  },
                ),
              ),
            );
          }
          return handler.reject(
            DioException(
              requestOptions: options,
              message: 'Unexpected request',
            ),
          );
        },
      ),
    );

    await _pumpScreen(tester);
    await tester.tap(find.text('Issue pickup code'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Issue code'));
    await tester.pumpAndSettle();

    expect(find.text('The rider is no longer at pickup.'), findsOneWidget);
    expect(find.text('Partner-to-rider handover'), findsNothing);
  });

  testWidgets('rapid confirmation taps submit pickup issuance once', (
    tester,
  ) async {
    var issueRequests = 0;
    apiClient.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path.endsWith('/platform-orders')) {
            return handler.resolve(
              _response(options, {
                'data': [_order],
              }),
            );
          }
          if (options.path.endsWith('/delivery-dispatch')) {
            return handler.resolve(
              _response(options, {
                'data': [
                  {
                    'job_id': 'qa-job-1',
                    'order_id': 'qa-order-1',
                    'execution_state': 'at_pickup',
                    'rider_assigned': true,
                  },
                ],
              }),
            );
          }
          if (options.method == 'POST' &&
              options.path.endsWith('/delivery-jobs/qa-job-1/pickup-code')) {
            issueRequests++;
            return handler.resolve(
              _response(options, {
                'data': {'pickup_code': '58127463', 'expires_in_seconds': 300},
              }),
            );
          }
          return handler.reject(
            DioException(
              requestOptions: options,
              message: 'Unexpected request',
            ),
          );
        },
      ),
    );

    await _pumpScreen(tester);
    final issueButton = find.byKey(
      const ValueKey('issue_pickup_code_qa-order-1'),
    );
    await tester.tap(issueButton);
    await tester.tap(issueButton, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Issue pickup code?'), findsOneWidget);
    expect(find.text('Confirming…'), findsOneWidget);
    expect(tester.widget<FilledButton>(issueButton).onPressed, isNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Issue code'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(issueRequests, 1);
    await tester.tap(find.text('Close and clear'));
    await tester.pumpAndSettle();
  });
}

const _order = {
  'id': 'qa-order-1',
  'reference_code': 'GN-QA-COD-1',
  'status': 'ready_for_pickup',
  'vertical': 'food',
  'delivery_locality': 'Kuanpal',
  'delivery_district': 'Cuttack',
  'items': [
    {
      'product_name': 'QA Meal',
      'variant_name': 'Regular',
      'unit_label': 'plate',
      'quantity': 1,
    },
  ],
};

Response<Map<String, dynamic>> _response(
  RequestOptions request,
  Map<String, dynamic> data,
) => Response(requestOptions: request, statusCode: 200, data: data);

Future<void> _pumpScreen(WidgetTester tester) async {
  final profile = _FakeMerchantProfile();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [merchantProfileProvider('').overrideWith((ref) => profile)],
      child: const MaterialApp(home: MerchantPlatformOrdersScreen()),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('GN-QA-COD-1'));
  await tester.pumpAndSettle();
}

class _FakeMerchantProfile extends MerchantProfileNotifier {
  _FakeMerchantProfile() : super('') {
    state = state.copyWith(profile: _business);
  }

  @override
  Future<void> load() async {
    state = state.copyWith(profile: _business, isLoading: false);
  }
}

const _business = {
  'id': 'qa-business-1',
  'name': 'QA Partner',
  'status': 'approved',
};
