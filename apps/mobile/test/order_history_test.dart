import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/models/customer_order.dart';
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
  TestOrders() {
    state = CustomerOrdersState(orders: [_order], hasLoaded: true);
  }

  @override
  Future<CustomerOrder> fetchOrderById(String orderId) async {
    if (orderId != _order.id) throw StateError('not found');
    return _order;
  }
}

void main() {
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
    await tester.pumpAndSettle();
    expect(find.byType(OrderTrackingScreen), findsOneWidget);
    expect(find.text('Order details'), findsOneWidget);
    expect(find.textContaining('Rice bowl'), findsOneWidget);
    expect(
      find.text('Live rider location is not available for this order.'),
      findsOneWidget,
    );
    expect(find.text('Preparing'), findsOneWidget);
    expect(
      find.text(
        'Payment is unavailable. No payment was collected or confirmed for this order.',
      ),
      findsOneWidget,
    );
  });
}
