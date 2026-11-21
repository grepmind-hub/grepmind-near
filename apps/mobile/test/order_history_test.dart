import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/models/customer_order.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/providers/customer_orders_provider.dart';
import 'package:grepmind_mobile/core/screens/order_history_screen.dart';
import 'package:grepmind_mobile/core/screens/order_tracking_screen.dart';

final _order = CustomerOrder(
  id: 'order-123',
  businessId: 'business-123',
  businessName: 'QA Restaurant',
  orderType: OrderType.foodDelivery,
  status: OrderStatus.preparing,
  createdAt: DateTime(2026),
  grandTotal: 290,
  items: const [
    CustomerOrderItem(
      id: 'product-1',
      name: 'Rice bowl',
      price: 290,
      quantity: 1,
    ),
  ],
  statusEvents: [
    OrderStatusEvent(
      status: OrderStatus.placed,
      eventKind: 'status_change',
      createdAt: DateTime(2026),
    ),
    OrderStatusEvent(
      status: OrderStatus.preparing,
      eventKind: 'status_change',
      createdAt: DateTime(2026, 1, 1, 1),
    ),
  ],
);

class TestOrders extends CustomerOrdersNotifier {
  TestOrders([CustomerOrder? order]) : order = order ?? _order {
    state = CustomerOrdersState(orders: [this.order], hasLoaded: true);
  }

  final CustomerOrder order;

  @override
  Future<CustomerOrder> fetchOrderById(String orderId) async {
    if (orderId != order.id) throw StateError('not found');
    return order;
  }
}

void main() {
  setUpAll(() => apiClient.init(baseUrl: 'https://orders.test/api/v1'));

  for (final source in ['merchant_catalog', 'platform_catalog']) {
    testWidgets('$source shows the verification action once en route', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final order = CustomerOrder(
        id: 'delivery-test',
        businessId: 'business-123',
        businessName: 'QA Restaurant',
        orderType: OrderType.foodDelivery,
        orderSource: source,
        status: OrderStatus.outForDelivery,
        createdAt: DateTime(2026),
        grandTotal: 290,
      );
      var executionState = 'picked_up';
      final dio = apiClient.dio;
      final savedInterceptors = List<Interceptor>.of(dio.interceptors);
      dio.interceptors
        ..clear()
        ..add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              final Object data = switch (options.path) {
                '/events' => ResponseBody.fromString('', 200),
                '/orders/delivery-test/delivery-status' => {
                  'data': {
                    'delivery_state': 'assigned',
                    'execution_state': executionState,
                    'rider_assigned': true,
                  },
                },
                '/orders/delivery-test/delivery-code' => {
                  'data': {
                    'delivery_code': 'fixture',
                    'expires_in_seconds': 60,
                  },
                },
                _ => {'data': []},
              };
              handler.resolve(Response(requestOptions: options, data: data));
            },
          ),
        );
      addTearDown(() {
        dio.interceptors
          ..clear()
          ..addAll(savedInterceptors);
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customerOrdersProvider.overrideWith((ref) => TestOrders(order)),
            currentUserProvider.overrideWithValue(
              const AppUser(
                id: 'customer-123',
                phoneE164: '+919876543210',
                status: 'active',
                preferredLanguage: 'en',
                roles: ['customer'],
              ),
            ),
          ],
          child: MaterialApp(home: OrderTrackingScreen(orderId: order.id)),
        ),
      );
      await tester.pumpAndSettle();
      final action = find.text('Show delivery verification code');
      expect(action, findsNothing);
      executionState = 'en_route';
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(action, 200);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('Your delivery code'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test(
    'platform fulfillment statuses and rejection reason parse for tracking',
    () {
      expect(CustomerOrder.parseStatus('accepted'), OrderStatus.accepted);
      expect(
        CustomerOrder.parseStatus('ready_for_pickup'),
        OrderStatus.readyForPickup,
      );
      expect(CustomerOrder.parseStatus('rejected'), OrderStatus.rejected);
      final event = OrderStatusEvent.fromJson({
        'status': 'rejected',
        'event_kind': 'partner_rejected',
        'reason': 'Partner capacity is unavailable today.',
        'created_at': '2026-11-06T10:00:00Z',
      });
      expect(event.reason, 'Partner capacity is unavailable today.');
    },
  );

  testWidgets('order list uses type labels and opens exact order details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dio = apiClient.dio;
    final savedInterceptors = List<Interceptor>.of(dio.interceptors);
    dio.interceptors
      ..clear()
      ..add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final Object data = options.path == '/events'
                ? ResponseBody.fromString('', 200)
                : {'data': <String, dynamic>{}};
            handler.resolve(Response(requestOptions: options, data: data));
          },
        ),
      );
    addTearDown(() {
      dio.interceptors
        ..clear()
        ..addAll(savedInterceptors);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          customerOrdersProvider.overrideWith((ref) => TestOrders()),
          currentUserProvider.overrideWithValue(
            const AppUser(
              id: 'customer-123',
              phoneE164: '+919876543210',
              status: 'active',
              preferredLanguage: 'en',
              roles: ['customer'],
            ),
          ),
        ],
        child: const MaterialApp(home: OrderHistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Orders & bookings'), findsOneWidget);
    expect(find.text('Food order · 2026-01-01 00:00'), findsOneWidget);
    await tester.tap(find.text('QA Restaurant'));
    // Tracking deliberately reconnects its live stream; settling indefinitely
    // waits on that continuing activity instead of just the route transition.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(OrderTrackingScreen), findsOneWidget);
    expect(find.text('Order details'), findsOneWidget);
    expect(find.textContaining('Rice bowl'), findsOneWidget);
    expect(
      find.text('Live rider location is not available for this order.'),
      findsOneWidget,
    );
    expect(find.text('Preparing'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text(
        'Payment is unavailable. No payment was collected or confirmed for this order.',
      ),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text(
        'Payment is unavailable. No payment was collected or confirmed for this order.',
      ),
      findsOneWidget,
    );
  });
}
